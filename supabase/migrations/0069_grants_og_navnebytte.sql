-- ============================================================
-- 0069_grants_og_navnebytte.sql                      2026-09-01
-- ------------------------------------------------------------
-- To feil som begge stammer fra at en migrasjon som allerede er
-- applisert ikke kjøres på nytt.
--
--
-- FEIL 1: «permission denied for table bookings»
--
-- Symptomet så ut som et rolle- eller RLS-problem, men er verken
-- eller. Feilen har SQLSTATE 42501 med hintet «GRANT SELECT ON
-- public.bookings TO authenticated», og det er en table-privilege-
-- feil. En RLS-avvisning på SELECT gir tom liste, ikke 403.
--
-- Målt på den faktiske databasen (supabase db dump) har rollen
-- authenticated disse rettighetene på kjernetabellene:
--
--   bookings        REFERENCES, TRIGGER, TRUNCATE, MAINTAIN
--   services        REFERENCES, TRIGGER, TRUNCATE, MAINTAIN
--   blocked_slots   REFERENCES, TRIGGER, TRUNCATE, MAINTAIN
--   staff_services  REFERENCES, TRIGGER, TRUNCATE, MAINTAIN
--   audit_log       REFERENCES, TRIGGER, MAINTAIN
--
-- Altså alt UNNTATT SELECT, INSERT, UPDATE og DELETE.
--
-- Årsaken er at Supabase sine «default privileges» ikke er i
-- effekt i dette prosjektet. Det ble oppdaget underveis og står
-- notert i 0036: «standard default privileges-auto-grant er ikke i
-- effekt her». Fra og med 0023 gir hver ny tabell derfor sine egne
-- grants: waitlist (0023), reviews (0036/0037), contact_messages
-- (0039), exercise_documents (0040), staff_members (0041),
-- holidays (0045), special_open_days (0059), journal_audit (0060),
-- push_subscriptions (0063).
--
-- Tabellene som ble opprettet FØR den oppdagelsen ble aldri
-- ettergått: bookings og blocked_slots (0000), audit_log (0002),
-- services og staff_services (0008). Ingen migrasjon fjerner
-- rettighetene deres; de har aldri hatt dem.
--
-- Rollen er ikke problemet: app_metadata.role = 'admin' ligger på
-- brukeren og kommer med i JWT-en. RLS-policyene fra 0010, 0012 og
-- 0016 leser (auth.jwt() -> 'app_metadata' ->> 'role') og er
-- riktige. Feilen ligger ett lag under RLS.
--
-- journal_entries står bevisst uten grants. 0051 la lesing og
-- skriving i get_journal_entries() og create_journal_entry(), som
-- logger hvert oppslag. Adminsidene bruker bare de RPC-ene, og
-- direkte tilgang skal fortsatt være stengt.
--
--
-- FEIL 2: Erik Westengen står igjen i databasen
--
-- Navnebyttet ble gjort i migrasjonsfilene, men 0008, 0041, 0065 og
-- 0067 var allerede applisert. `supabase db push` hopper over dem,
-- så endringen nådde aldri databasen. 0041 bruker dessuten
-- `on conflict (staff_id) do nothing`, så selv en re-kjøring ville
-- latt de gamle radene stå.
--
-- Resultatet er en database som spriker: 0068 var ny og ble kjørt,
-- og demo_seed() der lager bookinger med staff_id = 'markus' — en
-- behandler som ikke finnes i staff_members, der raden fortsatt
-- heter 'erik'. Kalenderen viser altså timer hos noen som ikke står
-- i behandlerlista.
--
-- Idempotent. Atomisk via begin/commit.
-- ============================================================

begin;

-- ============================================================
-- (a) De manglende tabellrettighetene
-- ------------------------------------------------------------
-- Verbene er valgt etter hva adminpanelet faktisk gjør, ikke etter
-- hva som er enklest. RLS-policyene bestemmer fortsatt HVILKE rader
-- hver rolle ser; grants bestemmer bare at tabellen kan røres i det
-- hele tatt.
-- ============================================================

-- Kalender, bestillingsadministrasjon og kundekort: full CRUD.
grant select, insert, update, delete on public.bookings to authenticated;

-- tjenester.html oppretter, endrer og deaktiverer tjenester.
grant select, insert, update, delete on public.services to authenticated;

-- Koblingen tjeneste/behandler settes i samme skjerm. Ingen update:
-- en kobling finnes eller finnes ikke.
grant select, insert, delete on public.staff_services to authenticated;

-- stengte-tider.html åpner og lukker enkelttimer.
grant select, insert, update, delete on public.blocked_slots to authenticated;

-- Audit-loggen skal kunne leses av admin og skrives av alle
-- innloggede. Den skal ALDRI kunne endres eller slettes; 0057
-- fjernet update/delete/truncate med vilje, og de gjenopprettes ikke.
grant select, insert on public.audit_log to authenticated;


