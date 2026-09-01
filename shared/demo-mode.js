/* ============================================================
   Westengen Klinikk — demo-modus (frontend-laget)
   ------------------------------------------------------------
   Denne filen lastes på HVER side, kundevendt som admin.
   Den gjør fire ting:

     1. Monterer det permanente demo-merket i headeren.
        Pillen «DEMO · fiktive data» ligger rett ved ordmerket,
        i den sticky headeren, altså synlig på hver side og i
        hver scroll-posisjon. Klikk åpner en dialog som sier hva
        demoen er og hvilken innlogging som gjelder.

     2. Leverer det typografiske ordmerket sin CSS. Klinikken har
        ingen logo-fil — navnet SKAL settes i tekst, så det skalerer
        og aldri kommer i utakt med merkenavnet.

     3. Fanger opp skrivesperren fra databasen. Migrasjon 0066
        avviser UPDATE/DELETE mot seed-rader med SQLSTATE PT403 og
        meldingen «demo_readonly». Vi patcher window.fetch slik at
        ALLE kall — Supabase-SDK-en, PostgREST-kallene i
        booking-engine.js, alt — får samme forklarende toast uten
        at et eneste kallsted må endres.

        VIKTIG DESIGNVALG: ingenting skjules og ingenting
        deaktiveres. Knappene virker, dialogene åpnes, skjemaene
        validerer. Det er databasen som sier nei, og toasten
        forteller hva som VILLE skjedd i drift. Demoen skal kunne
        vises fram, ikke bare betraktes.

     4. Eksponerer window.WestengenKlinikkDemo for sider som vil
        merke enkeltrader som seed-beskyttet (seedChip()) eller
        vise samme toast fra egen kode.

   Ingen avhengigheter. Selv-injiserende CSS. Idempotent.
   ============================================================ */
