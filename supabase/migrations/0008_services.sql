-- ============================================================
-- Westengen Klinikk — Services + staff_services (M:N)
-- Migration 0008
-- ------------------------------------------------------------
-- Flatt ut den tidligere hardkodede tjeneste-katalogen fra
-- shared/booking-engine.js (SERVICES-objektet keyed på staff_id)
-- til en database-tabell admin kan administrere via tjenester.html.
--
-- Bakoverkompat: dagens fire service_id-strenger
--   markus-konsult, markus-videre, ter-konsult, ter-videre
-- gjenbrukes som slug på de seedede radene, slik at eksisterende
-- bookinger.service_id matcher direkte mot services.slug.
--
-- Staff-modell: koblingen er M:N selv om dagens seed har 1:1
-- (hver tjeneste utføres av nøyaktig én staff). Fremtidig fleksibilitet
-- uten ny migrasjon.
--
-- RLS:
--   services.SELECT
--     - anon  → kun is_active = true (kunde-vendt bestilling)
--     - therapist → kun is_active = true
--     - admin → alle (også deaktiverte)
--   services.INSERT/UPDATE/DELETE → admin only
--   staff_services følger samme mønster.
--
-- DELETE finnes som policy men UI-en kaller den aldri — tjenester
-- deaktiveres (is_active = false) for at gamle bookinger fortsatt
-- skal kunne vise tjenestenavn i historikk.
-- ============================================================

-- ----- services -----------------------------------------------
create table if not exists public.services (
  id           uuid primary key default gen_random_uuid(),
  slug         text unique not null,
  name         text not null,
  description  text,
  duration_min int  not null check (duration_min > 0),
  price_nok    int  not null check (price_nok >= 0),
  color        text,
  icon         text,
  sort_order   int  not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists services_active_sort_idx
  on public.services(is_active, sort_order);
create index if not exists services_slug_idx
  on public.services(slug);

-- updated_at-trigger
create or replace function public._services_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists services_set_updated_at on public.services;
create trigger services_set_updated_at
  before update on public.services
  for each row execute function public._services_set_updated_at();

-- ----- staff_services -----------------------------------------
-- staff_id er text fordi STAFF-katalogen i booking-engine.js er
-- en konstant ('markus', 'terapeut'). Hvis vi senere lager en
-- staff-tabell kan denne refactores til uuid + FK.
create table if not exists public.staff_services (
  staff_id   text not null,
  service_id uuid not null references public.services(id) on delete cascade,
  primary key (staff_id, service_id)
);

create index if not exists staff_services_staff_idx
  on public.staff_services(staff_id);
create index if not exists staff_services_service_idx
  on public.staff_services(service_id);

-- ============================================================
-- Row-Level Security
-- ============================================================
alter table public.services       enable row level security;
alter table public.staff_services enable row level security;

-- ----- services policies --------------------------------------
drop policy if exists "services: anon select active"       on public.services;
drop policy if exists "services: auth select active"       on public.services;
drop policy if exists "services: admin select all"         on public.services;
drop policy if exists "services: admin insert"             on public.services;
drop policy if exists "services: admin update"             on public.services;
drop policy if exists "services: admin delete"             on public.services;

-- Anon kan kun se aktive tjenester (kunde-vendt booking).
create policy "services: anon select active"
  on public.services for select
  to anon
  using (is_active = true);

-- Authenticated therapeut kan kun se aktive.
-- Admin har separat policy under som dekker ALLE (inkl. deaktiverte) —
-- siden Postgres OR'er policies blir det riktig per rolle.
create policy "services: auth select active"
  on public.services for select
  to authenticated
  using (
    is_active = true
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "services: admin insert"
  on public.services for insert
  to authenticated
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "services: admin update"
  on public.services for update
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- DELETE finnes for fullstendighet men brukes ikke av UI-en.
-- (Tjenester deaktiveres, ikke slettes — bevarer historikk.)
create policy "services: admin delete"
  on public.services for delete
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- ----- staff_services policies --------------------------------
drop policy if exists "staff_services: anon select active"   on public.staff_services;
drop policy if exists "staff_services: auth select"          on public.staff_services;
drop policy if exists "staff_services: admin insert"         on public.staff_services;
drop policy if exists "staff_services: admin delete"         on public.staff_services;
drop policy if exists "staff_services: admin update"         on public.staff_services;

-- Anon kan se kobling KUN for aktive tjenester (begrenser bestilling-UI).
create policy "staff_services: anon select active"
  on public.staff_services for select
  to anon
  using (exists (
    select 1 from public.services s
    where s.id = staff_services.service_id and s.is_active = true
  ));

-- Authenticated kan se alt — admin trenger det for redigering,
-- therapist ser sin egen liste, og UI filtrerer videre på service.is_active.
create policy "staff_services: auth select"
  on public.staff_services for select
  to authenticated
  using (true);

create policy "staff_services: admin insert"
  on public.staff_services for insert
  to authenticated
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "staff_services: admin delete"
  on public.staff_services for delete
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- UPDATE-policy for fullstendighet — i praksis kaller UI-en kun
-- INSERT + DELETE for å oppdatere staff-koblingen på en tjeneste.
create policy "staff_services: admin update"
  on public.staff_services for update
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- ============================================================
-- Seed — dagens fire hardkodede tjenester fra booking-engine.js
-- ------------------------------------------------------------
-- Slug-verdiene matcher eksisterende bookings.service_id-strenger.
-- on conflict (slug) do nothing → idempotent.
-- ============================================================
insert into public.services (slug, name, description, duration_min, price_nok, sort_order, is_active)
values
  ('markus-konsult', 'Konsultasjon (Markus)',           'Førstegangsvurdering med Markus. Grundig kartlegging av plager.',          30, 4000, 10, true),
  ('markus-videre',  'Videre behandling (Markus)',      'Oppfølgingstime etter første konsultasjon.',                            30, 3000, 20, true),
  ('ter-konsult', 'Konsultasjon (terapeut)',      'Førstegangsvurdering med en av Markus'' terapeuter.',                       30, 2000, 30, true),
  ('ter-videre',  'Videre behandling (terapeut)', 'Oppfølgingstime etter første konsultasjon.',                            30, 1500, 40, true)
on conflict (slug) do nothing;

-- Seed staff_services: hver tjeneste kobles til riktig staff.
-- Sub-select på services.id slik at vi ikke trenger å hardkode uuid'ene.
insert into public.staff_services (staff_id, service_id)
select 'markus', id from public.services where slug in ('markus-konsult', 'markus-videre')
on conflict do nothing;

insert into public.staff_services (staff_id, service_id)
select 'terapeut', id from public.services where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--   select * from pg_policies where tablename in ('services', 'staff_services');
--   select slug, name, price_nok, is_active from public.services order by sort_order;
--   select * from public.staff_services;
-- Forventet: 4 services, 4 staff_services-rader (2 markus + 2 terapeut),
-- 7 policies på services (3 SELECT-roller med fallback OR for admin er
-- konsolidert til 2 stk) — totalt:
--   services: 5 policies (anon-select, auth-select, admin-insert, admin-update, admin-delete)
--   staff_services: 5 policies (anon-select, auth-select, admin-insert, admin-delete, admin-update)
-- ============================================================
