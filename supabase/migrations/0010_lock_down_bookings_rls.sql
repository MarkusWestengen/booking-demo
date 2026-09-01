-- ============================================================
-- 0010_lock_down_bookings_rls.sql                  2026-05-12
-- ------------------------------------------------------------
-- Sikkerhetskritisk lockdown — audit 2026-05-11 punkt 4 +
-- GDPR Art. 32 (sikkerhet i behandlingen).
--
-- Før denne migrasjonen kunne anon SELECT * fra public.bookings
-- og lese pasientdata (navn, e-post, telefon, notater) for alle
-- bookinger i klinikken. Etter migrasjonen:
--
--   - anon har KUN INSERT-tilgang på public.bookings
--   - anon har KUN SELECT på public.booked_slots
--   - authenticated (admin + therapist) har eksplisitt
--     SELECT/INSERT/UPDATE/DELETE på bookings
--   - service_role beholder BYPASSRLS-tilgang (Supabase-default,
--     ingen endring nødvendig)
--
-- View-en booked_slots ble tidligere opprettet manuelt i Supabase
-- Dashboard fra den gamle oppsettsguiden (nå 0000_base_schema.sql) "Hardening"-prosaen og har aldri
-- ligget i migrasjonshistorikken. Denne migrasjonen
-- versjonskontrollerer den. View-definisjonen er identisk med
-- det som ble verifisert via pg_get_viewdef 2026-05-12.
--
-- IKKE STRAMMET INN i denne migrasjonen (TODO senere fase):
--   "anon update bookings" og "anon delete bookings"-policiene fra
--   den gamle oppsettsguiden (nå 0000_base_schema.sql) er fortsatt aktive på policy-nivå. De er
--   nøytralisert i praksis fordi vi REVOKE-er table-grant under
--   (anon har ikke lenger UPDATE/DELETE-privilegium), men selve
--   policy-radene i pg_policies er ikke droppet. Defense-in-depth
--   prinsippet (policy + grant må begge tillate) gjør dem trygge,
--   men ryddes opp i fremtidig migrasjon.
--
-- Idempotent: kan kjøres flere ganger uten effekt utover første.
-- ============================================================

-- ============================================================
-- (a) Versjonskontroller view-en booked_slots --------------
-- Replikat av prod-definisjonen verifisert 2026-05-12. "time"
-- må sitateres siden det er et reservert ord i SQL-standard.
-- security_invoker = false (default i PG15+) gjør at view-en
-- evalueres med eierens (postgres) rolle, så anon kan lese
-- view-en uten å trigge RLS på underliggende public.bookings.
-- ============================================================
create or replace view public.booked_slots as
  select
    staff_id,
    date,
    "time",
    duration
  from public.bookings
  where status = any (array['confirmed'::text, 'completed'::text]);

comment on view public.booked_slots is
  'Public-safe slett av bookings — kun (staff_id, date, time, duration) '
  'for confirmed+completed bookinger. Versjonskontrollert i migrasjon '
  '0010 etter at view-en hadde levd usynkronisert i Dashboard. Brukes '
  'av shared/booking-engine.js getBookedSlots() til anon availability-sjekk.';

-- ============================================================
-- (b) Stram grants på booked_slots -------------------------
-- Supabase grant-er default ALL til anon/authenticated for nye
-- views (via "GRANT ALL IN SCHEMA public"-pattern). På et lese-
-- view er INSERT/UPDATE/DELETE praktisk talt no-ops siden view-en
-- ikke har INSTEAD OF-triggere, men det bryter least-privilege.
-- Vi reduserer til kun SELECT.
-- service_role beholder ALL via egen default-grant; postgres er eier.
-- ============================================================
revoke all on public.booked_slots from anon, authenticated;
grant select on public.booked_slots to anon, authenticated;

-- ============================================================
-- (c) Fjern den åpne anon-SELECT-policyen på bookings -----
-- Selve sikkerhetslukkingen. Etter denne har anon ingen SELECT-
-- policy på public.bookings, og RLS default-deny gjelder.
-- ============================================================
drop policy if exists "anon read bookings" on public.bookings;

-- ============================================================
-- (d) Defense-in-depth: REVOKE alle unødvendige grants -----
-- RLS uten permissive policy blokkerer allerede alt anon prøver
-- utenom INSERT (som har egen policy). Men vi fjerner også de
-- underliggende table-grants så fremtidige feil ikke kan åpne
-- flaten (f.eks. hvis noen ved et uhell legger til en bred
-- "for all"-policy senere). Konsistens-prinsipp:
--   - anon har KUN INSERT på public.bookings
--   - anon har KUN SELECT på public.booked_slots
-- service_role beholder ALL via egen default-grant; postgres er eier.
-- ============================================================
revoke select, update, delete, truncate, references, trigger
  on public.bookings from anon;

-- ============================================================
-- (e) Idempotente policies på bookings --------------------
-- DO-blokk med pg_policies-sjekk gir ekte idempotens (PG15/16 har
-- ikke CREATE POLICY IF NOT EXISTS — kun PG17+). Hvis policy
-- allerede er opprettet manuelt i Dashboard, beholdes evt.
-- tilpassede uttrykk uendret.
--
-- 5 policies sikres:
--   - anon insert bookings       (re-sikres, var i den gamle oppsettsguiden (nå 0000_base_schema.sql))
--   - auth read bookings         (NY)
--   - auth insert bookings       (NY — kreves av admin-booking.js)
--   - auth update bookings       (NY)
--   - auth delete bookings       (NY)
-- ============================================================
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'anon insert bookings'
  ) then
    create policy "anon insert bookings"
      on public.bookings for insert
      to anon
      with check (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'auth read bookings'
  ) then
    create policy "auth read bookings"
      on public.bookings for select
      to authenticated
      using (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'auth insert bookings'
  ) then
    create policy "auth insert bookings"
      on public.bookings for insert
      to authenticated
      with check (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'auth update bookings'
  ) then
    create policy "auth update bookings"
      on public.bookings for update
      to authenticated
      using (true) with check (true);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'bookings'
      and policyname = 'auth delete bookings'
  ) then
    create policy "auth delete bookings"
      on public.bookings for delete
      to authenticated
      using (true);
  end if;
end $$;
