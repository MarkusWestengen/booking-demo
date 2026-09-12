-- ============================================================
-- 0078 — opprydding: arvet markedsføringstekst ut, datoer fram i tid
-- ------------------------------------------------------------
-- Se docs/QA-lansering.md, «Opprydding 2026-09-12».
--
-- 1. TEKST
--    Demoen ble anonymisert ved å bytte navn, men formuleringene fra
--    klinikken den kom fra ble stående: behandlerbiografiene påsto
--    opplæring og felles metode, tjenestene beskrev en behandlingsmåte,
--    anmeldelsene var kundesitater om resultater, og én melding
--    fortalte om et behandlingsresultat. Demoen viser et bookingsystem
--    og skal ikke markedsføre en metode.
--
--      staff_members.role / .bio    lesbart for anon
--      services.description         lesbart for anon, steg 2 i flyten
--      demo_seed()                  anmeldelser, meldinger, journal
--
--    Journalnotater beholdes, fordi journalen er en av funksjonene
--    demoen viser, men teksten sier nå ingenting om behandling.
--
-- 2. DATOER
--    demo_seed() genererte bestillinger fra 30 dager tilbake til 10
--    dager fram. Det holdt kalenderen levende i dag, men ingenting lå
--    lenger fram enn halvannen uke. Nå:
--
--      -30 .. -1   historikk (completed / cancelled), gir journal
--        0 .. 21   tett: denne og de neste tre ukene
--       22 .. 100  glissent: annenhver hverdag, to behandlere
--
--    Alt er fortsatt current_date + et intervall. Ingen faste datoer.
--    Nullstillingen 01:00 UTC kaller demo_seed() og flytter hele
--    vinduet med seg hver natt.
--
--    Stengte dager havnet før på current_date + 21/22, som ofte er en
--    helg og derfor ikke synlig. De legges nå på første hverdag etter
--    +24 og +60, og bestillingsløkka hopper over dem.
--
--    Blokkeringen til jonas 14:00 kolliderte med en 60-minutters time
--    13:30 samme dag. Flyttet til 14:30.
--
-- Metode: demo_guard() slipper postgres forbi, så dette må kjøres i
-- SQL-editoren (eller db push) som postgres, ikke via PostgREST.
--
-- Idempotent. Avhenger av 0066, 0068, 0070 og 0071.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- (a) Behandlere
-- ------------------------------------------------------------
update public.staff_members
   set role = 'Terapeut-team',
       bio  = 'Timen settes opp hos en av klinikkens terapeuter. Oppdiktet team i en oppdiktet klinikk.'
 where staff_id = 'terapeut';

update public.staff_members
   set bio = 'Oppdiktet terapeut i en oppdiktet klinikk.'
 where staff_id <> 'terapeut'
   and staff_id <> 'markus'
   and (bio ilike '%oppl_rt%' or bio ilike '%metodikk%' or bio ilike '%grundighet%');

-- ------------------------------------------------------------
-- (b) Tjenester
-- ------------------------------------------------------------
update public.services set description = 'Første time for nye kunder. Oppdiktet tjeneste i demoen.'
 where slug = 'forstegangsvurdering';
update public.services set description = 'For kunder som har vært her før. Oppdiktet tjeneste i demoen.'
 where slug = 'oppfolging';
update public.services set description = 'Oppdiktet tjeneste i demoen.'
 where slug in ('trykkbolge', 'bevegelsesanalyse');
-- Utgåtte tjenester fra den første katalogen (inaktive, beholdt for
-- historiske bestillinger). Finnes ikke i alle databaser.
update public.services set description = 'Utgått tjeneste. Oppdiktet tjeneste i demoen.'
 where slug in ('markus-konsult', 'markus-videre', 'ter-konsult', 'ter-videre');

