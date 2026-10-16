/* ============================================================
   Westengen Klinikk — demodata, generert i nettleseren
   ------------------------------------------------------------
   Demoen har ingen database. Alt innholdet bygges her, i den
   besøkendes egen nettleser, og shared/demo-backend.js holder det
   i localStorage.

   Dette er en JavaScript-utgave av demo_seed() fra
   supabase/migrations/0078_opprydding_tekst_og_datoer.sql, pluss
   katalogen den forutsetter:

     staff_members   0041 (rader), 0049 (farger), 0078 (tekster)
     services        0068 (de fire behandlingene)
     staff_services  0068 (alle behandlinger hos alle aktive)

   Alle datoer regnes ut fra dagens dato i Europe/Oslo. Ingen faste
   datoer. Backenden kaller build() på nytt når datoen skifter, og
   det er det som erstatter den nattlige nullstillingen.

   Migrasjonene ligger fortsatt i supabase/ som fasit for verdiene.
   Endres generatoren der, må den endres her også.

   Eksponerer: window.WestengenKlinikkDemoSeed = { build, osloToday,
   osloWallToIso, uuid }
   ============================================================ */
(function (root) {
  'use strict';

  // ----- Hjelpere ------------------------------------------------
  function pad(n) { return String(n).padStart(2, '0'); }

  // Dagens dato i Oslo som YYYY-MM-DD. en-CA gir ISO-rekkefølge.
  function osloToday(nowMs) {
    var d = new Date(nowMs == null ? Date.now() : nowMs);
    try {
      return new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Europe/Oslo', year: 'numeric', month: '2-digit', day: '2-digit'
      }).format(d);
    } catch (_) {
      return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
    }
  }

  // Oslo-veggklokke (dato + HH:MM) som UTC-tidspunkt i ISO-format.
  // Gjetter først at veggklokka er UTC, ser hva klokka da viser i
  // Oslo, og trekker fra differansen. Riktig også rundt sommertid.
  function osloWallToIso(dateStr, timeStr) {
    var p = dateStr.split('-');
    var t = (timeStr || '00:00').split(':');
    var guess = Date.UTC(+p[0], +p[1] - 1, +p[2], +t[0], +t[1] || 0, 0);
    try {
      var parts = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Europe/Oslo', year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
      }).formatToParts(new Date(guess)).reduce(function (a, x) { a[x.type] = x.value; return a; }, {});
      var shown = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, 0);
      return new Date(guess - (shown - guess)).toISOString();
    } catch (_) {
      return new Date(guess).toISOString();
    }
  }

  function addDays(dateStr, n) {
    var p = dateStr.split('-');
    var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2]));
    d.setUTCDate(d.getUTCDate() + n);
    return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate());
  }

  // ISO-ukedag: 1 = mandag … 7 = søndag, som extract(isodow) i Postgres.
  function isoDow(dateStr) {
    var p = dateStr.split('-');
    var dow = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2])).getUTCDay();
    return dow === 0 ? 7 : dow;
  }

  function uuid() {
    try { if (root.crypto && root.crypto.randomUUID) return root.crypto.randomUUID(); } catch (_) {}
    var b = new Uint8Array(16);
    try { root.crypto.getRandomValues(b); }
    catch (_) { for (var i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256); }
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    var h = Array.prototype.map.call(b, function (x) { return (x + 0x100).toString(16).slice(1); }).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }

  // Erstatter md5()/hashtext() fra SQL-en. Verdiene blir ikke de
  // samme som i databasen, men de er stabile og godt spredt, som er
  // alt generatoren brukte dem til.
  function hash32(s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
    return h >>> 0;
  }
  function hex4(s) { return ('0000' + hash32(s).toString(16)).slice(-8).slice(0, 4).toUpperCase(); }

  // ----- Katalogen -----------------------------------------------
  var CREATED = '2026-09-01T08:00:00.000Z';

  var STAFF = [
    // staff_id, name, role, bio, bookable, is_pool, sortering, color
    ['markus',   'Markus Westengen',   'Behandler',
     'Timen settes opp hos Markus. Oppdiktet behandler i en oppdiktet klinikk.', true,  false, 10, '#3E6B47'],
    ['terapeut', 'Markus\' terapeuter', 'Terapeut-team',
     'Timen settes opp hos en av klinikkens terapeuter. Oppdiktet team i en oppdiktet klinikk.', true, false, 20, ''],
    ['sofie',  'Sofie Aune',     'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 30, '#B8754A'],
    ['henrik', 'Henrik Dal',     'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 40, '#5B7DB1'],
    ['jonas',  'Jonas Riis',     'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 50, '#8E6FA8'],
    ['amina',  'Amina Nour',     'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 60, '#C2A14D'],
    ['nora',   'Nora Ellingsen', 'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 65, '#D87FA0'],
    ['lena',   'Lena Vik',       'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 70, '#A85C5C'],
    ['petter', 'Petter Holm',    'Terapeut', 'Oppdiktet terapeut i en oppdiktet klinikk.', false, true, 80, '#4D9D9A']
  ];

  // Faste id-er, så en lenke eller en bestilling som peker på en
  // tjeneste fortsatt treffer etter at dataene er bygget på nytt.
  var SERVICES = [
    ['00000000-0000-4000-b000-000000000001', 'forstegangsvurdering', 'Førstegangsvurdering',
     'Første time for nye kunder. Oppdiktet tjeneste i demoen.', 60, 1290, 10],
    ['00000000-0000-4000-b000-000000000002', 'oppfolging', 'Oppfølgingstime',
     'For kunder som har vært her før. Oppdiktet tjeneste i demoen.', 30, 790, 20],
    ['00000000-0000-4000-b000-000000000003', 'trykkbolge', 'Trykkbølgebehandling',
     'Oppdiktet tjeneste i demoen.', 30, 690, 30],
    ['00000000-0000-4000-b000-000000000004', 'bevegelsesanalyse', 'Bevegelsesanalyse',
     'Oppdiktet tjeneste i demoen.', 60, 1490, 40]
  ];

  // ----- Generatorens tabeller (0078) ----------------------------
  var KUNDER = [
    ['Sindre Kolstad',   'sindre.kolstad@eksempel.example',   '+47 400 00 011', 'Ryggsmerter, sykling'],
    ['Amalie Holtan',    'amalie.holtan@eksempel.example',    '+47 400 00 012', 'Nakke og hodepine, kontorarbeid'],
    ['Malin Nyhus',      'malin.nyhus@eksempel.example',      '+47 400 00 013', 'Hamstring, gjentatte strekk'],
    ['Jonas Revheim',    'jonas.revheim@eksempel.example',    '+47 400 00 014', 'Kne etter vridning'],
    ['Nora Lindqvist',   'nora.lindqvist@eksempel.example',   '+47 400 00 015', 'Skulder, kastarm'],
    ['Terje Østby',      'terje.ostby@eksempel.example',      '+47 400 00 016', 'Hofte, lange turer'],
    ['Ingvild Rødal',    'ingvild.rodal@eksempel.example',    '+47 400 00 017', 'Korsrygg, løft på jobb'],
    ['Kasper Vold',      'kasper.vold@eksempel.example',      '+47 400 00 018', 'Legg, løping'],
    ['Solveig Bakkan',   'solveig.bakkan@eksempel.example',   '+47 400 00 019', 'Kjeve og nakke'],
    ['Fredrik Aasheim',  'fredrik.aasheim@eksempel.example',  '+47 400 00 020', 'Skulder, styrketrening'],
    ['Hedda Lindgren',   'hedda.lindgren@eksempel.example',   '+47 400 00 021', 'Ankel, gammel skade'],
    ['Oskar Rein',       'oskar.rein@eksempel.example',       '+47 400 00 022', 'Rygg, langkjøring'],
    ['Vilde Ramsvik',    'vilde.ramsvik@eksempel.example',    '+47 400 00 023', 'Håndledd, klatring'],
    ['Anders Tveten',    'anders.tveten@eksempel.example',    '+47 400 00 024', 'Nakke etter fall'],
    ['Live Sandaker',    'live.sandaker@eksempel.example',    '+47 400 00 025', 'Hofte, gravid uke 28'],
    ['Bjørnar Kvamme',   'bjornar.kvamme@eksempel.example',   '+47 400 00 026', 'Skulder, maler'],
    ['Thea Molvær',      'thea.molvaer@eksempel.example',     '+47 400 00 027', 'Fot, plantar'],
    ['Eirik Nordbø',     'eirik.nordbo@eksempel.example',     '+47 400 00 028', 'Rygg, tunge løft'],
    ['Sara Hjelmeland',  'sara.hjelmeland@eksempel.example',  '+47 400 00 029', 'Kne, håndball'],
    ['Ola Bringsvor',    'ola.bringsvor@eksempel.example',    '+47 400 00 030', 'Nakke, sovestilling']
  ];

  var BEHANDLERE = [
    ['markus', 'Markus Westengen'],
    ['sofie',  'Sofie Aune'],
    ['henrik', 'Henrik Dal'],
    ['jonas',  'Jonas Riis']
  ];

  var BEHANDLINGER = [
    ['forstegangsvurdering', 'Førstegangsvurdering', 1290, 60],
    ['oppfolging',           'Oppfølgingstime',       790, 30],
    ['trykkbolge',           'Trykkbølgebehandling',  690, 30],
    ['bevegelsesanalyse',    'Bevegelsesanalyse',    1490, 60]
  ];

  var NOTATER = [
    'Demonotat 1. Innholdet er konstruert for demonstrasjonen og gjelder ingen virkelig pasient. Notatet beskriver ingen behandling.',
    'Demonotat 2. Oppdiktet, og uten innhold om behandling. Gjelder ingen virkelig pasient.',
    'Demonotat 3. Konstruert tekst, fordelt over de gjennomførte timene så klientkortene ikke ser like ut.',
    'Demonotat 4. Fylltekst uten opplysninger om behandling eller om noen virkelig person.',
    'Demonotat 5. Oppdiktet notat. Det står her fordi en tom journal ikke demonstrerer journalfunksjonen.'
  ];

  var TIDER_MARKUS = ['07:00:00', '08:30:00', '10:30:00', '12:00:00'];
  var TIDER_TER    = ['08:00:00', '10:00:00', '11:30:00', '13:30:00'];

  var FRA_DAG = -30, TETT_TIL = 21, TIL_DAG = 100;

  // JS sin % avkorter mot null, akkurat som Postgres, så
  // normaliseringene fra SQL-en kan stå som de er.
  function mod(a, n) { return ((a % n) + n) % n; }

  function build(nowMs) {
    var now = nowMs == null ? Date.now() : nowMs;
    var nowIso = new Date(now).toISOString();
    var today = osloToday(now);
    function ago(ms) { return new Date(now - ms).toISOString(); }
    var H = 3600 * 1000, D = 24 * H;

    var t = {
      staff_members: [], services: [], staff_services: [],
      bookings: [], journal_entries: [], contact_messages: [], reviews: [],
      waitlist: [], exercise_documents: [], document_sends: [],
      blocked_slots: [], holidays: [], special_open_days: [],
      audit_log: [], push_subscriptions: []
    };

    // ----- Katalog ------------------------------------------------
    STAFF.forEach(function (s) {
      t.staff_members.push({
        staff_id: s[0], name: s[1], role: s[2], bio: s[3],
        bookable: s[4], is_pool: s[5], aktiv: true, sortering: s[6], color: s[7],
        created_at: CREATED, updated_at: CREATED
      });
    });
    SERVICES.forEach(function (s) {
      t.services.push({
        id: s[0], slug: s[1], name: s[2], description: s[3],
        duration_min: s[4], price_nok: s[5], color: null, icon: null,
        sort_order: s[6], is_active: true, is_public: true,
        created_at: CREATED, updated_at: CREATED
      });
    });
    STAFF.forEach(function (s) {
      SERVICES.forEach(function (svc) {
        t.staff_services.push({ staff_id: s[0], service_id: svc[0] });
      });
    });

    // ----- Stengte dager -----------------------------------------
    var stengt1 = addDays(today, 24);
    while (isoDow(stengt1) >= 6) stengt1 = addDays(stengt1, 1);
    var stengt2 = addDays(today, 60);
    while (isoDow(stengt2) >= 6) stengt2 = addDays(stengt2, 1);

    // ----- Bestillinger ------------------------------------------
    var n = 0;
    for (var offset = FRA_DAG; offset <= TIL_DAG; offset++) {
      var d = addDays(today, offset);
      if (isoDow(d) >= 6 || d === stengt1 || d === stengt2) continue;
      if (offset > TETT_TIL && offset % 2 !== 0) continue;

      for (var bi = 1; bi <= BEHANDLERE.length; bi++) {
        if (mod(offset + bi, 3) === 0) continue;
        if (offset > TETT_TIL && !(bi === 1 || bi === 2 + (Math.trunc(offset / 2) % 3))) continue;

        var spredning = mod(offset + bi, 4);
        var beh = BEHANDLERE[bi - 1];
        var klokke = beh[0] === 'markus' ? TIDER_MARKUS[spredning] : TIDER_TER[spredning];
        var ki = mod(offset * 3 + bi * 5, KUNDER.length);
        var kunde = KUNDER[ki];
        var behandling = BEHANDLINGER[spredning];
        n++;

        var bid = 'demo-' + d.replace(/-/g, '') + '-' + beh[0] + '-' + n;
        var bref = 'WK-' + hex4(bid) + '-' + String(1000 + n).padStart(4, '0');
        var status = d >= today ? 'confirmed' : (n % 11 === 0 ? 'cancelled' : 'completed');

        // Bestilt 3–22 dager før timen, men aldri i framtiden.
        var dagStart = Date.parse(d + 'T00:00:00Z');
        var opprettet = new Date(Math.min(now, dagStart) - ((Math.abs(offset) % 20) + 3) * D).toISOString();

        t.bookings.push({
          id: bid, ref: bref,
          staff_id: beh[0], staff_name: beh[1],
          service_id: behandling[0], service_name: behandling[1],
          price: behandling[2], duration: behandling[3],
          date: d, time: klokke,
          name: kunde[0], email: kunde[1], phone: kunde[2], notes: kunde[3],
          status: status,
          journal_consent: true, journal_consent_at: opprettet,
          newsletter_opt_in: false,
          cancel_token: uuid(), review_token: uuid(),
          reminder_sent_at: null,
          created_at: opprettet, is_demo_seed: true
        });
      }
    }

    // ----- Journalnotater ----------------------------------------
    t.bookings.forEach(function (b) {
      if (b.status !== 'completed') return;
      t.journal_entries.push({
        id: uuid(), booking_id: b.id,
        patient_email: b.email, patient_phone: b.phone,
        staff_id: b.staff_id, staff_name: b.staff_name,
        content: NOTATER[hash32(b.id) % NOTATER.length],
        created_at: osloWallToIso(b.date, '16:00'), is_demo_seed: true
      });
    });

    // ----- Innkomne meldinger ------------------------------------
    [
      ['Ingvild Rødal', 'ingvild.rodal@eksempel.example',
       'Hei! Jeg har vondt i korsryggen etter en del tunge løft på jobb. Passer en førstegangsvurdering, eller skal jeg begynne et annet sted?',
       'new', 2 * H],
      ['Vilde Ramsvik', 'vilde.ramsvik@eksempel.example',
       'Er det mulig å få time før klokka åtte? Jeg begynner på jobb 09:00.', 'new', 5 * H],
      ['Anders Tveten', 'anders.tveten@eksempel.example',
       'Jeg falt på ski i helgen og har vondt i nakken. Bør jeg vente med å bestille, eller komme så fort som mulig?',
       'new', 9 * H],
      ['Kasper Vold', 'kasper.vold@eksempel.example',
       'Kan jeg flytte timen min på torsdag til uka etter? Jeg er bortreist.', 'read', 1 * D],
      ['Live Sandaker', 'live.sandaker@eksempel.example',
       'Behandler dere gravide? Jeg er i uke 28 og har vondt i hoften.', 'read', 2 * D],
      ['Thea Molvær', 'thea.molvaer@eksempel.example',
       'Får jeg kvittering på e-post som kan brukes mot forsikring?', 'answered', 3 * D],
      ['Solveig Bakkan', 'solveig.bakkan@eksempel.example',
       'Hei. Har dere ledig time tidlig på morgenen i løpet av de neste ukene?', 'answered', 4 * D],
      ['Ola Bringsvor', 'ola.bringsvor@eksempel.example',
       'Hvor lang tid tar en førstegangsvurdering? Jeg må rekke et møte etterpå.', 'answered', 6 * D]
    ].forEach(function (m) {
      t.contact_messages.push({
        id: uuid(), name: m[0], email: m[1], message: m[2], status: m[3],
        created_at: ago(m[4]), updated_at: ago(m[4]), is_demo_seed: true
      });
    });

    // ----- Anmeldelser -------------------------------------------
    [
      ['Sindre K.',  5, 'Oppdiktet anmeldelse. Teksten er fyll, slik at moderasjonskøen i adminpanelet ikke står tom.', 'approved', 9],
      ['Amalie H.',  5, 'Oppdiktet anmeldelse. Ingen ekte kunde står bak den, og den beskriver ingen behandling.', 'approved', 21],
      ['Malin N.',   4, 'Oppdiktet anmeldelse med fire stjerner, slik at snittet i demoen ikke er fem blankt.', 'approved', 28],
      ['Oskar R.',   5, 'Oppdiktet anmeldelse. Teksten sier ingenting om behandling, og gjelder ingen virkelig person.', 'approved', 34],
      ['Hedda L.',   4, 'Oppdiktet anmeldelse. Innholdet er konstruert for demonstrasjonen.', 'approved', 41],
      ['Terje Ø.',   4, 'Oppdiktet anmeldelse til vurdering, så køen i adminpanelet har noe å vise.', 'pending', 2],
      ['Eirik N.',   5, 'Oppdiktet anmeldelse til vurdering. Ren fylltekst.', 'pending', 4],
      ['Bjørnar K.', 2, 'Oppdiktet anmeldelse, avvist i moderasjonen.', 'rejected', 12]
    ].forEach(function (r) {
      t.reviews.push({
        id: uuid(), name: r[0], rating: r[1], body: r[2], status: r[3],
        booking_id: null, approved_by: null, approved_at: null,
        created_at: ago(r[4] * D), is_demo_seed: true
      });
    });

    // ----- Venteliste --------------------------------------------
    var mmdd = today.slice(5, 7) + today.slice(8, 10);
    [
      ['markus', 'Markus Westengen', 'Fredrik Aasheim', 'fredrik.aasheim@eksempel.example', '+47 400 00 020',
       1, 21, '08:00:00', '12:00:00', 'Skulder. Kan komme på kort varsel.', 'waiting', 3 * D],
      [null, 'Markus\' terapeuter', 'Hedda Lindgren', 'hedda.lindgren@eksempel.example', '+47 400 00 021',
       3, null, null, null, 'Ankel. Fleksibel på tidspunkt.', 'waiting', 1 * D],
      ['markus', 'Markus Westengen', 'Sara Hjelmeland', 'sara.hjelmeland@eksempel.example', '+47 400 00 029',
       2, 14, '12:00:00', '15:00:00', 'Kne. Kun ettermiddag på grunn av trening.', 'waiting', 6 * H],
      [null, 'Markus\' terapeuter', 'Eirik Nordbø', 'eirik.nordbo@eksempel.example', '+47 400 00 028',
       5, 30, null, null, 'Rygg. Tar det som blir ledig.', 'offered', 2 * D],
      ['markus', 'Markus Westengen', 'Ola Bringsvor', 'ola.bringsvor@eksempel.example', '+47 400 00 030',
       -2, 7, null, null, 'Nakke. Fikk time, står som akseptert.', 'accepted', 8 * D],
      [null, 'Markus\' terapeuter', 'Vilde Ramsvik', 'vilde.ramsvik@eksempel.example', '+47 400 00 023',
       45, 80, '07:00:00', '09:00:00', 'Håndledd. Bare før jobb.', 'waiting', 5 * H]
    ].forEach(function (w, i) {
      t.waitlist.push({
        id: uuid(), ref: 'WK-WL-' + mmdd + '-' + String(i + 1).padStart(4, '0'),
        service_id: null, staff_id: w[0], staff_name: w[1],
        name: w[2], email: w[3], phone: w[4],
        preferred_date_from: addDays(today, w[5]),
        preferred_date_to: w[6] == null ? null : addDays(today, w[6]),
        preferred_time_from: w[7], preferred_time_to: w[8],
        notes: w[9], status: w[10],
        created_at: ago(w[11]), updated_at: ago(w[11]), is_demo_seed: true
      });
    });

    // ----- Øvelsesdokumenter -------------------------------------
    [
      ['Nakkeøvelser, nivå 1',       'nakke',   'nakke-1.pdf',   'Markus Westengen', 40],
      ['Nakkeøvelser, nivå 2',       'nakke',   'nakke-2.pdf',   'Markus Westengen', 38],
      ['Skulder, utadrotasjon',      'skulder', 'skulder-1.pdf', 'Sofie Aune',       31],
      ['Skulder, stabilitet',        'skulder', 'skulder-2.pdf', 'Sofie Aune',       29],
      ['Hofte, tøy og styrke',       'hofte',   'hofte-1.pdf',   'Henrik Dal',       22],
      ['Knekontroll etter vridning', 'kne',     'kne-1.pdf',     'Henrik Dal',       19],
      ['Ankel, balanse',             'ankel',   'ankel-1.pdf',   'Jonas Riis',       12],
      ['Fotbue og plantarfascie',    'fot',     'fot-1.pdf',     'Jonas Riis',        7]
    ].forEach(function (x) {
      t.exercise_documents.push({
        id: uuid(), title: x[0], category: x[1],
        storage_path: 'demo/' + x[2], file_name: x[2], mime_type: 'application/pdf',
        uploaded_by: null, uploaded_by_name: x[3],
        created_at: ago(x[4] * D), is_demo_seed: true
      });
    });
    // De fem eldste dokumentene er sendt til de fem første kundene.
    for (var i = 1; i <= 5; i++) {
      var doc = t.exercise_documents[i - 1];
      t.document_sends.push({
        id: uuid(), document_id: doc.id, document_title: doc.title,
        customer_email: KUNDER[i - 1][1],
        link_url: 'demo://exercise-documents/' + doc.storage_path,
        sent_by: null, sent_by_name: null,
        created_at: ago(i * 2 * D)
      });
    }

    // ----- Stengte tider -----------------------------------------
    [
      ['markus', 2, '11:00:00'], ['markus', 2, '11:30:00'],
      ['sofie', 4, '13:00:00'],
      ['henrik', 3, '09:00:00'], ['henrik', 3, '09:30:00'],
      ['jonas', 7, '14:30:00'],
      ['markus', 38, '11:00:00'],
      ['sofie', 75, '14:30:00']
    ].forEach(function (s) {
      t.blocked_slots.push({ staff_id: s[0], date: addDays(today, s[1]), time: s[2], description: null, is_demo_seed: true });
    });

    t.holidays.push({ date: stengt1, is_demo_seed: true });
    t.holidays.push({ date: stengt2, is_demo_seed: true });

    // En åpen lørdag neste uke og en om to måneder.
    var tilLordag = mod(6 - isoDow(today) + 7, 7);
    [tilLordag + 7, tilLordag + 63].forEach(function (off) {
      t.special_open_days.push({
        date: addDays(today, off), staff_id: 'markus',
        open_time: '09:00:00', close_time: '13:00:00',
        created_at: nowIso, is_demo_seed: true
      });
    });

    // ----- Audit-logg --------------------------------------------
    t.journal_entries.forEach(function (j) {
      t.audit_log.push({
        id: uuid(), actor_staff_id: j.staff_id, actor_staff_name: j.staff_name,
        action: 'journal_create', target_type: 'journal_entry', target_id: j.id,
        metadata: { booking_id: j.booking_id }, created_at: j.created_at
      });
    });
    t.journal_entries.forEach(function (j) {
      var sett = Date.parse(j.created_at) + 3 * D;
      if (sett >= now) return;
      t.audit_log.push({
        id: uuid(), actor_staff_id: j.staff_id, actor_staff_name: j.staff_name,
        action: 'journal_view', target_type: 'patient', target_id: j.patient_email,
        metadata: { via: 'kundekort' }, created_at: new Date(sett).toISOString()
      });
    });
    t.bookings.forEach(function (b) {
      if (b.status !== 'completed' && b.status !== 'cancelled') return;
      t.audit_log.push({
        id: uuid(), actor_staff_id: b.staff_id, actor_staff_name: b.staff_name,
        action: 'booking_status_change', target_type: 'booking', target_id: b.id,
        metadata: { from_status: 'confirmed', to_status: b.status },
        created_at: osloWallToIso(b.date, '17:00')
      });
    });

    return { day: today, tables: t };
  }

  root.WestengenKlinikkDemoSeed = {
    build: build,
    osloToday: osloToday,
    osloWallToIso: osloWallToIso,
    uuid: uuid
  };
})(window);
