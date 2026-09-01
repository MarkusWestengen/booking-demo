-- ============================================================
-- 0060_journal_audit.sql                              2026-06-23
-- ------------------------------------------------------------
-- Dedikert audit-logg for journal: OPPSLAG (select) + ENDRINGER
-- (insert/update/delete) på public.journal_entries.
--
-- ----- B0: HVA SOM ALLEREDE FINNES (lest fra faktiske filer) -----
-- journal_entries (0001_journal_entries.sql):
--   id uuid pk, booking_id text, patient_email text not null,
--   patient_phone text not null, staff_id text, staff_name text,
--   content text, created_at timestamptz.
--   Pasient identifiseres via e-post (+ telefon) — det finnes INGEN
--   numerisk pasient-id. Derfor lagres patient_email som patient_id
--   her (samme konvensjon som audit_log.target_id i 0002/0051).
--
-- LESING/SKRIVING i dag (0051_k2_journal_audit_rpc.sql, applisert i prod):
--   • Direkte tabelltilgang er REVOKED for anon + authenticated.
--   • Lesing skjer KUN via SECURITY DEFINER-RPC get_journal_entries(
--     p_email, p_phone) som allerede logger 'journal_view' til den
--     generelle audit_log-tabellen (0002_audit_log.sql).
--   • Skriving skjer KUN via SECURITY DEFINER-RPC create_journal_entry(...)
--     som logger 'journal_create' til audit_log.
--   • UPDATE/DELETE har RLS-policyer (0001) men ingen loggende vei.
--
-- ----- HVA DENNE MIGRASJONEN GJØR -----
--   B1: ny tabell journal_audit (eget skjema, append-only).
--   B2: AFTER INSERT/UPDATE/DELETE-trigger på journal_entries → logger
--       til journal_audit. Trigger fyrer også når create_journal_entry
--       gjør sin insert (SECURITY DEFINER hindrer ikke triggere).
--   B3: utvider get_journal_entries (RPC finnes alt) til å skrive en
--       'select'-rad til journal_audit i SAMME transaksjon som lesingen.
--       Den eksisterende audit_log('journal_view')-skrivingen BEHOLDES
--       (K2 — svekkes ikke). De to loggene er bevisst redundante:
--       audit_log = generell sporbarhet, journal_audit = dedikert,
--       admin-lesbar journal-trail med select/insert/update/delete.
--   B4: RLS — kun admin kan lese journal_audit; ingen update/delete
--       (append-only). Authenticated kan ikke insert'e direkte
--       (alle innslag kommer fra DEFINER-trigger/-RPC som omgår RLS).
--
-- Idempotent: create table if not exists / create or replace /
-- drop trigger if exists. Atomisk (begin/commit). search_path pinnes
-- på alle SECURITY DEFINER-funksjoner (repo-regel, jf. 0016/0051).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

-- Diagnostisk pre-sjekk (stopper ikke kjøringen — kun varsel).
do $$
begin
  if to_regclass('public.journal_entries') is null then
    raise notice '0060: public.journal_entries finnes ikke — kjør 0001 først.';
  end if;
  if to_regprocedure('public.get_journal_entries(text, text)') is null then
    raise notice '0060: get_journal_entries finnes ikke ennå — 0051 bør være applisert (B3 redefinerer den her uansett).';
  end if;
end $$;

begin;

-- ============================================================
-- B1: Audit-tabell (append-only)
-- ============================================================
create table if not exists public.journal_audit (
  id            uuid primary key default gen_random_uuid(),
  occurred_at   timestamptz not null default now(),
  actor_user_id uuid,                       -- auth.uid() (Supabase Auth-bruker)
  actor_role    text,                       -- app_metadata.role ('admin'|'therapist')
  action        text not null check (action in ('select', 'insert', 'update', 'delete')),
  patient_id    text,                       -- journal_entries.patient_email (pasientnøkkel)
  journal_id    uuid,                       -- journal_entries.id (null ved pasient-nivå select)
  detaljer      jsonb,                       -- f.eks. { "booking_id": "...", "staff_id": "..." }
  created_at    timestamptz not null default now()
);