-- ------------------------------------------------------------
-- (c) Ekte gateadresser i e-postfunksjonene
-- ------------------------------------------------------------
-- Sveipet 2026-09-02 fant en ekte gateadresse i Oslo i bunnteksten
-- til tre e-postfunksjoner, og 0076 rettet den ikke. Plassholderen
-- repoet brukte ellers var også en ekte adresse (Kartverket:
-- adressen finnes, med et annet postnummer). Begge byttes til
-- «Eksempelveien 12, 0000 Oslo»: gatenavnet finnes ikke i
-- adresseregisteret, og 0000 er ikke et postnummer.
--
-- Samme fremgangsmåte som 0076: definisjonen leses ut med
-- pg_get_functiondef(), endres i minnet og kjøres tilbake. Adressene
-- står ikke i denne fila; de matches med et generelt mønster, så
-- repoet ikke bærer dem.
do $do$
declare
  r        record;
  def      text;
  ny       text;
  moenster constant text :=
    '[A-ZÆØÅ][a-zæøå]+(gata|gaten|veien|vegen|gate|vei) [0-9]+[A-Za-z]?, [0-9]{4} (Oslo|OSLO)';
  n        int := 0;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.prokind = 'f'
  loop
    def := pg_get_functiondef(r.oid);
    ny  := regexp_replace(def, moenster, 'Eksempelveien 12, 0000 Oslo', 'g');
    ny  := regexp_replace(ny, '[A-ZÆØÅ]{3,}(GATA|GATEN|VEIEN|VEGEN) [0-9]+[A-Z]?, [0-9]{4} OSLO',
                          'EKSEMPELVEIEN 12, 0000 OSLO', 'g');
    if ny <> def then
      execute ny;
      n := n + 1;
      raise notice '0078: adresse byttet i %', r.proname;
    end if;
  end loop;

  if exists (
    select 1
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prokind = 'f'
       and regexp_replace(pg_get_functiondef(p.oid), 'eksempelveien 12, 0000 oslo', '', 'gi')
           ~* '(gata|gaten|veien|vegen|gate|vei) [0-9]+[a-z]?, [0-9]{4} oslo'
  ) then
    raise exception '0078: en funksjonskropp har fortsatt en gateadresse';
  end if;

  raise notice '0078: % funksjon(er) fikk ny adresse', n;
end
$do$;

