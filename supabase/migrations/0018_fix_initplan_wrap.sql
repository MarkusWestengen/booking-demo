-- ============================================================
-- 0018_fix_initplan_wrap.sql                         2026-05-15
-- ------------------------------------------------------------
-- Korrigerer wrap-mønsteret introdusert i 0017. Supabase
-- Performance Advisor flagger fortsatt 21 × auth_rls_initplan
-- etter 0017-apply fordi SELECT-wrappingen omfattet HELE
-- chain-uttrykket istedenfor kun `auth.jwt()`-kallet:
--
--   FEIL (0017):  (SELECT auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
--   RETT (0018): ((SELECT auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
--
-- Forskjellen: Planner/Linter ser kun auth.jwt() som InitPlan-
-- cached når SELECT-en wrapper akkurat funksjons-kallet —
-- chain-operatorene (`->`, `->>`) må ligge UTENFOR SELECTen.
-- Med 0017s mønster ble auth.jwt() fortsatt evaluert per rad
-- selv om SELECT-en var der.
--
-- INGEN SEMANTISK ENDRING. Hver brukerrolles tilgang er identisk
-- før/etter — kun parse-tree-strukturen rundt SELECTen flyttes.
--
-- Idempotent: drop policy if exists → create.
-- Atomic via begin/commit (én transaksjon).
--
-- 0017's konsolidering (multiple_permissive-fix) er bevart.
-- ============================================================

begin;

-- ============================================================
-- (1) bookings — 4 policies
-- ============================================================

drop policy if exists "Bookings read: admin or own"   on public.bookings;
drop policy if exists "Bookings insert: admin or own" on public.bookings;
drop policy if exists "Bookings update: admin or own" on public.bookings;
drop policy if exists "Bookings delete: admin"        on public.bookings;

create policy "Bookings read: admin or own"
  on public.bookings for select
  to authenticated
  using (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    )
  );

create policy "Bookings insert: admin or own"
  on public.bookings for insert
  to authenticated
  with check (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    )
  );

create policy "Bookings update: admin or own"
  on public.bookings for update
  to authenticated
  using (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    )
  )
  with check (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    )
  );

create policy "Bookings delete: admin"
  on public.bookings for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (2) journal_entries — 3 policies
-- ============================================================

drop policy if exists "journal: staff can insert"     on public.journal_entries;
drop policy if exists "journal: staff can update own" on public.journal_entries;
drop policy if exists "journal: admin can delete"     on public.journal_entries;

create policy "journal: staff can insert"
  on public.journal_entries for insert
  to authenticated
  with check (
    staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    or ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "journal: staff can update own"
  on public.journal_entries for update
  to authenticated
  using (
    staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    or ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  )
  with check (
    staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    or ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "journal: admin can delete"
  on public.journal_entries for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (3) blocked_slots — 1 policy (konsolidert FOR ALL fra 0017)
-- ============================================================

drop policy if exists "Blocked slots: admin or own" on public.blocked_slots;

create policy "Blocked slots: admin or own"
  on public.blocked_slots for all
  to authenticated
  using (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    )
  )
  with check (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    )
  );


-- ============================================================
-- (4) holidays — 4 policies (read for begge, write admin-only)
-- ============================================================

drop policy if exists "Holidays read: admin or therapist" on public.holidays;
drop policy if exists "Holidays insert: admin"            on public.holidays;
drop policy if exists "Holidays update: admin"            on public.holidays;
drop policy if exists "Holidays delete: admin"            on public.holidays;

create policy "Holidays read: admin or therapist"
  on public.holidays for select
  to authenticated
  using (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin', 'therapist')
  );

create policy "Holidays insert: admin"
  on public.holidays for insert
  to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "Holidays update: admin"
  on public.holidays for update
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "Holidays delete: admin"
  on public.holidays for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (5) audit_log — 2 policies (anon login_failed urørt)
-- ============================================================

drop policy if exists "audit: admin can read"               on public.audit_log;
drop policy if exists "audit: authenticated can insert own" on public.audit_log;

create policy "audit: admin can read"
  on public.audit_log for select
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "audit: authenticated can insert own"
  on public.audit_log for insert
  to authenticated
  with check (
    actor_staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
    or ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );


-- ============================================================
-- (6) services — 4 policies (anon select urørt)
-- ============================================================

drop policy if exists "services: auth select active" on public.services;
drop policy if exists "services: admin insert"       on public.services;
drop policy if exists "services: admin update"       on public.services;
drop policy if exists "services: admin delete"       on public.services;

create policy "services: auth select active"
  on public.services for select
  to authenticated
  using (
    is_active = true
    or ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "services: admin insert"
  on public.services for insert
  to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "services: admin update"
  on public.services for update
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "services: admin delete"
  on public.services for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (7) staff_services — 3 policies (anon select + auth select urørt)
-- ============================================================

drop policy if exists "staff_services: admin insert" on public.staff_services;
drop policy if exists "staff_services: admin update" on public.staff_services;
drop policy if exists "staff_services: admin delete" on public.staff_services;

create policy "staff_services: admin insert"
  on public.staff_services for insert
  to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "staff_services: admin update"
  on public.staff_services for update
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "staff_services: admin delete"
  on public.staff_services for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');


commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Spot-sjekk én policy — qual skal vise ((SELECT auth.jwt()) -> ...):
--    select policyname, qual
--      from pg_policies
--     where schemaname='public'
--       and policyname = 'Bookings read: admin or own';
--    Forventet: qual inneholder ((SELECT auth.jwt()) -> 'app_metadata' ...
--
-- B) Re-run Performance Advisor → forventet 0 WARN i auth_rls_initplan.
--    (multiple_permissive_policies-WARN'ene er allerede 0 fra 0017.)
--
-- C) Re-kjør supabase/tests/01_rls_policies.sql → alle PASS.
--    Test-suiten ble IKKE endret av 0018; det er beviset på at
--    semantikk er bevart.
-- ============================================================
