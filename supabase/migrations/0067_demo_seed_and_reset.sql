-- ============================================================
-- 0067_demo_seed_and_reset.sql                       2026-09-01
-- ------------------------------------------------------------
-- Innholdet demoen viser fram, og rutinen som setter det tilbake.
--
-- HVORFOR INNHOLD MÅ GENERERES, IKKE SKRIVES INN
-- Et adminpanel med tom kalender demonstrerer ingenting. Men en
-- håndskrevet liste med faste datoer er ferskvare: tre uker etter
-- at demoen ble satt opp, står kalenderen tom igjen fordi alt ligger
-- i fortiden. Derfor er innholdet en FUNKSJON av dagens dato.
-- Kalenderen har alltid noe forrige uke, noe i dag og noe neste uke,
-- uansett når noen åpner den.
--
-- TO SLAGS SEED
-- Katalogen — tjenester, behandlere, koblingen mellom dem — kommer
-- fra migrasjonene 0008, 0015, 0038 og 0041, og røres ikke her. Den
-- er klinikkens oppsett og skal ligge i ro.
-- Innholdet — bestillinger, journalnotater, meldinger, anmeldelser,
-- venteliste, stengte tider — er det denne filen lager, og det er
-- også det nullstillingen bygger opp igjen.
--
-- NULLSTILLINGEN
-- demo_reset() gjør to ting: sletter alt besøkende har lagt inn, og
-- genererer innholdet på nytt med dagens dato som utgangspunkt. Den
-- kjører hver natt via pg_cron. Sammen med skrivesperren i 0066 gir
-- det en demo som ikke kan ødelegges: seed-radene lar seg ikke rive,
-- og rot som legges oppå forsvinner av seg selv innen et døgn.
--
-- SECURITY DEFINER
-- Begge funksjonene eier seg selv som postgres. Det er nødvendig:
-- vaktposten i 0066 slipper bare privilegerte roller forbi, og både
-- generering og opprydding må kunne skrive på seed-rader. Funksjonene
-- tar ingen parametere, så det finnes ingen flate å injisere i.
--
-- ALLE PERSONER I DATASETTET ER OPPDIKTET.
-- Navn, e-postadresser og telefonnumre er konstruert. E-postene ligger
-- på .example, et toppdomene som per RFC 2606 aldri kan registreres,
-- og telefonnumrene er varianter av 400 00 000.
--
-- Idempotent. Avhenger av 0066 (is_demo_seed + vaktpost).
-- ============================================================

begin;

-- ============================================================
-- (a) Generatoren
-- ============================================================
create or replace function public.demo_seed()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Oppdiktede kunder. Fire kolonner: navn, e-post, telefon, plage.
  kunder text[][] := array[
    array['Sindre Kolstad',   'sindre.kolstad@eksempel.example',   '+47 400 00 011', 'Ryggsmerter, sykling'],
    array['Amalie Holtan',    'amalie.holtan@eksempel.example',    '+47 400 00 012', 'Nakke og hodepine, kontorarbeid'],
    array['Malin Nyhus',      'malin.nyhus@eksempel.example',      '+47 400 00 013', 'Hamstring, gjentatte strekk'],
    array['Jonas Revheim',    'jonas.revheim@eksempel.example',    '+47 400 00 014', 'Kne etter vridning'],
    array['Nora Lindqvist',   'nora.lindqvist@eksempel.example',   '+47 400 00 015', 'Skulder, kastarm'],
    array['Terje Østby',      'terje.ostby@eksempel.example',      '+47 400 00 016', 'Hofte, lange turer'],
    array['Ingvild Rødal',    'ingvild.rodal@eksempel.example',    '+47 400 00 017', 'Korsrygg, løft på jobb'],
    array['Kasper Vold',      'kasper.vold@eksempel.example',      '+47 400 00 018', 'Legg, løping'],
    array['Solveig Bakkan',   'solveig.bakkan@eksempel.example',   '+47 400 00 019', 'Kjeve og nakke'],
    array['Fredrik Aasheim',  'fredrik.aasheim@eksempel.example',  '+47 400 00 020', 'Skulder, styrketrening'],
    array['Hedda Lindgren',   'hedda.lindgren@eksempel.example',   '+47 400 00 021', 'Ankel, gammel skade'],
    array['Oskar Rein',       'oskar.rein@eksempel.example',       '+47 400 00 022', 'Rygg, langkjøring']
  ];

  -- Behandlere som får bestillinger i kalenderen, med pristier.
  -- Erik tar 4000/3000, terapeutene 2000/1500 (jf. 0030 og 0044).
  behandlere text[][] := array[
    array['erik',   'Erik Westengen', 'erik-konsult', 'Konsultasjon hos Erik',   '4000'],
    array['sofie',  'Sofie Aune',     'ter-konsult',  'Konsultasjon hos terapeut', '2000'],
    array['henrik', 'Henrik Dal',     'ter-konsult',  'Konsultasjon hos terapeut', '2000'],
    array['jonas',  'Jonas Riis',     'ter-videre',   'Videre behandling',        '1500']
  ];

  d          date;
  offset_i   int;
  b_i        int;
  k_i        int;
  spredning  int;            -- normalisert 0..n, aldri negativ
  klokke     time;

  -- Klokkeslett per behandler, innenfor behandlerens FAKTISKE arbeidstid
  -- slik shared/booking-engine.js definerer den. Holdes atskilt fordi
  -- Erik og terapeutene ikke har samme dag:
  --
  --   Erik       06:00-13:00, siste starttid 12:30 (30-min time), og
  --              09:30 er fast pause som aldri er bookbar.
  --   Terapeuter 07:00-15:00, siste starttid 14:30.
  --
  -- En seed-time utenfor disse vinduene ville vist en booking i en luke
  -- kalenderen selv nekter aa tilby - det ser ut som en feil i systemet.
  tider_erik text[] := array['07:00', '08:30', '10:30', '12:00'];
  tider_ter  text[] := array['08:00', '10:00', '11:30', '13:30'];
  bid        text;
  bref       text;
  bstatus    text;
  n          int := 0;
