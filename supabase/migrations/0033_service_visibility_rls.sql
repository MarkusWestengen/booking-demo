-- ============================================================
-- Westengen Klinikk — RLS-håndheving av is_public for anon
-- Migration 0033
-- ------------------------------------------------------------
-- Følger 0032 (som la til kolonnen `services.is_public boolean
-- DEFAULT true`). 0032 håndhevet synlighet KUN via klient-query
-- i shared/services.js (is_public=eq.true). Det er ikke nok:
-- anon-rollen kan kjøre `?is_active=eq.true&is_public=eq.false`
-- direkte mot PostgREST og fortsatt se interne tjenester, fordi
-- anon-SELECT-policyen fra 0008 kun sjekket `is_active = true`.
--
-- Denne migrasjonen strammer de to ANON-policyene slik at en
-- intern tjeneste (is_active=true, is_public=false) er usynlig
-- for anon på DB-nivå:
--   services        : anon ser kun is_active=true AND is_public=true
--   staff_services  : anon ser kobling kun for slike tjenester
--                     (ellers lekker service_id/staff_id for interne)
--
-- UENDRET (bevisst):
--   - authenticated/admin-policyene (0008 + 0017/0018) — innlogget
--     intern flyt ser fortsatt ALLE tjenester (inkl. interne).
--   - is_active-semantikken (deaktiverte tjenester skjules som før).
--
-- 0017/0018 rørte kun auth/admin-policyene; anon-policyene står
-- fortsatt slik 0008 definerte dem — derfor dropper/gjenoppretter
-- vi her trygt mot den definisjonen.
--
-- Idempotent: drop policy if exists + create. Trygg å re-kjøre.
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- ----- DIAGNOSE (read-only, FØR mutation) ---------------------
do $$
declare
  internal_count int;
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='services'
       and column_name='is_public'
  ) then
    raise exception 'services.is_public mangler — kjør 0032 først.';
  end if;
  select count(*) into internal_count
    from public.services
   where is_active = true and is_public = false;
  raise notice 'Interne tjenester (is_active=true, is_public=false) som nå skjules for anon: %', internal_count;
end $$;

-- ----- services: anon ser kun offentlige + aktive -------------
drop policy if exists "services: anon select active" on public.services;

create policy "services: anon select active"
  on public.services for select
  to anon
  using (is_active = true and is_public = true);

-- ----- staff_services: anon ser kobling kun for offentlige ----
-- Uten is_public-sjekken her ville anon kunne lese service_id +
-- staff_id for interne tjenester via join-tabellen.
drop policy if exists "staff_services: anon select active" on public.staff_services;

create policy "staff_services: anon select active"
  on public.staff_services for select
  to anon
  using (exists (
    select 1 from public.services s
    where s.id = staff_services.service_id
      and s.is_active = true
      and s.is_public = true
  ));

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- 1) Som anon (anon-nøkkel) skal interne tjenester være borte:
--      GET /rest/v1/services?select=slug,is_active,is_public&is_public=eq.false
--      → forventet: 0 rader (selv om is_active=true).
--
-- 2) Offentlig booking-flyt uendret:
--      GET /rest/v1/services?select=*&is_active=eq.true&is_public=eq.true
--      → samme antall som før.
--
-- 3) Innlogget admin/terapeut ser fortsatt ALT (uendret policy):
--      select slug, is_active, is_public from public.services order by sort_order;
--
-- Røyktest av skjuling:
--      update public.services set is_public = false where slug = 'tom-test';
--      → anon mister både services-raden OG staff_services-koblingen;
--        innlogget intern flyt ser den fortsatt.
-- ============================================================
