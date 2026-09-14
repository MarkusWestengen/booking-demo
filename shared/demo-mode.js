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
  // Rollene demoen kan vises i. E-post og passord laa her for, men
  // panelet apner seg av seg selv na, saa de var bade unodvendige og
  // en ting som kunne lekke ut i UI-et ved et uhell. Kontoene som
  // faktisk brukes til innlogging bor i shared/auth.js.
  // Rollene beskrives naar arket bygges, ikke naar fila lastes:
  // spraakfilene kan komme etter oss.
  function roller() {
    return [
      { role: t('demo.role_admin', 'Administrator'),
        note: t('demo.note_admin',
                'Ser alt: alle behandleres kalendere, kunderegister, journal, ' +
                'tjenester, behandlere og loggen over oppslag.') },
      { role: t('demo.role_therapist', 'Terapeut'),
        note: t('demo.note_therapist',
                'Ser sitt eget: egen kalender og egne pasienter. Bytt rolle i ' +
                'toppen av panelet for å se forskjellen.') }
    ];
  }

  var BADGE_TEXT = 'DEMO · fiktive data';

  // ============================================================
  // CSS
  // ============================================================
  var css = [
    /* ---- Typografisk ordmerke (erstatter logo-filen) ---- */
    '.brand-wordmark{display:flex;flex-direction:column;gap:2px;line-height:1;}',
    '.brand-wordmark strong{font-family:Fraunces,Georgia,serif;font-weight:500;',
      'font-size:24px;letter-spacing:-0.015em;color:#ebf2fa;}',
    '.brand-wordmark>span{font-family:"JetBrains Mono",ui-monospace,monospace;',
      'font-size:9px;letter-spacing:0.3em;text-transform:uppercase;color:#8fc1e0;}',
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
      'padding:5px 10px;border:1px solid #8fc1e0;color:#B9BDDC;',
      'background:rgba(6,71,137,.18);cursor:pointer;flex:0 0 auto;}',
    '.wk-demo-badge:hover{background:rgba(6,71,137,.34);color:#ebf2fa;}',
    '.wk-demo-badge:focus-visible{outline:2px solid #8fc1e0;outline-offset:2px;}',
    '.wk-demo-badge::before{content:"";width:6px;height:6px;border-radius:50%;',
      'background:#8fc1e0;flex:0 0 auto;}',
    /* På lyse flater (sider uten mørk header) snus kontrasten. */
    '.wk-demo-badge.on-light{border-color:#064789;color:#04315b;background:#cfe0f0;}',
    '.wk-demo-badge.on-light:hover{background:#DADDEF;}',
    /* I seksjonslinja er merket underordnet seksjonsnavnet: ingen ramme
       og ingen flate, bare dempet tekst med prikken foran. Trefflata er
       fortsatt 44 px hoey; den utvides usynlig rundt teksten. */
    '.wk-section-bar .wk-demo-badge.on-light{position:relative;border:0;background:transparent;',
      'padding:0;color:#4a5c6f;font-size:10px;letter-spacing:.1em;flex:0 0 auto;}',
    '.wk-section-bar .wk-demo-badge.on-light::before{background:#427aa1;}',
    '.wk-section-bar .wk-demo-badge.on-light::after{content:"";position:absolute;',
      'left:-8px;right:-8px;top:50%;height:44px;transform:translateY(-50%);}',
    '.wk-section-bar .wk-demo-badge.on-light:hover{background:transparent;color:#064789;}',
    /* Reservefeste når siden ikke har header å henge seg på. */
    '.wk-demo-badge.floating{position:fixed;left:12px;bottom:12px;z-index:9998;}',
    '@media (max-width:560px){.wk-demo-badge{font-size:9px;padding:4px 8px;letter-spacing:.08em;}}',

    /* ---- Dialogen bak pillen ---- */
    '.wk-demo-sheet{position:fixed;inset:0;z-index:10050;display:none;',
      'align-items:center;justify-content:center;padding:20px;',
      'background:rgba(11,26,43,.72);}',
    '.wk-demo-sheet[data-open]{display:flex;}',
    '.wk-demo-card{background:#ebf2fa;color:#0b1a2b;max-width:520px;width:100%;',
      'max-height:86vh;overflow:auto;padding:28px;border-top:3px solid #064789;',
      'font-family:Inter,system-ui,sans-serif;font-size:14px;line-height:1.6;}',
    '.wk-demo-card h2{font-family:Fraunces,Georgia,serif;font-weight:400;',
      'font-size:26px;margin:0 0 4px;}',
    '.wk-demo-card .wk-eyebrow{font-family:"JetBrains Mono",ui-monospace,monospace;',
      'font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:#064789;',
      'margin:0 0 12px;}',
    '.wk-demo-card p{margin:0 0 12px;color:#26384b;}',
    '.wk-demo-card h3{font-size:12px;letter-spacing:.1em;text-transform:uppercase;',
      'color:#4a5c6f;margin:22px 0 10px;font-weight:600;}',
    '.wk-cred{border:1px solid rgba(11,26,43,.16);padding:12px 14px;margin-bottom:10px;',
      'background:#fff;}',
    '.wk-cred b{display:block;font-size:13px;margin-bottom:6px;}',
    '.wk-cred code{font-family:"JetBrains Mono",ui-monospace,monospace;font-size:12.5px;',
      'background:#cfe0f0;padding:2px 6px;user-select:all;}',
    '.wk-cred .wk-note{display:block;margin-top:8px;font-size:12.5px;color:#4a5c6f;}',
    '.wk-demo-actions{display:flex;gap:10px;margin-top:22px;flex-wrap:wrap;}',
    '.wk-demo-actions a,.wk-demo-actions button{font:inherit;font-size:14px;',
      'padding:10px 16px;cursor:pointer;text-decoration:none;border:1px solid rgba(11,26,43,.16);',
      'background:transparent;color:#0b1a2b;}',
    '.wk-demo-actions .wk-primary{background:#064789;color:#fff;border-color:#064789;}',
    '.wk-demo-actions .wk-primary:hover{background:#04315b;}',

    /* ---- Toast for avvist skriving ---- */
    '.wk-demo-toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);',
      'z-index:10060;max-width:min(560px,calc(100vw - 32px));background:#0b1a2b;',
      'color:#ebf2fa;padding:14px 16px;font-family:Inter,system-ui,sans-serif;',
      'font-size:13.5px;line-height:1.5;border-left:3px solid #8fc1e0;',
      'box-shadow:0 10px 30px rgba(11,26,43,.28);display:flex;gap:12px;align-items:flex-start;}',
    '.wk-demo-toast b{display:block;font-size:11px;letter-spacing:.12em;',
      'text-transform:uppercase;color:#8fc1e0;margin-bottom:4px;',
      'font-family:"JetBrains Mono",ui-monospace,monospace;font-weight:500;}',
    '.wk-demo-toast button{background:none;border:0;color:#8fc1e0;font:inherit;',
      'font-size:18px;line-height:1;cursor:pointer;padding:0 2px;margin-left:auto;}',
    '@media (max-width:560px){.wk-demo-toast{bottom:76px;}}',

    /* ---- Seksjonslinje under topbaren i adminpanelet ---- */
    /* Topbaren er sticky paa ti av elleve adminsider, men med ulik
       z-index og ulik hoyde. I stedet for aa maale den og gjette et
       top-tall til seksjonslinja, legges begge inn i en felles
       sticky wrapper. Da folger de hverandre av seg selv, uansett
       hva den enkelte siden gjor med topbaren sin. */
    /* To grupper, ingen loese elementer:
         venstre  seksjonen (det viktigste) med demo-merket underordnet
         hoyre    verktoyene: rolle, spraak, veien til nettsiden
       Én rad paa bred skjerm, midtstilt paa samme linje. Paa telefon
       alltid to rader, i samme rekkefoelge, med samme luft: seksjonen
       oeverst, verktoyene under. Ingen flex-wrap som bestemmer selv. */
    '.wk-admin-head{position:sticky;top:0;z-index:50;}',
    '.wk-section-bar{background:#fff;border-bottom:1px solid #cfe0f0;',
      'font-family:Inter,system-ui,sans-serif;}',
    '.wk-section-bar .wk-inner{margin:0 auto;padding-top:8px;padding-bottom:8px;',
      'min-height:52px;box-sizing:border-box;display:flex;align-items:center;',
      'justify-content:space-between;gap:8px 24px;}',
    '.wk-section-bar .wk-head{display:flex;align-items:baseline;gap:6px 12px;min-width:0;}',
    '.wk-section-bar .wk-crumb{font-size:13px;color:#4a5c6f;white-space:nowrap;}',
    '.wk-section-bar .wk-crumb a{color:inherit;text-decoration:none;}',
    '.wk-section-bar .wk-crumb a:hover{color:#064789;text-decoration:underline;',
      'text-underline-offset:3px;}',
    '.wk-section-bar .wk-crumb span{margin-left:6px;color:#8a99a8;}',
    '.wk-section-bar .wk-where{margin:0;font-size:16px;line-height:1.25;font-weight:600;',
      'letter-spacing:-0.01em;color:#0b1a2b;white-space:nowrap;overflow:hidden;',
      'text-overflow:ellipsis;min-width:0;}',
    '.wk-section-bar .wk-tools{display:flex;align-items:center;gap:12px;flex:0 0 auto;}',
    '.wk-section-bar .wk-to-site{display:inline-flex;align-items:center;min-height:32px;',
      'font-size:13px;color:#064789;text-decoration:underline;text-underline-offset:3px;',
      'text-decoration-thickness:1px;white-space:nowrap;}',
    '.wk-section-bar .wk-to-site:hover{color:#427aa1;}',
    '.wk-section-bar .wk-to-site:focus-visible{outline:2px solid #064789;',
      'outline-offset:3px;}',
    /* Spraakvelgeren i verktoygruppa: samme komponent som paa
       kundesidene (shared/i18n.css er ikke lastet her), lys variant. */
    '.wk-section-bar .tas-lang{position:relative;display:inline-block;}',
    '.wk-section-bar .tas-lang .lang-btn{display:inline-flex;align-items:center;gap:8px;',
      'min-height:32px;padding:0 10px;background:#fff;border:1px solid #cfe0f0;',
      'font:500 12.5px Inter,system-ui,sans-serif;color:#064789;cursor:pointer;}',
    '.wk-section-bar .tas-lang .lang-btn:hover{border-color:#427aa1;}',
    '.wk-section-bar .tas-lang .lang-btn:focus-visible{outline:2px solid #064789;outline-offset:2px;}',
    '.wk-section-bar .tas-lang .chev{width:7px;height:7px;border-right:1.5px solid currentColor;',
      'border-bottom:1.5px solid currentColor;transform:rotate(45deg) translateY(-2px);}',
    '.wk-section-bar .tas-lang .lang-menu{position:absolute;top:calc(100% + 6px);right:0;',
      'min-width:168px;padding:4px 0;background:#fff;border:1px solid #cfe0f0;',
      'box-shadow:0 12px 32px -12px rgba(11,26,43,.28);z-index:1000;display:none;}',
    '.wk-section-bar .tas-lang.open .lang-menu{display:block;}',
    '.wk-section-bar .tas-lang .lang-menu button{display:flex;align-items:center;',
      'justify-content:space-between;width:100%;min-height:44px;padding:10px 16px;',
      'background:transparent;border:0;font:500 14px Inter,system-ui,sans-serif;',
      'color:#0b1a2b;text-align:left;cursor:pointer;}',
    '.wk-section-bar .tas-lang .lang-menu button+button{border-top:1px solid #cfe0f0;}',
    '.wk-section-bar .tas-lang .lang-menu button:hover{background:#ebf2fa;}',
    '.wk-section-bar .tas-lang .lang-menu button.active{color:#064789;font-weight:600;}',
    '.wk-section-bar .tas-lang .lang-menu button.active::after{content:"";width:10px;height:5px;',
      'border-left:2px solid currentColor;border-bottom:2px solid currentColor;',
      'transform:translateY(-2px) rotate(-45deg);}',
    /* To rader naar én ikke rommer alt (maales i mountSectionBar, ikke
       gjettet med et tall: engelsk og norsk er ulikt lange, og hver side
       har sin egen innholdsbredde). Samme oppsett som paa telefon. */
    '.wk-section-bar.wk-stablet .wk-inner{flex-direction:column;align-items:stretch;',
      'padding-top:10px;padding-bottom:10px;gap:8px;}',
    '.wk-section-bar.wk-stablet .wk-head .wk-demo-badge{margin-left:auto;}',
    '.wk-section-bar.wk-stablet .wk-tools{justify-content:flex-start;}',
    '.wk-section-bar.wk-stablet .wk-to-site{margin-left:auto;}',
    '@media (max-width:640px){',
      '.wk-section-bar .wk-inner{flex-direction:column;align-items:stretch;',
        'padding-top:10px;padding-bottom:10px;gap:8px;}',
      '.wk-section-bar .wk-head .wk-demo-badge{margin-left:auto;}',
      /* Paa telefon staar forelderen i menyen og i bunnlinja allerede. */
      '.wk-section-bar .wk-crumb{display:none;}',
      '.wk-section-bar .wk-tools{justify-content:space-between;}',
      '.wk-section-bar .wk-to-site{min-height:44px;margin-left:0;}',
      /* Spraaket ligger i menyen paa telefon, se shared/admin-nav.js. */
      '.wk-section-bar .wk-tools .tas-lang{display:none;}',
    '}',
    /* Under 400 px faar seksjonsnavnet plassen: merket sier bare «Demo».
       Hele teksten staar i title og i dialogen bak merket. */
    '@media (max-width:400px){.wk-section-bar .wk-badge-mer{display:none;}}',

    /* ---- Låsemerke på seed-rader i admin ---- */
    '.wk-seed-lock{display:inline-flex;align-items:center;gap:4px;',
      'font-family:"JetBrains Mono",ui-monospace,monospace;font-size:9px;',
      'letter-spacing:.1em;text-transform:uppercase;color:#064789;',
      'background:#cfe0f0;padding:2px 6px;margin-left:6px;vertical-align:middle;}'
  ].join('');

  var style = doc.createElement('style');
  style.setAttribute('data-wk-demo', '');
  style.textContent = css;
  doc.head.appendChild(style);

  // ============================================================
  // Dialog
  // ============================================================
  var sheet = null;

  // i18n-oppslag med fallback, slik resten av shared/ gjor det.
  function t(key, fallback) {
    var I = root.WestengenKlinikkI18n;
    return (I && typeof I.t === 'function') ? I.t(key, fallback) : fallback;
  }

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
    sheet.setAttribute('aria-label', t('demo.sheet_label', 'Om denne demoen'));

    // Innlogging vises ikke lenger. Panelet aapner seg av seg selv,
    // saa e-post og passord er noe brukeren aldri trenger aa se.
    // Rollene beskrives i stedet, siden det er forskjellen mellom dem
    // som er verdt aa legge merke til.
    //
    // Teksten laa foer hardkodet paa norsk. Pillen staar ogsaa paa de
    // kundevendte sidene, som finnes paa to spraak, saa en engelsk
    // leser fikk en norsk dialog. Alt gaar naa gjennom i18n; paa
    // ansattsidene, som er norske og ikke laster i18n, er det
    // fallback-teksten som vises, og den er norsk.
    var creds = roller().map(function (c) {
      return '<div class="wk-cred"><b>' + esc(c.role) + '</b>' +
        '<span class="wk-note">' + esc(c.note) + '</span></div>';
    }).join('');

    sheet.innerHTML =
      '<div class="wk-demo-card">' +
        '<p class="wk-eyebrow">' + esc(t('demo.eyebrow', 'Demonstrasjonsversjon')) + '</p>' +
        '<h2>' + esc(t('demo.heading', 'Westengen Klinikk finnes ikke')) + '</h2>' +
        '<p>' + esc(t('demo.body1',
          'Dette er en arbeidsprøve: et komplett booking- og administrasjonssystem ' +
          'for en klinikk. Klinikken er oppdiktet. Behandlere, kunder, bestillinger, ' +
          'meldinger og journalnotater er laget for demonstrasjonen, og ingen av ' +
          'dem gjelder et virkelig menneske.')) + '</p>' +
        '<p>' + esc(t('demo.body2',
          'Adresse, telefonnummer og e-postadresse er plassholdere. Ingen av dem ' +
          'er i bruk, og e-postdomenet kan ikke registreres.')) + '</p>' +
        '<h3>' + esc(t('demo.roles_heading', 'To roller')) + '</h3>' +
        creds +
        '<p style="font-size:12.5px;color:#4a5c6f;">' + esc(t('demo.own_rows',
          'Du kan opprette, endre og slette dine egne rader fritt. Radene som ' +
          'følger med demoen står igjen som de er, slik at panelet ser likt ut ' +
          'for neste besøkende.')) + '</p>' +
        '<div class="wk-demo-actions">' +
          '<a class="wk-primary" href="kalender.html">' +
            esc(t('demo.cta_open', 'Åpne adminpanelet →')) + '</a>' +
          '<button type="button" data-wk-close>' +
            esc(t('demo.close', 'Lukk')) + '</button>' +
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
    // To deler, så « · fiktive data» kan vike i seksjonslinja på smal
    // skjerm. Teksten er den samme som før.
    var del1 = doc.createElement('span');
    del1.textContent = 'DEMO';
    var del2 = doc.createElement('span');
    del2.className = 'wk-badge-mer';
    del2.textContent = '· fiktive data';
    badge.appendChild(del1);
    badge.appendChild(del2);
    badge.setAttribute('aria-label', BADGE_TEXT);
    badge.title = t('demo.badge_title',
      'Demonstrasjonsversjon med fiktive data. Klikk for detaljer.');
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
    // Adminpanelet: i seksjonslinja, rett etter seksjonsnavnet.
    // Pillen laa foer inne i .brand, som har overflow:hidden og
    // text-overflow:ellipsis for aa kunne korte ned et langt
    // merkenavn. Pillen ble derfor klippet bort av den regelen og
    // var i praksis usynlig i hele panelet.
    var head = doc.querySelector('.wk-section-bar .wk-head');
    if (head) {
      badge.classList.add('on-light');
      head.appendChild(badge);
      return;
    }

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
  // Seksjonslinje i adminpanelet
  // ------------------------------------------------------------
  // Her sto det tidligere en notis om at radene fra demo-oppsettet
  // er skrivebeskyttet. Den forklaringen trengs ikke lenger: en
  // avvist lagring hoeres naa som en rolig setning i oyeblikket den
  // skjer, ikke som en regel du maa lese paa forhaand.
  //
  // Plassen er bedre brukt paa tre ting panelet manglet:
  //   venstre  hvilken seksjon du staar i
  //   hoyre    hvilken rolle du ser panelet med (fylles av auth.js)
  //   hoyre    veien tilbake til den offentlige siden
  //
  // Linja ligger i normal flyt rett under topbaren, ikke fixed. Da
  // kan ingenting i den legge seg oppaa noe annet, uansett bredde.
  // ============================================================
  // Fil -> [i18n-nokkel, norsk tekst, forelder]. Navnet er det samme som
  // menypunktet siden hører til, slik at seksjonslinja, den grønne
  // bunnlinja og det markerte punktet i menyen sier det samme. Sider
  // som ikke er et eget menypunkt (kundekortet, stengte tider, loggen)
  // har en forelder: menypunktet man kommer dit fra.
  var SECTIONS = {
    'kalender.html':      ['admin.section.kalender',      'Kalender'],
    'booking-admin.html': ['admin.section.oversikt',      'Oversikt'],
    'kunder.html':        ['admin.section.kunder',        'Kunder'],
    'kunde-detalj.html':  ['admin.section.kunde',         'Kundekort',         'kunder.html'],
    'tjenester.html':     ['admin.section.tjenester',     'Tjenester'],
    'behandlere.html':    ['admin.section.behandlere',    'Behandlere'],
    'meldinger.html':     ['admin.section.meldinger',     'Meldinger'],
    'dokumenter.html':    ['admin.section.dokumenter',    'Dokumenter'],
    'stengte-tider.html': ['admin.section.stengte',       'Stengte tider',     'innstillinger.html'],
    'audit-logg.html':    ['admin.section.audit',         'Logg over oppslag', 'innstillinger.html'],
    'innstillinger.html': ['admin.section.innstillinger', 'Innstillinger']
  };

  function denneSiden() {
    return (root.location.pathname.split('/').pop() || '').toLowerCase();
  }

  // Leses av shared/admin-nav.js, som markerer riktig menypunkt og
  // setter samme navn i bunnlinja.
  function seksjon(fil) {
    fil = fil || denneSiden();
    var sec = SECTIONS[fil];
    if (!sec) return null;
    var forelder = sec[2] ? SECTIONS[sec[2]] : null;
    return {
      fil: fil,
      navn: t(sec[0], sec[1]),
      noekkel: sec[0],
      menypunkt: sec[2] || fil,
      forelder: forelder ? { fil: sec[2], navn: t(forelder[0], forelder[1]), noekkel: forelder[0] } : null
    };
  }

  function lagSpraakvelger() {
    var I = root.WestengenKlinikkI18n;
    if (!I) return null;
    var navn = { no: 'Norsk', en: 'English' };
    var lang = I.getLanguage();
    var w = doc.createElement('div');
    // data-last-paa-nytt: adminsidene bygger datoer og tabeller ved
    // lasting, saa et spraakbytte laster siden paa nytt (i18n.js).
    w.className = 'lang tas-lang';
    w.setAttribute('data-last-paa-nytt', '');
    w.innerHTML =
      '<button class="lang-btn" type="button" aria-haspopup="true" aria-expanded="false">' +
        '<span data-current-lang>' + navn[lang] + '</span><span class="chev" aria-hidden="true"></span>' +
      '</button>' +
      '<div class="lang-menu">' +
        '<button type="button" data-lang="no" lang="no">Norsk</button>' +
        '<button type="button" data-lang="en" lang="en">English</button>' +
      '</div>';
    return w;
  }

  function mountSectionBar() {
    var topbar = doc.querySelector('.topbar');
    if (!topbar || doc.querySelector('.wk-section-bar')) return;

    var sec = seksjon();
    if (!sec) return;   // ikke en av adminsidene

    var bar = doc.createElement('div');
    bar.className = 'wk-section-bar';

    var inner = doc.createElement('div');
    inner.className = 'wk-inner';

    var head = doc.createElement('div');
    head.className = 'wk-head';

    if (sec.forelder) {
      var crumb = doc.createElement('span');
      crumb.className = 'wk-crumb';
      var up = doc.createElement('a');
      up.href = sec.forelder.fil;
      up.setAttribute('data-i18n', sec.forelder.noekkel);
      up.textContent = sec.forelder.navn;
      var sep = doc.createElement('span');
      sep.setAttribute('aria-hidden', 'true');
      sep.textContent = '›';
      crumb.appendChild(up);
      crumb.appendChild(sep);
      head.appendChild(crumb);
    }

    var where = doc.createElement('p');
    where.className = 'wk-where';
    where.setAttribute('data-i18n', sec.noekkel);
    where.textContent = sec.navn;
    head.appendChild(where);
    inner.appendChild(head);

    var right = doc.createElement('div');
    right.className = 'wk-tools';
    right.setAttribute('role', 'group');
    right.setAttribute('aria-label', t('admin.tools', 'Verktøy'));

    // Rollevelgeren monteres hit av shared/auth.js, saa snart rollen
    // er kjent. Slotten staar tom inntil da.
    var slot = doc.createElement('div');
    slot.id = 'wkRoleSlot';
    slot.style.display = 'flex';
    right.appendChild(slot);

    var spraak = lagSpraakvelger();
    if (spraak) right.appendChild(spraak);

    var back = doc.createElement('a');
    back.className = 'wk-to-site';
    back.href = 'index.html';
    back.setAttribute('data-i18n', 'admin.to_site');
    back.textContent = t('admin.to_site', 'Til nettsiden');
    right.appendChild(back);

    inner.appendChild(right);
    bar.appendChild(inner);

    // Hver adminside har sin egen innholdsbredde: 720 px paa
    // kalenderen, 1100 paa kunder, 1300 paa meldinger. Linja maa
    // stille seg paa samme kant som innholdet, ellers henger den i
    // loese lufta. I stedet for aa liste bredder per side leser vi
    // den av topbarens egen container, og speiler den.
    function mirrorWidth() {
      var probe = topbar.firstElementChild;
      if (!probe) return;
      var pc = root.getComputedStyle(probe);
      var tc = root.getComputedStyle(topbar);
      if (pc.maxWidth && pc.maxWidth !== 'none') inner.style.maxWidth = pc.maxWidth;
      var l = parseFloat(tc.paddingLeft) + parseFloat(pc.paddingLeft);
      var r = parseFloat(tc.paddingRight) + parseFloat(pc.paddingRight);
      if (l === l) inner.style.paddingLeft = l + 'px';
      if (r === r) inner.style.paddingRight = r + 'px';
    }

    var wrap = doc.createElement('div');
    wrap.className = 'wk-admin-head';
    topbar.parentNode.insertBefore(wrap, topbar);
    wrap.appendChild(topbar);
    wrap.appendChild(bar);
    if (root.WestengenKlinikkI18n) root.WestengenKlinikkI18n.translate(bar);

    // Én rad eller to: prøv én, og gå over til to hvis seksjonsnavnet
    // må kortes ned eller verktøyene ikke får plass. Måles på nytt når
    // vinduet endres og når rollevelgeren kommer inn (den monteres
    // først når innloggingen er klar).
    function vurderRader() {
      bar.classList.remove('wk-stablet');
      if (root.matchMedia('(max-width:640px)').matches) return;
      var trang = where.scrollWidth > where.clientWidth + 1 ||
                  inner.scrollWidth > inner.clientWidth + 1 ||
                  head.getBoundingClientRect().right > right.getBoundingClientRect().left;
      if (trang) bar.classList.add('wk-stablet');
    }

    // Paddingen kan endre seg paa et breakpoint, saa den maales om
    // naar vinduet endrer stoerrelse.
    mirrorWidth();
    vurderRader();
    root.addEventListener('resize', function () { mirrorWidth(); vurderRader(); });
    if (root.ResizeObserver) new root.ResizeObserver(vurderRader).observe(right);
    if (root.MutationObserver) new root.MutationObserver(vurderRader).observe(inner, { childList: true, subtree: true, characterData: true });
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
  // Migrasjon 0066 avviser endring og sletting av seed-rader med
  // SQLSTATE PT403 og meldingen «demo_readonly». PostgREST gjor det
  // om til HTTP 403.
  //
  // FOR: avvisningen naadde kallstedet, som viste en nettleser-alert
  // med teksten «Kunne ikke oppdatere status: demo_readonly». Det er
  // bade en popup og en teknisk streng, og knappen sa ut som den var
  // odelagt.
  //
  // NA: avvisningen fanges her og gjores om til et vellykket svar,
  // slik at kallstedet gaar rett i suksess-grenen og oppdaterer
  // skjermen som normalt. Endringen huskes for okten og legges oppa
  // senere GET-svar, slik at sider som henter data paa nytt ikke
  // ruller den tilbake. En sletting far raden til aa forsvinne.
  //
  // Ingenting lagres i databasen. Det er hele poenget, og det staar
  // i et lavmaelt hint i stedet for en feilmelding.
  // ============================================================
  var DEMO_MARKER = 'demo_readonly';
  var nativeFetch = root.fetch && root.fetch.bind(root);

  // Overstyringer per tabell, kun i minnet, kun for denne okten.
  //   patches: [{ col, val, patch }]  — felter satt lokalt
  //   drops:   [{ col, val }]         — rader skjult lokalt
  var overrides = {};

  function parseRest(url) {
    var m = /\/rest\/v1\/([A-Za-z0-9_]+)(\?|$)/.exec(String(url));
    if (!m) return null;
    var table = m[1];
    var q = String(url).split('?')[1] || '';
    // Vi stotter likhetsfilter, som er det adminpanelet bruker for
    // aa treffe én rad: ?id=eq.<verdi>
    var f = /(?:^|&)([A-Za-z0-9_]+)=eq\.([^&]*)/.exec(q);
    if (!f) return { table: table, col: null, val: null };
    return { table: table, col: f[1], val: decodeURIComponent(f[2]) };
  }

  function remember(info, method, body) {
    if (!info || !info.col) return;
    var o = overrides[info.table] || (overrides[info.table] = { patches: [], drops: [] });
    if (method === 'DELETE') {
      o.drops.push({ col: info.col, val: info.val });
      return;
    }
    var patch = null;
    try { patch = JSON.parse(body); } catch (_) { return; }
    if (!patch || typeof patch !== 'object') return;
    o.patches.push({ col: info.col, val: info.val, patch: patch });
  }

  function sameVal(a, b) { return String(a) === String(b); }

  function applyOverrides(table, rows) {
    var o = overrides[table];
    if (!o || !Array.isArray(rows)) return rows;
    var out = rows.filter(function (r) {
      return !o.drops.some(function (d) { return sameVal(r[d.col], d.val); });
    });
    out.forEach(function (r) {
      o.patches.forEach(function (p) {
        if (sameVal(r[p.col], p.val)) {
          for (var k in p.patch) {
            if (Object.prototype.hasOwnProperty.call(p.patch, k)) r[k] = p.patch[k];
          }
        }
      });
    });
    return out;
  }

  function hasOverrides(table) {
    var o = overrides[table];
    return !!(o && (o.patches.length || o.drops.length));
  }

  // Svar som faar kallstedet til aa tro at lagringen gikk bra.
  //
  // Ba kallet om return=representation, maa svaret inneholde raden
  // det gjaldt. En tom liste er ikke godt nok: flere steder leses
  // «tom liste» som «ingen rad ble truffet», og da viser skjermen en
  // feil selv om vi nettopp har sagt at alt gikk fint. Vi ekker
  // derfor tilbake noekkelen fra filteret, pluss feltene som ble satt.
  function okResponse(init, info, method, body) {
    var prefer = '';
    try {
      var h = init && init.headers;
      if (h) {
        prefer = (typeof h.get === 'function')
          ? (h.get('Prefer') || '')
          : (h.Prefer || h.prefer || '');
      }
    } catch (_) {}

    if (String(prefer).indexOf('return=representation') !== -1) {
      var row = {};
      if (info && info.col) row[info.col] = info.val;
      if (method !== 'DELETE') {
        try {
          var patch = JSON.parse(body);
          if (patch && typeof patch === 'object') {
            for (var k in patch) {
              if (Object.prototype.hasOwnProperty.call(patch, k)) row[k] = patch[k];
            }
          }
        } catch (_) {}
      }
      return new Response(JSON.stringify([row]), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    return new Response(null, { status: 204 });
  }

  var hintShown = false;

  if (nativeFetch) {
    root.fetch = function (input, init) {
      var url = (typeof input === 'string') ? input : (input && input.url) || '';
      var method = ((init && init.method) ||
                    (input && input.method) || 'GET').toUpperCase();
      var info = parseRest(url);

      return nativeFetch(input, init).then(function (res) {
        // ----- Les-svar: legg paa det som er endret lokalt --------
        if (res.ok && method === 'GET' && info && hasOverrides(info.table)) {
          return res.clone().json().then(function (rows) {
            var patched = applyOverrides(info.table, rows);
            return new Response(JSON.stringify(patched), {
              status: res.status,
              headers: { 'Content-Type': 'application/json' }
            });
          }).catch(function () { return res; });
        }

        if (res.status !== 403) return res;

        // ----- Skrive-svar som ble avvist av skrivesperren --------
        return res.clone().text().then(function (body) {
          if (body.indexOf(DEMO_MARKER) === -1) return res;

          remember(info, method, (init && init.body) || '');

          // Ett rolig hint per okt. Gjentatt melding om det samme
          // blir mas, og regelen er den samme hver gang.
          if (!hintShown) {
            hintShown = true;
            toast(t('demo.local_only',
                    'Endringen vises bare hos deg. Demoen nullstilles hver natt.'),
                  t('demo.local_only_label', 'Lagres ikke'));
          }
          return okResponse(init, info, method, (init && init.body) || '');
        }).catch(function () { return res; });
      });
    };
  }

  // ============================================================
  // Eksport
  // ============================================================
  root.WestengenKlinikkDemo = {
    seksjon: seksjon,
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

  function mount() { mountSectionBar(); mountBadge(); }

  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', mount);
  } else {
    mount();
  }
})(window, document);
