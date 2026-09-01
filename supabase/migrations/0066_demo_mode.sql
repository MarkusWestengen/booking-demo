-- ============================================================
-- 0066_demo_mode.sql                                 2026-09-01
-- ------------------------------------------------------------
-- Skrivesperre for demoen.
--
-- PROBLEMET
-- Innloggingen til adminpanelet er publisert åpent. Uten en sperre
-- kan første besøkende slette alle behandlerne, tømme kalenderen
-- eller skrive noe stygt i en journal, og demoen er ødelagt for
-- alle etterpå.
--
-- LØSNINGEN, OG HVA DEN IKKE ER
-- Den nærliggende reflekser er å skru av knappene. Det er feil her:
-- poenget med demoen er nettopp å vise at knappene finnes og hva de
-- gjør. En grå «Slett»-knapp demonstrerer ingenting.
--
-- Derfor er skillet lagt et annet sted enn mellom «lese» og
-- «skrive». Det går mellom RADER:
--
--   * Radene som følger med demoen (is_demo_seed = true) kan leses,
--     åpnes, filtreres og sorteres, men ikke endres eller slettes.
--     Et forsøk går helt fram til databasen og blir avvist der, med
--     en forklaring frontend viser som en toast: hva som ville
--     skjedd i drift, og hvorfor det ikke skjedde nå.
--
--   * Radene den besøkende lager selv er helt vanlige rader. Opprett
--     en booking, rediger den, flytt den, avlys den, slett den —
--     hele CRUD-syklusen kan demonstreres på ekte data, uten at
--     grunnoppsettet kan rives.
--
-- Ingen knapper skjules, ingen felt låses, ingen ruter er stengt.
-- Systemet oppfører seg som seg selv; det er bare seks-sju rader
-- som ikke lar seg rive.
--
-- HVORDAN AVVISNINGEN NÅR FRAM
-- Triggeren kaster SQLSTATE «PT403». PostgREST tolker prefikset PT
-- som «sett HTTP-status til dette tallet», så klienten får 403 med
-- meldingen i JSON-feltet «message». shared/demo-mode.js lytter på
-- alle 403-svar, kjenner igjen strengen «demo_readonly» og viser
-- forklaringen. Ett sted i frontend, ingen endring i noe kallsted.
--
-- HVEM SLIPPER FORBI
-- service_role, postgres og supabase_admin. Det er ikke en bakdør,
-- men en nødvendighet: påminnelses-cronen (0014, 0062) og
-- e-postfunksjonene skriver reminder_sent_at tilbake på bookinger,
-- og nullstillingen i 0067 må kunne rydde. Ingen av de rollene er
-- tilgjengelige fra nettleseren.
--
-- Idempotent. Atomisk via begin/commit.
-- ============================================================

begin;

-- ============================================================
-- (a) Markørkolonnen
-- ------------------------------------------------------------
-- default false: alt som lages heretter er den besøkendes eget og
-- fritt å endre. Bare radene som allerede lå der når denne
-- migrasjonen kjører, blir markert som seed (steg c).
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'bookings', 'blocked_slots', 'holidays',
    'services', 'staff_services', 'staff_members',
    'waitlist', 'reviews', 'contact_messages',
    'journal_entries', 'exercise_documents', 'special_open_days'
  ] loop
    -- to_regclass gir null hvis tabellen ikke finnes. Det gjør filen
    -- trygg å kjøre mot en database der enkelte valgfrie migrasjoner
    -- er hoppet over.
    if to_regclass('public.' || t) is not null then
      execute format(
        'alter table public.%I add column if not exists is_demo_seed boolean not null default false',
        t);
      execute format(
        'comment on column public.%I.is_demo_seed is %L',
        t,
        'true = raden fulgte med demo-oppsettet og er skrivebeskyttet '
        '(migrasjon 0066). false = opprettet av en besøkende, fritt '
        'redigerbar, og slettes ved nattlig nullstilling.');
    end if;
  end loop;
end $$;


