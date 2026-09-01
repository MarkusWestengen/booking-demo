-- ============================================================
-- Westengen Klinikk — Audit log (append-only)
-- Migration 0002
-- ------------------------------------------------------------
-- Sporbarhet for sensitive handlinger. Tabellen er strikt
-- append-only: ingen UPDATE- eller DELETE-policy = umulig å
-- endre historikken via API. Selv admin kan kun lese.
--
-- VIKTIG: ingen rådata (journal-innhold, navn, e-post, telefon)
-- skal noensinne havne i denne tabellen. Bare ID-er og status-
-- transisjoner. Frontend håndhever dette, men gjør gjerne
-- spot-checks av eksisterende rader i pg_admin etter behov.
-- ============================================================

create table if not exists public.audit_log (
  id               uuid primary key default gen_random_uuid(),
  actor_staff_id   text not null,
  actor_staff_name text not null,
  action           text not null,        -- f.eks. 'journal_view', 'journal_create', 'booking_status_change'
  target_type      text not null,        -- 'journal_entry' | 'booking' | 'patient'
  target_id        text,                 -- id eller patient_email (for patient-nivå)
  metadata         jsonb,                -- f.eks. { "from_status": "confirmed", "to_status": "completed" }
  created_at       timestamptz not null default now()
);

create index if not exists audit_log_actor_idx
  on public.audit_log(actor_staff_id, created_at desc);
create index if not exists audit_log_target_idx
  on public.audit_log(target_type, target_id);
create index if not exists audit_log_action_idx
  on public.audit_log(action, created_at desc);

-- ============================================================
-- Row-Level Security
-- ============================================================
alter table public.audit_log enable row level security;

drop policy if exists "audit: admin can read"               on public.audit_log;
drop policy if exists "audit: authenticated can insert own" on public.audit_log;

-- Bare admin (Markus / Henrik) får lese audit-loggen.
create policy "audit: admin can read"
  on public.audit_log for select
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- Innloggede ansatte kan kun logge på vegne av seg selv.
-- Admin uten staff_id i app_metadata får skrive med vilkårlig
-- actor_staff_id (de er likevel admin og audit-trailen viser
-- det via actor_staff_name).
create policy "audit: authenticated can insert own"
  on public.audit_log for insert
  to authenticated
  with check (
    actor_staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- INGEN update- eller delete-policy = tabellen er append-only.
-- ============================================================
-- Sanity check etter migrasjon:
--   select * from pg_policies where tablename = 'audit_log';
-- Forventet: nøyaktig 2 policyer (read, insert). Ingen update/delete.
-- ============================================================
