-- ============================================================
-- Westengen Klinikk — Sikre admin-skrivetilgang til holidays (hele-klinikken-stenging)
-- Migration 0045
-- ------------------------------------------------------------
-- BAKGRUNN: DEL 6 gir stengte-tider.html et admin-UI for å stenge
-- HELE klinikken på gitte datoer (helligdag/ferie). Mekanismen finnes
-- allerede i booking-motoren — generateSlotsForDay() returnerer [] for
-- datoer som ligger i holidays-tabellen, for ALLE behandlere. UI-et
-- skriver derfor bare til holidays (kolonnen `date`, PK).
--
-- holidays-RLS er allerede satt opp (0018): admin kan insert/update/
-- delete, admin+therapist kan select. anon fikk SELECT-only i 0027.
-- MEN: ingen committed migrasjon har eksplisitt GRANT-et tabell-
-- privilegier til `authenticated` på holidays — den eksisterende
-- skrivetilgangen stammer trolig fra Supabase «default privileges»
-- (samme situasjon som beskrevet i 0037 for reviews). Hvis den default-
-- en mangler i prod, vil admin-UI-et feile med «permission denied» til
-- tross for at RLS-policyene tillater det.
--
-- FIKS (defensiv): REVOKE ALL fra klient-rollene, deretter GRANT kun
-- det som trengs — så holidays matcher samme eksplisitte mønster som
-- reviews (0037) og waitlist (0023), uavhengig av default privileges.
-- RLS-policyene fra 0018 re-asserteres verbatim slik at hele-klinikken-
-- stengingen er garantert å virke.
--   - anon:          SELECT (offentlig booking-side leser holidays)
--   - authenticated: SELECT + INSERT + UPDATE + DELETE
--                    RLS gater skriving til role='admin', lesing til
--                    role in ('admin','therapist').
-- postgres/service_role røres IKKE.
--
-- Idempotent (REVOKE/GRANT + drop policy if exists/create er trygt å
-- re-kjøre). Sannsynligvis et no-op i prod hvis default-grantene finnes
-- — men da er den harmløs. Avhenger av at holidays-tabellen + 0018 +
-- 0027 er applisert.
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- ---- Tabell-privilegier: rydd og gi minste nødvendige ----
revoke all on public.holidays from anon, authenticated;

grant select on public.holidays to anon;
grant select, insert, update, delete on public.holidays to authenticated;

-- ---- RLS-policyer (re-assertert verbatim fra 0018) ----
-- RLS er allerede aktivert på holidays (den gamle oppsettsguiden). Disse policyene
-- er den faktiske gaten; tabell-grantene over er bare «døråpneren».
drop policy if exists "Holidays read: admin or therapist" on public.holidays;
drop policy if exists "Holidays insert: admin"            on public.holidays;
drop policy if exists "Holidays update: admin"            on public.holidays;
drop policy if exists "Holidays delete: admin"            on public.holidays;

create policy "Holidays read: admin or therapist"
  on public.holidays for select
  to authenticated
  using (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin', 'therapist')
  );

create policy "Holidays insert: admin"
  on public.holidays for insert
  to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "Holidays update: admin"
  on public.holidays for update
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "Holidays delete: admin"
  on public.holidays for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
--   select grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_schema = 'public' and table_name = 'holidays'
--     and grantee in ('anon', 'authenticated')
--   order by grantee, privilege_type;
--
-- Forventet:
--   anon          | SELECT
--   authenticated | DELETE
--   authenticated | INSERT
--   authenticated | SELECT
--   authenticated | UPDATE
--
-- Funksjonell røyktest:
--   - Admin på stengte-tider.html: «Steng hele klinikken» for en dato →
--     raden dukker opp i holidays, og bestillingssiden viser ingen ledige
--     tider den dagen (for alle behandlere). «Åpne dagen igjen» fjerner den.
--   - Terapeut ser IKKE «Steng hele klinikken»-kortet (data-admin-only) og
--     kan uansett ikke insert/delete (RLS).
-- ============================================================
