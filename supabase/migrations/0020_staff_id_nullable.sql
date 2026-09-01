-- ============================================================
-- 0020_staff_id_nullable.sql                        2026-05-20
-- ------------------------------------------------------------
-- Terapeut-arkitektur: kunden velger IKKE en spesifikk terapeut
-- når de booker en "Eriks terapeuter"-tjeneste. Slike bookinger
-- lagres nå UFORDELT (staff_id = NULL), og admin/sekretær tildeler
-- en av de fem navngitte terapeutene manuelt i booking-admin.
-- Erik Westengen-bookinger er uendret (staff_id = 'erik').
--
-- Denne migrasjonen:
--   (a) Gjør bookings.staff_id nullable (var NOT NULL fra
--       den gamle oppsettsguiden (nå 0000_base_schema.sql) sitt opprinnelige skjema).
--   (b) Relakser "anon insert bookings"-policyen fra 0016 slik at
--       en ufordelt kunde-booking (staff_id IS NULL) ikke avvises
--       av WITH CHECK. Alle andre krav fra 0016 beholdes.
--   (c) Legger til en lett BEFORE INSERT-trigger som hindrer at
--       mer enn 5 ufordelte bookinger havner på samme (date, time)
--       — et grovt sikkerhetsnett bak frontend sin gruppe-
--       tilgjengelighet (getGroupAvailability). bookings_active_
--       slot_unique beskytter ikke NULL-rader (NULL er distinkt i
--       unike indekser), så uten dette finnes ingen DB-grense.
--
-- IKKE ENDRET (bevisst):
--   - SELECT/UPDATE-policyene fra 0018 håndterer NULL korrekt
--     allerede: admin ser alt; therapist sin "staff_id = jwt.
--     staff_id" ekskluderer NULL automatisk; admin kan UPDATE
--     enhver rad (= tildeling). Vi rører dem ikke.
--   - send_booking_email-triggeren — uendret (kunde-bekreftelse
--     er et eget spor som krever verifisert Resend-domene).
--   - bookings_active_slot_unique — uendret.
--
-- Idempotent: drop not null er no-op om kolonnen alt er nullable;
-- drop policy if exists + create; create or replace function;
-- drop trigger if exists + create. Atomisk via begin/commit.
-- ============================================================

begin;

-- ============================================================
-- (a) staff_id nullable --------------------------------------
-- Eksisterende staff_id-data er uendret — kun NOT NULL-
-- constrainten fjernes. Gamle bookinger beholder sin staff_id.
-- ============================================================
alter table public.bookings
  alter column staff_id drop not null;

-- ============================================================
-- (b) Relakser "anon insert bookings" ------------------------
-- 0016 sin WITH CHECK krevde staff_id IS NOT NULL. En ufordelt
-- "Eriks terapeuter"-booking (staff_id = NULL) ville derfor blitt
-- avvist. Vi fjerner KUN det leddet — status='confirmed', ikke-
-- tomme PII-felter og non-null service_id/date/time beholdes.
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
    and service_id is not null
    and date is not null
    and time is not null
  );

-- ============================================================
-- (c) Kapasitetstak for ufordelte bookinger ------------------
-- bookings_active_slot_unique (0004) er en unik indeks på
-- (staff_id, date, time). Postgres regner NULL som distinkt, så
-- ubegrenset antall staff_id=NULL-rader kan havne på samme slot.
-- Pool-en har 5 terapeuter — denne triggeren avviser INSERT av
-- en ufordelt booking når det alt finnes 5 aktive ufordelte på
-- samme (date, time).
--
-- SECURITY DEFINER er nødvendig: triggeren kjøres av anon (kunde-
-- insert), som etter 0010 ikke har SELECT på bookings. Uten
-- DEFINER ville count-spørringen returnert 0 (RLS) og taket aldri
-- slått inn. search_path pinnes (linter function_search_path_
-- mutable). REVOKE EXECUTE: funksjonen skal kun kjøre i trigger-
-- kontekst, aldri som RPC (samme mønster som 0016).
-- ============================================================
create or replace function public.enforce_unassigned_capacity()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  unassigned_count integer;
begin
  -- Gjelder kun nye aktive, ufordelte bookinger.
  if new.staff_id is null and new.status in ('confirmed', 'completed') then
    select count(*) into unassigned_count
      from public.bookings
     where staff_id is null
       and date = new.date
       and "time" = new.time
       and status in ('confirmed', 'completed');
    if unassigned_count >= 5 then
      raise exception
        'Ingen ledige terapeuter på % kl. %', new.date, to_char(new.time, 'HH24:MI')
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

comment on function public.enforce_unassigned_capacity() is
  'BEFORE INSERT-trigger på bookings: avviser en ufordelt (staff_id '
  'IS NULL) booking når 5 ufordelte alt finnes på samme (date, time). '
  'Grovt sikkerhetsnett — presis kapasitet håndteres av frontend '
  'getGroupAvailability(). Lagt til i migrasjon 0020.';

revoke execute on function public.enforce_unassigned_capacity()
  from anon, authenticated, public;

drop trigger if exists trg_unassigned_capacity on public.bookings;
create trigger trg_unassigned_capacity
  before insert on public.bookings
  for each row
  execute function public.enforce_unassigned_capacity();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) staff_id er nullable:
--    select column_name, is_nullable
--      from information_schema.columns
--     where table_name = 'bookings' and column_name = 'staff_id';
--    Forventet: 1 rad, is_nullable = 'YES'.
--
-- B) anon insert-policy mangler staff_id-leddet:
--    select with_check
--      from pg_policies
--     where tablename = 'bookings' and policyname = 'anon insert bookings';
--    Forventet: uttrykket inneholder IKKE "staff_id IS NOT NULL".
--
-- C) Kapasitets-triggeren finnes:
--    select tgname
--      from pg_trigger
--     where tgrelid = 'public.bookings'::regclass
--       and tgname = 'trg_unassigned_capacity';
--    Forventet: 1 rad.
--
-- D) Smoke-test taket (kjør i SQL Editor — bruk en framtidig
--    test-dato, og rydd opp radene etterpå):
--    -- 5 ufordelte INSERTs på samme slot skal gå gjennom,
--    -- den 6. skal feile med SQLSTATE 23514 (check_violation).
-- ============================================================