begin
  -- ----- Rydd bort forrige generasjon --------------------------
  -- Bare seed-innholdet. Katalogen (services, staff_members,
  -- staff_services) og alt en besøkende har laget står urørt her;
  -- besøkendes rader ryddes av demo_reset(), ikke av generatoren.
  delete from public.journal_entries   where is_demo_seed;
  delete from public.bookings          where is_demo_seed;
  delete from public.contact_messages  where is_demo_seed;
  delete from public.reviews           where is_demo_seed;
  delete from public.waitlist          where is_demo_seed;
  delete from public.blocked_slots     where is_demo_seed;
  delete from public.holidays          where is_demo_seed;

  -- ----- Bestillinger ------------------------------------------
  -- Fra en uke tilbake til ti dager fram. Helger hoppes over —
  -- klinikken er stengt lørdag og søndag, og en kalender med
  -- bookinger på en søndag ser feil ut for alle som kan faget.
  for offset_i in -7 .. 10 loop
    d := current_date + offset_i;
    if extract(isodow from d) >= 6 then
      continue;
    end if;

    -- Tre til fire timer per dag, fordelt på behandlerne. Modulo på
    -- offset gir variasjon uten å bli tilfeldig: samme dato gir samme
    -- kalender, så en demo som vises fram to ganger ser lik ut.
    for b_i in 1 .. array_length(behandlere, 1) loop
      if ((offset_i + b_i) % 3 + 3) % 3 = 0 then
        continue;                       -- lag hull, ikke en full vegg
      end if;

      -- Postgres trunkerer modulo mot null, saa (-5) % 4 = -1. Uten
      -- normaliseringen under ble indeksen 0 eller lavere for alle
      -- dagene foer i dag, og et array-oppslag utenfor 1..n gir i
      -- Postgres NULL i stedet for aa feile. Resultatet var en booking
      -- med time = NULL, avvist av not-null-skranken paa bookings."time".
      spredning := ((offset_i + b_i) % 4 + 4) % 4;

      if behandlere[b_i][1] = 'erik' then
        klokke := tider_erik[1 + spredning]::time;
      else
        klokke := tider_ter[1 + spredning]::time;
      end if;

      k_i     := 1 + ((offset_i * 3 + b_i * 5) % array_length(kunder, 1)
                      + array_length(kunder, 1)) % array_length(kunder, 1);
      n       := n + 1;

      bid     := 'demo-' || to_char(d, 'YYYYMMDD') || '-' || behandlere[b_i][1] || '-' || n;
      bref    := 'WK-' || upper(substr(md5(bid), 1, 4)) || '-' || lpad((1000 + n)::text, 4, '0');
      bstatus := case when d < current_date then 'completed' else 'confirmed' end;

      insert into public.bookings (
        id, ref, staff_id, staff_name, service_id, service_name,
        price, duration, date, "time",
        name, email, phone, notes, status,
        journal_consent, journal_consent_at, created_at, is_demo_seed
      ) values (
        bid, bref,
        behandlere[b_i][1], behandlere[b_i][2],
        behandlere[b_i][3], behandlere[b_i][4],
        behandlere[b_i][5]::int, 30,
        d, klokke,
        kunder[k_i][1], kunder[k_i][2], kunder[k_i][3],
        kunder[k_i][4], bstatus,
        true, now() - (offset_i + 14) * interval '1 day',
        now() - (offset_i + 14) * interval '1 day',
        true
      )
      on conflict do nothing;
    end loop;
  end loop;

  -- ----- Journalnotater ----------------------------------------
  -- Bare på gjennomførte timer, slik det ville vært i drift. Teksten
  -- er bevisst kort og klinisk, og sier ingenting en ekte journal
  -- ville sagt om et ekte menneske.
  insert into public.journal_entries (
    booking_id, patient_email, patient_phone, staff_id, staff_name,
    content, created_at, is_demo_seed
  )
  select
    b.id, b.email, b.phone, b.staff_id, b.staff_name,
    'Undersøkelse av ' || lower(b.notes) || '. Redusert bevegelighet på '
      || 'motsatt side, sannsynlig kompensasjon. Behandlet mykvev og '
      || 'ledd, ga to øvelser til hjemmebruk. Ny vurdering om to uker.',
    b.date + time '16:00',
    true
  from public.bookings b
  where b.is_demo_seed
    and b.status = 'completed'
  on conflict do nothing;

  -- ----- Innkomne meldinger ------------------------------------
  insert into public.contact_messages (name, email, message, status, created_at, is_demo_seed)
  values
    ('Ingvild Rødal', 'ingvild.rodal@eksempel.example',
     'Hei! Jeg har vondt i korsryggen etter en del tunge løft på jobb. '
     || 'Er det Erik eller en av terapeutene som passer best for en første time?',
     'new',      now() - interval '5 hours',  true),
    ('Kasper Vold', 'kasper.vold@eksempel.example',
     'Kan jeg flytte timen min på torsdag til uka etter? Jeg er bortreist.',
     'read',     now() - interval '1 day',    true),
    ('Solveig Bakkan', 'solveig.bakkan@eksempel.example',
     'Takk for sist. Kjeven er mye bedre. Trenger jeg flere timer, eller '
     || 'holder det med øvelsene?',
     'answered', now() - interval '4 days',   true);

  -- ----- Anmeldelser -------------------------------------------
  -- To godkjente og én til vurdering, så moderasjonskøen i admin
  -- ikke står tom.
  insert into public.reviews (name, rating, body, status, created_at, is_demo_seed)
  values
    ('Sindre K.',  5, 'Fant årsaken på første time etter to sesonger med '
                   || 'ryggsmerter. Grundig og rolig gjennomgang.',
     'approved', now() - interval '9 days',  true),
    ('Amalie H.',  5, 'Hodepinen jeg trodde hørte til jobben er nesten borte. '
                   || 'Fikk konkrete øvelser og en forklaring jeg forsto.',
     'approved', now() - interval '21 days', true),
    ('Terje Ø.',   4, 'God hjelp med hoften. Litt vanskelig å få time på '
                   || 'ettermiddagen, men verdt ventingen.',
     'pending',  now() - interval '2 days',  true);

  -- ----- Venteliste --------------------------------------------
  insert into public.waitlist (
    ref, service_id, staff_id, staff_name, name, email, phone,
    preferred_date_from, preferred_date_to, preferred_time_from, preferred_time_to,
    notes, status, created_at, is_demo_seed
  ) values
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0001',
     null, 'erik', 'Erik Westengen',
     'Fredrik Aasheim', 'fredrik.aasheim@eksempel.example', '+47 400 00 020',
     current_date + 1, current_date + 21, time '08:00', time '12:00',
     'Skulder. Kan komme på kort varsel.', 'waiting',
     now() - interval '3 days', true),
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0002',
     null, null, 'Eriks terapeuter',
     'Hedda Lindgren', 'hedda.lindgren@eksempel.example', '+47 400 00 021',
     current_date + 3, null, null, null,
     'Ankel. Fleksibel på tidspunkt.', 'waiting',
     now() - interval '1 day', true);

  -- ----- Stengte tider -----------------------------------------
  -- To blokkeringer som gir kalenderen litt tekstur, og én stengt dag
  -- et stykke fram som ikke krasjer med bestillingene over.
  insert into public.blocked_slots (staff_id, date, "time", is_demo_seed) values
    ('erik',  current_date + 2, time '11:00', true),
    ('erik',  current_date + 2, time '11:30', true),
    ('sofie', current_date + 4, time '13:00', true)
  on conflict do nothing;

  insert into public.holidays (date, is_demo_seed)
  values (current_date + 21, true)
  on conflict do nothing;
