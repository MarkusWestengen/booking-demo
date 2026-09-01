-- ============================================================
-- Westengen Klinikk — Services: is_public-flagg for kunde-synlighet
-- Migration 0032
-- ------------------------------------------------------------
-- Markus-feedback 2026-05-29 (D4): legg til mulighet for interne
-- tjenester som ikke vises i kunde-flyten. is_public skiller seg
-- fra is_active:
--   is_active  = false → tjenesten er deaktivert (admin har skjult).
--   is_public  = false → tjenesten er aktiv MEN intern (skal kun
--                        tilbys av admin/terapeut, ikke i bestilling.html).
-- Begge kreves true for at en kunde skal se tjenesten:
--   loadActiveServices() i shared/services.js filtrerer på
--   is_active=true AND is_public=true.
-- loadAllServices(sb) (admin-flyt) ser fortsatt ALLE rader.
--
-- Default = TRUE — alle eksisterende tjenester forblir synlige
-- inntil Markus eksplisitt flipper en til intern. Markus flipper
-- via SQL i Dashboard inntil videre (ingen admin-UI bygges).
--
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- ----- DIAGNOSE (read-only, FØR mutation) ---------------------
do $$
declare
  has_col boolean;
  row_count int;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='services'
       and column_name='is_public'
  ) into has_col;
  if has_col then
    raise notice 'is_public-kolonne finnes allerede — ALTER blir no-op.';
  else
    select count(*) into row_count from public.services;
    raise notice 'Legger til is_public BOOL DEFAULT TRUE på % services-rader (alle blir synlige).', row_count;
  end if;
end $$;

-- ----- MUTATION -----------------------------------------------
alter table public.services
  add column if not exists is_public boolean not null default true;

-- Sikkerhetsnett: hvis kolonnen ble lagt til med NULL-bare rader
-- (shouldn't happen siden vi har NOT NULL DEFAULT TRUE, men idempotent).
update public.services set is_public = true where is_public is null;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--   select slug, name, is_active, is_public
--     from public.services order by sort_order;
-- Forvent: alle rader har is_public = true.
--
-- Smoke-test:
--   anon GET /rest/v1/services?select=*&is_active=eq.true&is_public=eq.true
--   skal returnere samme antall rader som
--   /rest/v1/services?select=*&is_active=eq.true (inntil Markus flipper en).
--
-- Internt:
--   update public.services set is_public = false where slug = 'tom-test';
--   → kunde-flyten skjuler den umiddelbart, admin ser den fortsatt.
-- ============================================================
