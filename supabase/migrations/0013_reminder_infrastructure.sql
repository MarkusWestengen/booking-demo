-- ============================================================
-- 0013_reminder_infrastructure.sql                 2026-05-12
-- ------------------------------------------------------------
-- Skjema-laget for 24-timers påminnelse-cron-jobben i 0014.
-- Adresserer audit-rapport 2026-05-11 punkt 3 (reminder mangler).
--
-- Denne migrasjonen er bevisst splittet fra 0014 fordi 0014 har
-- en hard manuell forutsetning (pg_cron må enables i Dashboard
-- av en operatør med Pro-plan-tilgang). 0013 kan trygt appliseres
-- selv om pg_cron ikke er enablet — kolonne og indeks står klare.
--
-- ⚠️ FØR 0014 KAN APPLISERES:
--
--   (1) Enable pg_cron extension:
--       Dashboard → Database → Extensions → søk "pg_cron" → Enable.
--       Krever Pro-plan. Hvis du er på Free, bruk Supabase Cron som
--       beskrevet i 0014's kommentar (deres nyere scheduling-produkt).
--
--   (2) Sett Postgres-parametere som Edge Function-trigger trenger:
--       Dashboard → Database → Settings → Custom Postgres Parameters
--       ELLER via SQL:
--         alter database postgres set app.edge_function_url =
--           'https://<project-ref>.supabase.co/functions/v1/send-booking-email';
--         alter database postgres set app.webhook_secret = '<verdi>';
--       (Samme `app.webhook_secret`-verdi som Edge Function-secret
--        WEBHOOK_SECRET.)
--
--   (3) Edge Function `send-booking-email` må være deployd. Den har
--       allerede støtte for event='reminder' i supabase/functions/.
--
-- Idempotent: `add column if not exists` og `create index if not exists`.
-- ============================================================

-- ============================================================
-- (a) reminder_sent_at-kolonne på bookings -----------------
-- Lagrer tidspunktet for når 24h-reminder ble sendt. NULL =
-- ikke sendt ennå. Settes av process_pending_reminders() i 0014
-- når cron-jobben har kalt Edge Function for en booking.
-- ============================================================
alter table public.bookings
  add column if not exists reminder_sent_at timestamptz;

-- ============================================================
-- (b) Partial index for effektiv cron-spørring -------------
-- 0014's cron-jobb spør hver time etter bookinger 22-26 timer
-- frem i tid med status='confirmed' og reminder_sent_at IS NULL.
-- Partial index gjør at vi kun indekserer kandidat-radene — dette
-- er typisk en svært liten andel av total bookings-tabellen.
-- Sortert på (date, time) for å støtte range-scan på fremtidige
-- tidspunkter.
-- ============================================================
create index if not exists bookings_pending_reminder_idx
  on public.bookings(date, time)
  where status = 'confirmed' and reminder_sent_at is null;
