-- ============================================================
-- Westengen Klinikk — Journal-samtykke
-- Migration 0003
-- ------------------------------------------------------------
-- GDPR art. 9 nr. 2 a krever eksplisitt samtykke for behandling
-- av helseopplysninger (pasientjournal). Vi lagrer samtykke-
-- flagget + tidspunkt på bookings-raden som juridisk bevis.
--
-- Eksisterende rader får default = false. De er fra før samtykke-
-- kravet trådte i kraft i frontend, og må behandles som legacy.
-- Frontend håndhever at NYE bookinger har samtykke (DB-constraint
-- er bevisst utelatt så admin kan registrere muntlig samtykke).
-- ============================================================

alter table public.bookings
  add column if not exists journal_consent boolean not null default false,
  add column if not exists journal_consent_at timestamptz;

-- Partial index for raske compliance-rapporter ("hvor mange
-- bookinger har samtykke?").
create index if not exists bookings_journal_consent_idx
  on public.bookings(journal_consent) where journal_consent = true;

-- ============================================================
-- Sanity check etter migrasjon:
--   select column_name, data_type, column_default
--     from information_schema.columns
--    where table_name = 'bookings'
--      and column_name in ('journal_consent', 'journal_consent_at');
-- Forventer 2 rader: boolean default false, timestamptz null.
-- ============================================================
