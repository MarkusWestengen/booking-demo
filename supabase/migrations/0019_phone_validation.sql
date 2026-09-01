-- ============================================================
-- 0019_phone_validation.sql                          2026-05-16
-- ------------------------------------------------------------
-- Lukker P1-6 fra audit 2026-05-15: anon-insert-policyen fra 0016
-- krever bare `length(phone) > 0`, og admin-booking via JWT går
-- forbi den policyen helt. Frontend (booking-flow.js) krever minst
-- 8 sifre, men admin-flyten i shared/admin-booking.js gjenbruker
-- ikke den valideringen. Resultat: admin kan legge inn bookinger
-- med "ring meg på 9067..." eller tom phone, og Resend-triggeren
-- sender e-post med skitten data.
--
-- Defense-in-depth: legg en CHECK constraint på bookings.phone som
-- krever minst 8 sifre etter strip av alle non-digit-tegn. Norske
-- mobilnumre er 8 sifre; landskoder/separatorer/parenteser slipper
-- gjennom uten å telle. Frontend-validering beholdes som UX-første-
-- forsvarslinje; denne constrainen er backstop.
--
-- ============================================================
-- APPLY-FLYT (Markus kjører manuelt i Dashboard → SQL Editor):
--
--   1. Lim inn hele filen i SQL Editor → kjør.
--   2. Les NOTICE-output:
--        "Rows that would fail phone CHECK: N"
--      Hvis N = 0 → migrasjonen går rent gjennom VALIDATE.
--      Hvis N > 0 → migrasjonen vil KRÆSJE på VALIDATE-steget.
--        Stopp, rydd de eksisterende radene manuelt (UPDATE eller
--        slett), kjør så filen på nytt. Constrainen lagres som
--        NOT VALID hvis VALIDATE kræsjer, så CONSTRAINT-navnet er
--        opptatt og må droppes før retry:
--          alter table public.bookings drop constraint bookings_phone_min_digits;
--   3. Forventet sluttilstand:
--        select conname, convalidated
--          from pg_constraint c
--          join pg_class t on t.oid = c.conrelid
--         where t.relname = 'bookings' and c.conname = 'bookings_phone_min_digits';
--        → 1 rad, convalidated = true.
-- ============================================================
--
-- IKKE ENDRET i denne migrasjonen:
--   - RLS-policies (anon insert bookings WITH CHECK osv. fra 0016)
--   - Andre kolonner i bookings
--   - Eksisterende rader (ingen UPDATE/DELETE — kun VALIDATE)
--   - Frontend phone-validering (beholdes uavhengig av denne)
--
-- Idempotent: DO-blokk med pg_constraint-eksistens-sjekk gjør re-apply
-- til no-op hvis constrainen allerede finnes og er validated.
-- ============================================================

begin;

-- ============================================================
-- Pre-check: hvor mange eksisterende rader ville feilet constrainen?
-- Bare NOTICE — endrer ingenting. Lar operatøren bestemme om de skal
-- rydde data først, eller la VALIDATE kræsje og fikse manuelt.
-- ============================================================
do $$
declare
  bad_count int;
begin
  select count(*) into bad_count
    from public.bookings
   where length(regexp_replace(phone, '[^0-9]', '', 'g')) < 8;
  raise notice 'Rows that would fail phone CHECK: %', bad_count;
  if bad_count > 0 then
    raise notice 'VALIDATE-steget vil kreasje. Rydd dataene foer apply.';
  end if;
end $$;

-- ============================================================
-- Legg til constrainen som NOT VALID hvis den ikke finnes fra fœr.
-- NOT VALID gir kun lås på rader som faktisk valideres (= ingen
-- lås i dette steget). Senere VALIDATE-steg sjekker eksisterende
-- rader uten å holde en exclusive lock — bare SHARE UPDATE EXCLUSIVE.
-- ============================================================
do $$
begin
  if not exists (
    select 1
      from pg_constraint c
      join pg_class     t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public'
       and t.relname = 'bookings'
       and c.conname = 'bookings_phone_min_digits'
  ) then
    execute $ddl$
      alter table public.bookings
        add constraint bookings_phone_min_digits
        check (length(regexp_replace(phone, '[^0-9]', '', 'g')) >= 8)
        not valid
    $ddl$;
    raise notice 'Constraint bookings_phone_min_digits opprettet som NOT VALID.';
  else
    raise notice 'Constraint bookings_phone_min_digits finnes fra foer — hopper over CREATE.';
  end if;
end $$;

-- ============================================================
-- Valider mot eksisterende rader. Kjøres uavhengig av om constrainen
-- ble opprettet i forrige steg (idempotent — VALIDATE på en allerede
-- validert constraint er no-op).
--
-- Hvis dette steget kræsjer:
--   ERROR: check constraint "bookings_phone_min_digits" of relation "bookings" is violated by some row
-- Da må operatøren rydde dataene manuelt og kjøre filen på nytt.
-- Constraint-en blir stående som NOT VALID til VALIDATE lykkes.
-- ============================================================
alter table public.bookings
  validate constraint bookings_phone_min_digits;

commit;

-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--
--   -- Constraint finnes og er validert:
--   select conname, convalidated, pg_get_constraintdef(c.oid)
--     from pg_constraint c
--     join pg_class t on t.oid = c.conrelid
--    where t.relname = 'bookings' and c.conname = 'bookings_phone_min_digits';
--   -- Forventet: convalidated = true, def = CHECK ((length(...) >= 8))
--
--   -- Forsøk på ugyldig INSERT skal feile med 23514 (check_violation):
--   --   insert into public.bookings(...phone='abc',...) → ERROR
-- ============================================================
