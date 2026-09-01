-- ============================================================
-- 0049_staff_colors.sql                               2026-06-12
-- ------------------------------------------------------------
-- Behandler-farger: hver behandler får en egen farge som vises
-- som en subtil vertikal fargebar ved bookingene deres i admin
-- (bestillingstabellen desktop + mobilkortenes venstrekant).
-- Admin velger/bytter farge per behandler på behandlere.html.
--
-- Frontend-fallback: mangler kolonnen (migrasjonen ikke kjørt)
-- eller er verdien tom, brukes en hardkodet palett / nøytral grå —
-- ingenting knekker før eller etter apply.
--
-- Idempotent: add column if not exists; seed-UPDATE-ene treffer kun
-- rader uten farge (color = ''), så operatør-valgte farger
-- overskrives ALDRI ved re-apply. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- Avhenger av 0041 (staff_members). RLS/grants uendret (0041 gir
-- allerede admin UPDATE på alle kolonner).
-- ============================================================

begin;

alter table public.staff_members
  add column if not exists color text not null default '';

comment on column public.staff_members.color is
  'Hex-farge (#RRGGBB) for behandlerens fargebar i admin-UI. '
  'Markus streng = bruk frontend-fallback. Migrasjon 0049.';

-- Seed: distinkt, dempet palett i klinikkens toneleie.
-- Kun rader som IKKE allerede har farge (idempotent + bevarer valg).
update public.staff_members set color = '#3E6B47' where staff_id = 'markus'         and color = '';
update public.staff_members set color = '#B8754A' where staff_id = 'sofie'     and color = '';
update public.staff_members set color = '#5B7DB1' where staff_id = 'henrik'      and color = '';
update public.staff_members set color = '#8E6FA8' where staff_id = 'jonas' and color = '';
update public.staff_members set color = '#C2A14D' where staff_id = 'amina'         and color = '';
update public.staff_members set color = '#4D9D9A' where staff_id = 'petter'      and color = '';
update public.staff_members set color = '#A85C5C' where staff_id = 'lena'      and color = '';
update public.staff_members set color = '#D87FA0' where staff_id = 'nora'      and color = '';

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--   select staff_id, name, color from public.staff_members
--    order by sortering;
--   -- Forvent: tom=#3E6B47 (grønn), øvrige distinkte farger.
-- Ende-til-ende: booking-admin → Bestillinger viser fargebar per
-- behandler; behandlere.html viser fargevelger + swatch per kort.
-- ============================================================
