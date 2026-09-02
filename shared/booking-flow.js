/* ============================================================
   Westengen Klinikk — Booking flow UI
   Renders the multi-step booking flow into a host element.
   Steps: 1 Behandler  2 Tjeneste  3 Dato  4 Tid  5 Detaljer  6 Bekreftet
   Usage:
     window.WestengenKlinikkBookingFlow.mount(hostEl, { initialStaff: 'markus' });
   ============================================================ */
(function () {
  'use strict';

  var E = window.WestengenKlinikkBookingEngine;
  if (!E) { console.error('booking-flow: engine not loaded'); return; }

  // i18n-helper: vi binder t() én gang per kall slik at booking-flow også
  // fungerer hvis i18n.js ikke er lastet (admin-flyt eller eldre side). Da
  // returneres fallback-strengen (norsk) direkte.
  function t(key, fallback) {
    if (window.WestengenKlinikkI18n && typeof window.WestengenKlinikkI18n.t === 'function') {
      return window.WestengenKlinikkI18n.t(key, fallback);
    }
    return fallback != null ? fallback : '[' + key + ']';
  }

  // ----- Validation helpers --------------------------------------
  // Email: must have local-part, '@', domain, '.', and TLD of ≥2 chars.
  // Rejects whitespace anywhere and double-@. Not RFC 5322-strict — but
  // good enough to catch typos like "tull@junk.k" without false positives
  // on legitimate addresses.
  var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
  function validateEmail(s) { return EMAIL_RE.test((s || '').trim()); }

  // Phone: accepts '+', '(', ')', '-', spaces. Strips them and requires
  // at least 8 digits (Norwegian numbers are 8; international can be longer).
  function validatePhone(raw) {
    var digits = (raw || '').replace(/[+()\-\s]/g, '');
    return /^\d{8,}$/.test(digits);
  }

  // P1-9 fra audit 2026-05-15: 'html'-attributtet ble fjernet fra el()-
  // helperen for å lukke en latent XSS-overflate. Hvis du trenger SVG
  // eller annet markup-innhold, bygg det med createElementNS eller
  // bruk svgCheckmark()-helperen nedenfor.
  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === 'class') n.className = attrs[k];
      else if (k === 'on') Object.keys(attrs.on).forEach(function (ev) { n.addEventListener(ev, attrs.on[ev]); });
      else n.setAttribute(k, attrs[k]);
    });
    if (children) (Array.isArray(children) ? children : [children]).forEach(function (c) {
      if (c == null) return;
      n.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    });
    return n;
  }

  // Sirkel-med-checkmark SVG-ikon for bekreftelses-trinnet. Bygget via
  // createElementNS slik at vi ikke trenger innerHTML på SVG-elementet.
  // Innholdet er konstant — ingen brukerinput.
  function svgCheckmark() {
    var NS = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', '0 0 48 48');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '2');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    var circle = document.createElementNS(NS, 'circle');
    circle.setAttribute('cx', '24');
    circle.setAttribute('cy', '24');
    circle.setAttribute('r', '20');
    svg.appendChild(circle);
    var path = document.createElementNS(NS, 'path');
    path.setAttribute('d', 'M14 24l7 7 14-15');
    svg.appendChild(path);
    return svg;
  }

  function mount(host, opts) {
    opts = opts || {};
    host.innerHTML = '';
    host.classList.add('tabf-host');

    // Tjeneste-katalogen er nå database-drevet via shared/services.js.
    // bootedRender + startRender sikrer at vi rendrer nøyaktig én gang
    // — etter at SERVICES er populert (eller etter at load mislyktes).
    // ensureLoaded() er idempotent + cachet, så billig å vente på.
    var bootedRender = false;
    function startRender() {
      if (bootedRender) return;
      bootedRender = true;
      render();
    }

    var state = {
      step: opts.initialStaff ? 2 : 1,
      staffId: opts.initialStaff || null,
      serviceId: null,
      date: null,
      time: null,
      name: '',
      email: '',
      phone: '',
      notes: '',
      consent: false,
      // P2-2 fra audit 2026-05-15: eksplisitt init slik at cb.checked-binding
      // er pålitelig før første endring. Sluttsubmit (admin-flyt) krever
      // journalConsent=true; kundeflyt krever termsAccepted=true.
      journalConsent: false,
      journalConsentAt: null,
      // Avbestillingsvilkår: ren frontend-gate i kundeflyten. Default false;
      // må krysses av i steg 5 før Bekreft-knappen tillater innsending.
      // Sendes IKKE som persondata til backend.
      termsAccepted: false,
      // D3 (Markus-feedback 2026-05-29): nyhetsbrev-opt-in, valgfri.
      // Default false; krysses av i steg 5 hvis kunden vil ha nyhetsbrev.
      newsletterOptIn: false,
      booking: null,
      error: null,
      // One-shot banner shown at top of step 4 (e.g. after slot_taken bounce).
      // Survives a single goTo() and is cleared by renderTimeStep after display.
      flash: null
    };

    function render() {
      host.innerHTML = '';
      host.appendChild(renderStepper());
      var body = el('div', { class: 'tabf-body' });
      host.appendChild(body);
      if (state.step === 1) body.appendChild(renderStaffStep());
      else if (state.step === 2) body.appendChild(renderServiceStep());
      else if (state.step === 3) body.appendChild(renderDateStep());
      else if (state.step === 4) body.appendChild(renderTimeStep());
      else if (state.step === 5) body.appendChild(renderDetailsStep());
      else if (state.step === 6) body.appendChild(renderConfirmStep());
      // scroll body to top on step change
      body.scrollTop = 0;
      var scrollers = host.closest('.tas-modal-body');
      if (scrollers) scrollers.scrollTop = 0;
    }

    // ---------- Stepper ----------
    function renderStepper() {
      var steps = [
        t('booking.stepper.behandler', 'Behandler'),
        t('booking.stepper.tjeneste', 'Tjeneste'),
        t('booking.stepper.dato', 'Dato'),
        t('booking.stepper.tid', 'Tid'),
        t('booking.stepper.detaljer', 'Detaljer'),
        t('booking.stepper.bekreftet', 'Bekreftet')
      ];
      var bar = el('div', { class: 'tabf-stepper' });
      steps.forEach(function (label, i) {
        var n = i + 1;
        var cls = 'tabf-step';
        if (n < state.step) cls += ' done';
        if (n === state.step) cls += ' current';
        var canJump = n < state.step;
        var btn = el('button', {
          type: 'button', class: cls,
          on: canJump ? { click: function () { goTo(n); } } : {}
        }, [
          el('span', { class: 'tabf-step-num' }, String(n)),
          el('span', { class: 'tabf-step-label' }, label)
        ]);
        if (!canJump) btn.disabled = true;
        bar.appendChild(btn);
      });
      return bar;
    }

    // ============================================================
    // Portrett i behandlerkortet
    // ------------------------------------------------------------
    // Fotoene er ikke tatt enda. Tabellen er derfor tom, og da spoer
    // vi aldri etter en fil som ikke finnes — et <img> mot en manglende
    // sti gir en 404 i konsollen paa hver eneste visning, og kravet er
    // at konsollen skal vaere ren.
    //
    // Naar bildene legges i assets/avatars/, foeres de opp her:
    //
    //   var PORTRETTER = {
    //     markus:   'assets/avatars/markus.png',
    //     terapeut: 'assets/avatars/terapeut.png'
    //   };
    //
    // Uten oppfoering viser kortet initialene i den blaa boksen, som
    // foer. Det gjoer det ogsaa hvis en fil er foert opp men mangler:
    // error-handleren tar bildet ut igjen, og initialene staar der
    // fortsatt under.
    //
    // Bildet er dekorasjon, ikke informasjon — navnet staar ved siden
    // av — saa alt-teksten er tom med vilje.
    // ============================================================
    var PORTRETTER = {};

    function lagAvatar(id, initialer) {
      var boks = el('div', { class: 'tabf-avatar' }, initialer);
      var sti = PORTRETTER[id];
      if (!sti) return boks;

      var img = el('img', {
        class: 'tabf-avatar-img',
        src: sti,
        alt: '',
        width: '48',
        height: '48',
        loading: 'lazy',
        decoding: 'async'
      });
      img.addEventListener('error', function () {
        if (img.parentNode) img.parentNode.removeChild(img);
      });
      boks.appendChild(img);
      return boks;
    }

    // ---------- Step 1: Staff ----------
    function renderStaffStep() {
      var wrap = el('div', { class: 'tabf-step-wrap' });
      wrap.appendChild(el('div', { class: 'tabf-eyebrow' }, t('booking.step1.eyebrow', 'Trinn 1 av 5')));
      // Admin-flyt (skipConsent): nøytralt admin-språk i stedet for
      // kunde-tiltale. Admin er norsk-only — bevisst ingen i18n-nøkler.
      wrap.appendChild(el('h3', { class: 'tabf-h' }, opts.skipConsent
        ? 'Behandler'
        : t('booking.step1.heading', 'Hvem vil du bestille time hos?')));
      wrap.appendChild(el('p', { class: 'tabf-sub' }, t('booking.step1.intro', 'To veier til samme grundige behandling. Velg det som passer deg best.')));
      var grid = el('div', { class: 'tabf-staff-grid' });
      E.STAFF.forEach(function (s) {
        // bookable:false → staff vises ikke som kort i kunde-flyten (typisk
        // legacy gruppe-id som 'terapeut' etter at navngitte terapeuter er live).
        // Admin/kalender-UI bruker fortsatt objektet for å slå opp gamle bookinger.
        if (s.bookable === false) return;
        // Pris vises bevisst først i steg 2 (Tjeneste) — steg 1 er ren

        // behandler-velger (Markus-feedback 2026-05-29).
        // Initialene utledes fra navnet. Tidligere var de hardkodet per
        // staff-id, som betyr at de ikke fulgte med naar en behandler
        // byttet navn — og at en ny behandler fra databasen fikk feil
        // forbokstav. Na stemmer de alltid.
        var initials = (s.name || '').split(/\s+/).filter(Boolean).slice(0, 2)
                         .map(function (w) { return w.charAt(0).toUpperCase(); })
                         .join('') || '·';
        var avatar = lagAvatar(s.id, initials);
        var tenureNote = s.id === 'terapeut'
          ? el('p', { class: 'tabf-staff-tenure', style: 'font-size:13px; opacity:.7; font-style:italic; margin:8px 0 0;' },
              t('booking.step1.therapist_tenure', 'Markus\' erfarne terapeuter har vært tilknyttet klinikken i minst 2 år.'))
          : null;
        var card = el('button', {
          type: 'button',
          class: 'tabf-staff-card' + (state.staffId === s.id ? ' selected' : ''),
          on: { click: function () { state.staffId = s.id; state.serviceId = null; goTo(2); } }
        }, [
          el('div', { class: 'tabf-staff-head' }, [
            avatar,
            el('div', null, [
              el('h4', null, t('behandlere.' + s.id + '.name', s.name)),
              el('div', { class: 'tabf-staff-role' }, t('behandlere.' + s.id + '.role', s.role))
            ])
          ]),
          el('p', { class: 'tabf-staff-bio' }, t('booking.staff.' + s.id + '.bio', s.bio)),
          tenureNote,
          el('div', { class: 'tabf-staff-foot' }, [
            el('span', { class: 'tabf-staff-cta' }, t('booking.step1.choose', 'Velg →'))
          ])
        ]);
        grid.appendChild(card);
      });
      wrap.appendChild(grid);
      // B3 (Markus-feedback): lang, tynn venteliste-CTA under behandler-kortene
      // for de som ikke finner en passende time. Navigerer ut av flyten til
      // venteliste-siden. KUN i kundeflyt — i admin-ny-booking (opts.skipConsent)
      // er den unødvendig siden ventelista har sin egen admin-side.
      if (!opts.skipConsent) {
        wrap.appendChild(el('a', {
          href: 'venteliste.html',
          class: 'tabf-waitlist-cta'
        }, [
          el('span', null, t('booking.step1.waitlist_cta', 'Fant du ikke en time som passer deg? Sett deg på ventelisten her')),
          el('span', { class: 'tabf-waitlist-arrow', 'aria-hidden': 'true' }, '→')
        ]));
      }
      return wrap;
    }

    // ---------- Step 2: Service ----------
    function renderServiceStep() {
      var wrap = el('div', { class: 'tabf-step-wrap' });
      var staff = E.STAFF.find(function (s) { return s.id === state.staffId; });
      wrap.appendChild(el('div', { class: 'tabf-eyebrow' }, t('booking.step2.eyebrow', 'Trinn 2 av 5') + ' · ' + staff.name));
      wrap.appendChild(el('h3', { class: 'tabf-h' }, t('booking.step2.heading', 'Velg type behandling')));
      wrap.appendChild(el('p', { class: 'tabf-sub' }, t('booking.step2.intro', 'Førstegang? Velg konsultasjon. Har du vært her før, velg videre behandling.')));
      var list = el('div', { class: 'tabf-service-list' });
      var staffServices = E.SERVICES[state.staffId] || [];
      if (staffServices.length === 0) {
        // To helt ulike aarsaker saa like ut foer: en tom katalog for
        // én behandler, og en demo som ikke har database i det hele
        // tatt. Det siste er det vanlige, og «velg en annen behandler»
        // var da et raad som ikke kunne foelges, uansett hva man valgte.
        if (E.backend !== 'supabase') {
          var box = el('div', { class: 'tabf-empty tabf-empty-setup' });
          box.appendChild(el('strong', null,
            t('booking.step2.no_backend_h', 'Denne kopien er ikke koblet til en database')));
          box.appendChild(el('p', null,
            t('booking.step2.no_backend_p',
              'Behandlingene ligger i databasen, saa lista er tom til demoen har en. '
            + 'Fyll inn Supabase-URL og anon-noekkel i shared/booking-config.js, '
            + 'og kjoer migrasjonene. Stegene staar i DEMO_SETUP.md.')));
          box.appendChild(el('p', { class: 'tabf-empty-note' },
            t('booking.step2.no_backend_note',
              'Resten av flyten kan du fortsatt klikke gjennom for aa se stegene.')));
          list.appendChild(box);
        } else {
          list.appendChild(el('div', { class: 'tabf-empty' },
            t('booking.step2.no_services',
              'Ingen behandlinger er koblet til denne behandleren. Velg en annen behandler.')));
        }
      }
      staffServices.forEach(function (sv) {
        var card = el('button', {
          type: 'button',
          class: 'tabf-service-card' + (state.serviceId === sv.id ? ' selected' : ''),
          on: { click: function () { state.serviceId = sv.id; goTo(3); } }
        }, [
          el('div', { class: 'tabf-service-main' }, [
            el('h4', null, sv.name),
            el('p', null, sv.desc),
            el('div', { class: 'tabf-service-meta' }, sv.duration + ' ' + t('booking.step2.minutes', 'minutter'))
          ]),
          el('div', { class: 'tabf-service-price' }, [
            el('div', { class: 'tabf-price-num' }, E.formatPrice(sv.price)),
            el('div', { class: 'tabf-price-cta' }, t('booking.step2.choose', 'Velg →'))
          ])
        ]);
        list.appendChild(card);
      });
      wrap.appendChild(list);
      wrap.appendChild(renderBackRow(1));
      return wrap;
    }

    // ---------- Step 3: Date ----------
    function renderDateStep() {
      var wrap = el('div', { class: 'tabf-step-wrap' });
      var staff = E.STAFF.find(function (s) { return s.id === state.staffId; });
      var sv = E.SERVICES[state.staffId].find(function (s) { return s.id === state.serviceId; });
      wrap.appendChild(el('div', { class: 'tabf-eyebrow' }, t('booking.step3.eyebrow', 'Trinn 3 av 5') + ' · ' + staff.name + ' · ' + sv.name));
      wrap.appendChild(el('h3', { class: 'tabf-h' }, t('booking.step3.heading', 'Velg dag')));
      wrap.appendChild(el('p', { class: 'tabf-sub' }, t('booking.step3.intro', 'Klinikken er åpen mandag–fredag 07:00–15:00. Vi viser de neste fire ukene.')));

      var loading = el('div', { class: 'tabf-empty' }, t('booking.step3.loading', 'Laster ledige dager…'));
      wrap.appendChild(loading);
      wrap.appendChild(renderBackRow(2));

      // "Markus' terapeuter" (staffId 'terapeut') har ingen konkret
      // behandler — bruk pool-tilgjengelighet over de 5 terapeutene.
      var dur = selectedDuration(state);
      var daysPromise = state.staffId === 'terapeut'
        ? E.getGroupOpenDays(28, dur)
        : E.getOpenDays(state.staffId, 28, dur);
      daysPromise.then(function (days) {
        loading.remove();
        var calWrap = renderDateCalendar(days);
        wrap.insertBefore(calWrap, wrap.lastChild);
        // Venteliste-CTA UNDER kalenderen (over tilbake-raden) for de som
        // ikke finner en passende dag. Gjenbruker samme tekst/stil som
        // steg 1 (ingen ny i18n-nøkkel). KUN kundeflyt — admin-ny-booking
        // (opts.skipConsent) har ventelistas egen admin-side.
        if (!opts.skipConsent) {
          wrap.insertBefore(el('a', {
            href: 'venteliste.html',
            class: 'tabf-waitlist-cta'
          }, [
            el('span', null, t('booking.step1.waitlist_cta', 'Fant du ikke en time som passer deg? Sett deg på ventelisten her')),
            el('span', { class: 'tabf-waitlist-arrow', 'aria-hidden': 'true' }, '→')
          ]), wrap.lastChild);
        }
      }).catch(function (err) {
        loading.textContent = t('booking.step3.load_error', 'Kunne ikke laste tilgjengelige dager. Sjekk nettverk.');
        console.error(err);
      });
      return wrap;
    }

    function renderDateCalendar(days) {
      var calWrap = el('div', null);
      // Group by week (starting Monday)
      var weeks = [];
      var current = [];
      days.forEach(function (d, i) {
        if (d.dow === 1 && current.length) { weeks.push(current); current = []; }
        current.push(d);
      });
      if (current.length) weeks.push(current);

      var cal = el('div', { class: 'tabf-cal' });
      // Header row
      var head = el('div', { class: 'tabf-cal-head' });
      [
        t('booking.cal.head_mon', 'Man'),
        t('booking.cal.head_tue', 'Tir'),
        t('booking.cal.head_wed', 'Ons'),
        t('booking.cal.head_thu', 'Tor'),
        t('booking.cal.head_fri', 'Fre'),
        t('booking.cal.head_sat', 'Lør'),
        t('booking.cal.head_sun', 'Søn')
      ].forEach(function (l) {
        head.appendChild(el('div', null, l));
      });
      calWrap.appendChild(cal);
      cal.appendChild(head);
      weeks.forEach(function (week) {
        var row = el('div', { class: 'tabf-cal-row' });
        // Pad to align by weekday (Mon=1 .. Sun=0 → position 7)
        for (var pos = 1; pos <= 7; pos++) {
          (function (pos) {
            var dow = pos === 7 ? 0 : pos;
            var d = week.find(function (x) { return x.dow === dow; });
            if (!d) {
              row.appendChild(el('div', { class: 'tabf-cal-cell empty' }));
              return;
            }
            var cellCls = 'tabf-cal-cell';
            if (!d.isOpen) cellCls += ' closed';
            else if (!d.hasFree) cellCls += ' full';
            else cellCls += ' open';
            if (state.date === d.date && d.isOpen && d.hasFree) cellCls += ' selected';
            var dateValue = d.date;
            var btn;
            if (d.isOpen && d.hasFree) {
              btn = el('button', {
                type: 'button', class: cellCls,
                on: { click: function () { state.date = dateValue; goTo(4); } }
              }, [
                el('div', { class: 'tabf-cal-day' }, String(d.day)),
                el('div', { class: 'tabf-cal-mon' }, E.MONTHS_NO[d.month].slice(0, 3)),
                el('div', { class: 'tabf-cal-status' }, d.slotCount + ' ' + t('booking.step3.slot_count_suffix', 'ledig'))
              ]);
            } else {
              btn = el('div', { class: cellCls }, [
                el('div', { class: 'tabf-cal-day' }, String(d.day)),
                el('div', { class: 'tabf-cal-mon' }, E.MONTHS_NO[d.month].slice(0, 3)),
                el('div', { class: 'tabf-cal-status' }, !d.isOpen ? t('booking.step3.closed', 'Stengt') : t('booking.step3.full', 'Fullt'))
              ]);
            }
            row.appendChild(btn);
          })(pos);
        }
        cal.appendChild(row);
      });
      var legend = el('div', { class: 'tabf-cal-legend' }, [
        el('span', null, [el('i', { class: 'sw open' }), t('booking.step3.legend_open', 'Ledig')]),
        el('span', null, [el('i', { class: 'sw full' }), t('booking.step3.legend_full', 'Fullt')]),
        el('span', null, [el('i', { class: 'sw closed' }), t('booking.step3.legend_closed', 'Stengt')])
      ]);
      calWrap.appendChild(legend);
      return calWrap;
    }

    // ---------- Step 4: Time ----------
    function renderTimeStep() {
      var wrap = el('div', { class: 'tabf-step-wrap' });
      var staff = E.STAFF.find(function (s) { return s.id === state.staffId; });
      var sv = E.SERVICES[state.staffId].find(function (s) { return s.id === state.serviceId; });
      wrap.appendChild(el('div', { class: 'tabf-eyebrow' }, t('booking.step4.eyebrow', 'Trinn 4 av 5') + ' · ' + E.formatDateLong(state.date)));
      wrap.appendChild(el('h3', { class: 'tabf-h' }, t('booking.step4.heading', 'Velg tidspunkt')));
      wrap.appendChild(el('p', { class: 'tabf-sub' }, sv.name + ' ' + t('booking.step4.with', 'med') + ' ' + staff.name + ' · ' + sv.duration + ' min · ' + E.formatPrice(sv.price)));
      // One-shot banner (e.g. slot_taken bounce). Clear after first render.
      if (state.flash) {
        wrap.appendChild(el('div', { class: 'tabf-error' }, state.flash));
        state.flash = null;
      }

      var loading = el('div', { class: 'tabf-empty' }, t('booking.step4.loading', 'Laster ledige tider…'));
      wrap.appendChild(loading);
      wrap.appendChild(renderBackRow(3));

      // "Markus' terapeuter": slot er ledig hvis minst én av de 5 i
      // pool-en er fri (se booking-engine getGroupAvailability).
      var slotDur = selectedDuration(state);
      var slotsPromise = state.staffId === 'terapeut'
        ? E.getGroupAvailability(state.date, slotDur)
        : E.generateSlotsForDay(state.staffId, state.date, slotDur);
      slotsPromise.then(function (slots) {
        loading.remove();
        // Safeguard (erstatter den gamle synkrone helge-sjekken): en
        // strukturelt stengt dag (helg UTEN engangs-åpning) gir tom
        // slots-liste → sprett tilbake til dagvelgeren som før. En
        // engangs-åpnet lørdag gir slots og rendres normalt.
        var sd = E.parseYMD(state.date);
        if (state.date && sd && !E.HOURS[sd.getDay()] && slots.length === 0) {
          state.date = null; goTo(3); return;
        }
        var grid = el('div', { class: 'tabf-time-grid' });
        slots.forEach(function (s) {
          var time = s.time;
          var btn = el('button', {
            type: 'button',
            class: 'tabf-time-slot' + (s.available ? '' : ' unavailable') + (state.time === s.time ? ' selected' : ''),
            on: s.available ? { click: function () { state.time = time; goTo(5); } } : {}
          }, time);
          if (!s.available) btn.disabled = true;
          grid.appendChild(btn);
        });
        wrap.insertBefore(grid, wrap.lastChild);
        if (!slots.some(function (s) { return s.available; })) {
          var emptyBox = el('div', { class: 'tabf-empty' }, t('booking.step4.no_slots', 'Ingen ledige tider denne dagen. Velg en annen dag.'));
          // Venteliste-utvei — kun i kundeflyt (admin håndterer manuelt).
          if (!opts.skipConsent) {
            emptyBox.appendChild(el('div', { class: 'tabf-waitlist-link' }, [
              el('a', { href: 'venteliste.html' }, t('booking.step4.waitlist_link', 'Ingen ledige tider? Sett deg på venteliste →'))
            ]));
          }
          wrap.insertBefore(emptyBox, wrap.lastChild);
        }
      }).catch(function (err) {
        loading.textContent = t('booking.step4.load_error', 'Kunne ikke laste tider.');
        console.error(err);
      });
      return wrap;
    }

    // ---------- Step 5: Details ----------
    function renderDetailsStep() {
      var wrap = el('div', { class: 'tabf-step-wrap' });
      var staff = E.STAFF.find(function (s) { return s.id === state.staffId; });
      var sv = E.SERVICES[state.staffId].find(function (s) { return s.id === state.serviceId; });
      wrap.appendChild(el('div', { class: 'tabf-eyebrow' }, t('booking.step5.eyebrow', 'Trinn 5 av 5')));
      wrap.appendChild(el('h3', { class: 'tabf-h' }, opts.skipConsent
        ? 'Kundedetaljer'
        : t('booking.step5.heading', 'Dine detaljer')));

      var summary = el('div', { class: 'tabf-summary' }, [
        el('div', null, [el('dt', null, t('booking.step5.sum_behandler', 'Behandler')), el('dd', null, staff.name)]),
        el('div', null, [el('dt', null, t('booking.step5.sum_service', 'Tjeneste')), el('dd', null, sv.name + ' · ' + sv.duration + ' min')]),
        el('div', null, [el('dt', null, t('booking.step5.sum_time', 'Tidspunkt')), el('dd', null, E.formatDateLong(state.date) + ' ' + t('booking.step5.sum_at', 'kl.') + ' ' + state.time)]),
        el('div', null, [el('dt', null, t('booking.step5.sum_price', 'Pris')), el('dd', null, E.formatPrice(sv.price))])
      ]);
      wrap.appendChild(summary);

      var form = el('form', { class: 'tabf-form', novalidate: '' });
      // Honeypot anti-spam (4b Markus-feedback 2026-05-30). Skjult for
      // mennesker (display:none + aria-hidden + tabindex=-1) men synlig
      // for bots som fyller alle felt. Sjekkes først i submit-handleren.
      var honeypot = el('div', { 'aria-hidden': 'true', style: 'display:none;' }, [
        el('label', { for: 'tabf-website' }, 'Website'),
        el('input', { id: 'tabf-website', name: 'website', type: 'text', tabindex: '-1', autocomplete: 'off' })
      ]);
      form.appendChild(honeypot);
      // Admin-flyt: kun navn er påkrevd (telefon-bookinger har ofte
      // ikke e-post). Kundeflyt: e-post + telefon fortsatt påkrevd.
      if (opts.skipConsent) {
        form.appendChild(field('name', 'Kundens navn', 'text', state.name, true));
        var rowA = el('div', { class: 'tabf-form-row-2' });
        rowA.appendChild(field('email', 'E-post (valgfritt)', 'email', state.email, false));
        rowA.appendChild(field('phone', 'Telefon (valgfritt)', 'tel', state.phone, false));
        form.appendChild(rowA);
        form.appendChild(field('notes', 'Notat (valgfritt)', 'textarea', state.notes, false, 2000));
      } else {
        form.appendChild(field('name', t('booking.step5.field_name', 'Fullt navn'), 'text', state.name, true));
        var row = el('div', { class: 'tabf-form-row-2' });
        row.appendChild(field('email', t('booking.step5.field_email', 'E-post'), 'email', state.email, true));
        row.appendChild(field('phone', t('booking.step5.field_phone', 'Telefon'), 'tel', state.phone, true));
        form.appendChild(row);
        form.appendChild(field('notes', t('booking.step5.field_notes', 'Beskriv kort dine plager (valgfritt)'), 'textarea', state.notes, false, 2000));
      }

      // Avkryssingene sto foer slik: nyhetsbrev, saa en setning om
      // avbestilling, saa vilkaar. Setningen delte de to boksene i to,
      // og leseren maatte ta stilling til den ene, lese en setning,
      // og saa ta stilling til den andre.
      //
      // Naa kommer setningen foerst, og begge boksene under den, som
      // én gruppe. Da er rekkefoelgen: her er regelen, her er det du
      // krysser av for.
      //
      // valgrad() gir begge samme rad som resten av siden
      // (shared/choice.css): hele raden klikkbar, boksen paa foerste
      // tekstlinje, minst 44 px hoy.
      function valgrad(avkrysset, ved, tekst) {
        var cb = el('input', { type: 'checkbox' });
        if (avkrysset) cb.checked = true;
        cb.addEventListener('change', function () { ved(cb.checked); });
        return el('label', { class: 'wk-choice wk-choice-plain' }, [
          cb, el('span', { class: 'wk-choice-text' }, tekst)
        ]);
      }

      if (opts.skipConsent) {
        // Admin-flyt: bekreftelse paa at samtykke ble innhentet muntlig.
        // Ingen avbestillingssetning her — den gis muntlig i telefonen.
        form.appendChild(valgrad(
          state.journalConsent,
          function (v) { state.journalConsent = v; },
          t('booking.step5.consent_journal_admin', 'Pasienten har samtykket muntlig til at det føres journal i forbindelse med behandlingen.')
        ));
      } else {
        // Kunde-flyt: regelen foerst, saa de to avkryssingene samlet.
        form.appendChild(el('div', { class: 'tabf-terms-notice' },
          t('booking.step5.cancel_notice', 'Timer som avbestilles mindre enn 24 timer før avtalt tidspunkt belastes i sin helhet.')));

        var samtykker = el('div', { class: 'wk-choice-group tabf-consent-group' });
        samtykker.appendChild(valgrad(
          state.termsAccepted,
          function (v) { state.termsAccepted = v; },
          t('booking.step5.terms_label', 'Jeg bekrefter at jeg har lest og godtar avbestillingsvilkårene.')
        ));
        samtykker.appendChild(valgrad(
          state.newsletterOptIn,
          function (v) { state.newsletterOptIn = v; },
          t('booking.step5.newsletter_label', 'Jeg ønsker å motta nyhetsbrev, tilbud og relevant informasjon på e-post (valgfritt).')
        ));
        form.appendChild(samtykker);
        // Diskret personvern-lenke. Ren lenke, IKKE et påkrevd samtykke.
        // Peker til den interne personvernsiden (samme relative form som
        // øvrige interne lenker, jf. footer i bestilling.html). Åpner i ny
        // fane så kunden ikke mister booking-fremdriften.
        form.appendChild(el('div', { class: 'tabf-privacy-link' }, [
          el('a', { href: 'personvern.html', target: '_blank', rel: 'noopener' },
            t('booking.step5.privacy_link', 'Personvernerklæring'))
        ]));
      }

      if (state.error) {
        form.appendChild(el('div', { class: 'tabf-error' }, state.error));
      }

      var actions = el('div', { class: 'tabf-actions tabf-actions-step5' }, [
        el('button', { type: 'button', class: 'tabf-btn-ghost', on: { click: function () { goTo(4); } } }, t('booking.step5.back', '← Tilbake')),
        el('button', { type: 'submit', class: 'tabf-btn-primary' }, [t('booking.step5.submit', 'Bekreft bestilling') + ' ', el('span', { 'aria-hidden': 'true' }, '→')])
      ]);
      form.appendChild(actions);

      form.addEventListener('submit', function (e) {
        e.preventDefault();
        // Honeypot-sjekk FØRST (4b Markus-feedback 2026-05-30). Hvis
        // 'website'-feltet er fylt = bot. Vis falsk "Sender…" → "Bekreftet"
        // inline, ingen DB-insert, ingen reell goTo(6). Bot tror submit
        // gikk gjennom — vi har stille filtrert.
        var hp = form.querySelector('[name="website"]');
        if (hp && hp.value) {
          var hpBtn = form.querySelector('.tabf-btn-primary');
          if (hpBtn) {
            hpBtn.disabled = true;
            hpBtn.classList.add('is-loading');
            hpBtn.textContent = t('booking.step5.submitting', 'Sender…');
            setTimeout(function () {
              hpBtn.classList.remove('is-loading');
              hpBtn.textContent = t('booking.confirm.heading', 'Timen er bekreftet');
            }, 1200);
          }
          return;
        }
        // Pull values
        ['name','email','phone','notes'].forEach(function (k) {
          var inp = form.querySelector('[name="' + k + '"]');
          if (inp) state[k] = inp.value.trim();
        });
        state.error = null;
        if (!state.name)  { state.error = t('booking.errors.name_required', 'Skriv inn navnet ditt.'); render(); return; }
        // Admin-flyt: e-post/telefon er valgfrie — valider kun når utfylt.
        // Kundeflyt: begge fortsatt påkrevd (uendret).
        var emailRequired = !opts.skipConsent || state.email !== '';
        var phoneRequired = !opts.skipConsent || state.phone !== '';
        if (emailRequired && !validateEmail(state.email)) { state.error = t('booking.errors.email_invalid', 'E-postadressen er ikke gyldig.'); render(); return; }
        if (phoneRequired && !validatePhone(state.phone)) { state.error = t('booking.errors.phone_invalid', 'Telefonnummeret må inneholde minst 8 sifre.'); render(); return; }
        if (opts.skipConsent) {
          if (!state.journalConsent) {
            state.error = t('booking.errors.consent_journal_admin_required', 'Du må bekrefte at pasienten har samtykket muntlig til journalføring.');
            render(); return;
          }
        } else if (!state.termsAccepted) {
          state.error = t('booking.errors.terms_required', 'Du må godta avbestillingsvilkårene for å fullføre bestillingen.');
          render(); return;
        }

        var submitBtn = form.querySelector('.tabf-btn-primary');
        submitBtn.disabled = true;
        submitBtn.classList.add('is-loading'); // spinner via CSS ::before
        submitBtn.textContent = t('booking.step5.submitting', 'Sender…');
        var createFn = (typeof opts.createBooking === 'function') ? opts.createBooking : E.createBooking;
        createFn({
          staffId: state.staffId, serviceId: state.serviceId,
          date: state.date, time: state.time,
          name: state.name, email: state.email, phone: state.phone, notes: state.notes,
          journalConsent: true,
          journalConsentAt: new Date().toISOString(),
          newsletterOptIn: !!state.newsletterOptIn
        }).then(function (result) {
          if (!result.ok) {
            // slot_taken (23505) og no_capacity (23514): tiden/kapasiteten
            // forsvant under oss → flash + tilbake til tid-velgeren, som
            // henter ferske slots på nytt.
            if (result.reason === 'slot_taken' || result.reason === 'no_capacity') {
              state.flash = result.message;
              state.time = null;
              goTo(4);
              return;
            }
            state.error = result.error; render(); return;
          }
          state.booking = result.booking;
          if (typeof opts.onComplete === 'function') {
            opts.onComplete(result.booking);
            return;
          }
          goTo(6);
        }).catch(function (err) {
          state.error = t('booking.errors.submit_failed', 'Kunne ikke fullføre bestillingen. Prøv igjen.');
          console.error(err);
          render();
        });
      });

      wrap.appendChild(form);
      return wrap;
    }

    function field(name, label, type, value, required, maxlength) {
      var id = 'tabf-' + name;
      var row = el('div', { class: 'tabf-field' });
      row.appendChild(el('label', { for: id }, label + (required ? ' *' : '')));
      var input;
      if (type === 'textarea') {
        var taAttrs = { id: id, name: name, rows: '3' };
        if (maxlength) taAttrs.maxlength = String(maxlength);
        input = el('textarea', taAttrs);
        input.value = value || '';
      } else {
        input = el('input', { id: id, name: name, type: type, autocomplete: name === 'name' ? 'name' : name });
        if (required) input.required = true;
        input.value = value || '';
      }
      row.appendChild(input);
      // Tegnteller for textarea med maxlength (4a Markus-feedback 2026-05-30).
      // Defense-in-depth mot ekstremt store payloads — UI-grense + maxlength-attr.
      if (type === 'textarea' && maxlength) {
        var counter = el('div', { class: 'tabf-field-counter', 'aria-live': 'polite' });
        function updateCounter() {
          counter.textContent = input.value.length + ' / ' + maxlength + ' ' + t('booking.step5.chars_suffix', 'tegn');
        }
        input.addEventListener('input', updateCounter);
        updateCounter();
        row.appendChild(counter);
      }
      return row;
    }

    // ---------- Step 6: Confirmed ----------
    function renderConfirmStep() {
      var b = state.booking;
      var wrap = el('div', { class: 'tabf-step-wrap tabf-confirm' });
      wrap.appendChild(el('div', { class: 'tabf-confirm-icon' }, [
        svgCheckmark()
      ]));
      wrap.appendChild(el('h3', { class: 'tabf-h tabf-confirm-h' }, t('booking.confirm.heading', 'Timen er bekreftet')));
      wrap.appendChild(el('p', { class: 'tabf-sub' },
        t('booking.confirm.intro_pre', 'Timen er registrert på') + ' ' + b.email +
        t('booking.confirm.intro_post', '. Ta vare på referansekoden under.')));

      // Teksten sa foer «Vi har sendt en bekreftelse til <e-post>».
      // Demoen sender ingen e-post: Edge-funksjonene er ikke deployet,
      // og uten dem skjer det ingenting. Et lofte som ikke holdes er
      // verre enn ingen e-post, saa her staar det hva som faktisk
      // skjedde, og hva som ville skjedd i drift.
      wrap.appendChild(el('p', { class: 'tabf-confirm-note' },
        t('booking.confirm.demo_no_mail',
          'Demoen sender ikke e-post. I drift ville en bekreftelse med ' +
          'avbestillingslenke kommet i innboksen nå.')));

      var sum = el('dl', { class: 'tabf-confirm-sum' }, [
        el('div', null, [el('dt', null, t('booking.confirm.sum_ref', 'Referanse')), el('dd', null, b.ref)]),
        el('div', null, [el('dt', null, t('booking.confirm.sum_behandler', 'Behandler')), el('dd', null, b.staffName)]),
        el('div', null, [el('dt', null, t('booking.confirm.sum_service', 'Tjeneste')), el('dd', null, b.serviceName)]),
        el('div', null, [el('dt', null, t('booking.confirm.sum_when', 'Når')), el('dd', null, E.formatDateLong(b.date) + ' ' + t('booking.confirm.sum_at', 'kl.') + ' ' + b.time)]),
        el('div', null, [el('dt', null, t('booking.confirm.sum_where', 'Hvor')), el('dd', null, t('booking.confirm.sum_where_val', 'Bregneveien 12, 0283 Oslo'))]),
        el('div', null, [el('dt', null, t('booking.confirm.sum_price', 'Pris')), el('dd', null, E.formatPrice(b.price))])
      ]);
      wrap.appendChild(sum);

      var note = el('div', { class: 'tabf-confirm-note' }, [
        el('strong', null, t('booking.confirm.remember_label', 'Husk:') + ' '),
        t('booking.confirm.remember_body', 'Avbestilling senest 24 timer før timen.')
      ]);
      wrap.appendChild(note);

      // Token-basert avbestillings-lenke (0024). Har bookingen en
      // cancel_token (moderne nettleser), vis en stor lenke kunden kan
      // lagre/kopiere — ingen ref + e-post nødvendig. Eldre nettlesere
      // uten token faller tilbake til den ref-baserte beskjeden.
      var cancelBox;
      if (b.cancelToken) {
        cancelBox = el('div', { class: 'tabf-cancel-box' }, [
          el('p', { class: 'tabf-cancel-foot' }, [
            t('booking.confirm.cancel_token_pre', 'Avbestilling gjøres med referansekoden på '),
            el('a', { href: 'avbestill.html' },
               t('booking.confirm.cancel_link', 'avbestillingssiden')),
            t('booking.confirm.cancel_token_mid', ' (senest 24 timer før timen). Din referanse: '),
            el('strong', null, b.ref),
            '.'
          ])
        ]);
      } else {
        cancelBox = el('div', { class: 'tabf-confirm-note' }, [
          el('strong', null, t('booking.confirm.cancel_notoken_label', 'Avbestilling:') + ' '),
          t('booking.confirm.cancel_notoken_pre', 'Lagre referansen '),
          el('strong', null, b.ref),
          t('booking.confirm.cancel_notoken_mid', '. Må du avbestille (senest 24 timer før timen), gå til '),
          el('a', { href: '/avbestill.html' }, t('booking.confirm.cancel_notoken_link', 'avbestill-siden')),
          '.'
        ]);
      }
      wrap.appendChild(cancelBox);

      var actions = el('div', { class: 'tabf-actions tabf-actions-confirm' }, [
        el('a', { class: 'tabf-btn-ghost', href: buildIcsHref(b), download: 'westengenklinikk-' + b.ref + '.ics' }, t('booking.confirm.download_ics', 'Last ned kalender (.ics)')),
        el('a', { class: 'tabf-btn-primary', href: 'index.html' }, t('booking.confirm.to_home', 'Til forsiden'))
      ]);
      wrap.appendChild(actions);
      return wrap;
    }

    function buildIcsHref(b) {
      // Build a minimal .ics
      var d = E.parseYMD(b.date);
      var sh = b.time.split(':')[0], sm = b.time.split(':')[1];
      var start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), +sh, +sm);
      var end = new Date(start.getTime() + b.duration * 60000);
      function fmt(dt) {
        return dt.getFullYear() + pad(dt.getMonth() + 1) + pad(dt.getDate())
          + 'T' + pad(dt.getHours()) + pad(dt.getMinutes()) + '00';
      }
      function pad(n) { return String(n).padStart(2, '0'); }
      var ics = [
        'BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Westengen Klinikk//Booking//NO',
        'BEGIN:VEVENT',
        'UID:' + b.id + '@westengenklinikk.example',
        'DTSTAMP:' + fmt(new Date()),
        'DTSTART:' + fmt(start),
        'DTEND:' + fmt(end),
        'SUMMARY:Westengen Klinikk - ' + b.serviceName + ' med ' + b.staffName,
        'LOCATION:Bregneveien 12\\, 0283 Oslo',
        'DESCRIPTION:Referanse: ' + b.ref + '. Avbestilling senest 24 timer før.',
        'END:VEVENT','END:VCALENDAR'
      ].join('\r\n');
      return 'data:text/calendar;charset=utf-8,' + encodeURIComponent(ics);
    }

    // Kopier avbestillings-lenken til utklippstavla. navigator.clipboard
    // krever sikker kontekst (https/localhost) — faller tilbake til en
    // skjult textarea + execCommand for eldre/usikre kontekster.
    function copyCancelLink(text, btn) {
      function flash() {
        var original = 'Kopier lenke';
        btn.textContent = 'Kopiert ✓';
        btn.classList.add('copied');
        setTimeout(function () {
          btn.textContent = original;
          btn.classList.remove('copied');
        }, 2000);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(flash, function () {
          if (legacyCopy(text)) flash();
        });
      } else if (legacyCopy(text)) {
        flash();
      }
    }
    function legacyCopy(text) {
      try {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        var ok = document.execCommand('copy');
        document.body.removeChild(ta);
        return ok;
      } catch (e) {
        return false; // gi opp stille — lenken er fortsatt synlig + klikkbar
      }
    }

    function resetFlow() {
      state.step = opts.initialStaff ? 2 : 1;
      state.staffId = opts.initialStaff || null;
      state.serviceId = null;
      state.date = null;
      state.time = null;
      state.name = state.email = state.phone = state.notes = '';
      state.journalConsent = false;
      state.termsAccepted = false;
      state.booking = null;
      state.error = null;
      state.flash = null;
      render();
    }

    // Varigheten paa den valgte behandlingen. Tilgjengelighet regnes mot
  // den: en 60-minutters time trenger to ledige halvtimer paa rad.
  function selectedDuration(state) {
    var list = (E.SERVICES && E.SERVICES[state.staffId]) || [];
    var sv = list.find(function (x) { return x.id === state.serviceId; });
    return (sv && sv.duration) || 30;
  }

  function renderBackRow(prevStep) {
      var row = el('div', { class: 'tabf-actions' }, [
        el('button', { type: 'button', class: 'tabf-btn-ghost', on: { click: function () { goTo(prevStep); } } }, t('booking.step5.back', '← Tilbake'))
      ]);
      return row;
    }

    function goTo(n) {
      // Stepping back clears later picks so stale state can't carry forward
      if (n <= 3) state.time = null;
      if (n <= 2) state.date = null;
      state.step = n;
      state.error = null;
      render();
    }

    // Kick off engine-load deretter første render. Hvis ensureLoaded
    // ikke er tilgjengelig (eldre engine eller manglende services.js),
    // rendrer vi umiddelbart med fallback-håndtering for tomme arrays.
    if (typeof E.ensureLoaded === 'function') {
      host.innerHTML = '<div class="tabf-empty" style="padding:40px 18px;">' + t('booking.services_loading', 'Laster tjenester…') + '</div>';
      E.ensureLoaded().then(function () { startRender(); })
                       .catch(function () { startRender(); });
    } else {
      startRender();
    }
    return { reset: resetFlow };
  }

  window.WestengenKlinikkBookingFlow = { mount: mount };
})();
