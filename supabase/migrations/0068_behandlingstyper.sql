-- ============================================================
-- 0068_behandlingstyper.sql                          2026-09-01
-- ------------------------------------------------------------
-- Fire navngitte behandlinger i stedet for to generiske.
--
-- HVORFOR
-- Katalogen besto av «Konsultasjon» og «Videre behandling» i to
-- pristrinn — fire rader som egentlig var to tjenester priset
-- ulikt etter hvem som utførte dem. Steg 2 i bestillingsflyten
-- ba derfor kunden velge mellom to varianter av det samme, og
-- varighet var 30 minutter uansett hva man valgte.
--
-- Her erstattes den av fire behandlinger med eget navn, egen
-- varighet og egen pris. Prisen følger behandlingen, ikke
-- behandleren: det er enklere å forstå for kunden, og det er
-- slik en tjenestekatalog vanligvis ser ut.
--
-- VARIGHET BETYR NOE NÅ
-- To av behandlingene varer 60 minutter. Bookingmotoren regnet
-- tidligere all tilgjengelighet i faste 30-minutters luker og
-- sperret bare startpunktet, så en times behandling ville latt
-- neste halvtime stå ledig og to kunder kunne booket oppå
-- hverandre. shared/booking-engine.js er endret i samme runde:
-- en booking legger nå beslag på alle lukene den dekker, og en
-- luke tilbys bare hvis hele behandlingen får plass før stengetid.
-- Alle varigheter er derfor multipler av 30.
--
-- DE GAMLE RADENE
-- Deaktiveres, ikke slettes. Eksisterende bookinger lagrer
-- service_id som tekst og skal fortsatt kunne vises i kalenderen
-- og i kundens historikk.
--
-- Idempotent: insert .. on conflict (slug) do update.
-- Forutsetning: 0008 (services + staff_services), 0067 (demo_seed).
-- ============================================================

begin;

-- ============================================================
-- (a) Deaktiver den gamle katalogen
-- ============================================================
update public.services
   set is_active = false
 where slug in ('markus-konsult', 'markus-videre', 'ter-konsult', 'ter-videre');


-- ============================================================
-- (b) De fire behandlingene
-- ------------------------------------------------------------
-- on conflict do update slik at en re-kjøring retter opp verdier
-- en administrator har endret i tjenester.html — migrasjonen er
-- fasiten for hva demoen skal vise.
-- ============================================================
insert into public.services
  (slug, name, description, duration_min, price_nok, sort_order, is_active)
values
  ('forstegangsvurdering', 'Førstegangsvurdering',
   'Full gjennomgang av plagen: sykehistorie, bevegelsestester og en plan for videre forløp. Sett av en time.',
   60, 1290, 10, true),

  ('oppfolging', 'Oppfølgingstime',
   'Videre behandling etter førstegangsvurderingen, med justering av planen underveis.',
   30, 790, 20, true),

  ('trykkbolge', 'Trykkbølgebehandling',
   'Fokusert behandling av senefeste og muskulatur som ikke har gitt seg av hvile alene.',
   30, 690, 30, true),

  ('bevegelsesanalyse', 'Bevegelsesanalyse',
   'Video- og styrketesting for deg som vil vite hvorfor plagen kommer tilbake. Avsluttes med et treningsopplegg.',
   60, 1490, 40, true)
on conflict (slug) do update
  set name         = excluded.name,
      description  = excluded.description,
      duration_min = excluded.duration_min,
      price_nok    = excluded.price_nok,
      sort_order   = excluded.sort_order,
      is_active    = true;


-- ============================================================
-- (c) Koble alle behandlinger til alle aktive behandlere
-- ------------------------------------------------------------
-- Prisen ligger på behandlingen, så det finnes ikke lenger en
-- grunn til at katalogen skal være ulik per behandler.
-- ============================================================
insert into public.staff_services (staff_id, service_id)
select sm.staff_id, s.id
  from public.staff_members sm
 cross join public.services s
 where sm.aktiv = true
   and s.slug in ('forstegangsvurdering', 'oppfolging', 'trykkbolge', 'bevegelsesanalyse')
on conflict do nothing;


