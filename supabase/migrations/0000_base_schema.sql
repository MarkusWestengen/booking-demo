-- ============================================================
-- 0000_base_schema.sql                               2026-09-01
-- ------------------------------------------------------------
-- Basisskjemaet. Alle andre migrasjoner bygger på dette.
--
-- BAKGRUNN
-- Frem til nå har migrasjonshistorikken startet på 0001 og
-- forutsatt at de tre grunntabellene allerede fantes: de ble
-- opprettet ved å lime SQL fra oppsettsguiden inn i Supabase sin
-- SQL-editor, én gang, uten å bli versjonskontrollert. Det holdt
-- så lenge det bare fantes én database. Demoen skal kunne settes
-- opp fra bunnen i et tomt prosjekt, og da må steg null ligge i
-- repoet som alle de andre.
--
-- Denne filen er DDL-en fra den gamle guiden, skrevet om — samme
-- tabeller og kolonner, nye kommentarer, og én bevisst forskjell
-- i sikkerhetsoppsettet (se RLS-avsnittet nederst).
--
-- HVA SOM IKKE ER HER
-- Alt som senere migrasjoner legger til: journal, audit-logg,
-- tjenestekatalog, behandlertabell, venteliste, anmeldelser,
-- meldinger, dokumenter, påminnelser, demo-modus. Kjør
-- migrasjonene i nummerrekkefølge, så bygges resten oppå.
--
-- Idempotent: create table if not exists / create index if not
-- exists / drop policy if exists. Atomisk via begin/commit.
-- ============================================================

begin;

-- ============================================================
-- BESTILLINGER
-- ------------------------------------------------------------
-- Én rad per booket time. Tabellen er bevisst denormalisert:
-- staff_name, service_name, price og duration KOPIERES inn på
-- bestillingen i stedet for å slås opp via nøkkel. Det er et
-- valg, ikke en forglemmelse — en bestilling skal vise hva som
-- faktisk ble avtalt den dagen, også etter at behandleren har
-- byttet navn eller tjenesten har fått ny pris.
--
-- id er text, ikke uuid, fordi frontend genererer den før raden
-- sendes (bestillingen skal kunne mellomlagres lokalt hvis nettet
-- ryker midt i flyten). ref er den korte referansen kunden får i
-- bekreftelsen, av typen «WK-X4F2-1042».
-- ============================================================
create table if not exists public.bookings (
  id           text primary key,
  ref          text not null,

  -- Hvem og hva, frosset på bestillingstidspunktet.
  staff_id     text not null,
  staff_name   text not null,
  service_id   text not null,
  service_name text not null,
  price        integer not null,       -- hele kroner, ikke øre
  duration     integer not null,       -- minutter

  -- Når. date + time er skilt fordi kalenderen slår opp på dato
  -- og ledige tider beregnes per klokkeslett innenfor en dag.
  date         date not null,
  "time"       time not null,          -- reservert ord, må siteres

  -- Kunden.
  name         text not null,
  email        text not null,
  phone        text not null,
  notes        text default '',

  -- confirmed | completed | cancelled. Ingen enum: statusverdiene
  -- har endret seg et par ganger, og en text-kolonne med sjekk i
  -- applikasjonen har vært billigere å leve med enn en type som
  -- må migreres.
  status       text not null default 'confirmed',

  created_at   timestamptz default now()
);

comment on table public.bookings is
  'Bestillinger. Denormalisert med vilje: staff_name/service_name/price/'
  'duration er frosset på bestillingstidspunktet. Opprettet i migrasjon 0000.';

-- Kalenderen henter alltid ut en dag eller en uke om gangen.
create index if not exists bookings_date_idx  on public.bookings (date);
-- Behandlerens egen kalender, og ledig-tid-sjekken i bestillingsflyten.
create index if not exists bookings_staff_idx on public.bookings (staff_id, date);


