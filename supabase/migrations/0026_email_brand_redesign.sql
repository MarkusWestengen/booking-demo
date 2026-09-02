-- ============================================================
-- 0026_email_brand_redesign.sql                      2026-05-20
-- ------------------------------------------------------------
-- Brand-tema redesign av den interne "Ny bestilling"-varsel-eposten.
--
-- Erstatter den generiske HTML-templaten fra 0025 med et rent
-- Westengen Klinikk-tema: grønt header-band med wordmark, cream kort,
-- clay-aksent, tabell med god luft, innrammet avbestillings-seksjon
-- og mørkt ink-footer. Funksjonell logikk er uendret fra 0025 —
-- kun HTML-templaten er ny.
--
-- Brand-farger (hardkodet hex — e-postklienter støtter ikke
-- CSS-variabler):
--   grønn       #3E6B47   (header-band, knapp)
--   paper/cream #FAF7F1 / #F2EDE3
--   ink         #15191A   (verditekst, footer-band)
--   muted       #76776F
--   clay-aksent #B8754A   (divider)
-- Fonter: Georgia (serif), Helvetica/Arial (body), Courier (mono)
-- — alle web-safe, ingen navn med mellomrom (unngår quote-escaping).
--
-- ============================================================
-- ⚠️ KRITISK — MANUELL NØKKEL-REAPPLY ETTER APPLY:
--   `create or replace function` OVERSKRIVER hele prod-funksjonen,
--   inkludert den ekte Resend-nøkkelen. Etter apply MÅ Markus
--   erstatte `REDACTED_RESEND_KEY` med ekte nøkkel manuelt
--   (Dashboard → Database → Functions → send_booking_email).
--   Samme prosedyre som etter 0025.
--
-- ⚙️ base_url er satt til `http://localhost:5500` (lokal
--   Live Server). INGEN ekstra manuell endring nødvendig etter
--   apply. ⚠️ Må byttes til ekte prod-domene før lansering.
--
-- ⚠️ AVHENGIGHET: 0024 (cancel_token) + 0025 må være applisert.
--
-- 🔧 HTTP-mekanisme: `net.http_post` (pg_net) — IKKE `http()`.
-- 📌 ROLLBACK: forrige template ligger i 0025_email_cancel_button.sql.
--
-- Triggeren `trg_booking_email` røres IKKE — `create or replace`
-- beholder funksjon-OID-en, så den eksisterende triggeren
-- (AFTER INSERT ... WHEN new.status='confirmed', fra 0011) peker
-- uendret på den nye funksjonskroppen.
--
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
  -- ⚠️ HARDKODET API-NØKKEL — placeholder. På prod erstattes denne
  -- manuelt av operatøren etter apply. Lim ALDRI inn ekte nøkkel her.
  resend_key   text := 'REDACTED_RESEND_KEY';
  notify_to    text := 'post@westengenklinikk.example';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  -- Base-URL for avbestillings-lenken. Live Server for testing —
  -- bytt til ekte prod-domene før lansering.
  base_url     text := 'http://localhost:5500';
  cancel_url   text;
  date_str     text := to_char(new.date, 'DD.MM.YYYY');
  time_str     text := to_char(new.time, 'HH24:MI');
  notify_html  text;
