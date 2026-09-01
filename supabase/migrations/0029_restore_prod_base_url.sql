-- ============================================================
-- 0029_restore_prod_base_url.sql                     2026-05-23
-- ------------------------------------------------------------
-- P1-A fra audit-2026-05-23: prod-funksjonen send_booking_email
-- har base_url = 'http://localhost:5500' (lokal Live Server
-- LAN-IP). Avbestillings-lenken i bestillings-bekreftelses-eposten
-- er derfor død for alle som ikke er på samme Wi-Fi.
--
-- Denne migrasjonen kjører `create or replace function` og setter
-- base_url tilbake til prod-domenet `https://demo.westengenklinikk.example`.
-- HTML-template-strukturen er identisk med den committede 0025-
-- versjonen (som er den template-strukturen som ligger i prod per
-- 2026-05-23), MEN med en sikkerhets-fiks lagt på:
--
--   🛡 HTML-ESCAPE av kunde-input (lagt til 2026-05-23, samme commit):
--   Templaten konkatenerte tidligere new.name/email/phone/service_name/
--   staff_name/ref direkte inn i HTML — en ondsinnet booking-payload
--   kunne lande som klikkbar phishing-lenke eller tracking-pixel i
--   admin-innboksen. Denne migrasjonen legger til en `public.html_escape`-
--   hjelpefunksjon og wrapper alle 6 user-input-feltene i den. Standard
--   5-tegns escape (& først for å unngå double-encoding):
--     &  → &amp;
--     <  → &lt;
--     >  → &gt;
--     "  → &quot;
--     '  → &#39;
--   Trygge felter (date_str, time_str, cancel_url, base_url, subject)
--   er IKKE wrappet — de er enten typed-formatert eller server-konstruert.
--
-- 0026 (brand-tema) og 0028 (egen html_escape-versjon) er BEVISST
-- IKKE merged inn her — de er separate template-fikser. Hvis 0028
-- senere applieres, vil dens `create or replace function html_escape`
-- gi samme resultat (identisk body), så ingen konflikt.
--
-- ============================================================
-- ⚠️ KRITISK — MANUELL NØKKEL-REAPPLY ETTER APPLY:
--
--   `create or replace function` OVERSKRIVER hele prod-funksjonen,
--   inkludert den ekte Resend-nøkkelen som ble rotert 2026-05-23.
--   Den nye nøkkelen lever KUN hardkodet i prod-funksjonen NÅ —
--   ikke i denne migrasjonen, ikke i Edge Function-secrets, ikke
--   noe annet sted.
--
--   ETTER apply MÅ Markus erstatte `REDACTED_RESEND_KEY` med ekte
--   nøkkel manuelt:
--     Dashboard → Database → Functions → send_booking_email
--     → finn linja `resend_key text := 'REDACTED_RESEND_KEY';`
--     → erstatt med `resend_key text := 're_<EKTE_NØKKEL>';`
--     → Save (kjører create or replace).
--
--   Til det er gjort sendes INGEN varsel-eposter — alle INSERTs
--   på bookings vil committe, men trigger-eposten vil feile i
--   net.http_post (401 fra Resend). Booking-flyten selv er
--   uberørt (exception when others i funksjonen swallower feilen).
--
--   Lim ALDRI inn ekte nøkkel i denne fila, ikke i noen commit,
--   ikke i noe Issue/PR. Nøkkelen havner i git-historikken hvis
--   den committes selv én gang.
--
-- ⚠️ AVHENGIGHET: Migrasjon 0024 (cancel_token-kolonnen) MÅ være
--   applisert FØR denne. Funksjonen leser `new.cancel_token`.
--
-- 📌 ROLLBACK: Forrige funksjons-state er den som ligger i prod
--   per nå (base_url LAN-IP + 0025-template). For å rulle tilbake,
--   re-apply funksjonen med `base_url := 'http://localhost:5500'`
--   (men det ER bugen — så rollback gir ingen mening med mindre
--   hele 0029 trekkes tilbake av annen grunn).
--
-- 🔑 Mønster-valg: Manual-reapply (samme som 0025, 0026, 0028).
--   0011's skip-if-exists-guard ville vært no-op på prod (funksjonen
--   FINNES), og base_url ville aldri blitt oppdatert. Markus
--   bekreftet 2026-05-23 at manual-reapply er ønsket mønster.
--
-- Triggeren `trg_booking_email` røres IKKE — `create or replace`
-- beholder funksjon-OID-en, så den eksisterende triggeren
-- (AFTER INSERT ... WHEN new.status='confirmed', fra 0011) peker
-- uendret på den nye funksjonskroppen.
--
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ============================================================
-- HTML-escape-hjelpefunksjon (idempotent — `create or replace`).
-- Standard 5-tegns escape, & FØRST for å unngå double-encoding.
-- coalesce(..., '') gjør funksjonen null-safe så templaten ikke
-- får tom HTML hvis et felt skulle være null. Immutable + parallel
-- safe gir Postgres lov til å cache resultatet.
-- ============================================================
create or replace function public.html_escape(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(
    replace(
      replace(
        replace(
          replace(
            replace(p_text, '&', '&amp;'),
            '<', '&lt;'),
          '>', '&gt;'),
        '"', '&quot;'),
      '''', '&#39;'),
    ''
  );
$$;

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
  -- table-basert for Outlook-kompatibilitet. Bit-for-bit identisk
  -- med 0025-templaten (bevisst — denne migrasjonen endrer KUN
  -- base_url, ikke template).
  notify_html :=
       '<!DOCTYPE html><html><body style="font-family: -apple-system, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f5f5f0;">'
    || '<div style="background: #ffffff; padding: 32px; border-radius: 8px;">'
    || '<h2 style="color: #1a1a1a; margin: 0 0 24px 0;">Ny bestilling fra ' || html_escape(new.name) || '</h2>'
    || '<table style="width: 100%; border-collapse: collapse; margin-bottom: 32px;">'
    || '<tr><td style="padding: 8px 0; color: #666;">Referanse:</td><td style="padding: 8px 0; font-weight: 600;">' || html_escape(new.ref) || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Tjeneste:</td><td style="padding: 8px 0;">' || html_escape(new.service_name) || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Terapeut:</td><td style="padding: 8px 0;">' || html_escape(new.staff_name) || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Dato:</td><td style="padding: 8px 0;">' || date_str || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Tid:</td><td style="padding: 8px 0;">' || time_str || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Kunde:</td><td style="padding: 8px 0;">' || html_escape(new.name) || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">E-post:</td><td style="padding: 8px 0;">' || html_escape(new.email) || '</td></tr>'
    || '<tr><td style="padding: 8px 0; color: #666;">Telefon:</td><td style="padding: 8px 0;">' || html_escape(new.phone) || '</td></tr>'
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
-- Verifikasjon (kjør manuelt etter apply + nøkkel-reapply):
--
-- A) base_url er prod-domenet, HTML-escape på plass, nøkkel-placeholder
--    må erstattes:
--    select position('https://demo.westengenklinikk.example' in prosrc) > 0 as has_prod_url,
--           position('localhost'           in prosrc) > 0 as has_lan_ip,
--           position('html_escape(new.name)'   in prosrc) > 0 as has_escape,
--           position('REDACTED_RESEND_KEY'     in prosrc) > 0 as needs_key
--      from pg_proc where proname = 'send_booking_email';
--    -- forvent: has_prod_url = true, has_lan_ip = false, has_escape = true,
--    -- needs_key = false ETTER at ekte nøkkel er limt inn.
--
-- A2) html_escape-funksjonen er på plass og fungerer:
--     select public.html_escape('<script>"&''');
--     -- forvent: &lt;script&gt;&quot;&amp;&#39;
--
-- B) Triggeren er fortsatt koblet:
--    select tgname, tgenabled from pg_trigger
--     where tgrelid = 'public.bookings'::regclass
--       and tgname = 'trg_booking_email';
--    -- forvent: 1 rad, tgenabled = 'O'
--
-- C) Smoke-test (etter nøkkel-reapply): opprett en test-booking
--    ≥25t fram → Markus mottar e-post med "AVBESTILL TIMEN"-knapp
--    → klikk → URL åpner https://demo.westengenklinikk.example/avbestill.html?token=…
--    → bekreft avbestilling → status='cancelled' i DB. Slett test-raden.
-- ============================================================