-- ============================================================
-- (d) demo_seed(): bruk den nye katalogen
-- ------------------------------------------------------------
-- Bare behandler-/behandlingstabellene endres. Resten av
-- funksjonen er uendret fra 0067, inkludert normaliseringen av
-- modulo som holder klokkeslettene innenfor arbeidstiden.
-- ============================================================
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
    array['Oskar Rein',       'oskar.rein@eksempel.example',       '+47 400 00 022', 'Rygg, langkjøring']
  ];

  -- Behandlere som får bestillinger i kalenderen.
  behandlere text[][] := array[
    array['markus', 'Markus Westengen'],
    array['sofie',  'Sofie Aune'],
    array['henrik', 'Henrik Dal'],
    array['jonas',  'Jonas Riis']
  ];

  -- Behandlingene fra (b): slug, navn, pris, varighet.
  behandlinger text[][] := array[
    array['forstegangsvurdering', 'Førstegangsvurdering',  '1290', '60'],
    array['oppfolging',           'Oppfølgingstime',        '790', '30'],
    array['trykkbolge',           'Trykkbølgebehandling',   '690', '30'],
    array['bevegelsesanalyse',    'Bevegelsesanalyse',     '1490', '60']
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

  -- Klokkeslett innenfor hver behandlers faktiske arbeidstid, jf.
  -- shared/booking-engine.js. Markus 06:00–13:00 med fast pause
  -- 09:30; terapeutene 07:00–15:00. Startpunktene er valgt slik at
  -- ogsaa en 60-minutters behandling rekker aa bli ferdig.
  tider_markus text[] := array['07:00', '08:30', '10:30', '12:00'];
  tider_ter    text[] := array['08:00', '10:00', '11:30', '13:30'];
begin
  delete from public.journal_entries   where is_demo_seed;
  delete from public.bookings          where is_demo_seed;
  delete from public.contact_messages  where is_demo_seed;
  delete from public.reviews           where is_demo_seed;
  delete from public.waitlist          where is_demo_seed;
  delete from public.blocked_slots     where is_demo_seed;
  delete from public.holidays          where is_demo_seed;

  for offset_i in -7 .. 10 loop
    d := current_date + offset_i;
    if extract(isodow from d) >= 6 then
      continue;
    end if;

    for b_i in 1 .. array_length(behandlere, 1) loop
      if ((offset_i + b_i) % 3 + 3) % 3 = 0 then
        continue;
      end if;

      -- Postgres trunkerer modulo mot null, saa (-5) % 4 = -1. Uten
      -- normaliseringen ble indeksen 0 eller lavere for alle dagene
      -- foer i dag, og et array-oppslag utenfor 1..n gir NULL i
      -- stedet for aa feile — som ga en booking med time = NULL.
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
      bstatus := case when d < current_date then 'completed' else 'confirmed' end;

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
        true, now() - (offset_i + 14) * interval '1 day',
        now() - (offset_i + 14) * interval '1 day',
        true
      )
      on conflict do nothing;
    end loop;
  end loop;

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

  insert into public.contact_messages (name, email, message, status, created_at, is_demo_seed)
  values
    ('Ingvild Rødal', 'ingvild.rodal@eksempel.example',
     'Hei! Jeg har vondt i korsryggen etter en del tunge løft på jobb. '
     || 'Passer en førstegangsvurdering, eller skal jeg begynne et annet sted?',
     'new',      now() - interval '5 hours',  true),
    ('Kasper Vold', 'kasper.vold@eksempel.example',
     'Kan jeg flytte timen min på torsdag til uka etter? Jeg er bortreist.',
     'read',     now() - interval '1 day',    true),
    ('Solveig Bakkan', 'solveig.bakkan@eksempel.example',
     'Takk for sist. Kjeven er mye bedre. Trenger jeg flere timer, eller '
     || 'holder det med øvelsene?',
     'answered', now() - interval '4 days',   true);

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
     now() - interval '1 day', true);

  insert into public.blocked_slots (staff_id, date, "time", is_demo_seed) values
    ('markus', current_date + 2, time '11:00', true),
    ('markus', current_date + 2, time '11:30', true),
    ('sofie',  current_date + 4, time '13:00', true)
  on conflict do nothing;

  insert into public.holidays (date, is_demo_seed)
  values (current_date + 21, true)
  on conflict do nothing;
end $$;

comment on function public.demo_seed() is
  'Genererer demoens innhold relativt til current_date, markert som '
  'is_demo_seed, med behandlingskatalogen fra migrasjon 0068.';


-- ============================================================
-- (e) Generer på nytt med den nye katalogen
-- ============================================================
select public.demo_seed();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Fire aktive behandlinger, de gamle deaktivert:
--    select slug, name, duration_min, price_nok, is_active
--      from public.services order by is_active desc, sort_order;
--
-- B) Alle aktive behandlere er koblet til alle fire:
--    select staff_id, count(*) from public.staff_services ss
--      join public.services s on s.id = ss.service_id
--     where s.is_active group by staff_id order by staff_id;
--    -- Forvent 4 per behandler.
--
-- C) Seed-bookingene bruker den nye katalogen og har varighet:
--    select service_name, duration, price, count(*)
--      from public.bookings where is_demo_seed
--     group by 1,2,3 order by 1;
--    -- Forvent 60 min på Førstegangsvurdering og Bevegelsesanalyse,
--    --   30 min på Oppfølgingstime og Trykkbølgebehandling.
--
-- D) Ingen 60-minutters seed-booking krysser stengetid eller pause:
--    select staff_id, "time", duration from public.bookings
--     where is_demo_seed and duration > 30 order by "time";
--    -- Markus skal ikke ha noen som dekker 09:30.
-- ============================================================
