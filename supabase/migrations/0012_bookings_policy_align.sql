-- ============================================================
-- 0012_bookings_policy_align.sql                   2026-05-12
-- ------------------------------------------------------------
-- Retter et policy-overlapp på public.bookings:
--
-- Eksisterende Admin/Therapist-policies (manuelt opprettet før
-- migrasjons-systemet ble brukt — ikke i 0001-0010):
--   - "Admin insert bookings"         (insert, role=admin)
--   - "Admin read all bookings"       (select, role=admin)
--   - "Admin update bookings"         (update, role=admin)
--   - "Therapist insert own bookings" (insert, role=therapist + staff_id match)
--   - "Therapist read own bookings"   (select, role=therapist + staff_id match)
--   - "Therapist update own bookings" (update, role=therapist + staff_id match)
--
-- 0010 la til 4 brede policies som "alle authenticated får alt":
--   - "auth read bookings"   (select, using true)
--   - "auth insert bookings" (insert, with check true)
--   - "auth update bookings" (update, using true)
--   - "auth delete bookings" (delete, using true)
--
-- Postgres OR'er permissive policies. Resultat: en innlogget
-- therapist får full tilgang til ALLE bookinger via 0010's brede
-- SELECT — den strenge "egen staff_id"-policyen blir overflødig.
-- Det er en personvernregresjon vi ikke ønsker.
--
-- Denne migrasjonen:
--   (a) Dropper de 4 brede auth-policiene fra 0010
--   (b) Kodifiserer de eksisterende Admin/Therapist-policiene
--       som migrasjon (idempotent, så de finnes i source-of-truth)
--   (c) Legger til "Admin delete bookings" — admin DELETE i
--       booking-admin.html:1615 ville feile uten dette etter at
--       0010's brede "auth delete bookings" droppes
--
-- IKKE STRAMMET (TODO senere):
--   "anon update bookings" og "anon delete bookings" fra
--   den gamle oppsettsguiden (nå 0000_base_schema.sql) er fortsatt åpne på policy-nivå. De er
--   nøytralisert av REVOKE i 0010 (anon har ikke UPDATE/DELETE-
--   grant på tabellen). Krever migrering av lovlige anon-skrive-
--   tilfeller til service-role/RPC før de kan droppes trygt.
--
-- Idempotent: alle CREATE POLICY pakkes i DO-blokker med
-- pg_policies-eksistens-sjekk (PG15/16 har ikke CREATE POLICY
-- IF NOT EXISTS).
-- ============================================================

-- ============================================================
-- (a) Drop 0010's brede auth-policies ----------------------
-- Sikker å droppe fordi Admin/Therapist-policies allerede gir
-- riktig tilgang til admin og therapist. Etter dropping:
--   - admin: full read/insert/update/delete via Admin-policiene
--   - therapist: read/insert/update av EGNE bookinger
--   - therapist: ingen DELETE (medisinsk historikk er append-only
--     for therapist; admin har nødåpning)
-- ============================================================
drop policy if exists "auth read bookings"   on public.bookings;
drop policy if exists "auth insert bookings" on public.bookings;
drop policy if exists "auth update bookings" on public.bookings;
drop policy if exists "auth delete bookings" on public.bookings;

-- ============================================================
-- (b) Kodifiser Admin-policies (idempotent) ----------------
-- Disse finnes allerede i prod (manuelt opprettet), men ikke i
-- migrasjons-historikken. Vi registrerer dem her for source-of-
-- truth. DO-blokk hopper over hvis policy allerede eksisterer
-- — bevarer evt. tilpassede uttrykk i prod.
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Admin read all bookings'
  ) then
    create policy "Admin read all bookings"
      on public.bookings for select
      to authenticated
      using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Admin insert bookings'
  ) then
    create policy "Admin insert bookings"
      on public.bookings for insert
      to authenticated
      with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Admin update bookings'
  ) then
    create policy "Admin update bookings"
      on public.bookings for update
      to authenticated
      using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
      with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
  end if;
end $$;

-- ============================================================
-- (c) NY: Admin delete bookings -----------------------------
-- booking-admin.html:1615 kaller sb.from('bookings').delete().
-- Uten denne policyen ville den feile silent (0 rows affected)
-- etter at "auth delete bookings" droppes i (a).
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Admin delete bookings'
  ) then
    create policy "Admin delete bookings"
      on public.bookings for delete
      to authenticated
      using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');
  end if;
end $$;

-- ============================================================
-- (d) Kodifiser Therapist-policies (idempotent) ------------
-- staff_id-matchen sikrer at therapist kun ser EGNE bookinger.
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Therapist read own bookings'
  ) then
    create policy "Therapist read own bookings"
      on public.bookings for select
      to authenticated
      using (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
        and staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Therapist insert own bookings'
  ) then
    create policy "Therapist insert own bookings"
      on public.bookings for insert
      to authenticated
      with check (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
        and staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'Therapist update own bookings'
  ) then
    create policy "Therapist update own bookings"
      on public.bookings for update
      to authenticated
      using (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
        and staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
      )
      with check (
        (auth.jwt() -> 'app_metadata' ->> 'role') = 'therapist'
        and staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
      );
  end if;
end $$;

-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--   select policyname, cmd, roles
--     from pg_policies
--    where schemaname = 'public' and tablename = 'bookings'
--    order by policyname;
-- Forventet: 8 aktive role-baserte policies:
--   - anon insert bookings
--   - Admin insert bookings, Admin read all bookings,
--     Admin update bookings, Admin delete bookings
--   - Therapist insert own bookings, Therapist read own bookings,
--     Therapist update own bookings
-- (anon update/delete bookings fra den gamle oppsettsguiden (nå 0000_base_schema.sql) er fortsatt
--  registrert som policies men har ingen praktisk effekt fordi
--  anon mangler grants etter 0010. Totaltelling kan dermed bli 10.)
-- ============================================================
