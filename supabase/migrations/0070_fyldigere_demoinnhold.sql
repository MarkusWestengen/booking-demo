-- ============================================================
-- 0070_fyldigere_demoinnhold.sql                     2026-09-01
-- ------------------------------------------------------------
-- Adminpanelet så tomt ut fordi det var tomt.
--
-- 0067 og 0068 seedet bookinger, tre meldinger, tre anmeldelser og
-- to ventelisteoppføringer. Det holder til å vise at kalenderen
-- virker, men ikke til å vise et system i drift: dokumentarkivet
-- hadde null rader, audit-loggen null, og klientkortene hadde
-- historikk bare på de tolv kundene bookingene traff.
--
-- Et adminpanel som demonstrerer seg selv må ha nok innhold til at
-- lister får rulling, filtre får noe å filtrere, og en audit-logg
-- har mer enn én linje. Ellers ser hver skjerm ut som en feil.
--
-- SAMME MØNSTER SOM 0067
-- Alt genereres relativt til current_date, alt merkes is_demo_seed,
-- og alt legges inne i demo_seed(). Dermed dekker skrivesperren fra
-- 0066 innholdet, og den nattlige nullstillingen bygger det opp
-- igjen. Ingen faste datoer, så kalenderen er aldri utdatert.
--
-- ALLE PERSONER ER OPPDIKTET.
-- Navnene er satt sammen av vanlige norske for- og etternavn som
-- ikke hører sammen. E-postene ligger på .example, som per RFC 2606
-- aldri kan registreres, og telefonnumrene er varianter av
-- 400 00 000.
--
-- Idempotent. Avhenger av 0066 (is_demo_seed), 0068 (katalogen) og
-- 0069 (navnebyttet i databasen).
-- ============================================================

begin;

create or replace function public.demo_seed()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Tjue kunder. Nok til at kundelista får rulling og søk noe å
  -- gjøre, og til at journalhistorikken varierer mellom dem.
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
    array['Oskar Rein',       'oskar.rein@eksempel.example',       '+47 400 00 022', 'Rygg, langkjøring'],
    array['Vilde Ramsvik',    'vilde.ramsvik@eksempel.example',    '+47 400 00 023', 'Håndledd, klatring'],
    array['Anders Tveten',    'anders.tveten@eksempel.example',    '+47 400 00 024', 'Nakke etter fall'],
    array['Live Sandaker',    'live.sandaker@eksempel.example',    '+47 400 00 025', 'Hofte, gravid uke 28'],
    array['Bjørnar Kvamme',   'bjornar.kvamme@eksempel.example',   '+47 400 00 026', 'Skulder, maler'],
    array['Thea Molvær',      'thea.molvaer@eksempel.example',     '+47 400 00 027', 'Fot, plantar'],
    array['Eirik Nordbø',     'eirik.nordbo@eksempel.example',     '+47 400 00 028', 'Rygg, tunge løft'],
    array['Sara Hjelmeland',  'sara.hjelmeland@eksempel.example',  '+47 400 00 029', 'Kne, håndball'],
    array['Ola Bringsvor',    'ola.bringsvor@eksempel.example',    '+47 400 00 030', 'Nakke, sovestilling']
  ];

  behandlere text[][] := array[
    array['markus', 'Markus Westengen'],
    array['sofie',  'Sofie Aune'],
    array['henrik', 'Henrik Dal'],
    array['jonas',  'Jonas Riis']
  ];

  behandlinger text[][] := array[
    array['forstegangsvurdering', 'Førstegangsvurdering',  '1290', '60'],
    array['oppfolging',           'Oppfølgingstime',        '790', '30'],
    array['trykkbolge',           'Trykkbølgebehandling',   '690', '30'],
    array['bevegelsesanalyse',    'Bevegelsesanalyse',     '1490', '60']
  ];

  -- Journalnotatene varierer så to klientkort ikke ser like ut.
  notater text[] := array[
    'Undersøkelse og bevegelsestester. Redusert utslag på motsatt side, '
      || 'sannsynlig kompensasjon. Behandlet mykvev og ledd, ga to øvelser '
      || 'til hjemmebruk. Ny vurdering om to uker.',
    'Oppfølging. Bedring siden sist, mindre morgenstivhet. Justerte '
      || 'øvelsene opp ett nivå. Fortsetter samme plan.',
    'Tydelig bedring i bevegelsesutslag. Reduserte behandlingsfrekvens '
      || 'til hver tredje uke. Fortsetter egentrening.',
    'Fortsatt ømhet ved belastning. Prøvde annen teknikk denne gangen. '
      || 'Vurderer henvisning til bildediagnostikk hvis ingen endring.',
    'Symptomfri ved siste kontroll. Avsluttet forløpet, med beskjed om '
      || 'å ta kontakt hvis plagen kommer tilbake.'
  ];

  d          date;
  offset_i   int;
  b_i        int;
  k_i        int;
  spredning  int;
  klokke     time;
  bid        text;
  bref       text;
  bstatus    text;
  n          int := 0;
  i          int;
  doc_id     uuid;

  tider_markus text[] := array['07:00', '08:30', '10:30', '12:00'];
  tider_ter    text[] := array['08:00', '10:00', '11:30', '13:30'];
