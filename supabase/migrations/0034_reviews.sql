-- ============================================================
-- Westengen Klinikk — Anmeldelser med manuell godkjenning
-- Migration 0034
-- ------------------------------------------------------------
-- P2 (2026-06-01): kundeanmeldelser som modereres før publisering.
--   - Publikum (anon) sender inn → havner ALLTID som status='pending'.
--   - Publikum (anon) leser KUN status='approved'.
--   - Admin (app_metadata.role='admin') ser alle + godkjenner/avviser
--     via UPDATE (status + approved_by/approved_at).
--
-- RLS-detalj: anon-INSERT har WITH CHECK (status='pending') slik at en
-- innsender ALDRI kan selv-publisere ved å sende status='approved'.
-- En anon kan i teordien sende med approved_by/approved_at, men det er
-- meningsløst på en pending-rad og overskrives ved faktisk godkjenning.
--
-- Idempotent (IF NOT EXISTS / drop policy if exists + create).
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- ----- TABELL ------------------------------------------------
create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  rating      int  not null check (rating between 1 and 5),
  body        text,
  created_at  timestamptz not null default now(),
  status      text not null default 'pending'
              check (status in ('pending', 'approved', 'rejected')),
  approved_by uuid,
  approved_at timestamptz
);

-- Rask oppslag for de to vanlige spørringene (anon: approved,
-- admin: pending), sortert nyeste først.
create index if not exists reviews_status_created_idx
  on public.reviews (status, created_at desc);

-- ----- RLS ---------------------------------------------------
alter table public.reviews enable row level security;

-- Anon kan sende inn — men ALLTID som pending (kan ikke selv-godkjenne).
drop policy if exists "reviews: anon insert pending" on public.reviews;
create policy "reviews: anon insert pending"
  on public.reviews for insert
  to anon
  with check (status = 'pending');

-- Anon kan KUN lese godkjente anmeldelser.
drop policy if exists "reviews: anon select approved" on public.reviews;
create policy "reviews: anon select approved"
  on public.reviews for select
  to anon
  using (status = 'approved');

-- Admin ser ALLE (inkl. pending/rejected) for moderering.
drop policy if exists "reviews: admin select all" on public.reviews;
create policy "reviews: admin select all"
  on public.reviews for select
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Admin kan godkjenne/avvise (UPDATE av status + approved_by/at).
drop policy if exists "reviews: admin update" on public.reviews;
create policy "reviews: admin update"
  on public.reviews for update
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- 1) Som anon (anon-nøkkel): INSERT med status='pending' skal lykkes;
--    INSERT med status='approved' skal AVVISES av WITH CHECK.
--      insert into reviews (name, rating, body) values ('Test', 5, 'Bra!');
--      → ok (status defaulter til pending).
--      insert into reviews (name, rating, body, status)
--        values ('X', 5, 'Snik', 'approved');  → 42501 / policy-feil.
--
-- 2) Som anon: SELECT returnerer KUN approved-rader.
--      select count(*) from reviews;  → kun godkjente synlige.
--
-- 3) Som admin: ser alle, kan UPDATE:
--      update reviews set status='approved', approved_at=now()
--        where id = '...';  → ok.
-- ============================================================
