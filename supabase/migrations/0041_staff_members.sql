-- ============================================================
-- 0041_staff_members.sql                             2026-06-03
-- ------------------------------------------------------------
-- Behandler-CRUD (DEL C). Flytter behandler-listen fra hardkodet
-- STAFF/THERAPIST_POOL i booking-engine.js til DB, så admin kan
-- legge til / redigere / deaktivere behandlere uten kode-endring.
--
-- KRITISK SIKKERHETSNETT: booking-engine.js LESER denne tabellen,
-- men beholder kode-konstanten STAFF som FALLBACK. Hvis tabellen er
-- tom, utilgjengelig, eller gir 0 bookbare → bruker engine-en kode-
-- listen. Kunden skal ALDRI se en tom behandlerliste. (Derfor virker
-- booking helt likt FØR og ETTER denne migrasjonen — koden faller
-- tilbake til konstanten til tabellen er seedet.)
--
-- Modell (speiler STAFF i booking-engine.js):
--   - bookable=true  → vises som kunde-kort i bestillingsflyten
--     ('markus' + 'terapeut'-paraplyen). De 7 navngitte har bookable=false.
--   - is_pool=true   → medlem av "Markus' terapeuter"-poolen (de 7 navngitte;
--     brukes til gruppe-kapasitet + admin-tildeling). 'markus'/'terapeut'
--     er ikke pool-medlemmer.
--   - aktiv=false    → DEAKTIVERT (skjult fra nye bestillinger). INGEN
--     hard-delete (ingen DELETE-policy/-grant) — eksisterende bookinger
--     + historikk beholdes, kan reaktiveres.
--
-- Designvalg:
--   - staff_id text PK = NØYAKTIG dagens id-er (markus, terapeut, sofie,
--     henrik, jonas, amina, nora, lena, petter) → staff_services +
--     eksisterende bookings.staff_id matcher uendret (ingen FK, ingen
--     foreldreløse rader).
--   - RLS: anon SELECT (kun aktive — booking-flyten leser via REST);
--     alle ansatte SELECT (også deaktiverte, for admin-UI); admin
--     INSERT/UPDATE. Ingen DELETE.
--   - GRANTs: revoke all FØRST (0037-lærdom), så minste nødvendige.
--   - Seed er idempotent (on conflict do nothing) → re-apply klobrer
--     IKKE senere admin-redigeringer.
--
-- Idempotent, atomisk (begin/commit). IKKE applisert av repoet.
-- ============================================================

begin;