begin
  -- ----- Rydd bort forrige generasjon --------------------------
  delete from public.document_sends      where true;
  delete from public.exercise_documents  where is_demo_seed;
  delete from public.journal_entries     where is_demo_seed;
  delete from public.bookings            where is_demo_seed;
  delete from public.contact_messages    where is_demo_seed;
  delete from public.reviews             where is_demo_seed;
  delete from public.waitlist            where is_demo_seed;
  delete from public.blocked_slots       where is_demo_seed;
  delete from public.holidays            where is_demo_seed;
  delete from public.special_open_days   where is_demo_seed;
  delete from public.audit_log           where true;

  -- ----- Bestillinger ------------------------------------------
  -- Utvidet fra 18 til 40 dager: en måned tilbake gir klientkortene
  -- historikk, ti dager fram gir kalenderen noe å vise.
  for offset_i in -30 .. 10 loop
    d := current_date + offset_i;
    if extract(isodow from d) >= 6 then
      continue;
    end if;

    for b_i in 1 .. array_length(behandlere, 1) loop
      if ((offset_i + b_i) % 3 + 3) % 3 = 0 then
        continue;
      end if;

      -- Postgres trunkerer modulo mot null, så (-5) % 4 = -1. Uten
      -- normaliseringen blir indeksen 0 eller lavere, og et
      -- array-oppslag utenfor 1..n gir NULL i stedet for å feile.
      spredning := ((offset_i + b_i) % 4 + 4) % 4;

      if behandlere[b_i][1] = 'markus' then
        klokke := tider_markus[1 + spredning]::time;
      else
        klokke := tider_ter[1 + spredning]::time;
      end if;

      k_i := 1 + ((offset_i * 3 + b_i * 5) % array_length(kunder, 1)
                  + array_length(kunder, 1)) % array_length(kunder, 1);
      n   := n + 1;

      bid     := 'demo-' || to_char(d, 'YYYYMMDD') || '-' || behandlere[b_i][1] || '-' || n;
      bref    := 'WK-' || upper(substr(md5(bid), 1, 4)) || '-' || lpad((1000 + n)::text, 4, '0');

      -- Litt variasjon i status: de fleste gjennomførte timene er
      -- completed, men noen få er avlyst. En kalender uten et eneste
      -- avvik ser like usann ut som en uten innhold.
      bstatus := case
                   when d >= current_date then 'confirmed'
                   when n % 11 = 0        then 'cancelled'
                   else 'completed'
                 end;

      insert into public.bookings (
        id, ref, staff_id, staff_name, service_id, service_name,
        price, duration, date, "time",
        name, email, phone, notes, status,
        journal_consent, journal_consent_at, created_at, is_demo_seed
      ) values (
        bid, bref,
        behandlere[b_i][1], behandlere[b_i][2],
        behandlinger[1 + spredning][1], behandlinger[1 + spredning][2],
        behandlinger[1 + spredning][3]::int,
        behandlinger[1 + spredning][4]::int,
        d, klokke,
        kunder[k_i][1], kunder[k_i][2], kunder[k_i][3],
        kunder[k_i][4], bstatus,
        true, now() - (offset_i + 40) * interval '1 day',
        now() - (offset_i + 40) * interval '1 day',
        true
      )
      on conflict do nothing;
    end loop;
  end loop;

  -- ----- Journalnotater ----------------------------------------
  insert into public.journal_entries (
    booking_id, patient_email, patient_phone, staff_id, staff_name,
    content, created_at, is_demo_seed
  )
  select
    b.id, b.email, b.phone, b.staff_id, b.staff_name,
    notater[1 + (abs(hashtext(b.id)) % array_length(notater, 1))],
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
     || 'Passer en førstegangsvurdering, eller skal jeg begynne et annet sted?',
     'new',      now() - interval '2 hours',  true),
    ('Vilde Ramsvik', 'vilde.ramsvik@eksempel.example',
     'Er det mulig å få time før klokka åtte? Jeg begynner på jobb 09:00.',
     'new',      now() - interval '5 hours',  true),
    ('Anders Tveten', 'anders.tveten@eksempel.example',
     'Jeg falt på ski i helgen og har vondt i nakken. Bør jeg vente med '
     || 'å bestille, eller komme så fort som mulig?',
     'new',      now() - interval '9 hours',  true),
    ('Kasper Vold', 'kasper.vold@eksempel.example',
     'Kan jeg flytte timen min på torsdag til uka etter? Jeg er bortreist.',
     'read',     now() - interval '1 day',    true),
    ('Live Sandaker', 'live.sandaker@eksempel.example',
     'Behandler dere gravide? Jeg er i uke 28 og har vondt i hoften.',
     'read',     now() - interval '2 days',   true),
    ('Thea Molvær', 'thea.molvaer@eksempel.example',
     'Får jeg kvittering på e-post som kan brukes mot forsikring?',
     'answered', now() - interval '3 days',   true),
    ('Solveig Bakkan', 'solveig.bakkan@eksempel.example',
     'Takk for sist. Kjeven er mye bedre. Trenger jeg flere timer, eller '
     || 'holder det med øvelsene?',
     'answered', now() - interval '4 days',   true),
    ('Ola Bringsvor', 'ola.bringsvor@eksempel.example',
     'Hvor lang tid tar en førstegangsvurdering? Jeg må rekke et møte etterpå.',
     'answered', now() - interval '6 days',   true);

  -- ----- Anmeldelser -------------------------------------------
  insert into public.reviews (name, rating, body, status, created_at, is_demo_seed)
  values
    ('Sindre K.',  5, 'Fant årsaken på første time etter to sesonger med '
                   || 'ryggsmerter. Grundig og rolig gjennomgang.',
     'approved', now() - interval '9 days',  true),
    ('Amalie H.',  5, 'Hodepinen jeg trodde hørte til jobben er nesten borte. '
                   || 'Fikk konkrete øvelser og en forklaring jeg forsto.',
     'approved', now() - interval '21 days', true),
    ('Malin N.',   4, 'God oppfølging over flere timer. Trakk en stjerne fordi '
                   || 'det var vanskelig å få time på ettermiddagen.',
     'approved', now() - interval '28 days', true),
    ('Oskar R.',   5, 'Kom inn med lav skulder og gikk ut med en plan. '
                   || 'Setter pris på at jeg fikk vite hvorfor.',
     'approved', now() - interval '34 days', true),
    ('Hedda L.',   4, 'Ankelen har holdt seg i ro siden. Øvelsene tar fem '
                   || 'minutter, så de blir faktisk gjort.',
     'approved', now() - interval '41 days', true),
    ('Terje Ø.',   4, 'God hjelp med hoften. Litt vanskelig å få time på '
                   || 'ettermiddagen, men verdt ventingen.',
     'pending',  now() - interval '2 days',  true),
    ('Eirik N.',   5, 'Rask time, tydelig beskjed om hva jeg skulle gjøre selv.',
     'pending',  now() - interval '4 days',  true),
    ('Bjørnar K.', 2, 'Fikk ikke helt taket på øvelsene, og timen føltes kort.',
     'rejected', now() - interval '12 days', true);

  -- ----- Venteliste --------------------------------------------
  insert into public.waitlist (
    ref, service_id, staff_id, staff_name, name, email, phone,
    preferred_date_from, preferred_date_to, preferred_time_from, preferred_time_to,
    notes, status, created_at, is_demo_seed
  ) values
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0001',
     null, 'markus', 'Markus Westengen',
     'Fredrik Aasheim', 'fredrik.aasheim@eksempel.example', '+47 400 00 020',
     current_date + 1, current_date + 21, time '08:00', time '12:00',
     'Skulder. Kan komme på kort varsel.', 'waiting',
     now() - interval '3 days', true),
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0002',
     null, null, 'Markus'' terapeuter',
     'Hedda Lindgren', 'hedda.lindgren@eksempel.example', '+47 400 00 021',
     current_date + 3, null, null, null,
     'Ankel. Fleksibel på tidspunkt.', 'waiting',
     now() - interval '1 day', true),
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0003',
     null, 'markus', 'Markus Westengen',
     'Sara Hjelmeland', 'sara.hjelmeland@eksempel.example', '+47 400 00 029',
     current_date + 2, current_date + 14, time '12:00', time '15:00',
     'Kne. Kun ettermiddag på grunn av trening.', 'waiting',
     now() - interval '6 hours', true),
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0004',
     null, null, 'Markus'' terapeuter',
     'Eirik Nordbø', 'eirik.nordbo@eksempel.example', '+47 400 00 028',
     current_date + 5, current_date + 30, null, null,
     'Rygg. Tar det som blir ledig.', 'offered',
     now() - interval '2 days', true),
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0005',
     null, 'markus', 'Markus Westengen',
     'Ola Bringsvor', 'ola.bringsvor@eksempel.example', '+47 400 00 030',
     current_date - 2, current_date + 7, null, null,
     'Nakke. Fikk time, står som akseptert.', 'accepted',
     now() - interval '8 days', true);

  -- ----- Øvelsesdokumenter -------------------------------------
  -- storage_path peker på filer som ikke er lastet opp. Det er med
  -- vilje: arkivet skal se befolket ut, men demoen skal ikke ha
  -- binærfiler liggende i en bucket. Nedlasting gir en tom respons,
  -- og det er en ærligere feil enn en tom liste.
  insert into public.exercise_documents
    (title, category, storage_path, file_name, mime_type, uploaded_by_name, created_at, is_demo_seed)
  values
    ('Nakkeøvelser, nivå 1',        'nakke',   'demo/nakke-1.pdf',   'nakke-1.pdf',   'application/pdf', 'Markus Westengen', now() - interval '40 days', true),
    ('Nakkeøvelser, nivå 2',        'nakke',   'demo/nakke-2.pdf',   'nakke-2.pdf',   'application/pdf', 'Markus Westengen', now() - interval '38 days', true),
    ('Skulder, utadrotasjon',       'skulder', 'demo/skulder-1.pdf', 'skulder-1.pdf', 'application/pdf', 'Sofie Aune',       now() - interval '31 days', true),
    ('Skulder, stabilitet',         'skulder', 'demo/skulder-2.pdf', 'skulder-2.pdf', 'application/pdf', 'Sofie Aune',       now() - interval '29 days', true),
    ('Hofte, tøy og styrke',        'hofte',   'demo/hofte-1.pdf',   'hofte-1.pdf',   'application/pdf', 'Henrik Dal',       now() - interval '22 days', true),
    ('Knekontroll etter vridning',  'kne',     'demo/kne-1.pdf',     'kne-1.pdf',     'application/pdf', 'Henrik Dal',       now() - interval '19 days', true),
    ('Ankel, balanse',              'ankel',   'demo/ankel-1.pdf',   'ankel-1.pdf',   'application/pdf', 'Jonas Riis',       now() - interval '12 days', true),
    ('Fotbue og plantarfascie',     'fot',     'demo/fot-1.pdf',     'fot-1.pdf',     'application/pdf', 'Jonas Riis',       now() - interval '7 days',  true);

  -- Noen utsendinger, så loggen over sendte dokumenter ikke er tom.
  for i in 1 .. 5 loop
    select id into doc_id from public.exercise_documents
     where is_demo_seed order by created_at limit 1 offset (i - 1);
    if doc_id is not null then
      -- Lenka maa matche moensteret validate_document_send() krever
      -- (0054): HTTPS mot et supabase.co-prosjekt og noeyaktig vaar
      -- egen private bucket. Verdien er en attrapp og peker ikke paa
      -- en ekte fil, men den skal ha riktig form. Triggeren overstyrer
      -- dessuten sent_by og document_title fra JWT og dokumentregister,
      -- saa de settes ikke her.
      insert into public.document_sends
        (document_id, document_title, customer_email, link_url, created_at)
      select doc_id, ed.title, kunder[i][2],
             'https://demo-prosjekt.supabase.co/storage/v1/object/sign/'
               || 'exercise-documents/' || ed.storage_path || '?token=demo',
             now() - (i * interval '2 days')
        from public.exercise_documents ed where ed.id = doc_id;
    end if;
  end loop;

  -- ----- Stengte tider og åpne lørdager ------------------------
  insert into public.blocked_slots (staff_id, date, "time", is_demo_seed) values
    ('markus', current_date + 2, time '11:00', true),
    ('markus', current_date + 2, time '11:30', true),
    ('sofie',  current_date + 4, time '13:00', true),
    ('henrik', current_date + 3, time '09:00', true),
    ('henrik', current_date + 3, time '09:30', true),
    ('jonas',  current_date + 7, time '14:00', true)
  on conflict do nothing;

  insert into public.holidays (date, is_demo_seed)
  values (current_date + 21, true), (current_date + 22, true)
  on conflict do nothing;

  -- En engangs åpen lørdag, så funksjonen fra 0059 er synlig i UI-et.
  insert into public.special_open_days (date, staff_id, open_time, close_time, is_demo_seed)
  select d2, 'markus', time '09:00', time '13:00', true
    from (select current_date + ((6 - extract(isodow from current_date)::int + 7) % 7 + 7) as d2) x
  on conflict do nothing;

  -- ----- Audit-logg --------------------------------------------
  -- Bygges fra journalnotatene som faktisk finnes, så loggen viser
  -- de samme oppslagene en ekte drift ville produsert. Uten dette
  -- er audit-siden tom, og det er nettopp den siden som skal
  -- demonstrere at hvert oppslag blir liggende.
  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata, created_at)
  select
    j.staff_id, j.staff_name, 'journal_create', 'journal_entry', j.id::text,
    jsonb_build_object('booking_id', j.booking_id),
    j.created_at
  from public.journal_entries j
  where j.is_demo_seed;

  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata, created_at)
  select
    j.staff_id, j.staff_name, 'journal_view', 'patient', j.patient_email,
    jsonb_build_object('via', 'kundekort'),
    j.created_at + interval '3 days'
  from public.journal_entries j
  where j.is_demo_seed
    and j.created_at + interval '3 days' < now();

  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata, created_at)
  select
    b.staff_id, b.staff_name, 'booking_status_change', 'booking', b.id,
    jsonb_build_object('from_status', 'confirmed', 'to_status', b.status),
    b.date + time '17:00'
  from public.bookings b
  where b.is_demo_seed
    and b.status in ('completed', 'cancelled');