-- ------------------------------------------------------------
-- (d) Generatoren
-- ------------------------------------------------------------
create or replace function public.demo_seed()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
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

  notater text[] := array[
    'Demonotat 1. Innholdet er konstruert for demonstrasjonen '
      || 'og gjelder ingen virkelig pasient. Notatet beskriver ingen '
      || 'behandling.',
    'Demonotat 2. Oppdiktet, og uten innhold om behandling. '
      || 'Gjelder ingen virkelig pasient.',
    'Demonotat 3. Konstruert tekst, fordelt over de gjennomførte '
      || 'timene så klientkortene ikke ser like ut.',
    'Demonotat 4. Fylltekst uten opplysninger om behandling '
      || 'eller om noen virkelig person.',
    'Demonotat 5. Oppdiktet notat. Det står her fordi en tom '
      || 'journal ikke demonstrerer journalfunksjonen.'
  ];

  -- Hvor langt fram og tilbake kalenderen fylles.
  fra_dag    constant int := -30;
  tett_til   constant int := 21;
  til_dag    constant int := 100;

  d          date;
  offset_i   int;
  b_i        int;
  k_i        int;
  spredning  int;
  klokke     time;
  bid        text;
  bref       text;
  bstatus    text;
  opprettet  timestamptz;
  n          int := 0;
  i          int;
  doc_id     uuid;
  stengt_1   date;
  stengt_2   date;

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

  -- ----- Stengte dager -----------------------------------------
  -- Første hverdag fra og med +24 og +60. Regnes ut før bestillingene,
  -- så løkka kan hoppe over dem.
  stengt_1 := current_date + 24;
  while extract(isodow from stengt_1) >= 6 loop stengt_1 := stengt_1 + 1; end loop;
  stengt_2 := current_date + 60;
  while extract(isodow from stengt_2) >= 6 loop stengt_2 := stengt_2 + 1; end loop;

  -- ----- Bestillinger ------------------------------------------
  for offset_i in fra_dag .. til_dag loop
    d := current_date + offset_i;
    if extract(isodow from d) >= 6 or d in (stengt_1, stengt_2) then
      continue;
    end if;

    -- Etter de tre tette ukene: bare annenhver dag.
    if offset_i > tett_til and offset_i % 2 <> 0 then
      continue;
    end if;

    for b_i in 1 .. array_length(behandlere, 1) loop
      if ((offset_i + b_i) % 3 + 3) % 3 = 0 then
        continue;
      end if;

      -- Langt fram: bare Markus og én terapeut per dag, vekselvis.
      if offset_i > tett_til
         and not (b_i = 1 or b_i = 2 + ((offset_i / 2) % 3)) then
        continue;
      end if;

      -- Postgres trunkerer modulo mot null; normaliser til 0..3.
      spredning := ((offset_i + b_i) % 4 + 4) % 4;

      if behandlere[b_i][1] = 'markus' then
        klokke := tider_markus[1 + spredning]::time;
      else
        klokke := tider_ter[1 + spredning]::time;
      end if;

      k_i := 1 + ((offset_i * 3 + b_i * 5) % array_length(kunder, 1)
                  + array_length(kunder, 1)) % array_length(kunder, 1);
      n   := n + 1;

      bid  := 'demo-' || to_char(d, 'YYYYMMDD') || '-' || behandlere[b_i][1] || '-' || n;
      bref := 'WK-' || upper(substr(md5(bid), 1, 4)) || '-' || lpad((1000 + n)::text, 4, '0');

      bstatus := case
                   when d >= current_date then 'confirmed'
                   when n % 11 = 0        then 'cancelled'
                   else 'completed'
                 end;

      -- Bestilt 3–22 dager før timen, men aldri i framtiden.
      opprettet := least(now(), d::timestamptz)
                   - ((abs(offset_i) % 20) + 3) * interval '1 day';

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
        true, opprettet, opprettet,
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
     'Hei. Har dere ledig time tidlig på morgenen i løpet av '
     || 'de neste ukene?',
     'answered', now() - interval '4 days',   true),
    ('Ola Bringsvor', 'ola.bringsvor@eksempel.example',
     'Hvor lang tid tar en førstegangsvurdering? Jeg må rekke et møte etterpå.',
     'answered', now() - interval '6 days',   true);

  -- ----- Anmeldelser -------------------------------------------
  -- Ingen kundesitater. Stjerner og status holder moderasjonskøen og
  -- snittet realistisk; teksten sier ingenting om behandling.
  insert into public.reviews (name, rating, body, status, created_at, is_demo_seed)
  values
    ('Sindre K.',  5, 'Oppdiktet anmeldelse. Teksten er fyll, slik at '
                   || 'moderasjonskøen i adminpanelet ikke står tom.',
     'approved', now() - interval '9 days',  true),
    ('Amalie H.',  5, 'Oppdiktet anmeldelse. Ingen ekte kunde står bak '
                   || 'den, og den beskriver ingen behandling.',
     'approved', now() - interval '21 days', true),
    ('Malin N.',   4, 'Oppdiktet anmeldelse med fire stjerner, slik at '
                   || 'snittet i demoen ikke er fem blankt.',
     'approved', now() - interval '28 days', true),
    ('Oskar R.',   5, 'Oppdiktet anmeldelse. Teksten sier ingenting om '
                   || 'behandling, og gjelder ingen virkelig person.',
     'approved', now() - interval '34 days', true),
    ('Hedda L.',   4, 'Oppdiktet anmeldelse. Innholdet er konstruert for '
                   || 'demonstrasjonen.',
     'approved', now() - interval '41 days', true),
    ('Terje Ø.',   4, 'Oppdiktet anmeldelse til vurdering, så køen i '
                   || 'adminpanelet har noe å vise.',
     'pending',  now() - interval '2 days',  true),
    ('Eirik N.',   5, 'Oppdiktet anmeldelse til vurdering. Ren fylltekst.',
     'pending',  now() - interval '4 days',  true),
    ('Bjørnar K.', 2, 'Oppdiktet anmeldelse, avvist i moderasjonen.',
     'rejected', now() - interval '12 days', true);

  -- ----- Venteliste --------------------------------------------
  -- Ønskede perioder spredt fra i morgen til nesten tre måneder fram.
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
     now() - interval '8 days', true),
    ('WK-WL-' || to_char(current_date, 'MMDD') || '-0006',
     null, null, 'Markus'' terapeuter',
     'Vilde Ramsvik', 'vilde.ramsvik@eksempel.example', '+47 400 00 023',
     current_date + 45, current_date + 80, time '07:00', time '09:00',
     'Håndledd. Bare før jobb.', 'waiting',
     now() - interval '5 hours', true);

  -- ----- Øvelsesdokumenter -------------------------------------
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

  for i in 1 .. 5 loop
    select id into doc_id from public.exercise_documents
     where is_demo_seed order by created_at limit 1 offset (i - 1);
    if doc_id is not null then
      insert into public.document_sends
        (document_id, document_title, customer_email, link_url, created_at)
      select doc_id, ed.title, kunder[i][2],
             'https://demo-prosjekt.supabase.co/storage/v1/object/sign/'
               || 'exercise-documents/' || ed.storage_path || '?token=demo',
             now() - (i * interval '2 days')
        from public.exercise_documents ed where ed.id = doc_id;
    end if;
  end loop;

  -- ----- Stengte tider -----------------------------------------
  -- Nær og fjern, på tider som ikke overlapper en seedet time.
  insert into public.blocked_slots (staff_id, date, "time", is_demo_seed) values
    ('markus', current_date + 2,  time '11:00', true),
    ('markus', current_date + 2,  time '11:30', true),
    ('sofie',  current_date + 4,  time '13:00', true),
    ('henrik', current_date + 3,  time '09:00', true),
    ('henrik', current_date + 3,  time '09:30', true),
    ('jonas',  current_date + 7,  time '14:30', true),
    ('markus', current_date + 38, time '11:00', true),
    ('sofie',  current_date + 75, time '14:30', true)
  on conflict do nothing;

  insert into public.holidays (date, is_demo_seed)
  values (stengt_1, true), (stengt_2, true)
  on conflict do nothing;

  -- En åpen lørdag neste uke og en om to måneder.
  insert into public.special_open_days (date, staff_id, open_time, close_time, is_demo_seed)
  select dd, 'markus', time '09:00', time '13:00', true
    from (values
      (current_date + ((6 - extract(isodow from current_date)::int + 7) % 7 + 7)),
      (current_date + ((6 - extract(isodow from current_date)::int + 7) % 7 + 63))
    ) x(dd)
  on conflict do nothing;

  -- ----- Audit-logg --------------------------------------------
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
  'Genererer demoens innhold relativt til current_date (-30 til +100 '
  'dager), markert som is_demo_seed. Ingen faste datoer. Migrasjon 0078.';