create index if not exists journal_audit_occurred_idx
  on public.journal_audit (occurred_at desc);
create index if not exists journal_audit_patient_idx
  on public.journal_audit (patient_id, occurred_at desc);
create index if not exists journal_audit_action_idx
  on public.journal_audit (action, occurred_at desc);
create index if not exists journal_audit_journal_idx
  on public.journal_audit (journal_id);

comment on table public.journal_audit is
  'Dedikert append-only audit-trail for journal_entries: oppslag (select, '
  'via get_journal_entries-RPC) og endringer (insert/update/delete, via '
  'trigger). Kun admin kan lese. Lagt til i migrasjon 0060.';

-- ============================================================
-- B2: Trigger for ENDRINGER (insert/update/delete)
-- ============================================================
create or replace function public.log_journal_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_role   text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_action text := lower(tg_op);            -- 'insert' | 'update' | 'delete'
  v_rec    public.journal_entries;
begin
  if tg_op = 'DELETE' then
    v_rec := old;
  else
    v_rec := new;
  end if;

  -- Ingen journal-INNHOLD (content) logges — kun ID-er og nøkler,
  -- samme prinsipp som audit_log (0002).
  insert into public.journal_audit
    (actor_user_id, actor_role, action, patient_id, journal_id, detaljer)
  values (
    v_uid,
    v_role,
    v_action,
    coalesce(nullif(v_rec.patient_email, ''), v_rec.patient_phone),
    v_rec.id,
    jsonb_build_object('booking_id', v_rec.booking_id, 'staff_id', v_rec.staff_id)
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

comment on function public.log_journal_change() is
  'AFTER-trigger som skriver insert/update/delete på journal_entries til '
  'journal_audit. Aktør hentes fra JWT (auth.uid + app_metadata.role). '
  'Lagt til i migrasjon 0060.';

drop trigger if exists trg_journal_audit_change on public.journal_entries;
create trigger trg_journal_audit_change
  after insert or update or delete on public.journal_entries
  for each row execute function public.log_journal_change();

-- ============================================================
-- B3: Utvid lese-RPC med 'select'-logging til journal_audit
-- ------------------------------------------------------------
-- Identisk kropp som 0051 (scoping + audit_log('journal_view')
-- BEHOLDT uendret), med ÉN tilføyelse: en 'select'-rad til
-- journal_audit. Redefineres trygt med create or replace.
-- ============================================================
create or replace function public.get_journal_entries(
  p_email text default null,
  p_phone text default null
)
returns setof public.journal_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role       text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_staff_id   text := (auth.jwt() -> 'app_metadata' ->> 'staff_id');
  v_staff_name text := (auth.jwt() -> 'app_metadata' ->> 'staff_name');
  v_email      text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone      text := nullif(btrim(coalesce(p_phone, '')), '');
begin
  -- Kun ansatte med rolle (K7-scenarioet stoppes her).
  if v_role is null or v_role not in ('admin', 'therapist') then
    raise exception 'Ingen tilgang til journal' using errcode = '42501';
  end if;

  if v_email is null and v_phone is null then
    return; -- ingenting å slå opp — ikke logg støy
  end if;

  -- (uendret fra 0051) generell audit_log-trail.
  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata)
  values (
    coalesce(v_staff_id, case when v_role = 'admin' then 'admin' else 'unknown' end),
    coalesce(v_staff_name, case when v_role = 'admin' then 'Admin' else 'Ukjent' end),
    'journal_view',
    'patient',
    coalesce(v_email, v_phone),
    jsonb_build_object('via', 'rpc')
  );

  -- (NYTT i 0060) dedikert journal_audit-trail: action = 'select'.
  insert into public.journal_audit
    (actor_user_id, actor_role, action, patient_id, journal_id, detaljer)
  values (
    auth.uid(),
    v_role,
    'select',
    coalesce(v_email, v_phone),
    null, -- pasient-nivå oppslag — ingen enkelt journal-rad
    jsonb_build_object('via', 'rpc', 'by', case when v_email is not null then 'email' else 'phone' end)
  );

  -- Samme scoping som 0050-policyen (DEFINER omgår RLS).
  return query
  select j.*
    from public.journal_entries j
   where (
           (v_email is not null and lower(j.patient_email) = v_email)
        or (v_phone is not null and j.patient_phone = v_phone)
         )
     and (
           v_role = 'admin'
        or j.staff_id = v_staff_id
        or exists (
             select 1
               from public.bookings b
              where b.staff_id = v_staff_id
                and (
                     (j.patient_email <> '' and lower(b.email) = lower(j.patient_email))
                  or (j.patient_phone <> '' and b.phone = j.patient_phone)
                )
           )
         )
   order by j.created_at desc;