end $$;

comment on function public.demo_seed() is
  'Genererer demoens innhold relativt til current_date, markert som '
  'is_demo_seed. Utvidet i 0070 med flere kunder, journalnotater, '
  'meldinger, venteliste, dokumenter og audit-logg.';

select public.demo_seed();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Ingen tom tabell bak innloggingen:
--    select 'bookings', count(*) from public.bookings
--    union all select 'journal_entries', count(*) from public.journal_entries
--    union all select 'contact_messages', count(*) from public.contact_messages
--    union all select 'waitlist', count(*) from public.waitlist
--    union all select 'reviews', count(*) from public.reviews
--    union all select 'exercise_documents', count(*) from public.exercise_documents
--    union all select 'document_sends', count(*) from public.document_sends
--    union all select 'audit_log', count(*) from public.audit_log
--    union all select 'blocked_slots', count(*) from public.blocked_slots;
--
-- B) Alt er merket som seed og dekkes av skrivesperren:
--    select count(*) from public.bookings where not is_demo_seed;
--    -- Forvent 0 rett etter apply.
--
-- C) Hver booking peker på en behandler som finnes:
--    select b.staff_id from public.bookings b
--     where b.staff_id is not null
--       and not exists (select 1 from public.staff_members m
--                        where m.staff_id = b.staff_id);
--    -- Forvent 0 rader.
-- ============================================================
