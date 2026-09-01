-- ============================================================
-- 0011_schema_align.sql                            2026-05-12
-- ------------------------------------------------------------
-- Schema-drift opprydding etter at vi 2026-05-12 oppdaget at
-- migrasjoner 0001-0009 ikke er fullstendig applisert i prod-DB.
-- Diagnostiske spørringer (Q1-Q10) avdekket:
--
--   (a) bookings mangler journal_consent + journal_consent_at
--       (migrasjon 0003 ikke applisert)
--   (b) Duplikat unique-index på bookings: 0004's
--       "bookings_active_slot_unique" + manuelt opprettet
--       "bookings_no_double_book" har identisk definisjon
--   (c) Manuell send_booking_email-funksjon + trg_booking_email
--       finnes utenfor migrasjons-historikken og er det som faktisk
--       sender confirmation-epost i prod. Versjonskontrolleres her.
--       0007's notify_booking_change + trg_notify_booking_change er
--       funksjonelt død (app.edge_function_url NOT SET) og droppes.
--
-- Denne migrasjonen er idempotent: `add column if not exists`,
-- `drop ... if exists`, og DO-blokker med pg_proc/pg_policies-sjekk.
--
-- Policy-overlapp på bookings (Admin/Therapist vs. 0010's brede
-- auth-policies) håndteres i separat 0012_bookings_policy_align.sql.
-- ============================================================

-- ============================================================
-- (a) Catch-up av 0003 — journal_consent på bookings -------
-- GDPR Art. 9 nr. 2 a krever eksplisitt samtykke for behandling
-- av helseopplysninger. Vi lagrer samtykke + tidspunkt på
-- bookings-raden som juridisk bevis. Eksisterende rader får
-- default = false. Frontend håndhever at NYE bookinger har
-- samtykke (DB-constraint er bevisst utelatt så admin kan
-- registrere muntlig samtykke).
-- ============================================================
alter table public.bookings
  add column if not exists journal_consent boolean not null default false,
  add column if not exists journal_consent_at timestamptz;

create index if not exists bookings_journal_consent_idx
  on public.bookings(journal_consent) where journal_consent = true;

-- ============================================================
-- (b) Dropp duplikat-indeks --------------------------------
-- bookings_no_double_book ble opprettet manuelt i Dashboard og
-- har identisk definisjon som bookings_active_slot_unique fra
-- migrasjon 0004. Test 9 i 01_rls_policies.sql refererer
-- constraint-navnet "bookings_active_slot_unique" — den beholdes.
-- ============================================================
drop index if exists public.bookings_no_double_book;

-- ============================================================
-- (c) Email-infrastruktur — Option 1 (versjonskontroller manuell,
--     drop 0007's døde infrastruktur)
-- ------------------------------------------------------------
-- Etter Q6/Q7-diagnose 2026-05-12:
--   - 0007's notify_booking_change()/trg_notify_booking_change er
--     funksjonelt død — app.edge_function_url er NOT SET (Q9), så
--     funksjonen returnerer tidlig uten å gjøre noe. Droppes.
--   - public.send_booking_email() + trg_booking_email er manuelt
--     opprettet i Dashboard og er det som faktisk sender
--     confirmation-epost i prod. Versjonskontrolleres som status quo.
--
-- ⚠️ SIKKERHETSGJELD — kritisk TODO før produksjons-skalering:
--
--   1. Resend API-nøkkelen er hardkodet i funksjonskroppen.
--      Hvem som helst med read-access til pg_proc kan ekstrahere
--      den via pg_get_functiondef. Bør flyttes til Edge Function
--      secret + funksjonen kalles via pg_net med X-Webhook-Secret
--      (samme mønster som 0007 var bygget for).
--
--   2. Resend "from"-adresse er onboarding@resend.dev (sandbox).
--      Resend tillater kun sending TIL kontoinnehaverens egen
--      e-post fra sandbox. Må migreres til verifisert domene
--      (westengenklinikk.example e.l.) før vi sender til andre enn kontoinnehaveren.
--
--   3. Mottaker er hardkodet til post@westengenklinikk.example.
--      Bør parameteriseres (Postgres-parameter eller config-tabell)
--      hvis flere clinic-operators senere skal motta varsler.
--
--   4. Edge Function-en supabase/functions/send-booking-email/
--      finnes og er bygget for confirmation+cancellation+reminder,
--      men ingen DB-trigger kaller den etter denne migrasjonen.
--      Den vil bli brukt av Fase B (24h reminder cron-job).
--      Fremtidig opprydding: konsolider all email-logikk dit +
--      DB-trigger kaller via pg_net med konfigurerte params.
--
-- 🔑 IDEMPOTENT-MØNSTER FOR FUNKSJONS-OPPRETTELSE:
-- Funksjonen pakkes i en DO-blokk med pg_proc-eksistens-sjekk.
-- I prod (hvor funksjonen finnes med ekte API-nøkkel) blir hele
-- blokken en no-op og prod-versjonen bevares — INGEN downtime
-- for e-postvarsler ved apply. På fersk DB (test/DR/ny utvikler)
-- opprettes funksjonen med REDACTED_RESEND_KEY-placeholder, og
-- operatøren må manuelt erstatte den med ekte nøkkel etterpå.
--
-- For fremtidige logikk-endringer i funksjonen: lag separat
-- migrasjon med eksplisitt DROP FUNCTION + CREATE (eller CREATE
-- OR REPLACE) og dokumenter at operatøren må re-appliere ekte
-- nøkkel etter migrasjonen kjøres.
-- ============================================================

-- Drop 0007's døde infrastruktur ----------------------------
drop trigger if exists trg_notify_booking_change on public.bookings;
drop function if exists public.notify_booking_change();

-- Versjonskontroller den fungerende manuelle email-funksjonen
-- ONLY hvis den ikke finnes fra før (bevarer prod-versjon med ekte nøkkel).
do $do$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'send_booking_email'
  ) then
    raise notice 'send_booking_email function does not exist — creating with REDACTED_RESEND_KEY placeholder. Operator must manually apply real key after migration.';
    execute $func_def$
