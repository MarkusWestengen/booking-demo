-- ============================================================
-- E-postfunksjonene slik de kjorer i produksjon FOR 0076
-- Hentet: 2026-09-02, prosjekt pfyidlnztpwjnpxpoheu
-- Metode: select pg_get_functiondef(oid) from pg_proc ...
-- ------------------------------------------------------------
-- Dette er en KOPI, ikke en migrasjon. Den skal ikke kjores.
-- Den finnes fordi repoet er eldre enn produksjon: filene i
-- supabase/migrations gjengir ikke kroppene som faktisk kjorer.
-- Se docs/db-funksjoner-for-0074.sql for forrige uttak.
--
-- METADATA (identisk for alle fire):
--   eier            postgres
--   security        SECURITY DEFINER
--   search_path     public, extensions
--   volatilitet     volatile
--   returtype       trigger (unntatt process_pending_review_emails: void)
--   overloads       ingen
--
-- MASKERING
--   send_booking_email har
--       notify_to text := 'REDIGERT_PRIVAT_EPOST';
--   en ekte privat e-postadresse. Repoet er offentlig, saa den
--   staar ikke her. 0076 bytter den til
--   post@westengenklinikk.example.
--
--   resend_key staar som 'REDACTED_RESEND_KEY' i alle fire. Det er
--   plassholderen slik den faktisk er i produksjon, ikke maskering.
--
-- HVA 0076 ENDRER I DISSE KROPPENE
--   send_booking_email            notify_to + vakt
--   send_contact_message_email    vakt
--   send_document_email           vakt
--   process_pending_review_emails ingenting (kilden til vaktmonsteret)
-- ============================================================

-- ------------------------------------------------------------
-- process_pending_review_emails   (4417 tegn, 0 maskert linje)
-- ------------------------------------------------------------
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
  base_url    text := 'https://booking-demo-rosy.vercel.app';
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
$function$

-- ------------------------------------------------------------
-- send_booking_email   (10716 tegn, 1 maskert linje)
-- ------------------------------------------------------------
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
  base_url      text := 'https://booking-demo-rosy.vercel.app';
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
      ||   '<div style="font-family:Georgia,serif;font-size:24px;letter-spacing:0.30em;color:#FAF7F1;">WESTENGEN&nbsp;KLINIKK</div>'
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
$function$

-- ------------------------------------------------------------
-- send_contact_message_email   (4651 tegn, 0 maskert linje)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_contact_message_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  -- ⚠️ HARDKODET API-NØKKEL — placeholder kun for ferske deploys.
  -- DO-guarden hopper over CREATE på eksisterende prod-DB, så den
  -- ekte nøkkelen bevares. Aldri lim inn ekte nøkkel her (git).
  resend_key   text := 'REDACTED_RESEND_KEY';
  notify_to    text := 'post@westengenklinikk.example';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  date_str     text := to_char(new.created_at, 'DD.MM.YYYY HH24:MI');
  notify_html  text;
  -- Pre-escapet kunde-input (jf. 0028 P1-2).
  e_name       text := public.html_escape(new.name);
  e_email      text := public.html_escape(new.email);
  e_message    text := replace(public.html_escape(new.message), chr(10), '<br>');
begin
  notify_html :=
       '<!DOCTYPE html><html lang="no"><body style="margin:0;padding:0;background-color:#FAF7F1;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
    || '<tr><td align="center" style="padding:32px 12px;">'
    || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background-color:#ffffff;">'
    || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;padding:40px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:24px;letter-spacing:0.30em;color:#FAF7F1;">WESTENGEN&nbsp;KLINIKK</div>'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.24em;color:#A6C1AC;padding-top:14px;">NY HENVENDELSE</div>'
    || '</td></tr>'
    || '<tr><td style="padding:36px 40px 8px;">'
    ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
    ||     '<tr><td width="92" style="padding:13px 16px 13px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">NAVN</td>'
    ||       '<td style="padding:13px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || e_name || '</td></tr>'
    ||     '<tr><td width="92" style="padding:13px 16px 13px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">E-POST</td>'
    ||       '<td style="padding:13px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;"><a href="mailto:' || e_email || '" style="color:#3E6B47;">' || e_email || '</a></td></tr>'
    ||     '<tr><td width="92" style="padding:13px 16px 13px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">MOTTATT</td>'
    ||       '<td style="padding:13px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || date_str || '</td></tr>'
    ||   '</table>'
    || '</td></tr>'
    || '<tr><td style="padding:22px 40px 40px;">'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;padding-bottom:10px;">MELDING</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#15191A;background-color:#F2EDE3;border:1px solid #E4DAC8;padding:20px;">' || e_message || '</div>'
    || '</td></tr>'
    || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A;padding:26px 40px;">'
    ||   '<div style="font-family:Courier,monospace;font-size:10px;letter-spacing:0.14em;color:#5f6058;">AUTOMATISK VARSEL — WESTENGEN KLINIKK</div>'
    || '</td></tr>'
    || '</table></td></tr></table></body></html>';

  -- Send via Resend gjennom pg_net (asynkront). reply_to = kundens
  -- e-post så ansatte kan svare direkte.
  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'from',     from_email,
      'to',       notify_to,
      'reply_to', new.email,
      'subject',  'Ny henvendelse: ' || e_name,
      'html',     notify_html
    )
  );

  return new;

