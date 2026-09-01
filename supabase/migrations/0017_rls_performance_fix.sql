-- ============================================================
-- 0017_rls_performance_fix.sql                       2026-05-15
-- ------------------------------------------------------------
-- Lukker 31 Performance Advisor-WARN i Supabase Dashboard:
--   • 23 × auth_rls_initplan — RLS-policyer som kaller auth.uid() /
--     auth.jwt() / current_setting() direkte re-evalueres per rad.
--     Fix: wrap kallene i (select ...) så Postgres cacher dem som
--     InitPlan og evaluerer én gang per query.
--   • 8 × multiple_permissive_policies — overlappende Admin+Therapist-
--     policies på samme rolle+action evalueres begge før Postgres OR'er.
--     Fix: konsolider til ÉN permissive policy per action med OR-clause.
--
-- INGEN SEMANTISK ENDRING. Hver brukerrolles tilgang er identisk
-- før/etter. Dette er kun en ytelses-refaktor.
--
-- ⚠️ DRIFT-WARNING — blocked_slots + holidays:
-- De fire policiene under finnes IKKE i migrasjons-historikken
-- (0001-0016) — de er manuelt opprettet i Dashboard:
--     - "Admin manage blocked"        (blocked_slots, FOR ALL)
--     - "Therapist manage own blocked" (blocked_slots, FOR ALL)
--     - "Admin manage holidays"       (holidays, FOR ALL)
--     - "Therapist read holidays"     (holidays, FOR SELECT)
--
-- Denne migrasjonen ANTAR at uttrykkene følger samme standard som
-- bookings/journal/audit-policiene:
--     admin-check:    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
--     therapist-own:  role='therapist' AND staff_id = jwt-staff_id
--
-- KJØR DENNE READ-ONLY SQL FØR APPLY for å verifisere mot prod-state:
--     select policyname, cmd, qual, with_check
--       from pg_policies
--      where schemaname = 'public'
--        and tablename in ('blocked_slots', 'holidays')
--      order by tablename, policyname;
--
-- Hvis et uttrykk avviker fra antagelsen: ikke appliser denne
-- migrasjonen ennå — flagg til Claude/operator + tilpass før apply.
--
-- Idempotent: hver policy gjenskapes via drop if exists → create.
-- ============================================================

begin;

-- ============================================================
-- (1) bookings — konsolider Admin/Therapist på SELECT/INSERT/UPDATE
--     + wrap auth.* i (select ...). DELETE forblir admin-only.
-- ------------------------------------------------------------
-- Eksisterende policies fra 0012:
--   "Admin read all bookings"        (SELECT, admin-only)
--   "Admin insert bookings"          (INSERT, admin-only)
--   "Admin update bookings"          (UPDATE, admin-only)
--   "Admin delete bookings"          (DELETE, admin-only)
--   "Therapist read own bookings"    (SELECT, therapist + staff_id-match)
--   "Therapist insert own bookings"  (INSERT, therapist + staff_id-match)
--   "Therapist update own bookings"  (UPDATE, therapist + staff_id-match)
-- (Therapist har bevisst INGEN DELETE — medisinsk historikk er
--  append-only for terapeut; admin har nødåpning.)
--
-- Konsolidert: 3 nye SELECT/INSERT/UPDATE-policies med OR-clause
-- + uendret Admin delete bookings (men wrappet auth.jwt).
-- ============================================================

drop policy if exists "Admin read all bookings"       on public.bookings;
drop policy if exists "Admin insert bookings"         on public.bookings;
drop policy if exists "Admin update bookings"         on public.bookings;
drop policy if exists "Admin delete bookings"         on public.bookings;
drop policy if exists "Therapist read own bookings"   on public.bookings;
drop policy if exists "Therapist insert own bookings" on public.bookings;
drop policy if exists "Therapist update own bookings" on public.bookings;
-- Også drop eventuelle tidligere konsoliderte navn (idempotent ved re-apply):
drop policy if exists "Bookings read: admin or own"   on public.bookings;
drop policy if exists "Bookings insert: admin or own" on public.bookings;
drop policy if exists "Bookings update: admin or own" on public.bookings;
drop policy if exists "Bookings delete: admin"        on public.bookings;

create policy "Bookings read: admin or own"
  on public.bookings for select
  to authenticated
  using (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (select auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    )
  );

create policy "Bookings insert: admin or own"
  on public.bookings for insert
  to authenticated
  with check (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (select auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    )
  );

create policy "Bookings update: admin or own"
  on public.bookings for update
  to authenticated
  using (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (select auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    )
  )
  with check (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (select auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    )
  );

create policy "Bookings delete: admin"
  on public.bookings for delete
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (2) journal_entries — wrap auth.jwt. Ingen konsolidering
--     (hver policy treffer forskjellig action).
-- ------------------------------------------------------------
-- "journal: staff can read all" har using (true) — ingen auth.*-kall,
-- ingen wrap nødvendig. Lar den stå urørt.
-- ============================================================

drop policy if exists "journal: staff can insert"     on public.journal_entries;
drop policy if exists "journal: staff can update own" on public.journal_entries;
drop policy if exists "journal: admin can delete"     on public.journal_entries;