begin
  cancel_url := base_url || '/avbestill.html?token=' || new.cancel_token::text;

  -- Brand-tema HTML. All CSS inline, table-basert layout, web-safe
  -- fonter, maks 600px, ingen bilder — for e-postklient-kompatibilitet.
  notify_html :=
       '<!DOCTYPE html><html lang="no"><body style="margin:0; padding:0; background-color:#FAF7F1;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
    || '<tr><td align="center" style="padding:32px 12px;">'

    -- ===== 600px kort =====
    || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px; background-color:#ffffff;">'

    -- ----- HEADER (grønt band) -----
    || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47; padding:46px 40px 40px;">'
    ||   '<div style="font-family:Georgia,serif; font-size:24px; letter-spacing:0.30em; color:#FAF7F1;">MARKUS''&nbsp;ARENA</div>'
    ||   '<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:18px auto 16px;">'
    ||     '<tr><td style="width:46px; height:2px; background-color:#B8754A; font-size:0; line-height:0;">&nbsp;</td></tr>'
    ||   '</table>'
    ||   '<div style="font-family:Courier,monospace; font-size:11px; letter-spacing:0.24em; color:#A6C1AC;">NY BESTILLING</div>'
    || '</td></tr>'

    -- ----- BODY: intro + detalj-tabell -----
    || '<tr><td style="padding:40px 40px 6px;">'
    ||   '<div style="font-family:Georgia,serif; font-size:21px; color:#15191A;">'
    ||     new.name || ' har booket en time.</div>'
    || '</td></tr>'
    || '<tr><td style="padding:18px 40px 8px;">'
    ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">E-POST</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || new.email || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TELEFON</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || new.phone || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TJENESTE</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || new.service_name || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TERAPEUT</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || new.staff_name || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">DATO</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || date_str || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TID</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || time_str || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">REFERANSE</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:14px; color:#15191A; vertical-align:top;">' || new.ref || '</td>'
    ||     '</tr>'
    ||   '</table>'
    || '</td></tr>'

    -- ----- AVBESTILLINGS-SEKSJON (innrammet boks) -----
    || '<tr><td style="padding:26px 40px 40px;">'
    ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F2EDE3; border:1px solid #E4DAC8;">'
    ||     '<tr><td align="center" style="padding:32px 32px 34px;">'
    ||       '<div style="font-family:Georgia,serif; font-size:18px; color:#15191A;">Trenger du å avbestille?</div>'
    ||       '<div style="font-family:Helvetica,Arial,sans-serif; font-size:13px; color:#5c5d55; padding-top:8px;">Klikk knappen under — senest 24 timer før timen.</div>'
    ||       '<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:22px auto 0;">'
    ||         '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47; border-radius:4px;">'
    ||           '<a href="' || cancel_url || '" style="display:inline-block; padding:15px 42px; font-family:Helvetica,Arial,sans-serif; font-size:15px; font-weight:bold; letter-spacing:0.05em; color:#FAF7F1; text-decoration:none;">AVBESTILL TIMEN</a>'
    ||         '</td></tr>'
    ||       '</table>'
    ||       '<div style="font-family:Courier,monospace; font-size:11px; color:#8a8b82; padding-top:20px; word-break:break-all;">' || cancel_url || '</div>'
    ||     '</td></tr>'
    ||   '</table>'
    || '</td></tr>'

    -- ----- FOOTER (mørkt ink-band) -----
    || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A; padding:30px 40px;">'
    ||   '<div style="font-family:Georgia,serif; font-size:15px; letter-spacing:0.20em; color:#FAF7F1;">WESTENGEN KLINIKK</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif; font-size:12px; line-height:1.7; color:#8f9089; padding-top:9px;">Bregneveien 12, 0283 Oslo<br>+47 400 00 000</div>'
    ||   '<div style="font-family:Courier,monospace; font-size:10px; letter-spacing:0.14em; color:#5f6058; padding-top:14px;">AUTOMATISK VARSEL</div>'
    || '</td></tr>'

    || '</table>'
    || '</td></tr></table>'
    || '</body></html>';

  -- Send via Resend gjennom pg_net (asynkront). Samme mekanisme
  -- som prod-funksjonen i 0011/0025.
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
  -- E-post er sekundært: la bookingen committe selv om varselet feiler.
  raise notice 'send_booking_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$body$;

commit;

-- ============================================================
-- Triggeren trg_booking_email er BEVISST IKKE rørt — create or
-- replace beholder funksjon-OID-en, så triggeren fra 0011
-- (AFTER INSERT ... WHEN new.status='confirmed') peker uendret
-- på den nye kroppen. "Trigger-binding intakt" = den virker.
--
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Funksjonen oppdatert + nøkkel/base_url:
--    select position('REDACTED_RESEND_KEY' in prosrc) > 0 as needs_key,
--           substring(prosrc from 'base_url[^;]+;')      as base_url_line
--      from pg_proc where proname = 'send_booking_email';
--    -- needs_key = FALSE etter at ekte nøkkel er reapplisert.
--    -- base_url_line viser http://localhost:5500
--
-- B) Triggeren fortsatt koblet:
--    select tgname, tgenabled from pg_trigger
--     where tgrelid = 'public.bookings'::regclass
--       and tgname = 'trg_booking_email';        -- 1 rad, tgenabled='O'
--
-- C) Smoke-test: opprett en test-booking → Markus mottar e-post
--    med nytt brand-tema → klikk "AVBESTILL TIMEN" → avbestill.html.
-- ============================================================
