-- ============================================================
-- 0027_pre_deploy_security.sql                       2026-05-21
-- ------------------------------------------------------------
-- Pre-deploy sikkerhetsherding fra audit-2026-05-21:
--   P1-1  Skjerper anon insert bookings + UNIQUE på ref + email-indeks
--   P1-3  Skjerper anon insert waitlist
--   P2-1  Defense-in-depth: REVOKE unødvendige anon-grants (speiler 0010)
--   P2-2  Dropper stale alltid-sanne anon update/delete bookings-policyer
--
-- ⚠️ FORUTSETNING: Hvis prod har duplikate `bookings.ref`-verdier vil
--   ADD CONSTRAINT bookings_ref_unique feile (og rulle tilbake hele
--   migrasjonen). Sjekk FØR apply:
--     select ref, count(*) from public.bookings
--      group by ref having count(*) > 1;
--   Rydd evt. duplikater først.
--
-- Idempotent: DO-block-guard på constraint, IF NOT EXISTS, drop+create
-- policy, revoke/grant er naturlig idempotente. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ============================================================
-- P1-1: Skjerpe anon insert bookings + UNIQUE på ref
-- ============================================================

-- UNIQUE constraint på ref (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'bookings_ref_unique'
       and conrelid = 'public.bookings'::regclass
  ) then
    alter table public.bookings add constraint bookings_ref_unique unique (ref);
  end if;
end $$;

-- Indeks på email (audit P2-3 — cancel_booking_by_ref filtrerer på email)
create index if not exists bookings_email_idx
  on public.bookings (lower(email));

-- Skjerpet anon insert-policy: blokker system-felter, lengdebegrensninger
drop policy if exists "anon insert bookings" on public.bookings;
create policy "anon insert bookings" on public.bookings
  for insert to anon
  with check (
    status = 'confirmed'
    and length(coalesce(name, '')) between 1 and 200
    and length(coalesce(email, '')) between 3 and 254
    and length(coalesce(phone, '')) between 3 and 30
    and service_id is not null
    and date is not null
    and "time" is not null
    -- System-felter må ikke settes av anon
    and reminder_sent_at is null
    and (notes is null or length(notes) <= 2000)
    -- journal_consent må være ekte boolsk (ikke null)
    and journal_consent is not null
  );

-- ============================================================
-- P2-2: Drop stale anon update/delete policies (om de finnes)
-- ============================================================

drop policy if exists "anon update bookings" on public.bookings;
drop policy if exists "anon delete bookings" on public.bookings;

-- ============================================================
-- P1-3: Skjerpe anon insert waitlist
-- ============================================================

drop policy if exists "anon insert waitlist" on public.waitlist;
create policy "anon insert waitlist" on public.waitlist
  for insert to anon
  with check (
    status = 'waiting'
    and length(coalesce(name, '')) between 1 and 200
    and length(coalesce(email, '')) between 3 and 254
    and length(coalesce(phone, '')) between 3 and 30
    and preferred_date_from is not null
    and (notes is null or length(notes) <= 2000)
    and (staff_id is null or length(staff_id) <= 100)
  );

-- ============================================================
-- P2-1: Defense-in-depth — REVOKE unødvendige anon grants
-- Speiler mønsteret fra 0010 (bookings har bare INSERT).
-- Påvirker KUN anon-rollen; authenticated (admin/terapeut) urørt.
-- ============================================================

-- audit_log: kun INSERT (for login_failed-policyen)
revoke all on public.audit_log from anon;
grant insert on public.audit_log to anon;

-- blocked_slots: kun SELECT (booking-engine.js getBlocked leser denne)
revoke all on public.blocked_slots from anon;
grant select on public.blocked_slots to anon;

-- holidays: kun SELECT (booking-engine.js getHolidays leser denne)
revoke all on public.holidays from anon;
grant select on public.holidays to anon;

-- journal_entries: INGEN anon-tilgang
revoke all on public.journal_entries from anon;

-- services: kun SELECT (services.js loadActiveServices)
revoke all on public.services from anon;
grant select on public.services to anon;

-- staff_services: kun SELECT (services.js loadStaffMap)
revoke all on public.staff_services from anon;
grant select on public.staff_services to anon;

-- waitlist: kun INSERT (anon kan kun bli med, ikke se eller endre)
revoke all on public.waitlist from anon;
grant insert on public.waitlist to anon;

-- bookings: kun INSERT (allerede strammet i 0010 — idempotent revoke)
revoke all on public.bookings from anon;
grant insert on public.bookings to anon;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) UNIQUE-constraint på ref finnes:
--    select conname from pg_constraint
--     where conname = 'bookings_ref_unique';                  -- 1 rad
--
-- B) Skjerpet anon-policy aktiv:
--    select with_check from pg_policies
--     where tablename='bookings' and policyname='anon insert bookings';
--    -- skal inneholde "reminder_sent_at IS NULL"
--
-- C) Stale policyer borte:
--    select policyname from pg_policies where tablename='bookings'
--     and policyname in ('anon update bookings','anon delete bookings');
--    -- 0 rader
--
-- D) Anon-grants strammet:
--    select table_name, string_agg(privilege_type, ', ' order by privilege_type)
--      from information_schema.role_table_grants
--     where grantee='anon' and table_schema='public'
--     group by table_name order by table_name;
--    -- Forvent: bookings=INSERT, waitlist=INSERT, audit_log=INSERT,
--    --          blocked_slots/holidays/services/staff_services=SELECT,
--    --          journal_entries=(ingen rad)
-- ============================================================
