/* ============================================================
   Westengen Klinikk — In-house booking engine (async)
   Backend: Supabase (required). Historisk localStorage-fallback fjernet
   som del av V4-fix — pasientdata skal aldri ligge per-browser.
   ALL public methods return Promises.

   V8 (2026-05-11): tjeneste-katalogen er nå database-drevet via
   shared/services.js. STAFF og HOURS forblir hardkodet inntil videre
   (kun 2 staff-grupper, sjelden endring). SERVICES-objektet bygges
   opp dynamisk ved oppstart fra services + staff_services-tabellene.
   Eksisterende consumers leser SERVICES synkront — derfor må alle
   konsumere ventes på via ensureLoaded() før første render.
   ============================================================ */
(function () {
  'use strict';

  // ----- Config / backend detection -------------------------------
  var CFG = window.WestengenKlinikkBackend || {};
  var SUPABASE_URL = (CFG.supabaseUrl || '').replace(/\/+$/, '');
  var SUPABASE_KEY = CFG.supabaseAnonKey || '';
  var USE_SUPABASE = !!(SUPABASE_URL && SUPABASE_KEY);

  // Kanonisk klinikk-telefonnummer leses fra WestengenKlinikkConfig (P1-5 fra
  // audit 2026-05-15). Fallback til hardkodet verdi hvis config-scriptet
  // ikke har lastet (defensive — under normale page-load-rekkefølger
  // er booking-config.js alltid lastet før booking-engine.js).
  var CLINIC_PHONE = (window.WestengenKlinikkConfig && window.WestengenKlinikkConfig.CLINIC_PHONE)
    || '+47 400 00 000';

  // Rens historisk PII fra localStorage (V4). Eldre versjoner av engine-en
  // lagret bookinger lokalt; vi sikrer at ingen rester ligger igjen.
  try {
    localStorage.removeItem('tasbk_v1_bookings');
    localStorage.removeItem('tasbk_v1_blocked');
    localStorage.removeItem('tasbk_v1_holidays');
  } catch (e) {}

  if (!USE_SUPABASE) {
    // Forventet tilstand i en frisk klone, ikke en feil: derfor warn og
    // ikke error. Meldingen peker paa det ene steget som mangler.
    console.warn('Westengen Klinikk: Supabase er ikke konfigurert - '
      + 'bestillingsflyten er utilgjengelig. Fyll inn supabaseUrl og '
      + 'supabaseAnonKey i shared/booking-config.js (se DEMO_SETUP.md).');
  }

  // ----- Catalog --------------------------------------------------
  // STAFF og HOURS er hardkodet i frontend, men staff_services-koblingen
  // er DB-drevet (jf. 0008 + 0015). Hver staff-id under speiler en rad
  // i staff_services som peker på de aktive services-radene.
  //
  // bookable:false betyr at staff-objektet vises ikke som kort i
  // bestilling.html, men admin/kalender-UI kan fortsatt slå opp navn
  // og bio for gamle bookinger med denne staff_id. Kunde-fasende booking
  // skal vise nøyaktig to valg: 'markus' (Markus selv) og 'terapeut' (anonymisert
  // paraply). De 6 navngitte terapeutene er bookable:false her men beholdes
  // i tabellen for admin-tildeling og historiske bookinger.
  var STAFF = [
    { id: 'markus', name: 'Markus Westengen', role: 'Behandler',
      bio: 'Timen settes opp hos Markus. Oppdiktet behandler i en oppdiktet klinikk.' },
    { id: 'terapeut', name: 'Markus\' terapeuter', role: 'Opplært av Markus selv',
      bio: 'Vi tildeler en av våre erfarne terapeuter, alle opplært direkte i Markus\' metoder. Samme filosofi, samme grundighet.' },
    { id: 'sofie', name: 'Sofie Aune', role: 'Terapeut',
      bio: 'Opplært direkte av Markus. Samme metodikk, samme grundighet.',
      bookable: false },
    { id: 'henrik', name: 'Henrik Dal', role: 'Terapeut',
      bio: 'Opplært direkte av Markus. Samme metodikk, samme grundighet.',
      bookable: false },
    { id: 'jonas', name: 'Jonas Riis', role: 'Terapeut',
      bio: 'Opplært direkte av Markus. Samme metodikk, samme grundighet.',
      bookable: false },
    { id: 'amina', name: 'Amina Nour', role: 'Terapeut',
      bio: 'Opplært direkte av Markus. Samme metodikk, samme grundighet.',
      bookable: false },
    { id: 'petter', name: 'Petter Holm', role: 'Terapeut',
      bio: 'Opplært direkte av Markus. Samme metodikk, samme grundighet.',
      bookable: false },
    { id: 'lena', name: 'Lena Vik', role: 'Terapeut',
      bio: 'Opplært direkte av Markus. Samme metodikk, samme grundighet.',
      bookable: false }
  ];
  // De seks navngitte terapeutene som "Markus' terapeuter"-paraplyen
  // (staff_id NULL) fordeles på. Brukes av gruppe-tilgjengelighet og
  // kapasitetsregningen. Speiler bookable:false-radene i STAFF over.
  var THERAPIST_POOL = ['sofie', 'henrik', 'jonas', 'amina', 'petter', 'lena'];
  // SERVICES-objektet keys staff_id → array av tjeneste-objekter.
  // Felt-mapping fra services-tabellen:
  //   id ← services.id (UUID), beholder også slug for fallback-oppslag
  //   name ← services.name
  //   desc ← services.description
  //   price ← services.price_nok
  //   duration ← services.duration_min
  // Pre-load: tomme arrays, fylles av loadServices() ved boot.
  var SERVICES = {};
  STAFF.forEach(function (s) { SERVICES[s.id] = []; });

  var HOURS = {
    1: { open: '07:00', close: '15:00' }, 2: { open: '07:00', close: '15:00' },
    3: { open: '07:00', close: '15:00' }, 4: { open: '07:00', close: '15:00' },
    5: { open: '07:00', close: '15:00' }
  };

  // ----- Per-terapeut arbeidstid (overstyrer HOURS) ---------------
  // Kun staff-id-er som ligger her avviker fra standard HOURS; alle
  // andre behandlere beholder HOURS uendret. `breaks` er 30-min
  // starttider som ALDRI er bookbare (faste, tilbakevendende pauser) —
  // løses i kode (ikke som blocked_slots-rader, som er per-dato og
  // dermed ikke kan være permanente).
  var STAFF_HOURS = {
    // Markus: bookbar 06:00–13:00 (åpner 06:00, siste starttid 12:30 siden
    // en 30-min time må slutte innen 13:00). Fast pause 09:30–10:00 →
    // 09:30-slotet er aldri bookbart.
    markus: { open: '06:00', close: '13:00', breaks: ['09:30'] }
  };

  // Returnerer { open, close, breaks } for en staff på en gitt ukedag,
  // eller null hvis klinikken er stengt den dagen. Helg er stengt for
  // ALLE (HOURS har bare man–fre); per-staff-overstyring gjelder kun
  // åpne dager, så Markus får ikke booking i helg av dette.
  function getHoursForStaff(staffId, dow) {
    var base = HOURS[dow];
    if (!base) return null;
    var ov = STAFF_HOURS[staffId];
    if (!ov) return { open: base.open, close: base.close, breaks: [] };
    return { open: ov.open, close: ov.close, breaks: ov.breaks || [] };
  }

  // Behandlerens faste pauser, uavhengig av ukedag. Trengs fordi en
  // special_open_days-rad kan åpne en dag der getHoursForStaff() gir
  // null (helg), og pausene skal gjelde også da: en fast pause er
  // behandlerens, ikke ukedagens. Tidligere satte engangsåpningen
  // breaks til [], slik at Markus' 09:30-pause var bookbar på en åpen
  // lørdag.
  function breaksForStaff(staffId) {
    var ov = STAFF_HOURS[staffId];
    return (ov && ov.breaks) ? ov.breaks : [];
  }

  // ----- Staff loader (DB-drevet med KODE-FALLBACK) ----------------
  // V?-DEL-C (2026-06-03): STAFF + THERAPIST_POOL leses nå fra
  // staff_members-tabellen (migrasjon 0041) slik at admin kan legge
  // til / deaktivere behandlere. Konstantene over forblir FALLBACK:
  // loadStaff() muterer arrayene KUN hvis DB gir gyldige, ikke-tomme
  // data med minst én BOOKBAR behandler. Ved tom tabell, feil,
  // manglende tabell (før 0041 apply), eller 0 bookbare → beholdes
  // kode-konstantene. Kunden ser derfor ALDRI en tom behandlerliste.
  //
  // STAFF/THERAPIST_POOL eksporteres by reference (jf. Export-blokken),
  // så mutering IN-PLACE (ikke reassignment) oppdaterer alle konsumenter
  // (booking-flow.js, booking-admin.html, kalender.html).
  function applyStaffRows(rows) {
    var newStaff = rows.map(function (r) {
      return {
        id: r.staff_id,
        name: r.name,
        role: r.role || '',
        bio: r.bio || '',
        bookable: (r.bookable === true)
      };
    });
    // SIKKERHETSNETT: minst én bookbar behandler, ellers behold fallback.
    if (newStaff.filter(function (s) { return s.bookable; }).length === 0) return false;
    // Muter STAFF in-place (bevarer eksportert referanse).
    STAFF.length = 0;
    Array.prototype.push.apply(STAFF, newStaff);
    // Muter THERAPIST_POOL in-place — kun hvis DB gir minst én pool-id
    // (ellers beholdes kode-poolen, så gruppe-kapasiteten aldri blir 0).
    var pool = rows.filter(function (r) { return r.is_pool === true; })
                   .map(function (r) { return r.staff_id; });
    if (pool.length > 0) {
      THERAPIST_POOL.length = 0;
      Array.prototype.push.apply(THERAPIST_POOL, pool);
    }
    // Sørg for SERVICES-nøkkel for hver staff (loadServices re-initer uansett).
    STAFF.forEach(function (s) { if (!SERVICES[s.id]) SERVICES[s.id] = []; });
    return true;
  }
  function loadStaff() {
    if (!USE_SUPABASE) return Promise.resolve();
    return sbGet('staff_members?select=staff_id,name,role,bio,bookable,is_pool,sortering&aktiv=eq.true&order=sortering.asc,name.asc')
      .then(function (rows) {
        if (Array.isArray(rows) && rows.length > 0 && applyStaffRows(rows)) return;
        console.warn('booking-engine: staff_members tom/utilgjengelig eller 0 bookbare, beholder kode-fallback (STAFF/THERAPIST_POOL).');
      })
      .catch(function (err) {
        // Tabell finnes ikke (før 0041) / nettverksfeil → behold fallback.
        console.warn('booking-engine: kunne ikke laste staff_members (' +
          ((err && err.message) || 'ukjent') + '), beholder kode-fallback (STAFF/THERAPIST_POOL).');
      });
  }

  // ----- Service loader -------------------------------------------
  // Bygger SERVICES-objektet fra services + staff_services-tabellene
  // via shared/services.js. Promise singleton — flere ensureLoaded()-kall
  // returnerer samme in-flight load.
  var _servicesLoadPromise = null;
  function loadServices() {
    if (!USE_SUPABASE) return Promise.resolve(SERVICES);
    var Services = window.WestengenKlinikkServices;
    if (!Services) {
      console.error('booking-engine: shared/services.js er ikke lastet, kan ikke hente tjenester.');
      return Promise.resolve(SERVICES);
    }
    return Promise.all([Services.loadActiveServices(), Services.loadStaffMap()])
      .then(function (res) {
        var allServices = res[0] || [];
        var staffMap = res[1] || {};

        // Tøm og bygg på nytt slik at refresh kan endre SERVICES uten
        // å la dødvekt fra forrige last bli igjen.
        STAFF.forEach(function (s) { SERVICES[s.id] = []; });

        // Map service.id → service for raskt oppslag
        var byId = {};
        allServices.forEach(function (s) { byId[s.id] = s; });

        Object.keys(staffMap).forEach(function (staffId) {
          if (!SERVICES[staffId]) SERVICES[staffId] = [];
          (staffMap[staffId] || []).forEach(function (serviceId) {
            var svc = byId[serviceId];
            if (!svc) return;
            SERVICES[staffId].push({
              id: svc.id,
              slug: svc.slug,
              name: svc.name,
              desc: svc.description || '',
              price: svc.price_nok,
              duration: svc.duration_min,
              color: svc.color || null,
              icon: svc.icon || null,
              sort_order: svc.sort_order
            });
          });
        });

        // Sort per-staff på sort_order (services.js sorterte allerede globalt,
        // men staffMap-iterasjon kan ha rotet rekkefølgen).
        Object.keys(SERVICES).forEach(function (k) {
          SERVICES[k].sort(function (a, b) {
            return (a.sort_order || 0) - (b.sort_order || 0);
          });
        });

        return SERVICES;
      });
  }

  function ensureLoaded() {
    // Hvis WestengenKlinikkServices ikke var tilgjengelig forrige gang vi prøvde
    // (feil script-rekkefølge), cacher vi IKKE løftet — slik at neste kall
    // får en ny sjanse når services.js har lastet.
    if (_servicesLoadPromise) return _servicesLoadPromise;
    var hasServicesModule = !!window.WestengenKlinikkServices;
    // Last behandlere FØRST (loadStaff feiler aldri — den faller tilbake til
    // kode-konstanten internt), så tjenester (loadServices re-initer SERVICES
    // ut fra STAFF, så DB-behandlere må være på plass først).
    var p = loadStaff().then(function () { return loadServices(); });
    if (hasServicesModule) _servicesLoadPromise = p;
    return p;
  }

  // Tvinger fersk last (admin har endret services).
  function reloadServices() {
    if (window.WestengenKlinikkServices) window.WestengenKlinikkServices.invalidate();
    _servicesLoadPromise = loadServices();
    return _servicesLoadPromise;
  }

  // Tvinger fersk last av behandlere (admin har lagt til/deaktivert).
  // Muterer STAFF/THERAPIST_POOL in-place med samme fallback-garanti.
  function reloadStaff() {
    return loadStaff();
  }

  // Synkront oppslag mot allerede-lastet katalog. Hvis service_id
  // ikke matcher en aktiv tjeneste (gammel booking med utgått slug),
  // returnerer null — caller må ha en fallback (typisk: les serviceName
  // direkte fra booking-raden i stedet).
  function getServiceById(staffId, serviceId) {
    var list = SERVICES[staffId] || [];
    for (var i = 0; i < list.length; i++) {
      var s = list[i];
      if (s.id === serviceId || s.slug === serviceId) return s;
    }
    return null;
  }

  // Boot: start lasting med en gang scriptet kjører. Consumers som er
  // raskere enn nettet får et fallback fra ensureLoaded().
  if (USE_SUPABASE) { ensureLoaded(); }

  // ----- ID generation --------------------------------------------
  // P2-8 fra audit 2026-05-15: bookings.id er nå crypto.randomUUID (~122
  // bits entropy, RFC 4122 v4). Erstatter ad-hoc 'bk_'+timestamp+Math.random
  // -mønsteret. bookings.id er `text NOT NULL` i DB — UUID-string passer
  // uten migrasjon. UUID-formatet er også nødvendig forutsetning for P1-7
  // sin retry-dedup: stabil id lar oss tolke bookings_pkey-conflict ved
  // retry som "INSERTen gikk gjennom forrige forsøk".
  function generateBookingId() {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    // Fallback for legacy browsers (iOS <15.4, Chrome <92). Lower entropy
    // men preservere historisk format slik at gamle bookinger fortsatt har
    // matchende mønster om databasen sammenlignes på prefiks.
    return 'bk_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  }

  // Token-basert avbestilling (0024): genereres klient-side slik at
  // bekreftelses-skjermen har token UTEN et SELECT (anon har ikke
  // SELECT på bookings). uuid-format matcher kolonnen bookings.cancel_token.
  // Eldre nettlesere uten crypto.randomUUID → null: feltet utelates fra
  // INSERT-en, DB-DEFAULT gen_random_uuid() tar over (lenke vises da ikke).
  function generateCancelToken() {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
    return null;
  }

  // ----- Date helpers ---------------------------------------------
  function pad(n) { return String(n).padStart(2, '0'); }
  function ymd(date) { return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate()); }
  function parseYMD(str) { var p = str.split('-'); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function timeToMinutes(t) { var p = t.split(':'); return (+p[0]) * 60 + (+p[1]); }
  function minutesToTime(m) { return pad(Math.floor(m / 60)) + ':' + pad(m % 60); }
  function addDays(date, n) { var d = new Date(date); d.setDate(d.getDate() + n); return d; }
  // ----- Klinikkens klokke, ikke besøkendes ------------------------
  // «I dag» og «for sent å booke» skal regnes i Europe/Oslo. Tidligere
  // brukte begge nettleserens lokale klokke, så en besøkende i en annen
  // tidssone fikk et annet «i dag» og en annen 60-minutters grense enn
  // klinikken faktisk har. Datoene og klokkeslettene i basen er
  // vegg-klokke uten sone (date + time without time zone) — altså
  // Oslo-tid — så det er Oslo vi må sammenligne mot.
  //
  // Intl med hourCycle h23 gir 00–23 (h12/hour12:false kan gi «24»).
  // en-CA gir ISO-formatert dato, som lar seg sammenligne som streng.
  function osloNow() {
    try {
      var p = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Europe/Oslo',
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', hourCycle: 'h23'
      }).formatToParts(new Date()).reduce(function (a, x) { a[x.type] = x.value; return a; }, {});
      return { date: p.year + '-' + p.month + '-' + p.day,
               minutes: (+p.hour) * 60 + (+p.minute) };
    } catch (e) {
      // Uten Intl/sonedata: fall tilbake til lokal klokke framfor å kaste.
      var n = new Date();
      return { date: ymd(n), minutes: n.getHours() * 60 + n.getMinutes() };
    }
  }
  function isPastDate(date) { return ymd(date) < osloNow().date; }
  function isToday(date) { return ymd(date) === osloNow().date; }

  // ----- Supabase REST wrapper ------------------------------------
  function sbHeaders(extra) {
    var h = {
      'apikey': SUPABASE_KEY,
      'Authorization': 'Bearer ' + SUPABASE_KEY,
      'Content-Type': 'application/json'
    };
    if (extra) for (var k in extra) h[k] = extra[k];
    return h;
  }
  function sbGet(path) {
    return fetch(SUPABASE_URL + '/rest/v1/' + path, { headers: sbHeaders() })
      .then(function (r) { if (!r.ok) throw new Error('Supabase GET ' + r.status); return r.json(); });
  }
  function sbPost(path, body, prefer) {
    return fetch(SUPABASE_URL + '/rest/v1/' + path, {
      method: 'POST',
      headers: sbHeaders({ 'Prefer': prefer || 'return=representation' }),
      body: JSON.stringify(body)
    }).then(function (r) {
      if (!r.ok) return r.text().then(function (t) { throw new Error('Supabase POST ' + r.status + ': ' + t); });
      // return=minimal yields an empty body; tolerate that without throwing on parse.
      return r.text().then(function (t) { return t ? JSON.parse(t) : null; });
    });
  }

  // P1-7 fra audit 2026-05-15: detekter transiente feil som er trygge å
  // retry-e. Permanente feil (4xx unntatt 408/429) skal IKKE retry-es —
  // dårlig input vil bare feile likt N ganger.
  function isTransientError(status, errName) {
    if (errName === 'TypeError' || errName === 'AbortError') return true;
    if (typeof status === 'number') {
      return status >= 500 || status === 429 || status === 408;
    }
    return false;
  }

  // P1-7: booking-INSERT med exponential-backoff retry (250→500→1000 ms)
  // og dedup via bookings_pkey-conflict-deteksjon. Forutsetning: id (P2-8)
  // er generert ÉN gang utenfor denne funksjonen, slik at retry-attempts
  // sender samme id. Hvis attempt 0 lyktes i DB men response gikk tapt
  // (network drop midt i HTTP-svar), vil attempt 1 med samme id treffe
  // bookings_pkey → vi tolker det som "success, vår booking eksisterer".
  //
  // bookings_active_slot_unique (også 23505) håndteres IKKE som dedup —
  // det betyr at en ANNEN klient tok slot-en mellom våre forsøk og caller
  // får legitim slot_taken-feil via existing catch-block.
  function sbPostBookingWithRetry(body, opts) {
    opts = opts || {};
    var maxAttempts = opts.maxAttempts || 3;
    var baseDelay = opts.baseDelay || 250;
    var attempt = 0;

    function once() {
      return fetch(SUPABASE_URL + '/rest/v1/bookings', {
        method: 'POST',
        headers: sbHeaders({ 'Prefer': 'return=minimal' }),
        body: JSON.stringify(body)
      }).then(function (r) {
        if (r.ok) return { ok: true };
        return r.text().then(function (t) {
          // Dedup: retry + 23505 + bookings_pkey = vår INSERT gikk gjennom
          // forrige attempt, response forsvant. Returner som success.
          if (attempt > 0 && r.status === 409
              && t.indexOf('23505') !== -1
              && t.indexOf('bookings_pkey') !== -1) {
            return { ok: true, dedupedRetry: true };
          }
          return { ok: false, status: r.status, body: t,
                   transient: isTransientError(r.status, null) };
        });
      }, function (err) {
        return { ok: false, status: 0, body: (err && err.message) || 'Network error',
                 transient: isTransientError(0, err && err.name) };
      });
    }

    function next() {
      return once().then(function (res) {
        if (res.ok) return res;
        if (!res.transient || attempt >= maxAttempts - 1) {
          // Permanent-feil eller siste retry: throw med samme format
          // som sbPost slik at createBooking's existing catch kan
          // detektere 23505/bookings_active_slot_unique uendret.
          var e = new Error('Supabase POST ' + res.status + ': ' + res.body);
          e.statusCode = res.status;
          throw e;
        }
        attempt++;
        var delay = baseDelay * Math.pow(2, attempt - 1);
        return new Promise(function (resolve) { setTimeout(resolve, delay); }).then(next);
      });
    }

    return next();
  }
  function sbPatch(path, body) {
    return fetch(SUPABASE_URL + '/rest/v1/' + path, {
      method: 'PATCH', headers: sbHeaders({ 'Prefer': 'return=representation' }), body: JSON.stringify(body)
    }).then(function (r) { if (!r.ok) throw new Error('Supabase PATCH ' + r.status); return r.json(); });
  }
  function sbDelete(path) {
    return fetch(SUPABASE_URL + '/rest/v1/' + path, { method: 'DELETE', headers: sbHeaders() })
      .then(function (r) { if (!r.ok) throw new Error('Supabase DELETE ' + r.status); });
  }
  // RPC-kall mot PostgREST: POST /rest/v1/rpc/<fn> med JSON-body der
  // hver nøkkel er en navngitt funksjons-parameter (p_staff_id osv.).
  // Brukes for SECURITY DEFINER-funksjoner som erstatter views (jf. 0016).
  function sbRpc(fn, args) {
    return fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: sbHeaders(),
      body: JSON.stringify(args || {})
    }).then(function (r) {
      if (!r.ok) return r.text().then(function (t) { throw new Error('Supabase RPC ' + fn + ' ' + r.status + ': ' + t); });
      return r.json();
    });
  }

  // ----- Row mappers (DB <-> JS) ----------------------------------
  function rowToBooking(r) {
    return {
      id: r.id, ref: r.ref,
      staffId: r.staff_id, staffName: r.staff_name,
      serviceId: r.service_id, serviceName: r.service_name,
      price: r.price, duration: r.duration,
      date: r.date, time: (r.time || '').slice(0, 5),
      name: r.name, email: r.email, phone: r.phone,
      notes: r.notes || '', status: r.status,
      journalConsent: !!r.journal_consent,
      journalConsentAt: r.journal_consent_at || null,
      cancelToken: r.cancel_token || null,
      createdAt: r.created_at
    };
  }
  function bookingToRow(b) {
    var row = {
      id: b.id, ref: b.ref,
      staff_id: b.staffId, staff_name: b.staffName,
      service_id: b.serviceId, service_name: b.serviceName,
      price: b.price, duration: b.duration,
      date: b.date, time: b.time,
      name: b.name, email: b.email, phone: b.phone,
      notes: b.notes || '', status: b.status,
      journal_consent: !!b.journalConsent,
      journal_consent_at: b.journalConsentAt || null,
      newsletter_opt_in: !!b.newsletterOptIn,
      created_at: b.createdAt
    };
    // cancel_token: inkluder kun hvis frontend genererte en. Utelates
    // helt (ikke null) for eldre nettlesere → DB-DEFAULT tar over.
    if (b.cancelToken) row.cancel_token = b.cancelToken;
    return row;
  }

  // ----- Storage facade (returns Promises) ------------------------
  function getBookings() {
    return sbGet('bookings?select=*').then(function (rows) { return rows.map(rowToBooking); });
  }
  // Lite read for public booking flow: kaller SECURITY DEFINER-funksjonen
  // public.get_booked_slots() (jf. migrasjon 0016) som server-side filtrerer
  // til status IN ('confirmed','completed') og kun returnerer 4 kolonner
  // uten PII. Erstattet det tidligere booked_slots-viewet for å lukke
  // Supabase Database Linter sin security_definer_view-ERROR.
  // Default args (alle null) gir samme resultatmengde som det gamle viewet.
  function getBookedSlots() {
    return sbRpc('get_booked_slots', {}).then(function (rows) {
      return rows.map(function (r) {
        return { staffId: r.staff_id, date: r.date, time: (r.time || '').slice(0, 5), duration: r.duration };
      });
    });
  }
  function getBlocked() {
    // Eksplisitt kolonneliste: anon har kolonne-grant på kun
    // (staff_id, date, time) etter migrasjon 0057 — select=* ville gitt
    // permission denied, og description-fritekst skal uansett aldri til anon.
    return sbGet('blocked_slots?select=staff_id,date,time').then(function (rows) {
      return rows.map(function (r) { return { staffId: r.staff_id, date: r.date, time: (r.time || '').slice(0,5) }; });
    });
  }
  function getHolidays() {
    return sbGet('holidays?select=date').then(function (rows) { return rows.map(function (r) { return r.date; }); });
  }
  // Engangs «åpne en lørdag»-overstyring per (staff, dato). Anon har
  // kolonne-grant på (staff_id, date, open_time, close_time) etter 0059.
  // En rad gjør en normalt stengt dag (helg) bookbar for ÉN navngitt
  // behandler innenfor [open, close). Holiday vinner fortsatt (sjekkes
  // før denne i slot-genereringen). Pool-paraplyen påvirkes ikke.
  function getSpecialOpenDays() {
    return sbGet('special_open_days?select=staff_id,date,open_time,close_time').then(function (rows) {
      return rows.map(function (r) {
        return { staffId: r.staff_id, date: r.date,
          open: (r.open_time || '').slice(0, 5), close: (r.close_time || '').slice(0, 5) };
      });
    });
  }
  function specialFor(special, staffId, dateStr) {
    for (var i = 0; i < special.length; i++) {
      if (special[i].staffId === staffId && special[i].date === dateStr) return special[i];
    }
    return null;
  }

  // ----- Slot generation (now async) ------------------------------
  // ----- Varighet og opptatte blokker -----------------------------
  // Rutenettet er 30 minutter. En behandling som varer lenger legger
  // beslag paa flere blokker etter hverandre, og maa derfor bade
  // sjekke og reservere alle sammen.
  //
  // Foer dette blokkerte en booking bare sitt eget starttidspunkt.
  // Det gikk saa lenge alle tjenestene var 30 minutter; med ulike
  // varigheter ville en 60-minutters time latt neste halvtime staa
  // ledig, og to kunder kunne booket oppa hverandre.
  function blocksFor(minutes) {
    return Math.max(1, Math.ceil((minutes || 30) / 30));
  }

  // Utvider hver booking til alle blokkene den faktisk opptar.
  // blocked_slots har ingen varighet og dekker alltid én blokk.
  function occupiedMap(bookings, blockedList) {
    var occ = {};
    (bookings || []).forEach(function (b) {
      var start = timeToMinutes(b.time);
      var n = blocksFor(b.duration);
      for (var i = 0; i < n; i++) occ[minutesToTime(start + i * 30)] = true;
    });
    (blockedList || []).forEach(function (b) { occ[b.time] = true; });
    return occ;
  }

  // Er det plass til `need` blokker fra og med minutt m?
  function fits(m, need, endMin, occ, breaks) {
    if (m + need * 30 > endMin) return false;
    for (var i = 0; i < need; i++) {
      var t = minutesToTime(m + i * 30);
      if (occ[t]) return false;
      if (breaks.indexOf(t) !== -1) return false;
    }
    return true;
  }

  function generateSlotsForDay(staffId, dateStr, durationMinutes) {
    var date = parseYMD(dateStr);
    if (isPastDate(date)) return Promise.resolve([]);
    return Promise.all([getHolidays(), getBookedSlots(), getBlocked(), getSpecialOpenDays()]).then(function (res) {
      var holidays = res[0], bookedSlots = res[1], blocked = res[2], special = res[3];
      if (holidays.indexOf(dateStr) !== -1) return [];
      var dow = date.getDay();
      // Engangs lørdagsåpning: en special_open_days-rad for (staff, dato)
      // overstyrer ukedag-stengingen (holiday er allerede sjekket over).
      var sp = specialFor(special, staffId, dateStr);
      var hrs = sp ? { open: sp.open, close: sp.close, breaks: breaksForStaff(staffId) } : getHoursForStaff(staffId, dow);
      if (!hrs) return [];
      var startMin = timeToMinutes(hrs.open), endMin = timeToMinutes(hrs.close), stepMin = 30;
      var need = blocksFor(durationMinutes);
      var occ = occupiedMap(
        bookedSlots.filter(function (b) { return b.staffId === staffId && b.date === dateStr; }),
        blocked.filter(function (b) { return b.staffId === staffId && b.date === dateStr; }));
      var nowBuffer = 0;
      if (isToday(date)) { nowBuffer = osloNow().minutes + 60; }
      var slots = [];
      for (var m = startMin; m + stepMin <= endMin; m += stepMin) {
        var t = minutesToTime(m);
        if (hrs.breaks.indexOf(t) !== -1) continue; // fast pause — aldri bookbar
        var past = m < nowBuffer;
        // Hele behandlingen maa faa plass, ikke bare foerste halvtime.
        var room = fits(m, need, endMin, occ, hrs.breaks);
        slots.push({ time: t, available: room && !past,
                     reason: past ? 'past' : (room ? null : 'taken') });
      }
      return slots;
    });
  }

  function getOpenDays(staffId, daysAhead, durationMinutes) {
    daysAhead = daysAhead || 28;
    return Promise.all([getHolidays(), getBookedSlots(), getBlocked(), getSpecialOpenDays()]).then(function (res) {
      var holidays = res[0], bookedSlots = res[1], blocked = res[2], special = res[3];
      var out = [];
      var today = new Date(); today.setHours(0,0,0,0);
      for (var i = 0; i < daysAhead; i++) {
        var d = addDays(today, i);
        var dateStr = ymd(d);
        var dow = d.getDay();
        // Lørdagsåpning: en special-rad gjør en ellers stengt dag åpen.
        var sp = specialFor(special, staffId, dateStr);
        var isOpen = (!!HOURS[dow] || !!sp) && holidays.indexOf(dateStr) === -1;
        var slotCount = 0;
        if (isOpen) {
          var hrs = sp ? { open: sp.open, close: sp.close, breaks: breaksForStaff(staffId) } : getHoursForStaff(staffId, dow);
          var startMin = timeToMinutes(hrs.open), endMin = timeToMinutes(hrs.close), stepMin = 30;
          var need = blocksFor(durationMinutes);
          var occ = occupiedMap(
            bookedSlots.filter(function (b) { return b.staffId === staffId && b.date === dateStr; }),
            blocked.filter(function (b) { return b.staffId === staffId && b.date === dateStr; }));
          var nowBuffer = 0;
          if (isToday(d)) { nowBuffer = osloNow().minutes + 60; }
          for (var m = startMin; m + stepMin <= endMin; m += stepMin) {
            if (m >= nowBuffer && fits(m, need, endMin, occ, hrs.breaks)) slotCount++;
          }
        }
        out.push({ date: dateStr, dow: dow, day: d.getDate(), month: d.getMonth(), year: d.getFullYear(),
          isOpen: isOpen, hasFree: slotCount > 0, slotCount: slotCount });
      }
      return out;
    });
  }

  // ----- Gruppe-tilgjengelighet ("Markus' terapeuter") ---------------
  // Når kunden booker en "Markus' terapeuter"-tjeneste velges ingen
  // konkret terapeut — bookingen lagres ufordelt (staff_id = NULL) og
  // admin tildeler en av THERAPIST_POOL senere. Tilgjengelighet er da
  // et POOL-spørsmål: et slot er ledig hvis FÆRRE enn 5 terapeut-
  // plasser er opptatt. Opptatt = (navngitte pool-terapeuter med
  // booking ELLER blokkert tid) + (ufordelte bookinger på slotet).
  //
  // Ufordelt teller med: en NULL-booking blir tildelt en av de 5
  // senere, så den konsumerer en plass nå. Gamle bookinger fra før
  // arkitektur-endringen har staff_id = 'terapeut' — de teller også
  // som ufordelt pool-forbruk.
  function isUnassignedPool(staffId) {
    return staffId == null || staffId === 'terapeut';
  }

  // Bygger { 'HH:MM': { busy: {staffId:true,...}, unassigned: int } }
  // for én dato ut fra booked slots + blokkerte tider.
  function groupOccupancyForDate(dateStr, bookedSlots, blocked) {
    var perTime = {};
    function slot(t) {
      if (!perTime[t]) perTime[t] = { busy: {}, unassigned: 0 };
      return perTime[t];
    }
    bookedSlots.forEach(function (b) {
      if (b.date !== dateStr) return;
      // En booking legger beslag paa plassen sin i hele sin lengde,
      // ikke bare i foerste halvtime.
      var start = timeToMinutes(b.time);
      var n = blocksFor(b.duration);
      for (var i = 0; i < n; i++) {
        var t = minutesToTime(start + i * 30);
        if (isUnassignedPool(b.staffId)) {
          slot(t).unassigned++;
        } else if (THERAPIST_POOL.indexOf(b.staffId) !== -1) {
          slot(t).busy[b.staffId] = true;
        }
      }
      // staff_id = 'markus' teller ikke mot terapeut-poolen.
    });
    blocked.forEach(function (b) {
      if (b.date !== dateStr) return;
      if (THERAPIST_POOL.indexOf(b.staffId) !== -1) {
        slot(b.time).busy[b.staffId] = true;
      }
    });
    return perTime;
  }

  // Antall opptatte pool-plasser på et gitt tidspunkt.
  function occupiedCount(slotInfo) {
    if (!slotInfo) return 0;
    return Object.keys(slotInfo.busy).length + slotInfo.unassigned;
  }

  // Slots for én dato for "Markus' terapeuter"-paraplyen. Samme retur-
  // shape som generateSlotsForDay() slik at booking-flow kan bruke
  // dem om hverandre. durationMinutes er reservert for framtidige
  // ikke-30-min-tjenester — slot-rutenettet er 30 min som ellers i
  // engine-en.
  function getGroupAvailability(dateStr, durationMinutes) {
    var date = parseYMD(dateStr);
    if (isPastDate(date)) return Promise.resolve([]);
    return Promise.all([getHolidays(), getBookedSlots(), getBlocked()]).then(function (res) {
      var holidays = res[0], bookedSlots = res[1], blocked = res[2];
      if (holidays.indexOf(dateStr) !== -1) return [];
      var dow = date.getDay();
      var hrs = HOURS[dow]; if (!hrs) return [];
      var occ = groupOccupancyForDate(dateStr, bookedSlots, blocked);
      var startMin = timeToMinutes(hrs.open), endMin = timeToMinutes(hrs.close), stepMin = 30;
      var nowBuffer = 0;
      if (isToday(date)) { nowBuffer = osloNow().minutes + 60; }
      var need = blocksFor(durationMinutes);
      var slots = [];
      for (var m = startMin; m + stepMin <= endMin; m += stepMin) {
        var t = minutesToTime(m);
        // Poolen maa ha en ledig plass i HVER blokk behandlingen dekker,
        // og hele behandlingen maa rekke aa bli ferdig innen stengetid.
        var full = m + need * 30 > endMin;
        for (var k = 0; !full && k < need; k++) {
          if (occupiedCount(occ[minutesToTime(m + k * 30)]) >= THERAPIST_POOL.length) full = true;
        }
        var past = m < nowBuffer;
        slots.push({ time: t, available: !full && !past, reason: past ? 'past' : (full ? 'taken' : null) });
      }
      return slots;
    });
  }

  // 28-dagers oversikt for "Markus' terapeuter"-paraplyen. Samme shape
  // som getOpenDays() — én datahenting, gruppe-kapasitet per dag.
  function getGroupOpenDays(daysAhead, durationMinutes) {
    daysAhead = daysAhead || 28;
    return Promise.all([getHolidays(), getBookedSlots(), getBlocked()]).then(function (res) {
      var holidays = res[0], bookedSlots = res[1], blocked = res[2];
      var out = [];
      var today = new Date(); today.setHours(0,0,0,0);
      for (var i = 0; i < daysAhead; i++) {
        var d = addDays(today, i);
        var dateStr = ymd(d);
        var dow = d.getDay();
        var isOpen = !!HOURS[dow] && holidays.indexOf(dateStr) === -1;
        var slotCount = 0;
        if (isOpen) {
          var hrs = HOURS[dow];
          var occ = groupOccupancyForDate(dateStr, bookedSlots, blocked);
          var startMin = timeToMinutes(hrs.open), endMin = timeToMinutes(hrs.close), stepMin = 30;
          var nowBuffer = 0;
          if (isToday(d)) { nowBuffer = osloNow().minutes + 60; }
          var need = blocksFor(durationMinutes);
          for (var m = startMin; m + stepMin <= endMin; m += stepMin) {
            if (m < nowBuffer || m + need * 30 > endMin) continue;
            var free = true;
            for (var k = 0; free && k < need; k++) {
              if (occupiedCount(occ[minutesToTime(m + k * 30)]) >= THERAPIST_POOL.length) free = false;
            }
            if (free) slotCount++;
          }
        }
        out.push({ date: dateStr, dow: dow, day: d.getDate(), month: d.getMonth(), year: d.getFullYear(),
          isOpen: isOpen, hasFree: slotCount > 0, slotCount: slotCount });
      }
      return out;
    });
  }

  // ----- Booking creation -----------------------------------------
  function createBooking(payload) {
    return ensureLoaded().then(function () {
      // 'terapeut' = "Markus' terapeuter"-paraplyen → bookingen lagres
      // ufordelt (staff_id NULL), og tilgjengelighet er et pool-
      // spørsmål. 'markus' og evt. andre staff-id-er er uendret.
      var isGroup = payload.staffId === 'terapeut';
      return Promise.all([getBookedSlots(), getBlocked()]).then(function (pre) {
        var bookedSlots = pre[0], blocked = pre[1];
        var conflict;
        if (isGroup) {
          // Ufordelt booking: slotet er fullt hvis alle 5 pool-
          // plassene allerede er opptatt.
          var occ = groupOccupancyForDate(payload.date, bookedSlots, blocked);
          conflict = occupiedCount(occ[payload.time]) >= THERAPIST_POOL.length;
        } else {
          conflict = bookedSlots.some(function (b) {
            return b.staffId === payload.staffId && b.date === payload.date
              && b.time === payload.time;
          });
        }
        if (conflict) return { ok: false, reason: 'slot_taken', message: 'Denne tiden ble nettopp booket av en annen. Velg en annen tid.' };
        var service = getServiceById(payload.staffId, payload.serviceId);
        if (!service) return { ok: false, error: 'Ugyldig tjeneste.' };
        var staff = STAFF.find(function (s) { return s.id === payload.staffId; });
        if (!staff) return { ok: false, error: 'Ugyldig behandler.' };
        var nowIso = new Date().toISOString();
        var booking = {
          id: generateBookingId(),
          ref: 'TA-' + (Math.random().toString(36).slice(2, 6)).toUpperCase() + '-' + Date.now().toString().slice(-4),
          // Ufordelte "Markus' terapeuter"-bookinger lagres med staff_id
          // NULL; admin tildeler en navngitt terapeut i booking-admin.
          // staff_name beholdes som kunde-vendt placeholder.
          staffId: isGroup ? null : payload.staffId, staffName: staff.name,
          serviceId: service.id, serviceName: service.name,
          price: service.price, duration: service.duration,
          date: payload.date, time: payload.time,
          name: payload.name, email: payload.email, phone: payload.phone,
          notes: payload.notes || '', status: 'confirmed',
          journalConsent: !!payload.journalConsent,
          journalConsentAt: payload.journalConsent ? (payload.journalConsentAt || nowIso) : null,
          // Token-basert avbestillings-lenke (0024). Sendes med i INSERT-en
          // og returneres i booking-objektet → bekreftelses-skjermen kan
          // bygge avbestill.html?token=… uten et SELECT mot bookings.
          cancelToken: generateCancelToken(),
          createdAt: nowIso
        };
        // return=minimal so PostgREST doesn't run RETURNING * (which would need anon SELECT).
        // Engine generates id + ref client-side, no need for return data.
        // P1-7: wrap-et i sbPostBookingWithRetry for å håndtere transiente
        // feil (5xx, 429, network drops). booking.id er allerede generert
        // her — retry sender SAMME id → pkey-conflict på retry = dedup-success.
        return sbPostBookingWithRetry(bookingToRow(booking)).then(function (res) {
          if (res && res.dedupedRetry) {
            console.warn('Booking dedup: retry hit existing bookings_pkey for id ' + booking.id +
                         ', første attempt lyktes i DB men response gikk tapt.');
          }
          return { ok: true, booking: booking };
        })
          .catch(function (e) {
            console.error(e);
            var msg = (e && e.message) ? String(e.message) : '';
            // 23505 / bookings_active_slot_unique: race der en annen klient
            // tok nøyaktig denne slot-en mellom pre-sjekk og INSERT.
            if (msg.indexOf('23505') !== -1 || msg.indexOf('bookings_active_slot_unique') !== -1) {
              return { ok: false, reason: 'slot_taken', message: 'Denne tiden ble nettopp booket av en annen. Velg en annen tid.' };
            }
            // 23514 / enforce_unassigned_capacity: 0020-kapasitetstriggeren
            // avviste — alle terapeut-plassene på dette tidspunktet er fylt.
            if (msg.indexOf('23514') !== -1 || msg.indexOf('enforce_unassigned_capacity') !== -1) {
              return { ok: false, reason: 'no_capacity', message: 'Det er ingen ledige terapeuter på dette tidspunktet lenger. Velg en annen tid.' };
            }
            return { ok: false, error: 'Noe gikk galt. Prøv igjen, eller kontakt oss på ' + CLINIC_PHONE + '.' };
          });
      });
    });
  }

  function cancelBooking(id) {
    return sbPatch('bookings?id=eq.' + encodeURIComponent(id), { status: 'cancelled' }).then(function () { return true; });
  }
  function deleteBooking(id) {
    return sbDelete('bookings?id=eq.' + encodeURIComponent(id));
  }

  // ----- Block / unblock / holidays -------------------------------
  function blockSlot(staffId, date, time) {
    return sbPost('blocked_slots', { staff_id: staffId, date: date, time: time }).catch(function () {});
  }
  function unblockSlot(staffId, date, time) {
    return sbDelete('blocked_slots?staff_id=eq.' + encodeURIComponent(staffId) + '&date=eq.' + date + '&time=eq.' + time);
  }
  function toggleHoliday(date) {
    return getHolidays().then(function (arr) {
      var has = arr.indexOf(date) !== -1;
      if (has) return sbDelete('holidays?date=eq.' + date);
      return sbPost('holidays', { date: date });
    });
  }

  // ----- Formatting -----------------------------------------------
  var DAYS_NO_LONG  = ['Søndag','Mandag','Tirsdag','Onsdag','Torsdag','Fredag','Lørdag'];
  var DAYS_NO_SHORT = ['Søn','Man','Tir','Ons','Tor','Fre','Lør'];
  var MONTHS_NO     = ['januar','februar','mars','april','mai','juni','juli','august','september','oktober','november','desember'];
  function formatDateLong(s)  { var d = parseYMD(s); return DAYS_NO_LONG[d.getDay()] + ' ' + d.getDate() + '. ' + MONTHS_NO[d.getMonth()]; }
  function formatDateShort(s) { var d = parseYMD(s); return DAYS_NO_SHORT[d.getDay()] + ' ' + d.getDate() + '/' + (d.getMonth() + 1); }
  function formatPrice(n) { return 'kr ' + n.toLocaleString('no-NO').replace(/,/g, ' '); }

  // ----- Export ---------------------------------------------------
  window.WestengenKlinikkBookingEngine = {
    backend: USE_SUPABASE ? 'supabase' : 'unavailable',
    CLINIC_PHONE: CLINIC_PHONE,
    STAFF: STAFF, SERVICES: SERVICES, HOURS: HOURS,
    // Eksponert for admin-UI (stengte-tider.html) som setter min/max på
    // tidsvelgerne etter behandlerens standard arbeidstid (Markus 06–13,
    // andre 07–15). dow=1 (mandag) gir alltid det åpne ukedags-vinduet.
    getHoursForStaff: getHoursForStaff, breaksForStaff: breaksForStaff,
    osloNow: osloNow,
    ensureLoaded: ensureLoaded, reloadServices: reloadServices, reloadStaff: reloadStaff,
    getServiceById: getServiceById,
    generateSlotsForDay: generateSlotsForDay, getOpenDays: getOpenDays,
    getGroupAvailability: getGroupAvailability, getGroupOpenDays: getGroupOpenDays,
    THERAPIST_POOL: THERAPIST_POOL,
    createBooking: createBooking, cancelBooking: cancelBooking, deleteBooking: deleteBooking,
    getBookings: getBookings, getBookedSlots: getBookedSlots, getBlocked: getBlocked, getHolidays: getHolidays,
    blockSlot: blockSlot, unblockSlot: unblockSlot, toggleHoliday: toggleHoliday,
    ymd: ymd, parseYMD: parseYMD,
    formatDateLong: formatDateLong, formatDateShort: formatDateShort, formatPrice: formatPrice,
    DAYS_NO_LONG: DAYS_NO_LONG, DAYS_NO_SHORT: DAYS_NO_SHORT, MONTHS_NO: MONTHS_NO
  };
})();
