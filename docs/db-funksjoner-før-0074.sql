-- ============================================================
-- Sikkerhetskopi: funksjonene slik de faktisk kjorer i produksjon
-- ------------------------------------------------------------
-- Tatt ut 2. september 2026, FOER migrasjon 0074.
--
-- Bakgrunn: migrasjonsfilene 0026, 0028, 0039, 0040 og 0048 kan ikke
-- ha kjort som de staar i git (uescapet apostrof, SQLSTATE 42601),
-- men staar likevel som appliserte. Repoet er derfor ikke en tro
-- kopi av databasen for disse to funksjonene. Dette er den eneste
-- kopien som finnes av det som virkelig kjorer.
--
-- Hentet med:
--   select pg_get_functiondef(p.oid)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('send_booking_email',
--                        'process_pending_review_emails');
--
-- Metadata paa uttaksdatoen, begge funksjoner:
--   eier          postgres
--   security      SECURITY DEFINER
--   search_path   public, extensions
--   overloads     ingen, én oid per navn
--
-- ============================================================
-- EN LINJE ER MASKERT I DENNE FILA
-- ------------------------------------------------------------
-- send_booking_email har
--
--     notify_to text := 'REDIGERT_PRIVAT_EPOST';
--
-- en ekte privat e-postadresse. Repoet er offentlig, saa den staar
-- ikke her. Verdien er URORT i databasen; migrasjon 0074 tar ikke i
-- den. Skal du gjenopprette fra denne fila, husk aa sette den
-- tilbake foerst.
--
-- Ingen ekte API-noekkel finnes i noen av kroppene: begge har
-- fortsatt plassholderen 'REDACTED_RESEND_KEY'.
-- ============================================================


-- ============================================================
-- process_pending_review_emails
-- ============================================================

CREATE OR REPLACE FUNCTION public.process_pending_review_emails()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  b           record;
  -- ⚠️ HARDKODET API-NØKKEL — placeholder. På prod erstattes denne
  -- manuelt av operatøren etter apply. Lim ALDRI inn ekte nøkkel her —
  -- den havner i git-historikken.
  resend_key  text := 'REDACTED_RESEND_KEY';
  from_email  text := 'Westengen Klinikk <onboarding@resend.dev>';
  base_url    text := 'https://demo.westengenklinikk.example';
  review_url  text;
  date_str    text;
  e_name      text;
  sent        int  := 0;
  email_html  text;
begin
  -- DO-GUARD (sandbox): så lenge nøkkelen er placeholder gjør vi INGENTING
  -- — ingen HTTP-kall og ingen rader markeres. Når ekte nøkkel limes inn
  -- plukkes de siste 72t opp ved neste cron-tikk.
  if resend_key = 'REDACTED_RESEND_KEY' then
    raise warning 'process_pending_review_emails: Resend-nøkkel er placeholder — hopper over (sandbox-modus).';
    return;
  end if;

  for b in
    select *
      from public.bookings
     where review_email_sent_at is null
       and status in ('confirmed', 'completed')
       and email is not null and email <> ''
       and ((date + time + (coalesce(duration, 30) || ' minutes')::interval)
              at time zone 'Europe/Oslo')
             between (now() - interval '72 hours')
                 and (now() - interval '1 hour')
       and not exists (select 1 from public.reviews r where r.booking_id = b.id)
  loop
    review_url := base_url || '/anmeldelser.html?token=' || b.review_token::text;
    date_str   := to_char(b.date, 'DD.MM.YYYY');
    -- D-MEDIUM-fiksen: kunde-styrt navn escapes (0028-disiplin).
    e_name     := public.html_escape(coalesce(b.name, ''));

    email_html :=
         '<!DOCTYPE html><html><body style="font-family: -apple-system, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f5f5f0;">'
      || '<div style="background: #ffffff; padding: 32px; border-radius: 8px;">'
      || '<h2 style="color: #1a1a1a; margin: 0 0 16px 0;">Hvordan var timen hos Westengen Klinikk?</h2>'
      || '<p style="margin: 0 0 8px 0; color: #555; font-size: 15px;">Hei ' || e_name || ',</p>'
      || '<p style="margin: 0 0 24px 0; color: #555; font-size: 15px;">Takk for at du var hos oss '
         || date_str || '. Vi setter stor pris på om du deler et par ord om opplevelsen — '
         || 'det hjelper andre å finne riktig behandling.</p>'
      || '<div style="margin: 28px 0; padding: 24px; background: #eef3ee; border-left: 4px solid #3E6B47; border-radius: 4px;">'
      || '<p style="margin: 0 0 18px 0; color: #2A4A31; font-size: 14px;">Klikk knappen for å legge igjen anmeldelsen din:</p>'
      || '<table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">'
      || '<tr><td align="center" style="background: #3E6B47; border-radius: 6px;">'
      || '<a href="' || review_url || '" '
      || 'style="display: inline-block; padding: 14px 32px; color: #ffffff; text-decoration: none; '
      || 'font-weight: 600; font-size: 16px; font-family: -apple-system, Arial, sans-serif;">'
      || 'SKRIV EN ANMELDELSE</a>'
      || '</td></tr></table>'
      || '<p style="margin: 16px 0 0 0; font-size: 12px; color: #888; word-break: break-all;">'
      || 'Eller kopier denne lenken: ' || review_url || '</p>'
      || '</div>'
      || '<p style="margin-top: 28px; font-size: 12px; color: #999;">Westengen Klinikk · Storgata 1, 0155 Oslo</p>'
      || '</div></body></html>';

    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || resend_key,
        'Content-Type',  'application/json'
      ),
      body    := jsonb_build_object(
        'from',    from_email,
        'to',      b.email,
        'subject', 'Hvordan var timen hos Westengen Klinikk?',
        'html',    email_html
      )
    );

    -- Marker umiddelbart (hindrer dobbeltsending; jf. 0014-avveiingen).
    update public.bookings set review_email_sent_at = now() where id = b.id;
    sent := sent + 1;
  end loop;

  if sent > 0 then
    raise notice 'process_pending_review_emails: sendte % anmeldelse-e-poster', sent;
  end if;

