-- ============================================================
-- 0057_c_med_defense_hardening.sql                   2026-06-13
-- ------------------------------------------------------------
-- Samler fire mindre funn fra security-review-2026-06-12 som hører
-- til samme defense-in-depth-runde:
--
--   (a) [A-MEDIUM/verifiser] RLS-enable på bookings/blocked_slots/
--       holidays var aldri versjonskontrollert (tabellene ble
--       opprettet i Dashboard/den gamle oppsettsguiden). `enable row level
--       security` er idempotent — etter dette er ønsket tilstand
--       kodefestet. NB: krever at anon får eksplisitte SELECT-
--       policyer på blocked_slots/holidays (laget her i (c)) siden
--       bootstrap-policyene droppes.
--
--   (b) [C-MEDIUM] den gamle oppsettsguiden (nå 0000_base_schema.sql) sine bootstrap-policyer
--       «anon all blocked»/«anon all holidays» (FOR ALL, true/true)
--       ble aldri droppet. Skriving var nøytralisert av grant-
--       revoke (0027), men én fremtidig grant-glipp ville re-åpnet
--       anon-skriving. Droppes her.
--
--   (c) [C-MEDIUM] blocked_slots.description var lesbar for anon
--       (grant select på hele tabellen + select=* i booking-engine)
--       — fritekst om ansattes fravær/årsak lekket til hvem som
--       helst med anon-nøkkelen. Nå: kolonne-grant på KUN
--       (staff_id, date, time) + eksplisitt anon-SELECT-policy.
--       FRONTEND-IMPLIKASJON (samme commit): booking-engine.js
--       getBlocked() bytter select=* → select=staff_id,date,time
--       (select=* gir permission denied med kolonne-grant).
--
--   (d) [B-LAV] audit_log append-only hvilte kun på fravær av
--       UPDATE/DELETE-policy. Nå trekkes grantsene eksplisitt —
--       to uavhengige lag. (gdpr_erase_patient (0053) er SECURITY
--       DEFINER og påvirkes ikke.)
--
-- Idempotent: enable RLS, drop/create policy, revoke/grant.
-- Atomisk (begin/commit).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ============================================================
-- (a) Versjonskontrollert RLS-enable (idempotente no-ops hvis på)
-- ============================================================
alter table public.bookings      enable row level security;
alter table public.blocked_slots enable row level security;
alter table public.holidays      enable row level security;

-- ============================================================
-- (b) Dropp stale bootstrap-policyer fra den gamle oppsettsguiden (nå 0000_base_schema.sql)
-- ============================================================
drop policy if exists "anon all blocked"  on public.blocked_slots;
drop policy if exists "anon all holidays" on public.holidays;

-- ============================================================
-- (c) anon-lesing: eksplisitte SELECT-policyer + kolonne-grant
-- ------------------------------------------------------------
-- Booking-flyten (anon) trenger blocked_slots (hvilke slots er
-- sperret) og holidays (stengte dager) — men ALDRI description-
-- fritekst. Policyene erstatter bootstrap-policyene som (b) droppet;
-- uten dem ville (a) gjort tilgjengelighets-kallene tomme.
-- ============================================================
drop policy if exists "blocked_slots: anon read" on public.blocked_slots;
create policy "blocked_slots: anon read"
  on public.blocked_slots for select
  to anon
  using (true); -- radnivå åpent; kolonnenivå strammes av grant under

drop policy if exists "holidays: anon read" on public.holidays;
create policy "holidays: anon read"
  on public.holidays for select
  to anon
  using (true);

-- Kolonne-grant: anon ser KUN det availability-logikken trenger.
revoke select on public.blocked_slots from anon;
grant select (staff_id, date, "time") on public.blocked_slots to anon;

-- holidays beholder tabell-grant fra 0027 (kun dato-rader, ingen fritekst-
-- kolonne i bruk av anon-flyten) — idempotent re-assert:
grant select on public.holidays to anon;

-- ============================================================
-- (d) audit_log: eksplisitt append-only på grant-laget
-- ============================================================
revoke update, delete, truncate on public.audit_log from anon, authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) RLS på (V2 fra revisjonen):
--    select relname, relrowsecurity from pg_class
--     where relname in ('bookings','blocked_slots','holidays');
--    -- Forvent: alle t.
--
-- B) Stale policyer borte + nye anon-read finnes (V8):
--    select tablename, policyname, cmd, roles from pg_policies
--     where schemaname='public' and tablename in ('blocked_slots','holidays')
--     order by tablename, policyname;
--    -- Forvent: INGEN 'anon all %'; 'blocked_slots: anon read' og
--    --          'holidays: anon read' finnes.
--
-- C) Kolonne-grant virker (anon REST):
--    GET /rest/v1/blocked_slots?select=staff_id,date,time  → 200
--    GET /rest/v1/blocked_slots?select=*                   → 4xx permission denied
--    (booking-engine.js er oppdatert til kolonnelisten i samme commit)
--
-- D) audit_log-grants:
--    select grantee, privilege_type from information_schema.role_table_grants
--     where table_name='audit_log' and grantee in ('anon','authenticated');
--    -- Forvent: anon=INSERT, authenticated=INSERT,SELECT — ingen UPDATE/DELETE.
--
-- E) Booking-siden (bestilling.html, anon): tilgjengelighet laster
--    fortsatt — sperrede slots/helligdager respekteres.
-- ============================================================
