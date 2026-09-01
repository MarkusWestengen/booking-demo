-- ============================================================
-- 0025_email_cancel_button.sql                       2026-05-20
-- ------------------------------------------------------------
-- Avbestillings-knapp i den interne "Ny bestilling"-varsel-eposten.
--
-- send_booking_email-triggeren sender i dag et internt varsel til
-- post@westengenklinikk.example hver gang noen booker. Denne migrasjonen
-- bytter ut HTML-templaten slik at den inkluderer en stor
-- "AVBESTILL TIMEN"-knapp + token-URL (avbestill.html?token=…) bygget
-- fra cancel_token-kolonnen (migrasjon 0024). Da har Markus lenken
-- klar i e-posten hvis han må videresende til en kunde manuelt.
--
-- Fase 2 (senere, egen jobb): når Resend-domenet er verifisert byttes
-- kun `to`-mottakeren til kundens e-post — da får kunden samme e-post.
--
-- ============================================================
-- ⚠️ KRITISK — MANUELL NØKKEL-REAPPLY ETTER APPLY:
--   Denne migrasjonen kjører `create or replace function` og
--   OVERSKRIVER hele prod-funksjonen — inkludert den ekte Resend-
--   nøkkelen som i dag bare finnes hardkodet i prod-bodyen.
--   Etter apply MÅ Markus erstatte `REDACTED_RESEND_KEY` med ekte
--   nøkkel manuelt (Dashboard → Database → Functions →
--   send_booking_email). Til det er gjort sendes INGEN varsler.
--
-- ⚠️ AVHENGIGHET: Migrasjon 0024 (cancel_token-kolonnen) MÅ være
--   applisert FØR denne. Funksjonen leser `new.cancel_token`.
--
-- 🔧 RETTELSE vs. opprinnelig jobb-spec: spec-en kalte Resend via
--   `http()` (pgsql-http-extensionen). Den extensionen er IKKE
--   installert — prod bruker `pg_net` (`net.http_post`), jf.
--   0007 + 0011. Denne migrasjonen beholder `net.http_post` slik at
--   e-post-utsendingen faktisk fortsetter å virke.
--
-- 📌 ROLLBACK: forrige funksjonsdefinisjon er dokumentert i
--   `0011_schema_align.sql` (linjene 116-175). Bruk den ved behov.
--
-- Triggeren `trg_booking_email` røres IKKE — `create or replace`
-- beholder samme funksjon-OID, så den eksisterende triggeren
-- (AFTER INSERT ... WHEN new.status='confirmed') peker uendret på
-- den nye funksjonskroppen.
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
  -- manuelt av operatøren etter apply (se header). Lim ALDRI inn ekte
  -- nøkkel her — den havner i git-historikken.
  resend_key   text := 'REDACTED_RESEND_KEY';
  notify_to    text := 'post@westengenklinikk.example';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  -- Base-URL for avbestillings-lenken. Frontend bruker
  -- window.location.origin; e-posten må hardkode prod-domenet.
  base_url     text := 'https://demo.westengenklinikk.example';
  cancel_url   text;
  date_str     text := to_char(new.date, 'DD.MM.YYYY');
  time_str     text := to_char(new.time, 'HH24:MI');
  notify_html  text;
begin
  cancel_url := base_url || '/avbestill.html?token=' || new.cancel_token::text;

  -- HTML-template med tydelig avbestillings-knapp. Knappen er
  -- table-basert for Outlook-kompatibilitet.
  notify_html :=
       '<!DOCTYPE html><html><body style="font-family: -apple-system, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f5f5f0;">'
    || '<div style="background: #ffffff; padding: 32px; border-radius: 8px;">'
    || '<h2 style="color: #1a1a1a; margin: 0 0 24px 0;">Ny bestilling fra ' || new.name || '</h2>'
    || '<table style="width: 100%; border-collapse: collapse; margin-bottom: 32px;">'
    || '<tr><td style="padding: 8px 0; color: #666;">Referanse:</td><td style="padding: 8px 0; font-weight: 600;">' || new.ref || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Tjeneste:</td><td style="padding: 8px 0;">' || new.service_name || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Terapeut:</td><td style="padding: 8px 0;">' || new.staff_name || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Dato:</td><td style="padding: 8px 0;">' || date_str || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Tid:</td><td style="padding: 8px 0;">' || time_str || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Kunde:</td><td style="padding: 8px 0;">' || new.name || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">E-post:</td><td style="padding: 8px 0;">' || new.email || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Telefon:</td><td style="padding: 8px 0;">' || new.phone || '</td></tr>'
    || '</table>'
    -- Stor avbestillings-knapp (table-basert for Outlook-kompatibilitet)
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

  -- Send via Resend gjennom pg_net (asynkront — booking-flyten venter
  -- ikke på HTTP-svaret). Samme mekanisme som prod-funksjonen i 0011.
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
-- Triggeren trg_booking_email er BEVISST IKKE rørt. Den ble opprettet
-- i 0011 (AFTER INSERT ... WHEN new.status='confirmed') og peker via
-- funksjon-OID på send_booking_email — create or replace beholder
-- OID-en, så triggeren bruker den nye kroppen automatisk.
--
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Funksjonen er oppdatert + nøkkel-placeholder må erstattes:
--    select position('REDACTED_RESEND_KEY' in prosrc) > 0 as needs_key,
--           position('AVBESTILL TIMEN'    in prosrc) > 0 as has_button
--      from pg_proc where proname = 'send_booking_email';
--    -- needs_key skal være FALSE etter at ekte nøkkel er limt inn.
--    -- has_button skal være TRUE.
--
-- B) Triggeren er fortsatt koblet:
--    select tgname, tgenabled from pg_trigger
--     where tgrelid = 'public.bookings'::regclass
--       and tgname = 'trg_booking_email';
--    -- forvent: 1 rad, tgenabled = 'O'
--
-- C) Smoke-test: opprett en test-booking ≥25t fram → Markus mottar
--    e-post med "AVBESTILL TIMEN"-knapp → klikk → avbestill.html?token=…
-- ============================================================