end $$;

comment on function public.demo_seed() is
  'Genererer demoens innhold relativt til current_date, markert som '
  'is_demo_seed. Katalogen (services/staff_members/staff_services) røres '
  'ikke. Migrasjon 0067.';


-- ============================================================
-- (b) Nullstillingen
-- ------------------------------------------------------------
-- Sletter alt en besøkende har lagt igjen, tømmer driftsloggene og
-- bygger innholdet opp på nytt. Rekkefølgen følger fremmednøklene:
-- barn før foreldre.
-- ============================================================
create or replace function public.demo_reset()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t text;
begin
  -- Besøkendes rader, barn først.
  delete from public.journal_entries    where not is_demo_seed;
  delete from public.exercise_documents where not is_demo_seed;
  delete from public.bookings           where not is_demo_seed;
  delete from public.waitlist           where not is_demo_seed;
  delete from public.reviews            where not is_demo_seed;
  delete from public.contact_messages   where not is_demo_seed;
  delete from public.blocked_slots      where not is_demo_seed;
  delete from public.holidays           where not is_demo_seed;
  delete from public.special_open_days  where not is_demo_seed;

  -- Katalogendringer en besøkende har rukket å legge til.
  delete from public.staff_services     where not is_demo_seed;
  delete from public.services           where not is_demo_seed;
  delete from public.staff_members      where not is_demo_seed;

  -- Driftslogger. Ingen av dem har seed-rader, og en audit-logg som
  -- vokser i det uendelige er ikke til nytte for noen i en demo.
  -- to_regclass gjør at valgfrie tabeller kan mangle uten at
  -- nullstillingen feiler.
  foreach t in array array[
    'audit_log', 'journal_audit', 'anon_insert_events',
    'document_sends', 'push_subscriptions'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I', t);
    end if;
  end loop;

  -- Og opp igjen, med dagens dato som utgangspunkt.
  perform public.demo_seed();
end $$;

comment on function public.demo_reset() is
  'Sletter besøkendes rader og driftslogger, og kaller demo_seed() på '
  'nytt. Kjøres nattlig av pg_cron-jobben «demo-nightly-reset». Kan også '
  'kalles som RPC av en innlogget admin. Migrasjon 0067.';

-- Kun admin skal kunne trigge en nullstilling manuelt. Vi kan ikke
-- lese rollen inne i en SECURITY DEFINER-funksjon uten å gjøre
-- signaturen mer sammensatt, så gatingen ligger i grantene:
-- authenticated får ikke kalle den direkte.
revoke all on function public.demo_reset()  from public, anon, authenticated;
revoke all on function public.demo_seed()   from public, anon, authenticated;
grant execute on function public.demo_reset() to service_role;
grant execute on function public.demo_seed()  to service_role;


-- ============================================================
-- (c) Første generering
-- ============================================================
select public.demo_seed();

commit;


-- ============================================================
-- (d) Nattlig nullstilling
-- ------------------------------------------------------------
-- Forutsetter pg_cron, som allerede er en forutsetning for
-- påminnelsene i 0014 og 0062. Er ikke extensionen aktivert, hopper
-- blokka over jobben uten å feile — demoen fungerer fint uten, den
-- må bare nullstilles for hånd:
--     select public.demo_reset();
--
-- 04:15 UTC er valgt for å ligge klar av påminnelses-jobbene, og
-- fordi ingen ser på en norsk klinikkdemo klokka seks om morgenen.
-- ============================================================
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron ikke aktivert — hopper over demo-nightly-reset. '
                 'Kjør «select public.demo_reset();» manuelt ved behov.';
    return;
  end if;

  -- Idempotent: fjern eventuell tidligere versjon av jobben først.
  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'demo-nightly-reset';

  perform cron.schedule(
    'demo-nightly-reset',
    '15 4 * * *',
    $cron$ select public.demo_reset(); $cron$
  );
end $$;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Kalenderen har innhold rundt i dag:
--    select date, count(*) from public.bookings
--     where is_demo_seed group by date order by date;
--    -- Forvent rader fra current_date - 7 til current_date + 10,
--    --   uten lørdag og søndag.
--
-- B) Fortid er completed, framtid er confirmed:
--    select status, count(*) from public.bookings
--     where is_demo_seed group by status;
--
-- C) Journalnotater bare på gjennomførte timer:
--    select count(*) from public.journal_entries where is_demo_seed;
--    -- Forvent samme antall som completed-bookingene i B.
--
-- D) Nullstillingen virker og er trygg å gjenta:
--    select public.demo_reset();
--    select public.demo_reset();
--    -- Ingen feil, og A gir samme svar begge ganger.
--
-- E) Cron-jobben er registrert (hvis pg_cron er på):
--    select jobname, schedule, active from cron.job
--     where jobname = 'demo-nightly-reset';
--
-- F) Ende-til-ende: logg inn som admin, se at kalenderen for denne
--    uka er full, at innboksen har tre meldinger, at anmeldelses-
--    køen har én til vurdering, og at ventelista har to navn.
-- ============================================================
