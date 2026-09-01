-- ============================================================
-- 0016_security_hardening.sql                        2026-05-15
-- ------------------------------------------------------------
-- Lukker 11 av 12 Supabase Database Linter-funn i én migrasjon.
-- Det 12. funnet (auth_leaked_password_protection) kan ikke
-- konfigureres via SQL — det er en Dashboard-toggle, dokumentert
-- i docs/admin-onboarding.md.
--
-- Linter-funn håndtert her:
--   (a) ERROR security_definer_view på public.booked_slots
--       → drop view, opprett SECURITY DEFINER-funksjon med
--         eksplisitt kolonne-whitelist i stedet.
--   (b) WARN function_search_path_mutable på notify_booking_change()
--       og _services_set_updated_at()
--       → ALTER FUNCTION ... SET search_path = public, pg_temp
--   (c) WARN anon/authenticated_security_definer_function_executable
--       på notify_booking_change() og send_booking_email()
--       → REVOKE EXECUTE FROM anon, authenticated. Triggere kjører i
--         egen kontekst (eier av trigger), så REVOKE påvirker bare
--         direkte RPC-kall som ikke skal forekomme.
--   (d) WARN rls_policy_always_true på "anon insert bookings"
--       → drop og erstatt med constrained WITH CHECK som krever
--         status='confirmed' + ikke-tomme PII-felter + non-null FK'er.
--   (Resterende rls_policy_always_true-funn på "auth delete/insert/
--    update bookings" droppes av 0012. Hvis 0012 ikke er applisert,
--    løses de likevel der — ikke her.)
--
-- IKKE ENDRET:
--   - body på send_booking_email() bevares uendret. Funksjonen har
--     hardkodet prod Resend API-key som ikke skal i repo. Vi rører
--     kun GRANT-tabellen.
--   - body på notify_booking_change() bevares uendret. 0011 droppet
--     denne i et separat drop-spor, men hvis den fortsatt finnes
--     etter 0011 (fersk DB, eller 0011 ikke applisert), ALTER+REVOKE
--     er trygge no-ops.
--   - Triggere på public.bookings (trg_booking_email, trg_audit_*)
--     berøres ikke. Trigger-kall til SECURITY DEFINER-funksjoner
--     fungerer fortsatt etter REVOKE EXECUTE — bare RPC-kall blokkeres.
--
-- AVHENGIGHETER:
--   - Forutsetter at 0011 + 0012 + 0015 er applisert. Verifiser:
--       select policyname from pg_policies
--        where tablename = 'bookings'
--        order by policyname;
--     Skal IKKE inneholde "auth read/insert/update/delete bookings"
--     (de er droppet av 0012). Hvis de fortsatt finnes, appliser
--     0012 først.
--
-- FRONTEND-IMPLIKASJON:
--   shared/booking-engine.js getBookedSlots() må byttes fra
--     GET /rest/v1/booked_slots?select=...
--   til
--     POST /rest/v1/rpc/get_booked_slots
--   Returshapen er identisk. Endring i samme commit som denne migrasjonen.
--
-- Idempotent: alle CREATE OR REPLACE, DROP IF EXISTS, og DO-blokker
-- med pg_policies-sjekk.
-- ============================================================

-- ============================================================
-- (a) Erstatt booked_slots-view med SECURITY DEFINER-funksjon
-- ------------------------------------------------------------
-- View-en hadde implicit SECURITY DEFINER-evaluering (postgres
-- som eier) for at anon skulle kunne lese tross RLS på underliggende
-- bookings-tabell. Linter (security_definer_view) anser dette som
-- ERROR fordi view-eier kan utilsiktet eksponere mer kolonner enn
-- intendert hvis view-definisjonen endres.
--
-- Funksjon-tilnærmingen er strammere:
--   - Eksplisitt RETURNS TABLE-deklarasjon låser kolonnelisten —
--     en endring i underliggende bookings-schema kan ikke lekke nye
--     kolonner via funksjonen.
--   - STABLE + SECURITY DEFINER + SET search_path er linter-compliant
--     og funksjonelt identisk med dagens view-bruk.
--   - Valgfrie filter-parametre (p_staff_id, p_from, p_to) lar
--     frontend hente bare det som trengs. Default NULL = alle rader,
--     samme som dagens view.
-- ============================================================

drop view if exists public.booked_slots;

create or replace function public.get_booked_slots(
  p_staff_id text default null,
  p_from     date default null,
  p_to       date default null
)
returns table (
  staff_id text,
  "date"   date,
  "time"   time,
  duration integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select b.staff_id, b.date, b.time, b.duration
    from public.bookings b
   where b.status in ('confirmed', 'completed')
     and (p_staff_id is null or b.staff_id = p_staff_id)
     and (p_from     is null or b.date >= p_from)
     and (p_to       is null or b.date <= p_to);
$$;

comment on function public.get_booked_slots(text, date, date) is
  'Returnerer (staff_id, date, time, duration) for confirmed/completed bookinger. '
  'Eksponerer ingen PII. Erstatter booked_slots-viewet (security_definer_view '
  'linter-ERROR). Brukes av shared/booking-engine.js getBookedSlots() til '
  'anon availability-sjekk i bestilling.html.';

-- Lås EXECUTE-tilgang ned til kun anon + authenticated. PUBLIC fjernes
-- som default for security definer-funksjoner med RLS-bypass-konsekvens.
revoke execute on function public.get_booked_slots(text, date, date) from public;
grant  execute on function public.get_booked_slots(text, date, date) to anon, authenticated;


-- ============================================================
-- (b) Pinn search_path på flagged funksjoner -----------------
-- function_search_path_mutable-linter-funn på funksjoner uten
-- eksplisitt SET search_path. Pinner til samme verdi som funksjons-
-- definisjonen ville fått i en fresh CREATE OR REPLACE — ingen
-- side-effekt på funksjonalitet.
--
-- ALTER FUNCTION bevarer body og er tryggere enn CREATE OR REPLACE
-- (sistnevnte måtte hatt full body, og send_booking_email bør aldri
-- få sin body re-applisert utenfor 0011s DO-blokk-guard).
--
-- DO-blokker med pg_proc-sjekk gjør ALTER no-op hvis funksjonen
-- ikke finnes (f.eks. notify_booking_change ble droppet av 0011).
-- ============================================================

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'notify_booking_change'
  ) then
    execute 'alter function public.notify_booking_change() set search_path = public, pg_temp';
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = '_services_set_updated_at'
  ) then
    execute 'alter function public._services_set_updated_at() set search_path = public, pg_temp';
  end if;