revoke all on function public.demo_seed() from public, anon, authenticated;
grant execute on function public.demo_seed() to service_role;

-- ------------------------------------------------------------
-- (e) Bygg innholdet på nytt og kontroller resultatet
-- ------------------------------------------------------------
select public.demo_seed();

do $do$
declare
  n_fram   int;
  n_uke    int;
  n_mnd    int;
  n_3mnd   int;
  n_tekst  int;
begin
  select count(*) filter (where date >= current_date and status = 'confirmed'),
         count(*) filter (where date between current_date and current_date + 7),
         count(*) filter (where date between current_date + 22 and current_date + 45),
         count(*) filter (where date between current_date + 75 and current_date + 100)
    into n_fram, n_uke, n_mnd, n_3mnd
    from public.bookings where is_demo_seed;

  if n_uke = 0 or n_mnd = 0 or n_3mnd = 0 then
    raise exception '0078: framtidige bestillinger mangler (uke %, neste mnd %, 3 mnd %)',
      n_uke, n_mnd, n_3mnd;
  end if;

  if exists (select 1 from public.bookings
              where is_demo_seed and date < current_date and status = 'confirmed') then
    raise exception '0078: bekreftet seed-time i fortiden';
  end if;

  select
      (select count(*) from public.staff_members
        where concat_ws(' ', role, bio) ~* '(oppl.rt|metodikk|metoder|filosofi|grundighet|erfarne)')
    + (select count(*) from public.services
        where description ~* '(senefeste|sykehistorie|hvorfor plagen|justering av planen|kartlegging)')
    + (select count(*) from public.reviews
        where is_demo_seed and body !~ '^Oppdiktet anmeldelse')
    + (select count(*) from public.contact_messages
        where message ~* 'mye bedre')
    + (select count(*) from public.journal_entries
        where is_demo_seed and content ~* '(mykvev|kompensasjon|bedring|symptomfri)')
    into n_tekst;

  if n_tekst > 0 then
    raise exception '0078: % rad(er) med arvet tekst står igjen', n_tekst;
  end if;

  raise notice '0078: % kommende bestillinger (% neste uke, % om 3–6 uker, % om 11–14 uker)',
    n_fram, n_uke, n_mnd, n_3mnd;
end
$do$;

commit;

-- ============================================================
-- Verifikasjon etter apply (SQL-editoren):
--
--   select min(date), max(date),
--          count(*) filter (where date >= current_date) as kommende
--     from public.bookings where is_demo_seed;
--   -- Forvent: min = current_date - 30 (eller nærmeste hverdag),
--   --          max nær current_date + 100.
--
--   select public.demo_reset();   -- samme spørring skal gi samme svar
-- ============================================================
