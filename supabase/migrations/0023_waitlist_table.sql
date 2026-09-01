-- ============================================================
-- 0023_waitlist_table.sql                            2026-05-20
-- ------------------------------------------------------------
-- Venteliste: kunder kan melde seg på når ingen slots er ledige.
-- Separate køer for Erik (staff_id = 'erik') og Eriks terapeuter
-- (staff_id = NULL). Sekretær/admin tildeler manuelt fra
-- booking-admin → fanen "Venteliste". Auto-tildeling med e-post
-- er et senere spor (krever verifisert Resend-domene).
--
-- Designvalg (avklart med Markus):
--   - service_id er NULLABLE: ventelista opererer på staff-gruppe-
--     nivå; konkret tjeneste velges av admin ved tildeling.
--   - RLS er admin-only for SELECT/UPDATE/DELETE (ingen therapist-
--     gren — ventelista forvaltes av sekretær). anon kan INSERT.
--   - RLS bruker 0018-wrap-mønsteret ((select auth.jwt()) -> ...).
--   - status har CHECK-constraint.
--   - cancel_waitlist_by_ref: ingen 24t-frist (kan meldes av når
--     som helst), markerer status='cancelled', uniform not_found.
--
-- Idempotent: create table/index/policy if (not) exists, create
-- or replace function. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ----- waitlist-tabell ----------------------------------------
create table if not exists public.waitlist (
  id                  uuid primary key default gen_random_uuid(),
  ref                 text not null unique,              -- TA-WL-XXXX-XXXX
  service_id          text,                              -- NULL: velges ved tildeling
  staff_id            text,                              -- 'erik' = Erik-køen, NULL = terapeut-køen
  staff_name          text not null,                     -- "Erik Westengen" / "Eriks terapeuter"
  name                text not null,
  email               text not null,
  phone               text not null,
  preferred_date_from date not null,
  preferred_date_to   date,                              -- NULL = fleksibel
  preferred_time_from time,                              -- NULL = når som helst
  preferred_time_to   time,
  notes               text default '',
  status              text not null default 'waiting'
    check (status in ('waiting','offered','accepted','declined','cancelled','expired')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Partial indeks for FIFO-kø innenfor hver staff_id-gruppe.
create index if not exists idx_waitlist_queue
  on public.waitlist (staff_id, created_at)
  where status = 'waiting';

-- updated_at-trigger (samme mønster som services, 0008).
create or replace function public._waitlist_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists waitlist_set_updated_at on public.waitlist;
create trigger waitlist_set_updated_at
  before update on public.waitlist
  for each row execute function public._waitlist_set_updated_at();

-- ----- Grants + RLS -------------------------------------------
-- Eksplisitte grants (RLS gater fortsatt alt — begge må tillate).
grant insert                   on public.waitlist to anon;
grant select, update, delete   on public.waitlist to authenticated;

alter table public.waitlist enable row level security;

drop policy if exists "anon insert waitlist"   on public.waitlist;
drop policy if exists "Waitlist read: admin"   on public.waitlist;
drop policy if exists "Waitlist update: admin" on public.waitlist;
drop policy if exists "Waitlist delete: admin" on public.waitlist;

-- Anon kan melde seg på ventelista. service_id er IKKE påkrevd.
create policy "anon insert waitlist"
  on public.waitlist
  for insert
  to anon
  with check (
        status = 'waiting'
    and length(coalesce(name,  '')) > 0
    and length(coalesce(email, '')) > 0
    and length(coalesce(phone, '')) > 0
    and preferred_date_from is not null
  );

-- Admin leser/oppdaterer/sletter alt. Ingen therapist-gren —
-- ventelista forvaltes av sekretær/admin.
create policy "Waitlist read: admin"
  on public.waitlist
  for select
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "Waitlist update: admin"
  on public.waitlist
  for update
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "Waitlist delete: admin"
  on public.waitlist
  for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

-- ----- cancel_waitlist_by_ref RPC -----------------------------
-- Parallell til 0022 sin cancel_booking_by_ref, men uten 24t-frist
-- (en venteliste-oppføring kan meldes av når som helst).
create or replace function public.cancel_waitlist_by_ref(
  p_ref   text,
  p_email text
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  w public.waitlist%rowtype;
begin
  select * into w
    from public.waitlist
   where ref = p_ref
     and lower(email) = lower(coalesce(p_email, ''))
   limit 1;

  -- Uniform not_found (ukjent ref ELLER feil e-post) — ingen oracle.
  if not found then
    return json_build_object('ok', false, 'reason', 'not_found');
  end if;

  if w.status = 'cancelled' then
    return json_build_object('ok', false, 'reason', 'already_cancelled');
  end if;

  if w.status = 'accepted' then
    return json_build_object('ok', false, 'reason', 'already_accepted');
  end if;

  update public.waitlist set status = 'cancelled' where id = w.id;

  return json_build_object('ok', true, 'ref', w.ref, 'staff_name', w.staff_name);
end;
$$;

comment on function public.cancel_waitlist_by_ref(text, text) is
  'Kunde-avmelding fra ventelista via venteliste.html. Verifiserer '
  '(ref, e-post), setter status=cancelled. Ingen tidsfrist. '
  'not_found returneres uniformt (ingen oracle). Migrasjon 0023.';

revoke execute on function public.cancel_waitlist_by_ref(text, text) from public;
grant  execute on function public.cancel_waitlist_by_ref(text, text) to anon, authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Tabellen finnes:
--    select tablename from pg_tables
--     where schemaname='public' and tablename='waitlist';      -- 1 rad
--
-- B) RLS er på + 4 policies:
--    select policyname, cmd from pg_policies
--     where schemaname='public' and tablename='waitlist'
--     order by policyname;
--    -- Forvent: anon insert waitlist (INSERT),
--    --          Waitlist read/update/delete: admin
--
-- C) cancel-RPC kallbar av anon:
--    select has_function_privilege(
--      'anon', 'public.cancel_waitlist_by_ref(text,text)', 'execute');  -- t
--
-- D) Uniform not_found:
--    select public.cancel_waitlist_by_ref('TA-WL-FINNES-IKKE', 'x@y.example');
--    -- {"ok":false,"reason":"not_found"}
-- ============================================================
