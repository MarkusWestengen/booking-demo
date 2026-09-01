-- ============================================================
-- 0059_special_open_days.sql                          2026-06-20
-- ------------------------------------------------------------
-- ENGANGS LØRDAGSÅPNING (ingen gjentakelse). Lar admin åpne EN
-- konkret normalt-stengt dag (typisk en lørdag) for UTVALGTE
-- behandlere innenfor et satt tidsvindu. Booking-motoren stenger
-- helg KUN i frontend (HOURS i booking-engine.js har bare man–fre);
-- en rad her overstyrer den stengingen for (staff_id, date) og gir
-- åpningstider open_time..close_time den dagen.
--
--   - Én rad = én behandler på én konkret dato. Åpne for 3 behandlere
--     = 3 rader (upsert onConflict (date, staff_id)).
--   - Holiday vinner FORTSATT: booking-engine sjekker holidays før
--     special_open_days, så en klinikk-stengt dag forblir stengt.
--   - «Eriks terapeuter»-paraplyen (pool) påvirkes IKKE (Alt. 1):
--     kun direkte booking av navngitt behandler åpnes.
--
-- Sikkerhet (speiler blocked_slots 0057 + holidays 0018):
--   - anon: SELECT, men KOLONNE-GRANT på kun (staff_id, date,
--     open_time, close_time) — created_at lekker aldri til anon.
--   - admin: full skriving (insert/update/delete) via RLS role='admin'.
--   - therapist + admin: SELECT (kalender.html leser den).
-- bookings anon INSERT WITH CHECK (0052) har INGEN ukedag-sjekk og
-- tillater 06:00–22:00, så en lørdagsbooking innenfor vinduet passerer
-- allerede DB-laget — ingen bookings-policy-endring nødvendig.
--
-- Idempotent: create table/index if not exists, drop policy if exists
-- før create, revoke-all-først. Atomisk (begin/commit).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

create table if not exists public.special_open_days (
  date        date not null,
  staff_id    text not null,
  open_time   time not null,
  close_time  time not null,
  created_at  timestamptz not null default now(),
  primary key (date, staff_id)
);

create index if not exists special_open_days_date_idx
  on public.special_open_days(date);

alter table public.special_open_days enable row level security;

-- ----- Policyer (revoke-all-først-mønsteret) ------------------
drop policy if exists "special_open_days: anon read"   on public.special_open_days;
drop policy if exists "special_open_days read: staff"   on public.special_open_days;
drop policy if exists "special_open_days insert: admin"  on public.special_open_days;
drop policy if exists "special_open_days update: admin"  on public.special_open_days;
drop policy if exists "special_open_days delete: admin"  on public.special_open_days;

-- anon (booking-motoren) leser for å åpne dagen i slot-genereringen.
create policy "special_open_days: anon read"
  on public.special_open_days for select
  to anon
  using (true);

-- authenticated (kalender.html / admin-UI): admin + therapist kan lese.
create policy "special_open_days read: staff"
  on public.special_open_days for select
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin', 'therapist'));

-- Skriving er admin-only (samme nivå som holidays «steng hele klinikken»).
create policy "special_open_days insert: admin"
  on public.special_open_days for insert
  to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "special_open_days update: admin"
  on public.special_open_days for update
  to authenticated
  using   (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "special_open_days delete: admin"
  on public.special_open_days for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

-- ----- Grants: revoke-all-først, så minste nødvendige -----------
revoke all on public.special_open_days from anon, authenticated;
-- anon: KUN disse kolonnene (created_at holdes tilbake).
grant select (staff_id, date, open_time, close_time) on public.special_open_days to anon;
grant select, insert, update, delete on public.special_open_days to authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) 5 policies:
--    select policyname, cmd from pg_policies
--     where schemaname='public' and tablename='special_open_days'
--     order by policyname;
--
-- B) Grants (anon = kun de 4 kolonnene; authenticated = alt):
--    select grantee, privilege_type, column_name
--      from information_schema.role_column_grants
--     where table_schema='public' and table_name='special_open_days'
--       and grantee='anon' order by column_name;
--
-- C) Ende-til-ende:
--    - Som ADMIN i stengte-tider.html «Åpne en enkelt lørdag»: velg en
--      lørdag, kryss av behandler(e), sett 09:00–14:00 → lagre.
--    - Kunde i bestilling.html: velg den behandleren → lørdagen vises
--      som bookbar (kun innenfor vinduet); andre lørdager forblir stengt.
--    - Admin-kalender (kalender.html): lørdagen viser ledige slots for
--      de valgte behandlerne.
--    - «Eriks terapeuter» (pool) viser fortsatt lørdagen som stengt.
-- ============================================================