(function (root, doc) {
  'use strict';

  if (root.WestengenKlinikkDemo) return;   // idempotent

  // ----- Publisert innlogging ------------------------------------
  // Opprettet av migrasjon 0065. Bevisst offentlig: uten den kommer
  // ingen inn i adminpanelet, som er halve poenget med demoen.
  var CREDENTIALS = [
    { role: 'Administrator', email: 'admin@westengenklinikk.example',    password: 'demo-admin-2026',
      note: 'Full tilgang: kalender, kunder, journal, tjenester, behandlere, audit-logg.' },
    { role: 'Terapeut',      email: 'terapeut@westengenklinikk.example', password: 'demo-terapeut-2026',
      note: 'Begrenset tilgang: egen kalender og egne pasienter. Viser rolleskillet.' }
  ];

  var BADGE_TEXT = 'DEMO · fiktive data';

  // ============================================================
  // CSS
  // ============================================================
  var css = [
    /* ---- Typografisk ordmerke (erstatter logo-filen) ---- */
    '.brand-wordmark{display:flex;flex-direction:column;gap:2px;line-height:1;}',
    '.brand-wordmark strong{font-family:Fraunces,Georgia,serif;font-weight:500;',
      'font-size:24px;letter-spacing:-0.015em;color:#efe5dc;}',
    '.brand-wordmark>span{font-family:"JetBrains Mono",ui-monospace,monospace;',
      'font-size:9px;letter-spacing:0.3em;text-transform:uppercase;color:#93c2bb;}',
    '@media (max-width:640px){.brand-wordmark strong{font-size:19px;}',
      '.brand-wordmark>span{font-size:8px;letter-spacing:0.22em;}}',

    /* ---- Demo-pillen ---- */
    /* Ordmerket og pillen deler én grid-celle, så headerens
       grid-template-columns ikke trenger å endres per side. */
    '.wk-brand-group{display:flex;align-items:center;gap:12px;min-width:0;}',
    '@media (max-width:900px){.wk-brand-group{gap:8px;}}',
    '.wk-demo-badge{display:inline-flex;align-items:center;gap:6px;',
      'font-family:"JetBrains Mono",ui-monospace,monospace;font-size:10px;',
      'letter-spacing:0.11em;text-transform:uppercase;white-space:nowrap;',
      'padding:5px 10px;border:1px solid #93c2bb;color:#B9BDDC;',
      'background:rgba(31,78,74,.18);cursor:pointer;flex:0 0 auto;}',
    '.wk-demo-badge:hover{background:rgba(31,78,74,.34);color:#efe5dc;}',
    '.wk-demo-badge:focus-visible{outline:2px solid #93c2bb;outline-offset:2px;}',
    '.wk-demo-badge::before{content:"";width:6px;height:6px;border-radius:50%;',
      'background:#93c2bb;flex:0 0 auto;}',
    /* På lyse flater (sider uten mørk header) snus kontrasten. */
    '.wk-demo-badge.on-light{border-color:#1f4e4a;color:#163b37;background:#dce7e4;}',
    '.wk-demo-badge.on-light:hover{background:#DADDEF;}',
    /* Reservefeste når siden ikke har header å henge seg på. */
    '.wk-demo-badge.floating{position:fixed;left:12px;bottom:12px;z-index:9998;}',
    '@media (max-width:560px){.wk-demo-badge{font-size:9px;padding:4px 8px;letter-spacing:.08em;}}',

    /* ---- Dialogen bak pillen ---- */
    '.wk-demo-sheet{position:fixed;inset:0;z-index:10050;display:none;',
      'align-items:center;justify-content:center;padding:20px;',
      'background:rgba(46,35,32,.72);}',
    '.wk-demo-sheet[data-open]{display:flex;}',
    '.wk-demo-card{background:#efe5dc;color:#2e2320;max-width:520px;width:100%;',
      'max-height:86vh;overflow:auto;padding:28px;border-top:3px solid #1f4e4a;',
      'font-family:Inter,system-ui,sans-serif;font-size:14px;line-height:1.6;}',
    '.wk-demo-card h2{font-family:Fraunces,Georgia,serif;font-weight:400;',
      'font-size:26px;margin:0 0 4px;}',
    '.wk-demo-card .wk-eyebrow{font-family:"JetBrains Mono",ui-monospace,monospace;',
      'font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:#1f4e4a;',
      'margin:0 0 12px;}',
    '.wk-demo-card p{margin:0 0 12px;color:#4a3b35;}',
    '.wk-demo-card h3{font-size:12px;letter-spacing:.1em;text-transform:uppercase;',
      'color:#5c4d46;margin:22px 0 10px;font-weight:600;}',
    '.wk-cred{border:1px solid rgba(46,35,32,.16);padding:12px 14px;margin-bottom:10px;',
      'background:#fff;}',
    '.wk-cred b{display:block;font-size:13px;margin-bottom:6px;}',
    '.wk-cred code{font-family:"JetBrains Mono",ui-monospace,monospace;font-size:12.5px;',
      'background:#dce7e4;padding:2px 6px;user-select:all;}',
    '.wk-cred .wk-note{display:block;margin-top:8px;font-size:12.5px;color:#5c4d46;}',
    '.wk-demo-actions{display:flex;gap:10px;margin-top:22px;flex-wrap:wrap;}',
    '.wk-demo-actions a,.wk-demo-actions button{font:inherit;font-size:14px;',
      'padding:10px 16px;cursor:pointer;text-decoration:none;border:1px solid rgba(46,35,32,.16);',
      'background:transparent;color:#2e2320;}',
    '.wk-demo-actions .wk-primary{background:#1f4e4a;color:#fff;border-color:#1f4e4a;}',
    '.wk-demo-actions .wk-primary:hover{background:#163b37;}',

    /* ---- Toast for avvist skriving ---- */
    '.wk-demo-toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);',
      'z-index:10060;max-width:min(560px,calc(100vw - 32px));background:#2e2320;',
      'color:#efe5dc;padding:14px 16px;font-family:Inter,system-ui,sans-serif;',
      'font-size:13.5px;line-height:1.5;border-left:3px solid #93c2bb;',
      'box-shadow:0 10px 30px rgba(46,35,32,.28);display:flex;gap:12px;align-items:flex-start;}',
    '.wk-demo-toast b{display:block;font-size:11px;letter-spacing:.12em;',
      'text-transform:uppercase;color:#93c2bb;margin-bottom:4px;',
      'font-family:"JetBrains Mono",ui-monospace,monospace;font-weight:500;}',
    '.wk-demo-toast button{background:none;border:0;color:#93c2bb;font:inherit;',
      'font-size:18px;line-height:1;cursor:pointer;padding:0 2px;margin-left:auto;}',
    '@media (max-width:560px){.wk-demo-toast{bottom:76px;}}',

    /* ---- Notislinje øverst i adminpanelet ---- */
    '.wk-admin-note{background:#dce7e4;border-bottom:1px solid #C9CDE4;',
      'font-family:Inter,system-ui,sans-serif;font-size:13px;line-height:1.5;',
      'color:#163b37;}',
    '.wk-admin-note .wk-inner{max-width:1280px;margin:0 auto;padding:9px 28px;',
      'display:flex;gap:10px;align-items:baseline;}',
    '.wk-admin-note b{font-family:"JetBrains Mono",ui-monospace,monospace;',
      'font-size:10px;letter-spacing:.12em;text-transform:uppercase;',
      'flex:0 0 auto;color:#1f4e4a;}',
    '@media (max-width:640px){.wk-admin-note .wk-inner{padding:8px 16px;',
      'flex-direction:column;gap:3px;}}',

    /* ---- Låsemerke på seed-rader i admin ---- */
    '.wk-seed-lock{display:inline-flex;align-items:center;gap:4px;',
      'font-family:"JetBrains Mono",ui-monospace,monospace;font-size:9px;',
      'letter-spacing:.1em;text-transform:uppercase;color:#1f4e4a;',
      'background:#dce7e4;padding:2px 6px;margin-left:6px;vertical-align:middle;}'
  ].join('');

  var style = doc.createElement('style');
  style.setAttribute('data-wk-demo', '');
  style.textContent = css;
  doc.head.appendChild(style);

  // ============================================================
  // Dialog
  // ============================================================
  var sheet = null;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function buildSheet() {
    if (sheet) return sheet;
    sheet = doc.createElement('div');
    sheet.className = 'wk-demo-sheet';
    sheet.setAttribute('role', 'dialog');
    sheet.setAttribute('aria-modal', 'true');
    sheet.setAttribute('aria-label', 'Om denne demoen');

    var creds = CREDENTIALS.map(function (c) {
      return '<div class="wk-cred"><b>' + esc(c.role) + '</b>' +
        '<code>' + esc(c.email) + '</code> &nbsp;/&nbsp; <code>' + esc(c.password) + '</code>' +
        '<span class="wk-note">' + esc(c.note) + '</span></div>';
    }).join('');

    sheet.innerHTML =
      '<div class="wk-demo-card">' +
        '<p class="wk-eyebrow">Demonstrasjonsversjon</p>' +
        '<h2>Westengen Klinikk finnes ikke</h2>' +
        '<p>Dette er et arbeidsprøve-oppsett av et komplett booking- og ' +
          'journalsystem. Klinikken er oppdiktet. Alle behandlere, kunder, ' +
          'bestillinger, meldinger og journalnotater er konstruert for ' +
          'demonstrasjonen, og ingen av dem gjelder et virkelig menneske.</p>' +
        '<p>Adresse, telefonnummer og e-postadresse er plassholdere. ' +
          'Ingen av dem er i bruk, og e-postdomenet kan ikke registreres.</p>' +
        '<h3>Logg inn i adminpanelet</h3>' +
        creds +
        '<p style="font-size:12.5px;color:#5c4d46;">Du kan opprette, endre og ' +
          'slette dine egne rader fritt. Radene som fulgte med demoen er ' +
          'skrivebeskyttet, slik at panelet ser likt ut for neste besøkende, ' +
          'du får en forklaring i stedet for en lagring når du prøver.</p>' +
        '<div class="wk-demo-actions">' +
          '<a class="wk-primary" href="' + loginHref() + '">Åpne innloggingen →</a>' +
          '<button type="button" data-wk-close>Lukk</button>' +
        '</div>' +
      '</div>';

    sheet.addEventListener('click', function (e) {
      if (e.target === sheet || e.target.hasAttribute('data-wk-close')) closeSheet();
    });
    doc.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && sheet.hasAttribute('data-open')) closeSheet();
    });
    doc.body.appendChild(sheet);
    return sheet;
  }

  // Innloggingssiden ligger i rota; undermapper må opp et hakk.
  function loginHref() {
    var depth = (location.pathname.replace(/\/[^/]*$/, '/').match(/\//g) || []).length - 1;
    return (depth > 0 ? new Array(depth + 1).join('../') : '') + 'ansatt.html';
  }

  function openSheet() {
    buildSheet().setAttribute('data-open', '');
    doc.body.style.overflow = 'hidden';
    var btn = sheet.querySelector('[data-wk-close]');
    if (btn) setTimeout(function () { btn.focus(); }, 30);
  }
  function closeSheet() {
    if (!sheet) return;
    sheet.removeAttribute('data-open');
    doc.body.style.overflow = '';
  }

  // ============================================================
  // Merket
  // ============================================================
  function mountBadge() {
    if (doc.querySelector('.wk-demo-badge')) return;

    var badge = doc.createElement('button');
    badge.type = 'button';
    badge.className = 'wk-demo-badge';
    badge.textContent = BADGE_TEXT;
    badge.title = 'Demonstrasjonsversjon med fiktive data. Klikk for detaljer.';
    badge.setAttribute('aria-haspopup', 'dialog');
    badge.addEventListener('click', openSheet);

    // Kundevendt header: rett ved ordmerket i den sticky baren.
    // .nav er et grid med faste kolonner — derfor pakkes merket og
    // pillen i én wrapper som overtar ordmerkets celle, i stedet for
    // å legge til et fjerde barn og skyve kolonnene ut av stilling.
    var brand = doc.querySelector('.nav-shell .brand');
    if (brand && brand.parentNode) {
      var group = doc.createElement('span');
      group.className = 'wk-brand-group';
      brand.parentNode.insertBefore(group, brand);
      group.appendChild(brand);
      group.appendChild(badge);
      return;
    }
    // Admin-header: inne i .brand, ved siden av rolle-merket.
    var adminBrand = doc.querySelector('.topbar .brand');
    if (adminBrand) { adminBrand.appendChild(badge); return; }

    // Innloggingssiden og andre kort-skall uten header. Pillen legges
    // øverst i selve kortet, ikke inne i .brand — merkenavnet ligger i
    // en view som er skjult mens sesjonen sjekkes, og pillen skal være
    // synlig fra første frame. Kortsidene er lyse, så kontrasten snus.
    badge.classList.add('on-light');
    var card = doc.querySelector('.shell .card') || doc.querySelector('.card');
    if (card) {
      badge.style.marginBottom = '18px';
      card.insertBefore(badge, card.firstChild);
      return;
    }
    badge.classList.add('floating');
    doc.body.appendChild(badge);
  }

  // ============================================================
  // Notislinje i adminpanelet
  // ------------------------------------------------------------
  // Skrivesperren forklarer seg selv når du treffer den, men det er
  // bedre å vite regelen før du bruker et minutt på et skjema som
  // ikke lagres. Linja legges rett under den mørke topbaren, på alle
  // admin-sidene, og sier én ting: hvilke rader som er låst og
  // hvilke som ikke er det.
  // ============================================================
  function mountAdminNote() {
    var topbar = doc.querySelector('.topbar');
    if (!topbar || doc.querySelector('.wk-admin-note')) return;

    var note = doc.createElement('div');
    note.className = 'wk-admin-note';
    note.setAttribute('role', 'note');
    note.innerHTML =
      '<div class="wk-inner"><b>Demo</b>' +
      '<span>Radene som fulgte med demoen er skrivebeskyttet, knappene ' +
      'virker, men lagringen avvises av databasen med en forklaring. ' +
      'Rader du oppretter selv kan du endre og slette fritt. Alt ' +
      'nullstilles hvert døgn.</span></div>';

    topbar.parentNode.insertBefore(note, topbar.nextSibling);
  }

  // ============================================================
  // Toast
  // ============================================================
  var toastEl = null, toastTimer = null;

  function toast(message, label) {
    if (toastEl && toastEl.parentNode) toastEl.parentNode.removeChild(toastEl);
    if (toastTimer) clearTimeout(toastTimer);

    toastEl = doc.createElement('div');
    toastEl.className = 'wk-demo-toast';
    toastEl.setAttribute('role', 'status');
    toastEl.innerHTML = '<div><b>' + esc(label || 'Demo') + '</b>' +
      esc(message) + '</div>' +
      '<button type="button" aria-label="Lukk">×</button>';
    toastEl.querySelector('button').addEventListener('click', function () {
      if (toastEl && toastEl.parentNode) toastEl.parentNode.removeChild(toastEl);
    });
    doc.body.appendChild(toastEl);
    toastTimer = setTimeout(function () {
      if (toastEl && toastEl.parentNode) toastEl.parentNode.removeChild(toastEl);
    }, 9000);
  }

  // ============================================================
  // Skrivesperre — fetch-patch
  // ------------------------------------------------------------
  // Migrasjon 0066 svarer PT403 + «demo_readonly» på forsøk på å
  // endre eller slette seed-data. PostgREST oversetter PT403 til
  // HTTP 403 og legger meldingen i JSON-feltet `message`.
  // Vi klonr KUN 403-svar, så normal drift er upåvirket.
  // ============================================================
  var DEMO_MARKER = 'demo_readonly';
  var nativeFetch = root.fetch && root.fetch.bind(root);

  if (nativeFetch) {
    root.fetch = function (input, init) {
      return nativeFetch(input, init).then(function (res) {
        if (res.status !== 403) return res;
        // Klon før noen andre leser bodyen.
        res.clone().text().then(function (body) {
          if (body.indexOf(DEMO_MARKER) === -1) return;
          var hint = '';
          try {
            var j = JSON.parse(body);
            hint = j.hint || j.details || j.detail || '';
          } catch (_) {}
          toast(hint || 'Denne raden er en del av demo-oppsettet og lagres ikke. ' +
            'I drift ville endringen blitt lagret og ført i audit-loggen. ' +
            'Rader du oppretter selv, kan du endre og slette fritt.',
            'Demo · ikke lagret');
        }).catch(function () {});
        return res;
      });
    };
  }

  // ============================================================
  // Eksport
  // ============================================================
  root.WestengenKlinikkDemo = {
    CREDENTIALS: CREDENTIALS,
    open: openSheet,
    close: closeSheet,
    toast: toast,
    /** Låsemerke å henge på en rad som kommer fra seed-dataene. */
    seedChip: function (title) {
      var s = doc.createElement('span');
      s.className = 'wk-seed-lock';
      s.textContent = 'demo';
      s.title = title || 'Seed-rad fra demo-oppsettet. Kan leses og vises, men ikke endres.';
      return s;
    },
    /** true hvis en Supabase/PostgREST-feil er demo-skrivesperren. */
    isBlocked: function (err) {
      if (!err) return false;
      var s = JSON.stringify(err.message || err.msg || err) || '';
      return s.indexOf(DEMO_MARKER) !== -1;
    }
  };

  function mount() { mountBadge(); mountAdminNote(); }

  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', mount);
  } else {
    mount();
  }
})(window, document);