exception when others then
  -- E-post er sekundært: la meldingen lagres selv om varselet feiler
  -- (forventet i sandbox før domeneverifisering).
  raise notice 'send_contact_message_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$function$

-- ------------------------------------------------------------
-- send_document_email   (4223 tegn, 0 maskert linje)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_document_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  -- ⚠️ HARDKODET API-NØKKEL — placeholder kun for ferske deploys.
  -- DO-guarden hopper over CREATE på eksisterende prod-DB, så den
  -- ekte nøkkelen bevares. Aldri lim inn ekte nøkkel her (git).
  resend_key   text := 'REDACTED_RESEND_KEY';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  notify_to    text := new.customer_email;
  e_title      text := public.html_escape(new.document_title);
  e_link       text := public.html_escape(new.link_url);
  e_sender     text := public.html_escape(coalesce(new.sent_by_name, 'Westengen Klinikk'));
  notify_html  text;
begin
  notify_html :=
       '<!DOCTYPE html><html lang="no"><body style="margin:0;padding:0;background-color:#FAF7F1;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
    || '<tr><td align="center" style="padding:32px 12px;">'
    || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background-color:#ffffff;">'
    || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;padding:40px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:24px;letter-spacing:0.30em;color:#FAF7F1;">WESTENGEN&nbsp;KLINIKK</div>'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.24em;color:#A6C1AC;padding-top:14px;">ØVELSER &amp; OPPFØLGING</div>'
    || '</td></tr>'
    || '<tr><td style="padding:40px 40px 8px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:21px;color:#15191A;">Du har fått tilsendt et dokument.</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#5c5d55;padding-top:12px;">'
    ||     e_sender || ' ved Westengen Klinikk har delt «' || e_title || '» med deg. Klikk knappen under for å laste det ned.</div>'
    || '</td></tr>'
    || '<tr><td align="center" style="padding:14px 40px 8px;">'
    ||   '<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:8px auto 0;">'
    ||     '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;border-radius:4px;">'
    ||       '<a href="' || e_link || '" style="display:inline-block;padding:15px 42px;font-family:Helvetica,Arial,sans-serif;font-size:15px;font-weight:bold;letter-spacing:0.05em;color:#FAF7F1;text-decoration:none;">LAST NED DOKUMENT</a>'
    ||     '</td></tr>'
    ||   '</table>'
    || '</td></tr>'
    || '<tr><td style="padding:18px 40px 40px;">'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;color:#8a8b82;word-break:break-all;">' || e_link || '</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8a8b82;padding-top:14px;">Lenken er gyldig i 30 dager. Trenger du den på nytt etterpå, ta kontakt med klinikken.</div>'
    || '</td></tr>'
    || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A;padding:30px 40px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:15px;letter-spacing:0.20em;color:#FAF7F1;">WESTENGEN KLINIKK</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:12px;line-height:1.7;color:#8f9089;padding-top:9px;">Storgata 1, 0155 Oslo<br>+47 400 00 000</div>'
    || '</td></tr>'
    || '</table></td></tr></table></body></html>';

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'from',    from_email,
      'to',      notify_to,
      'subject', 'Dokument fra Westengen Klinikk: ' || e_title,
      'html',    notify_html
    )
  );

  return new;

exception when others then
  -- E-post er sekundært: la utsendings-loggen lagres selv om varselet
  -- feiler (forventet i sandbox før domeneverifisering).
  raise notice 'send_document_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$function$

