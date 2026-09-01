-- ============================================================
-- 0043_review_email_cron.sql                         2026-06-04
-- ------------------------------------------------------------
-- Tidsbasert utsending av anmeldelse-lenken: ~1 time etter at en
-- time er avsluttet får kunden en e-post med en unik lenke til
-- anmeldelser.html?token=<review_token> (token fra 0042).
-- (Gruppe C, del 2 av 2.)
--
-- En ren DB-trigger kan ikke «vente 1 time». Vi speiler derfor
-- 0014_reminder_cron_job.sql: en helper-funksjon kjørt periodisk av
-- pg_cron som finner bookinger som ble avsluttet for >1t (men <72t)
-- siden, og som ikke alt har fått anmeldelse-e-post.
--
-- ⚠️⚠️ SANDBOX — LEVERER IKKE ENNÅ:
--   - resend_key er placeholder REDACTED_RESEND_KEY. Funksjonen har en
--     DO-guard som HOPPER OVER all utsending så lenge nøkkelen er
--     placeholder (ingen rader markeres, ingen HTTP-kall). Det betyr
--     at når ekte nøkkel limes inn senere, plukkes de siste 72t opp.
--   - Selv MED ekte nøkkel sendes e-post til KUNDENS adresse, og det
--     krever at Resend-DOMENET er verifisert (sandbox/onboarding-from
--     kan kun sende til konto-eierens egen adresse). Til domenet er
--     verifisert leverer dette IKKE til kunder. Samme begrensning som
--     er dokumentert i 0025.
--
-- 1t–72t-VINDUET er bevisst: nedre grense (1t) gir «litt etter timen»,
--   øvre grense (72t) sikrer at man IKKE spammer HELE bookinghistorikken
--   første gang jobben (eller en ekte nøkkel) blir aktiv.
--
-- review_email_sent_at settes UMIDDELBART etter http_post (før vi vet om
--   Resend faktisk leverte) — samme avveining som 0014: hindrer
--   dobbeltsending ved race/forsinkelser; i verste fall mister én kunde
--   anmeldelse-invitasjonen.
--
-- AVHENGER AV: 0042 (review_token), pg_cron (samme extension som
--   0014-reminder-jobben allerede bruker — INGEN ny aktivering nødvendig
--   hvis 0014 er live). Apply ETTER 0042.
-- Idempotent (add column/index if not exists, create or replace,
--   cron.unschedule-først). ⚠️ IKKE applisert av repoet.
-- ============================================================

begin;

-- ----- (a) Sporings-kolonne (speiler reminder_sent_at, 0013) -----
alter table public.bookings
  add column if not exists review_email_sent_at timestamptz;

create index if not exists idx_bookings_review_email_pending
  on public.bookings (review_email_sent_at)
  where review_email_sent_at is null;

-- ----- (b) Helper-funksjon — process_pending_review_emails ----------
-- Idempotent via CREATE OR REPLACE. Kalles av cron. Manuell test:
--   select public.process_pending_review_emails();
create or replace function public.process_pending_review_emails()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
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
       -- Ikke send hvis bookingen alt er anmeldt (kunden brukte lenken raskt
       -- via et annet kanal, eller dette er en re-kjøring).
       and not exists (select 1 from public.reviews r where r.booking_id = b.id)
  loop
    review_url := base_url || '/anmeldelser.html?token=' || b.review_token::text;
    date_str   := to_char(b.date, 'DD.MM.YYYY');

    -- HTML-template med tydelig «Skriv en anmeldelse»-knapp (table-basert
    -- for Outlook-kompatibilitet). Speiler stilen i 0025.
    email_html :=
         '<!DOCTYPE html><html><body style="font-family: -apple-system, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f5f5f0;">'
      || '<div style="background: #ffffff; padding: 32px; border-radius: 8px;">'
      || '<h2 style="color: #1a1a1a; margin: 0 0 16px 0;">Hvordan var timen hos Westengen Klinikk?</h2>'
      || '<p style="margin: 0 0 8px 0; color: #555; font-size: 15px;">Hei ' || coalesce(b.name, '') || ',</p>'
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
      || '<p style="margin-top: 28px; font-size: 12px; color: #999;">Westengen Klinikk · Bregneveien 12, 0283 Oslo</p>'
      || '</div></body></html>';

    -- Send via Resend gjennom pg_net (asynkront). Samme mekanisme som 0025.
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
  -- E-post er sekundært: la jobben feile mykt uten å velte cron-kjøringen.
  raise warning 'process_pending_review_emails feilet: % %', sqlstate, sqlerrm;
end;
$$;

-- ----- (c) Schedule cron-jobben (speiler 0014, minutt :15 for å unngå
-- kollisjon med reminder-jobben på :05). Idempotent: unschedule først. -----
do $$
begin
  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'westengen-klinikk-review-emails';

  perform cron.schedule(
    'westengen-klinikk-review-emails',
    '15 * * * *',
    $cron$ select public.process_pending_review_emails(); $cron$
  );
end $$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Kolonnen finnes:
--    select column_name from information_schema.columns
--     where table_name='bookings' and column_name='review_email_sent_at';
--
-- B) Funksjon + cron-job finnes:
--    select proname from pg_proc where proname='process_pending_review_emails';
--    select jobname, schedule, active from cron.job
--     where jobname='westengen-klinikk-review-emails';
--
-- C) Sandbox-guard: kjør manuelt FØR ekte nøkkel — skal være no-op:
--    select public.process_pending_review_emails();
--    -- forvent: WARNING «...placeholder — hopper over», ingen rader markert.
--
-- D) ETTER at ekte Resend-nøkkel er limt inn + DOMENET er verifisert:
--    - Sjekk at placeholderen er borte:
--      select position('REDACTED_RESEND_KEY' in prosrc) > 0 as needs_key
--        from pg_proc where proname='process_pending_review_emails';
--      -- needs_key skal være FALSE.
--    - Smoke-test: lag/ha en booking som ble avsluttet for 1-72t siden med
--      status confirmed/completed + gyldig e-post → kjør funksjonen →
--      verifiser at kunden mottar e-post + at review_email_sent_at er satt.
--
-- ALTERNATIV (Free-plan / uten pg_cron): bruk Supabase Cron
--   (Dashboard → Integrations → Cron → New job), schedule '15 * * * *',
--   SQL: select public.process_pending_review_emails();  — funksjonen er
--   kompatibel med begge, akkurat som process_pending_reminders (0014).
-- ============================================================