end $$;

-- send_booking_email har allerede SET search_path = public, extensions
-- fra 0011 (eller manuelt opprettet versjon i prod). Vi rører den ikke
-- her — body inneholder Resend-nøkkel og skal ikke re-applieres.
-- Linter-funnet for søkesti er bare aktivt hvis funksjonen mangler
-- SET, så hvis den fortsatt flagges må prod-funksjonen ALTER-es
-- manuelt:
--   alter function public.send_booking_email() set search_path = public, extensions;


-- ============================================================
-- (c) Lås RPC-tilgang til SECURITY DEFINER-funksjoner ----------
-- ------------------------------------------------------------
-- notify_booking_change og send_booking_email skal KUN kjøre i
-- trigger-kontekst. Triggere bruker eierens (postgres) rolle, så
-- REVOKE EXECUTE FROM anon/authenticated/PUBLIC stopper RPC-kall
-- (/rest/v1/rpc/...) uten å påvirke trigger-fyring.
--
-- DO-blokker så REVOKE blir no-op hvis funksjonen ikke finnes.
-- ============================================================

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'notify_booking_change'
  ) then
    execute 'revoke execute on function public.notify_booking_change() from anon, authenticated, public';
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'send_booking_email'
  ) then
    execute 'revoke execute on function public.send_booking_email() from anon, authenticated, public';
  end if;
end $$;

-- _services_set_updated_at er ikke security definer og finnes
-- ikke i linter-funn-listen for RPC-tilgang, men har samme
-- trigger-only-bruk. Konsistens-defense-in-depth:
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = '_services_set_updated_at'
  ) then
    execute 'revoke execute on function public._services_set_updated_at() from anon, authenticated, public';
  end if;
end $$;


-- ============================================================
-- (d) Stram WITH CHECK på "anon insert bookings"-policy --------
-- ------------------------------------------------------------
-- Tidligere `with check (true)` ga anon mulighet til å insert-e
-- bookinger med vilkårlige verdier — inkludert status='cancelled'
-- (skjuler bookingen fra booked_slots fra start) eller tomme PII-
-- felter (omgår booking-engine.js sin validering).
--
-- Den nye constrainen krever at:
--   - status = 'confirmed' (default for legit kunde-booking)
--   - name, email, phone er ikke-tomme strenger
--   - staff_id, service_id, date, time er non-null
--
-- shared/booking-engine.js createBooking() sender alle disse feltene
-- med ikke-tomme verdier (jf. booking-flow.js sin step-by-step-
-- validering). Ingen kunde-regresjon forventet.
--
-- 0004's partial unique index (bookings_active_slot_unique) håndterer
-- fortsatt race conditions; vi duplikerer ikke den constrainen her.
-- ============================================================

drop policy if exists "anon insert bookings" on public.bookings;

create policy "anon insert bookings"
  on public.bookings
  for insert
  to anon
  with check (
        status = 'confirmed'
    and length(coalesce(name,  '')) > 0
    and length(coalesce(email, '')) > 0
    and length(coalesce(phone, '')) > 0
    and staff_id   is not null
    and service_id is not null
    and date is not null
    and time is not null
  );


-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--
--   -- get_booked_slots finnes og er kallbar av anon:
--   select count(*) from public.get_booked_slots();
--
--   -- search_path er pinned:
--   select proname, proconfig
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and proname in ('notify_booking_change', '_services_set_updated_at',
--                      'send_booking_email', 'get_booked_slots');
--   -- Forventet: alle har 'search_path=...' i proconfig.
--
--   -- REVOKE EXECUTE er gjeldende:
--   select proname,
--          has_function_privilege('anon',          oid, 'execute') as anon,
--          has_function_privilege('authenticated', oid, 'execute') as auth
--     from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and proname in ('notify_booking_change', 'send_booking_email',
--                      '_services_set_updated_at', 'get_booked_slots');
--   -- Forventet:
--   --   notify_booking_change       | f | f
--   --   send_booking_email          | f | f
--   --   _services_set_updated_at    | f | f
--   --   get_booked_slots            | t | t
--
--   -- anon insert bookings har constrained WITH CHECK:
--   select policyname, cmd, with_check
--     from pg_policies
--    where tablename = 'bookings' and policyname = 'anon insert bookings';
--   -- Forventet: with_check inneholder status-sjekk + length-sjekker.
--
-- DASHBOARD-STEG (kan ikke gjøres via SQL):
--   Authentication → Policies → Password Strength →
--   toggle "Check passwords against HaveIBeenPwned" → save.
--   Lukker auth_leaked_password_protection-linter-funn.
-- ============================================================