create policy "journal: staff can insert"
  on public.journal_entries for insert
  to authenticated
  with check (
    staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "journal: staff can update own"
  on public.journal_entries for update
  to authenticated
  using (
    staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  )
  with check (
    staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "journal: admin can delete"
  on public.journal_entries for delete
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (3) blocked_slots — konsolider Admin+Therapist FOR ALL til
--     ÉN FOR ALL med OR-clause.
-- ------------------------------------------------------------
-- ⚠️ UKJENT MIGRASJONS-HISTORIE — antar standard role-pattern.
-- Eksisterende FOR ALL-policies skapte 4 × multiple_permissive
-- WARN (én per command). Konsolidert FOR ALL eliminerer alle.
--
-- Semantikk: admin har full tilgang, therapist har full tilgang
-- til egne (staff_id-match), anon har ingen tilgang (ingen anon-
-- policy = default-deny).
-- ============================================================

drop policy if exists "Admin manage blocked"         on public.blocked_slots;
drop policy if exists "Therapist manage own blocked" on public.blocked_slots;
drop policy if exists "Blocked slots: admin or own"  on public.blocked_slots;

create policy "Blocked slots: admin or own"
  on public.blocked_slots for all
  to authenticated
  using (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (select auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    )
  )
  with check (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
    or (
      (select auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
      and staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    )
  );


-- ============================================================
-- (4) holidays — konsolider SELECT (Admin+Therapist), splitt
--     write til admin-only.
-- ------------------------------------------------------------
-- ⚠️ UKJENT MIGRASJONS-HISTORIE — antar standard role-pattern.
-- Eksisterende:
--   "Admin manage holidays"  (FOR ALL, admin)
--   "Therapist read holidays" (SELECT, therapist)
-- → multiple_permissive på SELECT (overlapp).
--
-- Konsolidert:
--   SELECT: admin OR therapist (begge ser helligdager — de gjelder
--           hele klinikken, ingen staff_id-distinksjon nødvendig)
--   INSERT/UPDATE/DELETE: admin-only (bevarer originalt mønster der
--           kun admin kan endre helligdager).
-- holidays-tabellen har bare én kolonne (date) — ingen staff_id å
-- filtrere på.
-- ============================================================

drop policy if exists "Admin manage holidays"            on public.holidays;
drop policy if exists "Therapist read holidays"          on public.holidays;
drop policy if exists "Holidays read: admin or therapist" on public.holidays;
drop policy if exists "Holidays insert: admin"           on public.holidays;
drop policy if exists "Holidays update: admin"           on public.holidays;
drop policy if exists "Holidays delete: admin"           on public.holidays;

create policy "Holidays read: admin or therapist"
  on public.holidays for select
  to authenticated
  using (
    (select auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'therapist')
  );

create policy "Holidays insert: admin"
  on public.holidays for insert
  to authenticated
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "Holidays update: admin"
  on public.holidays for update
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "Holidays delete: admin"
  on public.holidays for delete
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (5) audit_log — wrap auth.jwt. Ingen konsolidering (én policy
--     per action). "audit: anon can insert login_failed" har
--     ingen auth.*-kall → urørt.
-- ============================================================

drop policy if exists "audit: admin can read"                on public.audit_log;
drop policy if exists "audit: authenticated can insert own"  on public.audit_log;

create policy "audit: admin can read"
  on public.audit_log for select
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "audit: authenticated can insert own"
  on public.audit_log for insert
  to authenticated
  with check (
    actor_staff_id = (select auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );


-- ============================================================
-- (6) services — wrap auth.jwt. Ingen konsolidering — anon og
--     authenticated SELECT-policies targeter forskjellige roller
--     (ingen multiple_permissive).
-- ------------------------------------------------------------
-- "services: anon select active" har ingen auth.*-kall → urørt.
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
    or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "services: admin insert"
  on public.services for insert
  to authenticated
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "services: admin update"
  on public.services for update
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "services: admin delete"
  on public.services for delete
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');


-- ============================================================
-- (7) staff_services — wrap auth.jwt. Ingen konsolidering —
--     "auth select" har using (true), og anon-policy targeter
--     forskjellig rolle.
-- ============================================================

drop policy if exists "staff_services: admin insert" on public.staff_services;
drop policy if exists "staff_services: admin update" on public.staff_services;
drop policy if exists "staff_services: admin delete" on public.staff_services;

create policy "staff_services: admin insert"
  on public.staff_services for insert
  to authenticated
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "staff_services: admin update"
  on public.staff_services for update
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "staff_services: admin delete"
  on public.staff_services for delete
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');


commit;

-- ============================================================
-- Verifikasjon — kjør disse manuelt i SQL Editor etter apply:
--
-- A) Policy-telling per tabell (sanity-check):
--    select tablename, count(*) as n
--      from pg_policies
--     where schemaname = 'public'
--       and tablename in ('bookings','journal_entries','blocked_slots',
--                         'holidays','audit_log','services','staff_services')
--     group by tablename order by tablename;
--    Forventet:
--       audit_log       | 3   (anon login_failed + admin read + auth insert own)
--       blocked_slots   | 1   (én konsolidert FOR ALL)
--       bookings        | 5   (anon insert + 4 konsoliderte/admin-only)
--       holidays        | 4   (read + 3 admin write)
--       journal_entries | 4   (read all + insert + update own + admin delete)
--       services        | 5   (anon select + auth select + 3 admin write)
--       staff_services  | 5   (anon select + auth select + 3 admin write)
--
-- B) Per-tabell visuell sjekk:
--    select policyname, cmd, qual, with_check
--      from pg_policies where schemaname='public' and tablename='<tabellen>'
--      order by policyname;
--
-- C) Re-kjør Supabase Performance Advisor → forventet 0 WARN i
--    auth_rls_initplan + multiple_permissive_policies-kategoriene.
--
-- D) Re-kjør supabase/tests/01_rls_policies.sql → alle PASS.
-- ============================================================