-- ============================================================
-- (b) Vaktposten
-- ------------------------------------------------------------
-- Én funksjon for alle tabellene. tg_table_name gir oss tabellnavnet
-- til feilmeldingen, så forklaringen blir konkret.
--
-- Tre regler:
--   INSERT — is_demo_seed tvinges til false. Ingen kan gi sin egen
--            rad beskyttelse og dermed låse den for neste besøkende.
--   UPDATE — avvis hvis raden ER seed. Ellers tvinges flagget til
--            false, så en rad ikke kan «forfremmes» via en update.
--   DELETE — avvis hvis raden er seed.
-- ============================================================
create or replace function public.demo_guard()
returns trigger
language plpgsql
as $$
begin
  -- Bakenforliggende roller: cron, edge-funksjoner, nullstillingen.
  -- Ingen av dem er nåbare fra en nettleser.
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if tg_op = 'INSERT' then
    new.is_demo_seed := false;
    return new;
  end if;

  if coalesce(old.is_demo_seed, false) then
    raise sqlstate 'PT403' using
      message = 'demo_readonly',
      detail  = format('%s er en del av demo-oppsettet og kan ikke %s.',
                       tg_table_name,
                       case when tg_op = 'DELETE' then 'slettes' else 'endres' end),
      hint    = 'Dette er en demo. Endringen ble ikke lagret, men i drift '
             || 'ville den blitt utført og ført i audit-loggen. Rader du '
             || 'oppretter selv kan du endre og slette fritt.';
  end if;

  if tg_op = 'UPDATE' then
    new.is_demo_seed := false;
    return new;
  end if;

  return old;
end $$;

comment on function public.demo_guard() is
  'Skrivesperre for demo-seed-rader. Kaster PT403 «demo_readonly», som '
  'PostgREST oversetter til HTTP 403 og shared/demo-mode.js viser som '
  'en forklarende toast. Migrasjon 0066.';


-- ============================================================
-- (c) Marker det som allerede ligger der, og heng på triggerne
-- ------------------------------------------------------------
-- Rekkefølgen er ikke tilfeldig: markeringen MÅ skje før triggeren
-- finnes, ellers ville UPDATE-en som setter flagget blitt avvist av
-- sin egen vaktpost på andre gjennomkjøring.
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'bookings', 'blocked_slots', 'holidays',
    'services', 'staff_services', 'staff_members',
    'waitlist', 'reviews', 'contact_messages',
    'journal_entries', 'exercise_documents', 'special_open_days'
  ] loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;

    -- Slipp en eventuell eksisterende trigger først, så markeringen
    -- går gjennom også ved re-apply.
    execute format('drop trigger if exists demo_guard_trg on public.%I', t);

    execute format(
      'update public.%I set is_demo_seed = true where is_demo_seed = false', t);

    execute format(
      'create trigger demo_guard_trg before insert or update or delete '
      'on public.%I for each row execute function public.demo_guard()', t);
  end loop;
end $$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Kolonnen finnes overalt:
--    select table_name from information_schema.columns
--     where table_schema='public' and column_name='is_demo_seed'
--     order by table_name;
--
-- B) Triggerne henger på:
--    select event_object_table, trigger_name
--      from information_schema.triggers
--     where trigger_name = 'demo_guard_trg'
--     order by event_object_table;
--
-- C) Sperren biter — kjør som authenticated, ikke som postgres i
--    SQL-editoren (der slipper du forbi med vilje):
--      update public.staff_members set name = 'Test' where staff_id='erik';
--    -- Forvent: ERROR ... demo_readonly
--
-- D) Egne rader er frie:
--    Opprett en booking gjennom bestillingsflyten, åpne den i admin,
--    endre tidspunktet, og slett den. Alle tre skal gå gjennom.
--
-- E) Ende-til-ende i UI: logg inn som admin, prøv å deaktivere
--    behandleren Erik Westengen. Knappen skal virke, dialogen skal
--    åpne seg, og først når lagringen når databasen skal du få
--    toasten «Demo · ikke lagret».
-- ============================================================