-- ============================================================
-- (b) Erik -> Markus i databasen
-- ------------------------------------------------------------
-- staff_id er text uten fremmednøkler, så navnet må rettes i hver
-- tabell som bærer det. Rekkefølgen er likegyldig; det finnes ingen
-- referanseintegritet å bryte.
--
-- Kjøres som postgres, så skrivesperren fra 0066 slipper oss forbi.
-- ============================================================
do $$
declare
  t text;
begin
  -- staff_members har staff_id som primærnøkkel. Finnes 'markus'
  -- allerede (fra en tidligere delvis kjøring), fjernes 'erik' i
  -- stedet for at vi får en nøkkelkollisjon.
  if exists (select 1 from public.staff_members where staff_id = 'markus')
     and exists (select 1 from public.staff_members where staff_id = 'erik') then
    delete from public.staff_members where staff_id = 'erik';
  else
    update public.staff_members set staff_id = 'markus' where staff_id = 'erik';
  end if;

  -- Alle tabeller som bærer en staff_id.
  foreach t in array array[
    'staff_services', 'bookings', 'waitlist', 'blocked_slots',
    'journal_entries', 'special_open_days'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('update public.%I set staff_id = %L where staff_id = %L',
                     t, 'markus', 'erik');
    end if;
  end loop;
end $$;

-- Visningsnavn. Apostrofen i «Markus' terapeuter» må dobles i SQL.
update public.staff_members
   set name = 'Markus Westengen',
       role = 'Behandler',
       bio  = 'Timen settes opp hos Markus. Oppdiktet behandler i en oppdiktet klinikk.'
 where staff_id = 'markus';

update public.staff_members
   set name = 'Markus'' terapeuter',
       role = 'Opplært av Markus selv'
 where staff_id = 'terapeut';

update public.bookings
   set staff_name = replace(replace(staff_name, 'Eriks', 'Markus'''), 'Erik', 'Markus')
 where staff_name like '%Erik%';

update public.waitlist
   set staff_name = replace(replace(staff_name, 'Eriks', 'Markus'''), 'Erik', 'Markus')
 where staff_name like '%Erik%';

update public.journal_entries
   set staff_name = replace(replace(staff_name, 'Eriks', 'Markus'''), 'Erik', 'Markus')
 where staff_name like '%Erik%';


-- ============================================================
-- (c) Den gamle tjenestekatalogen
-- ------------------------------------------------------------
-- 0068 deaktiverte 'markus-konsult' og 'markus-videre'. De slugene
-- finnes ikke i denne databasen: her heter de fortsatt 'erik-*',
-- fordi 0008 var applisert før navnebyttet. Derfor sto de gamle
-- tjenestene igjen som aktive ved siden av de fire nye.
-- ============================================================
update public.services
   set is_active = false
 where slug in ('erik-konsult', 'erik-videre', 'ter-konsult', 'ter-videre',
                'markus-konsult', 'markus-videre');


-- ============================================================
-- (d) Demobrukernes app_metadata
-- ------------------------------------------------------------
-- Rollen var riktig hele veien, men staff_id og staff_name pekte på
-- 'erik'/'Erik Westengen'. Frontend leser begge derfra (shared/auth.js),
-- så en terapeut ville fått feil kalender etter navnebyttet.
--
-- jsonb || jsonb overskriver bare nøklene vi oppgir, så provider,
-- providers og demo-flagget står urørt.
-- ============================================================
update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(
         'role',       'admin',
         'staff_id',   'markus',
         'staff_name', 'Markus Westengen'),
       raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
         'full_name',  'Markus Westengen')
 where email = 'admin@westengenklinikk.example';

update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(
         'role',       'therapist',
         'staff_id',   'sofie',
         'staff_name', 'Sofie Aune'),
       raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
         'full_name',  'Sofie Aune')
 where email = 'terapeut@westengenklinikk.example';

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Rettighetene er på plass:
--    select table_name, string_agg(privilege_type, ', ' order by privilege_type)
--      from information_schema.role_table_grants
--     where grantee = 'authenticated' and table_schema = 'public'
--       and table_name in ('bookings','services','staff_services',
--                          'blocked_slots','audit_log')
--     group by table_name order by table_name;
--    -- Forvent SELECT på alle fem, og INSERT/UPDATE/DELETE der
--    --   (a) gir det. audit_log skal IKKE ha UPDATE eller DELETE.
--
-- B) Ingen Erik igjen:
--    select staff_id, name from public.staff_members order by sortering;
--    select distinct staff_id, staff_name from public.bookings;
--    select raw_app_meta_data from auth.users
--     where email like '%@westengenklinikk.example';
--
-- C) Bookingene peker på en behandler som finnes:
--    select b.staff_id from public.bookings b
--     where b.staff_id is not null
--       and not exists (select 1 from public.staff_members m
--                        where m.staff_id = b.staff_id);
--    -- Forvent 0 rader.
--
-- D) Bare de fire nye tjenestene er aktive:
--    select slug, is_active from public.services order by sort_order;
-- ============================================================