exception when others then
  raise warning 'process_pending_review_emails feilet: % %', sqlstate, sqlerrm;
end;
$function$;


-- ============================================================
-- send_booking_email   (1 linje maskert)
-- ============================================================

CREATE OR REPLACE FUNCTION public.send_booking_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  -- ⚠️ HARDKODET API-NØKKEL — placeholder. Operatør setter ekte
  -- nøkkel manuelt etter apply. Lim ALDRI ekte nøkkel inn her.
  resend_key    text := 'REDACTED_RESEND_KEY';
  notify_to     text := 'REDIGERT_PRIVAT_EPOST';
  from_email    text := 'Westengen Klinikk <onboarding@resend.dev>';
  reply_to      text := 'post@westengenklinikk.example';
  base_url      text := 'https://demo.westengenklinikk.example';
  cancel_url    text;
  date_str      text := to_char(new.date, 'DD.MM.YYYY');
  time_str      text := to_char(new.time, 'HH24:MI');
  price_str     text := 'kr ' || coalesce(new.price, 0)::text;
  customer_html text;
  notify_html   text;
  -- Pre-escapet kundeinput (0028-disiplin).
  e_name    text := public.html_escape(new.name);
  e_service text := public.html_escape(new.service_name);
  e_staff   text := public.html_escape(new.staff_name);
  e_ref     text := public.html_escape(new.ref);