end;
$$;

comment on function public.get_journal_entries(text, text) is
  'Eneste lesevei til journal_entries for frontend. Logger BÅDE '
  'audit_log(journal_view) (K2, 0051) OG journal_audit(select) (0060) i '
  'samme transaksjon som lesingen. Scoping speiler 0050-policyen.';

-- ============================================================
-- B4: RLS på journal_audit — admin-lese, append-only
-- ============================================================
alter table public.journal_audit enable row level security;

-- Direkte API-tilgang lukkes; kun admin-SELECT åpnes (RLS under).
-- Trigger/RPC er SECURITY DEFINER og omgår både grants og RLS, så de
-- skriver fortsatt. Authenticated kan dermed ikke forfalske rader.
revoke all on public.journal_audit from anon, authenticated;
grant select on public.journal_audit to authenticated;

drop policy if exists "journal_audit: admin can read" on public.journal_audit;

create policy "journal_audit: admin can read"
  on public.journal_audit for select
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- INGEN insert/update/delete-policy = ingen authenticated kan endre
-- loggen via API. Append-only håndheves slik (samme mønster som
-- audit_log i 0002).

commit;

-- ============================================================
-- B5: Verifikasjon (kjør manuelt etter apply):
--
-- 1) Trigger er på plass:
--    select tgname, tgenabled
--      from pg_trigger
--     where tgrelid = 'public.journal_entries'::regclass
--       and tgname = 'trg_journal_audit_change';
--    -- Forvent: én rad, tgenabled = 'O'.
--
-- 2) RLS-policy er admin-only og append-only:
--    select cmd, qual
--      from pg_policies
--     where tablename = 'journal_audit';
--    -- Forvent: nøyaktig 1 policy (cmd = SELECT). Ingen INSERT/UPDATE/DELETE.
--
-- 3) Append-only via grants:
--    select has_table_privilege('authenticated','public.journal_audit','select') as can_select,
--           has_table_privilege('authenticated','public.journal_audit','insert') as can_insert,
--           has_table_privilege('authenticated','public.journal_audit','update') as can_update,
--           has_table_privilege('authenticated','public.journal_audit','delete') as can_delete;
--    -- Forvent: t (RLS begrenser til admin), f, f, f.
--
-- 4) Endring logges (kjør via REST/RPC med ansatt-JWT):
--    POST /rest/v1/rpc/create_journal_entry { ... }
--    select action, patient_id, journal_id, occurred_at
--      from journal_audit where action = 'insert'
--     order by occurred_at desc limit 1;   -- Forvent: ny rad.
--
-- 5) Oppslag logges:
--    POST /rest/v1/rpc/get_journal_entries { "p_email": "test@example.com" }
--    select action, patient_id, occurred_at
--      from journal_audit where action = 'select'
--     order by occurred_at desc limit 1;   -- Forvent: ny rad.
-- ============================================================
