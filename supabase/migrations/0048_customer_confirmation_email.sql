-- ============================================================
-- 0048_customer_confirmation_email.sql               2026-06-12
-- ------------------------------------------------------------
-- KUNDEBEKREFTELSE på e-post. Funn under DEL 2-verifisering:
-- send_booking_email sendte KUN ett varsel — til KLINIKKEN
-- (notify_to). Kunden fikk ingenting, verken i kunde- eller
-- admin-flyt. Denne migrasjonen utvider funksjonen til å sende TO
-- e-poster per bekreftet booking:
--
--   1) KUNDEBEKREFTELSE (ny) → new.email, når e-post finnes:
--      full timeoversikt — referanse, tjeneste, terapeut, dato,
--      tid, pris, adresse (Storgata 1, 0155 Oslo) — pluss
--      avbestillingsregelen (24 t / no-show) og AVBESTILL-knapp
--      med token-lenke. Brand-stil (grønn header) som 0039-malen.
--   2) KLINIKK-VARSEL (uendret innhold fra 0025/0029) → notify_to.
--
-- Admin- og kundeflyt deler trigger (trg_booking_email), så begge
-- gir identisk kundebekreftelse. Bookinger UTEN e-post (admin-
-- flyten, 0047): trigger-WHEN hopper over hele funksjonen — ingen
-- sending forsøkes, ingen feil.
--
-- ⚠️ ERSTATTER 0029 I KØEN: base_url settes her til prod-domenet
--    https://demo.westengenklinikk.example. Kjør 0048 I STEDET FOR 0029.
-- ⚠️ CREATE OR REPLACE OVERSKRIVER PROD-FUNKSJONEN: etter apply MÅ
--    operatøren lime inn EKTE Resend-nøkkel (erstatte
--    REDACTED_RESEND_KEY i begge http_post-kall via en
--    CREATE OR REPLACE i SQL Editor — aldri i git).
-- ⚠️ AVHENGIGHET: 0024 (cancel_token) må være applisert (er den).
--
-- Idempotent: create or replace. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

create or replace function public.send_booking_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $body$
declare
  -- ⚠️ HARDKODET API-NØKKEL — placeholder. Operatør setter ekte
  -- nøkkel manuelt etter apply. Lim ALDRI ekte nøkkel inn her.
  resend_key    text := 'REDACTED_RESEND_KEY';
  notify_to     text := 'post@westengenklinikk.example';
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
      ||   '<div style="font-family:Courier,monospace;font-size:10px;letter-spacing:0.14em;color:#5f6058;">WESTENGEN KLINIKK · STORGATA 1, 0155 OSLO · +47 400 00 000</div>'
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
$body$;

commit;

-- ============================================================
-- ETTER APPLY (operatør):
--   1. Lim inn EKTE Resend-nøkkel: kjør CREATE OR REPLACE på nytt i
--      SQL Editor med resend_key := 're_…' (aldri i git).
--   2. Bytt from_email til verifisert avsender (f.eks.
--      'Westengen Klinikk <booking@westengenklinikk.example>') når domenet er verifisert.
--
-- Verifikasjon:
-- A) Funksjonen sender to e-poster og har prod-base_url:
--    select prosrc like '%Timen din er bekreftet%'  as har_kundemal,
--           prosrc like '%no.westengenklinikk.example%'         as prod_url,
--           prosrc like '%REDACTED_RESEND_KEY%'      as maa_faa_ekte_nokkel
--    from pg_proc where proname = 'send_booking_email';
-- B) Ende-til-ende (etter ekte nøkkel): lag testbooking med din egen
--    e-post → motta «Timen din er bekreftet …» med tjeneste/behandler/
--    dato/tid/pris/sted/referanse + avbestillingsknapp; klinikken får
--    «Ny bestilling: …». Admin-booking UTEN e-post → ingen sending,
--    ingen feil (trigger-WHEN fra 0047 hopper over).
-- ============================================================