begin
  cancel_url := base_url || '/avbestill.html?token=' || new.cancel_token::text;

  -- ===== 1) KUNDEBEKREFTELSE (full timeoversikt) =====
  if coalesce(new.email, '') <> '' then
    customer_html :=
         '<!DOCTYPE html><html lang="no"><body style="margin:0;padding:0;background-color:#FAF7F1;">'
      || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
      || '<tr><td align="center" style="padding:32px 12px;">'
      || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background-color:#ffffff;">'
      || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;padding:40px;">'
      ||   '<div style="font-family:Georgia,serif;font-size:24px;letter-spacing:0.30em;color:#FAF7F1;">ERIKS&nbsp;ARENA</div>'
      ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.24em;color:#A6C1AC;padding-top:14px;">TIMEN DIN ER BEKREFTET</div>'
      || '</td></tr>'
      || '<tr><td style="padding:32px 40px 6px;">'
      ||   '<p style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#15191A;margin:0;">Hei ' || e_name || ',</p>'
      ||   '<p style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#15191A;margin:12px 0 0;">Her er oversikten over timen din hos Westengen Klinikk:</p>'
      || '</td></tr>'
      || '<tr><td style="padding:18px 40px 8px;">'
      ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">TJENESTE</td>'
      ||       '<td style="padding:12px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || e_service || '</td></tr>'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">BEHANDLER</td>'
      ||       '<td style="padding:12px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || e_staff || '</td></tr>'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">DATO</td>'
      ||       '<td style="padding:12px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;font-weight:bold;">' || date_str || '</td></tr>'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">TID</td>'
      ||       '<td style="padding:12px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;font-weight:bold;">kl. ' || time_str || '</td></tr>'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">PRIS</td>'
      ||       '<td style="padding:12px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || price_str || '</td></tr>'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">STED</td>'
      ||       '<td style="padding:12px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">Storgata 1, 0155 Oslo</td></tr>'
      ||     '<tr><td width="110" style="padding:12px 16px 12px 0;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">REFERANSE</td>'
      ||       '<td style="padding:12px 0;font-family:Courier,monospace;font-size:14px;color:#15191A;">' || e_ref || '</td></tr>'
      ||   '</table>'
      || '</td></tr>'
      || '<tr><td style="padding:10px 40px 36px;">'
      ||   '<div style="background-color:#F2EDE3;border-left:3px solid #3E6B47;padding:18px 20px;">'
      ||     '<p style="font-family:Helvetica,Arial,sans-serif;font-size:13px;line-height:1.6;color:#2D3330;margin:0 0 14px;">'
      ||       'Avbestilling må skje senest <strong>24 timer før timen</strong>. Time som ikke møtes til (no-show) faktureres.</p>'
      ||     '<table role="presentation" cellpadding="0" cellspacing="0" border="0">'
      ||     '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;">'
      ||       '<a href="' || cancel_url || '" style="display:inline-block;padding:12px 26px;color:#ffffff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:bold;">Avbestill timen</a>'
      ||     '</td></tr></table>'
      ||     '<p style="font-family:Helvetica,Arial,sans-serif;font-size:11px;color:#76776F;margin:12px 0 0;word-break:break-all;">Eller kopier lenken: ' || cancel_url || '</p>'
      ||   '</div>'
      || '</td></tr>'
      || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A;padding:26px 40px;">'
      ||   '<div style="font-family:Courier,monospace;font-size:10px;letter-spacing:0.14em;color:#5f6058;">WESTENGEN KLINIKK · ROSENBORGGATA 8, 0356 OSLO · +47 400 00 000</div>'
      || '</td></tr>'
      || '</table></td></tr></table></body></html>';

    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || resend_key,
        'Content-Type',  'application/json'
      ),
      body    := jsonb_build_object(
        'from',     from_email,
        'to',       new.email,
        'reply_to', reply_to,
        'subject',  'Timen din er bekreftet — ' || date_str || ' kl. ' || time_str || ' · Westengen Klinikk',
        'html',     customer_html
      )
    );
  end if;

  -- ===== 2) KLINIKK-VARSEL (innhold uendret fra 0025/0029) =====
  notify_html :=
       '<!DOCTYPE html><html><body style="font-family: -apple-system, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f5f5f0;">'
    || '<div style="background: #ffffff; padding: 32px; border-radius: 8px;">'
    || '<h2 style="color: #1a1a1a; margin: 0 0 24px 0;">Ny bestilling fra ' || e_name || '</h2>'
    || '<table style="width: 100%; border-collapse: collapse; margin-bottom: 32px;">'
    || '<tr><td style="padding: 8px 0; color: #666;">Referanse:</td><td style="padding: 8px 0; font-weight: 600;">' || e_ref || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Tjeneste:</td><td style="padding: 8px 0;">' || e_service || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Terapeut:</td><td style="padding: 8px 0;">' || e_staff || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Dato:</td><td style="padding: 8px 0;">' || date_str || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Tid:</td><td style="padding: 8px 0;">' || time_str || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Kunde:</td><td style="padding: 8px 0;">' || e_name || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">E-post:</td><td style="padding: 8px 0;">' || public.html_escape(new.email) || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Telefon:</td><td style="padding: 8px 0;">' || public.html_escape(new.phone) || '</td></tr>'
    || '</table>'
    || '<div style="margin: 32px 0; padding: 24px; background: #f9f4e8; border-left: 4px solid #c4a661; border-radius: 4px;">'
    || '<p style="margin: 0 0 16px 0; font-weight: 600; color: #1a1a1a; font-size: 16px;">Avbestilling</p>'
    || '<p style="margin: 0 0 20px 0; color: #555; font-size: 14px;">Klikk knappen under for å avbestille timen (senest 24 timer før):</p>'
    || '<table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">'
    || '<tr><td align="center" style="background: #c0392b; border-radius: 6px;">'
    || '<a href="' || cancel_url || '" '
    || 'style="display: inline-block; padding: 14px 32px; color: #ffffff; text-decoration: none; '
    || 'font-weight: 600; font-size: 16px; font-family: -apple-system, Arial, sans-serif;">'
    || 'AVBESTILL TIMEN</a>'
    || '</td></tr></table>'
    || '<p style="margin: 16px 0 0 0; font-size: 12px; color: #888; word-break: break-all;">'
    || 'Eller kopier denne lenken: ' || cancel_url || '</p>'
    || '</div>'
    || '<p style="margin-top: 32px; font-size: 12px; color: #999;">Westengen Klinikk — automatisk varsel</p>'
    || '</div></body></html>';

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'from',    from_email,
      'to',      notify_to,
      'subject', 'Ny bestilling: ' || new.name || ' — ' || date_str || ' kl. ' || time_str,
      'html',    notify_html
    )
  );

  return new;

exception when others then
  -- E-post er sekundært: la bookingen committe selv om sending feiler.
  raise notice 'send_booking_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$function$;