-- ============================================================
-- BLOKKERTE TIDER
-- ------------------------------------------------------------
-- Enkelttimer en behandler stenger: lunsj, kurs, tannlege.
-- Sammensatt primærnøkkel gjør at samme time ikke kan blokkeres
-- to ganger for samme behandler, uten at vi trenger en egen
-- unique-constraint.
--
-- Merk at dette IKKE er det samme som helligdager under: en
-- blokkering gjelder én behandler, en helligdag gjelder hele
-- klinikken.
-- ============================================================
create table if not exists public.blocked_slots (
  staff_id     text not null,
  date         date not null,
  "time"       time not null,
  primary key (staff_id, date, "time")
);

comment on table public.blocked_slots is
  'Enkelttimer stengt for én behandler. Hele-klinikken-stenging ligger '
  'i public.holidays. Opprettet i migrasjon 0000.';


-- ============================================================
-- STENGTE DAGER
-- ------------------------------------------------------------
-- Datoer der hele klinikken holder stengt. Bare datoen — det
-- finnes ingen delvis stengt dag i denne modellen; skal en dag
-- være halvåpen, blokkeres timene i blocked_slots i stedet.
-- ============================================================
create table if not exists public.holidays (
  date         date primary key
);

comment on table public.holidays is
  'Datoer hele klinikken er stengt. Opprettet i migrasjon 0000.';


-- ============================================================
-- ROW-LEVEL SECURITY
-- ------------------------------------------------------------
-- Her avviker denne filen bevisst fra oppsettsguiden den er
-- skrevet av.
--
-- Guiden slo på RLS og la deretter inn vidåpne policyer: anon
-- kunne lese, endre og slette alt i alle tre tabellene. Det var
-- forsvart med at adminpanelet var passordbeskyttet i frontend og
-- at URL-en ikke var offentlig — altså ikke forsvart i det hele
-- tatt. Migrasjon 0010 stengte lesetilgangen, og 0027 og 0045
-- ryddet resten.
--
-- Å gjenskape den åpne tilstanden her, bare for å lukke den igjen
-- ti migrasjoner senere, ville gitt et vindu der en fersk
-- installasjon står åpen. Derfor oppretter 0000 bare den ene
-- policyen som overlever hele historikken:
--
--     anon kan sette inn en bestilling. Ingenting annet.
--
-- Alt annet — anon SELECT via booked_slots-viewet, innloggede
-- behandleres tilgang, admin-rettigheter på blocked_slots og
-- holidays — kommer i 0010, 0012, 0017, 0018, 0027 og 0045.
-- De migrasjonene bruker «drop policy if exists», så de er
-- upåvirket av at policyene fra guiden aldri ble laget.
--
-- Konsekvens av at RLS er på uten flere policyer: default deny.
-- En fersk database er stille og lukket til de neste
-- migrasjonene åpner nøyaktig det som trengs.
-- ============================================================
alter table public.bookings      enable row level security;
alter table public.blocked_slots enable row level security;
alter table public.holidays      enable row level security;

drop policy if exists "anon insert bookings" on public.bookings;
create policy "anon insert bookings"
  on public.bookings for insert to anon
  with check (true);

comment on policy "anon insert bookings" on public.bookings is
  'Bestillingsskjemaet på den offentlige siden. Eneste skriverett anon '
  'har i basisskjemaet. Lesing skjer via public.booked_slots (0010).';

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Tabellene finnes:
--    select table_name from information_schema.tables
--     where table_schema = 'public'
--       and table_name in ('bookings','blocked_slots','holidays')
--     order by table_name;
--    -- Forvent 3 rader.
--
-- B) RLS er på alle tre:
--    select relname, relrowsecurity from pg_class
--     where relname in ('bookings','blocked_slots','holidays');
--    -- Forvent relrowsecurity = true overalt.
--
-- C) Nøyaktig én policy, og den er anon INSERT på bookings:
--    select tablename, policyname, cmd, roles from pg_policies
--     where schemaname = 'public'
--       and tablename in ('bookings','blocked_slots','holidays');
--    -- Forvent 1 rad: bookings | anon insert bookings | INSERT | {anon}
--
-- D) Indeksene:
--    select indexname from pg_indexes
--     where schemaname='public' and tablename='bookings'
--     order by indexname;
--    -- Forvent bookings_pkey, bookings_date_idx, bookings_staff_idx.
-- ============================================================
