-- ============================================================
-- Westengen Klinikk — Bookings: newsletter_opt_in-felt
-- Migration 0031
-- ------------------------------------------------------------
-- Erik-feedback 2026-05-29 (D3): nyhetsbrev-opt-in valgfri ved booking.
-- Kunde krysser av i steg 5 (Detaljer) hvis han vil ha nyhetsbrev,
-- tilbud og relevant informasjon på e-post. Default = FALSE (GDPR-
-- vennlig — eksplisitt opt-in kreves).
--
-- Lagres som BOOLEAN-kolonne på `bookings`. Markus/Erik henter ut
-- listen senere (CSV-eksport eller direkte SELECT inntil egen
-- newsletter-subscribers-tabell er på plass — se D-roadmap).
--
-- Anon INSERT-policy fra 0027 er ikke-restriktiv på dette feltet
-- (WITH CHECK refererer kun PII-validering + status='confirmed'),
-- så anon kan sette TRUE uten ekstra policy-endring. Hvis ikke
-- sendt, faller den til DEFAULT FALSE.
--
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- ----- DIAGNOSE (read-only, FØR mutation) ---------------------
do $$
declare
  has_col boolean;
  row_count int;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='bookings'
       and column_name='newsletter_opt_in'
  ) into has_col;
  if has_col then
    raise notice 'newsletter_opt_in-kolonne finnes allerede — ALTER blir no-op.';
  else
    select count(*) into row_count from public.bookings;
    raise notice 'Legger til newsletter_opt_in BOOL DEFAULT FALSE på % bookings-rader (alle starter unchecked).', row_count;
  end if;
end $$;

-- ----- MUTATION -----------------------------------------------
alter table public.bookings
  add column if not exists newsletter_opt_in boolean not null default false;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--   select column_name, data_type, column_default, is_nullable
--     from information_schema.columns
--    where table_name='bookings' and column_name='newsletter_opt_in';
-- Forvent: 1 rad, boolean, default 'false', is_nullable='NO'.
--
--   select count(*) filter (where newsletter_opt_in = true) as opted_in,
--          count(*) as total
--     from public.bookings;
-- Forvent: opted_in = 0 (alle eksisterende har DEFAULT FALSE).
--
-- Smoke-test (etter frontend deploy):
--   gjør en testbooking med checkboxen krysset av →
--   select email, newsletter_opt_in from public.bookings
--    order by created_at desc limit 1;
-- Forvent: newsletter_opt_in = true.
--
-- For å hente alle opted-in:
--   select distinct lower(email) as email
--     from public.bookings
--    where newsletter_opt_in = true
--      and status <> 'cancelled';
-- ============================================================