-- ----- staff_members-tabell -----------------------------------
create table if not exists public.staff_members (
  staff_id    text primary key,            -- matcher dagens id-er
  name        text not null,
  role        text not null default '',     -- tittel/rolle
  bio         text not null default '',
  bookable    boolean not null default false, -- vises som kunde-kort
  is_pool     boolean not null default false, -- medlem av terapeut-pool
  aktiv       boolean not null default true,  -- aktiv/deaktivert
  sortering   integer not null default 100,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_staff_members_active
  on public.staff_members (aktiv, sortering);

-- updated_at-trigger (samme mønster som waitlist 0023 / services 0008).
create or replace function public._staff_members_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists staff_members_set_updated_at on public.staff_members;
create trigger staff_members_set_updated_at
  before update on public.staff_members
  for each row execute function public._staff_members_set_updated_at();

-- ----- Grants (revoke all FØRST — 0037-lærdom) ---------------
revoke all on public.staff_members from anon, authenticated;
-- anon: kun SELECT (booking-flyten leser aktive behandlere). RLS gater til aktive.
grant select on public.staff_members to anon;
-- authenticated: SELECT (alle, for admin-UI) + INSERT/UPDATE (RLS gater til admin).
grant select, insert, update on public.staff_members to authenticated;

-- ----- RLS ---------------------------------------------------
alter table public.staff_members enable row level security;

drop policy if exists "staff_members read active: anon" on public.staff_members;
drop policy if exists "staff_members read all: staff"    on public.staff_members;
drop policy if exists "staff_members insert: admin"      on public.staff_members;
drop policy if exists "staff_members update: admin"      on public.staff_members;

-- Anon (booking-flyten) ser KUN aktive behandlere.
create policy "staff_members read active: anon"
  on public.staff_members for select to anon
  using (aktiv = true);

-- Alle ansatte ser alle (også deaktiverte) for admin-UI.
create policy "staff_members read all: staff"
  on public.staff_members for select to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'));

-- Kun admin legger til.
create policy "staff_members insert: admin"
  on public.staff_members for insert to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

-- Kun admin redigerer (inkl. deaktivering aktiv=false / reaktivering).
create policy "staff_members update: admin"
  on public.staff_members for update to authenticated
  using   (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');
-- INGEN delete-policy → ingen hard-delete mulig (deaktivering = UPDATE).

-- ----- Seed: dagens behandlere (idempotent) ------------------
-- NØYAKTIG samme staff_id-er, navn, rolle og bio som STAFF-konstanten
-- i booking-engine.js, så systemet fungerer identisk fra dag én.
-- on conflict do nothing → re-apply bevarer admin-redigeringer.
insert into public.staff_members (staff_id, name, role, bio, bookable, is_pool, aktiv, sortering) values
  ('markus',     'Markus Westengen',   'Behandler', 'Timen settes opp hos Markus. Oppdiktet behandler i en oppdiktet klinikk.', true,  false, true, 10),
  ('terapeut', 'Markus'' terapeuter', 'Opplært av Markus selv',            'Vi tildeler en av våre erfarne terapeuter, alle opplært direkte i Markus'' metoder. Samme filosofi, samme grundighet.', true,  false, true, 20),
  ('sofie',    'Sofie Aune',       'Daglig leder',                    'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 30),
  ('henrik',   'Henrik Dal',       'Leder for produktutvikling',      'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 40),
  ('jonas',    'Jonas Riis',       'Markedssjef',                     'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 50),
  ('amina',    'Amina Nour',       'Trainee-koordinator',             'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 60),
  ('nora',     'Nora Ellingsen',   'Pasientkoordinator',              'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 65),
  ('lena',     'Lena Vik',         'Trainee',                         'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 70),
  ('petter',   'Petter Holm',      'Trainee',                         'Opplært direkte av Markus. Samme metodikk, samme grundighet.', false, true, true, 80)
on conflict (staff_id) do nothing;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Tabell + RLS + 4 policies:
--    select policyname, cmd from pg_policies
--     where schemaname='public' and tablename='staff_members' order by policyname;
--    -- Forvent: read active: anon (SELECT), read all: staff (SELECT),
--    --          insert: admin (INSERT), update: admin (UPDATE)
--    --          (INGEN delete-policy)
--
-- B) Grants minimale (jf. 0037):
--    select grantee, string_agg(privilege_type, ',' order by privilege_type) as privs
--      from information_schema.role_table_grants
--     where table_schema='public' and table_name='staff_members'
--       and grantee in ('anon','authenticated') group by grantee order by grantee;
--    -- Forvent: anon=SELECT ; authenticated=INSERT,SELECT,UPDATE
--    --          (INGEN DELETE/TRUNCATE for noen)
--
-- C) SEED-SJEKK: alle 9 staff_id-er finnes (= det booking-engine.js
--    sin STAFF/THERAPIST_POOL og staff_services bruker):
--    select staff_id, bookable, is_pool, aktiv from public.staff_members
--     order by sortering;
--    -- Forvent 9 rader: markus(bookable,t), terapeut(bookable,t),
--    --   sofie/henrik/jonas/amina/nora/lena/petter (is_pool, aktiv)
--
-- D) Konsistens mot staff_services (ingen foreldreløse koblinger):
--    select distinct ss.staff_id
--      from public.staff_services ss
--     where ss.staff_id not in (select staff_id from public.staff_members);
--    -- Forvent: 0 rader (alle staff_services-koblinger har en staff_member)
--
-- E) anon ser kun aktive (test via anon REST):
--    -- GET /rest/v1/staff_members?select=staff_id&aktiv=eq.true  → de aktive
--    -- (deaktiverte skal ikke komme med for anon)
-- ============================================================