create function public.send_booking_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $body$
declare
  -- ⚠️ HARDKODET API-NØKKEL — se sikkerhetsgjeld-kommentar over.
  -- Denne placeholder-en gjelder kun ferske deploys. På eksisterende
  -- prod-DB hopper DO-blokken over hele dette CREATE-utsagnet, så
  -- prod-funksjonen med ekte nøkkel bevares uendret. Aldri lim inn
  -- ekte nøkkel her — den havner i git-historikken.
  resend_key   text := 'REDACTED_RESEND_KEY';
  notify_to    text := 'post@westengenklinikk.example';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  date_str     text := to_char(new.date, 'FMDD.MM.YYYY');
  time_str     text := to_char(new.time, 'HH24:MI');
  notify_html  text;
begin
  notify_html := format(
    '<div style="font-family:-apple-system,Segoe UI,sans-serif;max-width:560px;color:#1f2a23;padding:24px;">' ||
    '<div style="font-size:11px;letter-spacing:.15em;text-transform:uppercase;color:#3e6b47;margin-bottom:8px;">— Ny bestilling</div>' ||
    '<h2 style="margin:0 0 24px;font-size:24px;font-weight:600;">%s kl. %s</h2>' ||
    '<table style="border-collapse:collapse;width:100%%;margin-bottom:24px;">' ||
    '<tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#666;width:130px;">Klient</td><td style="padding:10px 0;border-bottom:1px solid #eee;"><strong>%s</strong></td></tr>' ||
    '<tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#666;">E-post</td><td style="padding:10px 0;border-bottom:1px solid #eee;"><a href="mailto:%s" style="color:#3e6b47;">%s</a></td></tr>' ||
    '<tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#666;">Telefon</td><td style="padding:10px 0;border-bottom:1px solid #eee;"><a href="tel:%s" style="color:#3e6b47;">%s</a></td></tr>' ||
    '<tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#666;">Behandler</td><td style="padding:10px 0;border-bottom:1px solid #eee;">%s</td></tr>' ||
    '<tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#666;">Tjeneste</td><td style="padding:10px 0;border-bottom:1px solid #eee;">%s · %s min · kr %s</td></tr>' ||
    '<tr><td style="padding:10px 0;color:#666;vertical-align:top;">Notater</td><td style="padding:10px 0;">%s</td></tr>' ||
    '</table>' ||
    '<div style="font-size:12px;color:#888;font-family:monospace;border-top:1px solid #eee;padding-top:16px;">Referanse: %s</div>' ||
    '</div>',
    date_str, time_str,
    new.name,
    new.email, new.email,
    new.phone, new.phone,
    new.staff_name,
    new.service_name, new.duration, new.price,
    coalesce(nullif(new.notes, ''), '(ingen)'),
    new.ref
  );

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body := jsonb_build_object(
      'from',    from_email,
      'to',      notify_to,
      'subject', 'Ny bestilling: ' || new.name || ' — ' || date_str || ' kl. ' || time_str,
      'html',    notify_html
    )
  );

  return new;
end;
$body$;
$func_def$;
  else
    raise notice 'send_booking_email function already exists — preserving prod version (assumed to contain real API key).';
  end if;
end
$do$;

-- Trigger: AFTER INSERT, kun når status='confirmed'.
-- Trygt å droppe + gjenskape på hver applikasjon — inneholder ingen secret,
-- og refererer kun funksjonen som allerede er bevart over.
drop trigger if exists trg_booking_email on public.bookings;
create trigger trg_booking_email
  after insert on public.bookings
  for each row
  when (new.status = 'confirmed')
  execute function public.send_booking_email();
