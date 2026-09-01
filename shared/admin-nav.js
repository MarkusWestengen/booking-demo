/* ============================================================
   shared/admin-nav.js — admin bunn-nav på mobil
   ------------------------------------------------------------
   På mobil (≤760px) erstattes hele 8-punkts-stripa (som scrollet
   horisontalt) med ÉN grønn stripe: sidetittel til venstre + en ren
   «Meny»-knapp til høyre. Knappen åpner et gjennomarbeidet popup-ark
   (bunn-sheet) med ALLE destinasjonene som touch-vennlige kort.
   Desktop er uendret. Admin er norsk-only — ingen i18n.

   Rolle-synlighet (data-admin-only) speiles inn i arket når det åpnes,
   så terapeut/admin ser akkurat samme sett som de skal. Idempotent,
   selv-injiserende CSS (ingen ekstra <link>).
   ============================================================ */
(function () {
  'use strict';

  // i18n med norsk fallback. Admin-skallet laster normalt ikke i18n-
  // runtime (admin er norsk-only), men nøklene finnes i alle språkfiler
  // for konsistens med varsling.js — fallback brukes når runtime mangler.
  function t(key, fallback) {
    try {
      if (window.WestengenKlinikkI18n && typeof window.WestengenKlinikkI18n.t === 'function') {
        return window.WestengenKlinikkI18n.t(key, fallback);
      }
    } catch (_) {}
    return fallback;
  }

  function init() {
    var nav = document.querySelector('.bottom-nav');
    if (!nav || nav.getAttribute('data-mer-enhanced')) return;
    nav.setAttribute('data-mer-enhanced', '1');

    var btns = [].slice.call(nav.querySelectorAll('.bn-btn'));
    if (!btns.length) return;

    var activeBtn = nav.querySelector('.bn-btn.active');
    var pageTitle = (activeBtn ? activeBtn.textContent : '').trim() || 'Westengen Klinikk';

    // ---- Injiser CSS ----
    var st = document.createElement('style');
    st.textContent =
      /* DEL 0b — konsistent grønn overskrift-aksent på admin (delt enkeltkilde).
         .adm-accent settes på sideoverskrifter (h1). Seksjonstitler i de vanlige
         kort-/editor-containerne får aksenten automatisk. Tynn grønn understrek
         + litt luft, samme språk som «Aktive blokkeringer». Bruker --green fra
         sidens :root med fallback. (booking-admin .panel-head + kalender .subhead
         er bevisst utelatt — egen visuell sjekk, jf. plan.) */
      /* LANG strek (brukerpreferanse): full bredde av innholdsområdet, ikke kun
         under teksten. display:block → border-bottom spenner tvers over. Farge/
         tykkelse/luft beholdt. */
      '.adm-accent{display:block;padding-bottom:6px;border-bottom:2px solid var(--green,#464C8C);margin-bottom:14px;}' +
      '.card>h2,.upload-card>h2,.editor>h2{padding-bottom:8px;border-bottom:2px solid var(--green,#464C8C);}' +

      /* ===== BØLGE 1 — delt admin-fundament (tokens, knapper, input, fokus, kort).
         ADDITIVT: supplerer sidenes inline :root + komponenter, river ingenting.
         Injisert etter sidens inline-CSS (document.head.appendChild) → vinner på
         lik spesifisitet uten !important. font:inherit unngår quote-escaping i
         CSS-i-JS. 0-radius beholdes som identitet. ===== */
      /* Token-skala (additivt — nye navn, ingen kollisjon med sidens :root). */
      ':root{--sp-1:4px;--sp-2:8px;--sp-3:12px;--sp-4:16px;--sp-5:24px;--sp-6:32px;' +
        '--radius:0;--radius-pill:999px;' +
        '--shadow-sm:0 1px 2px rgba(23, 26, 33,.05);' +
        '--shadow-md:0 4px 14px rgba(23, 26, 33,.08);' +
        '--shadow-lg:0 -14px 36px rgba(23, 26, 33,.18);}' +
      /* Subtil dybde på de flate admin-kortene (additiv hvileskygge). */
      '.card{box-shadow:var(--shadow-sm,0 1px 2px rgba(23, 26, 33,.05));}' +
      /* Konsistent grønn fokus-ring på tvers. Lav (element-)spesifisitet, så
         sider med egne .btn:focus-visible (klasse) beholder sine. */
      'a:focus-visible,button:focus-visible,[tabindex]:focus-visible,[role=button]:focus-visible,[role=link]:focus-visible{outline:2px solid var(--green,#464C8C);outline-offset:2px;}' +
      'input:focus-visible,select:focus-visible,textarea:focus-visible{outline:2px solid var(--green,#464C8C);outline-offset:-1px;}' +
      /* Delt knappe-hierarki (opt-in via .ui-btn*). Primær fylt grønn, sekundær
         rolig kant, stille = lav vekt (Avbryt/Logg ut), fare rød. Bred adopsjon
         på eksisterende knapper hører til bølge 3. */
      '.ui-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;font:inherit;font-size:14px;font-weight:500;line-height:1;cursor:pointer;padding:10px 16px;border:1px solid transparent;border-radius:var(--radius,0);text-decoration:none;transition:background .15s ease,border-color .15s ease,color .15s ease,box-shadow .15s ease;}' +
      '.ui-btn:disabled,.ui-btn[disabled]{opacity:.55;cursor:not-allowed;}' +
      '.ui-btn-primary{background:var(--green,#464C8C);color:#fff;}' +
      '.ui-btn-secondary{background:transparent;color:var(--ink,#171A21);border-color:var(--rule,#171a2622);}' +
      '.ui-btn-quiet{background:transparent;color:var(--muted,#6B7080);border-color:transparent;}' +
      '.ui-btn-danger{background:transparent;color:var(--danger,#c0392b);border-color:var(--danger,#c0392b);}' +
      '@media (hover:hover){' +
        '.ui-btn-primary:hover{background:var(--green-deep,#2F3463);}' +
        '.ui-btn-secondary:hover{border-color:var(--ink,#171A21);}' +
        '.ui-btn-quiet:hover{color:var(--ink,#171A21);background:var(--paper-2,#EDEFF3);}' +
        '.ui-btn-danger:hover{background:var(--danger,#c0392b);color:#fff;}' +
      '}' +
      /* Delt input-stil (opt-in via .ui-input) — lik høyde/padding/kant + grønn fokus. */
      '.ui-input{width:100%;box-sizing:border-box;height:38px;padding:9px 11px;font:inherit;font-size:14px;border:1px solid var(--rule,#171a2622);background:#fff;border-radius:var(--radius,0);}' +
      'textarea.ui-input{height:auto;min-height:64px;resize:vertical;}' +
      /* Delt kort-base (opt-in via .ui-card) — subtil dybde + myk hover, kun på
         pekerenheter (touch får ikke hengende hover). */
      '.ui-card{background:#fff;border:1px solid var(--rule,#171a2622);border-radius:var(--radius,0);box-shadow:var(--shadow-sm,0 1px 2px rgba(23, 26, 33,.05));transition:box-shadow .15s ease,border-color .15s ease,transform .15s ease;}' +
      '@media (hover:hover){.ui-card.is-interactive:hover{box-shadow:var(--shadow-md,0 4px 14px rgba(23, 26, 33,.08));border-color:var(--green-soft,#7A80B8);transform:translateY(-1px);}}' +
      /* Delt tom-tilstand (.ui-empty) — rolig, sentrert, diskret ikon. Brukes på
         «Ingen X ennå»-tilstander (IKKE feil-/tilgang-tilstander). */
      '.ui-empty{display:flex;flex-direction:column;align-items:center;gap:12px;padding:44px 18px;text-align:center;}' +
      '.ui-empty svg{width:32px;height:32px;color:var(--green-soft,#7A80B8);opacity:.85;}' +
      '.ui-empty p{margin:0;font-size:14px;color:var(--ink-2,#2E323C);}' +
      '.ui-empty .hint{font-size:12.5px;color:var(--muted,#6B7080);max-width:34ch;line-height:1.5;}' +
      /* Kompakt variant for tom-tilstand INNE i et kort/en kategori (mindre luft). */
      '.ui-empty.compact{padding:18px 14px;gap:8px;}' +
      '.ui-empty.compact svg{width:24px;height:24px;}' +
      '.ui-empty.compact p{font-size:13px;}' +

      /* Mobil: grønn stripe med kun tittel + meny-knapp */
      '@media (max-width:760px){' +
        '.bottom-nav{display:block !important;background:var(--green,#464C8C) !important;' +
          'border-top:0 !important;overflow:visible !important;' +
          'padding:0 0 env(safe-area-inset-bottom,0px) 0 !important;}' +
        '.bottom-nav .bn-btn{display:none !important;}' +
        '.bn-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;height:54px;padding:0 8px 0 18px;}' +
        '.bn-bar-title{font-family:\'Fraunces\',Georgia,serif;font-weight:500;font-size:17px;letter-spacing:-0.01em;' +
          'color:#fff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0;}' +
        '.bn-menu-btn{display:inline-flex;align-items:center;gap:9px;flex:0 0 auto;cursor:pointer;' +
          'background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.28);color:#fff;' +
          'font-family:\'JetBrains Mono\',monospace;font-size:11px;letter-spacing:0.14em;text-transform:uppercase;' +
          'padding:0 15px;min-height:40px;}' +
        '.bn-menu-btn:hover,.bn-menu-btn:focus-visible{background:rgba(255,255,255,.22);border-color:#fff;outline:none;}' +
        '.bn-menu-btn .bn-menu-ico{display:inline-flex;}' +
      '}' +
      '@media (min-width:761px){.bn-bar,.bn-sheet-ov{display:none !important;}}' +
      /* Popup-ark (bunn-sheet) */
      '.bn-sheet-ov{position:fixed;inset:0;background:rgba(23, 26, 33,.5);z-index:9500;' +
        'opacity:0;visibility:hidden;transition:opacity .2s ease;}' +
      '.bn-sheet-ov.open{opacity:1;visibility:visible;}' +
      '.bn-sheet{position:fixed;left:0;right:0;bottom:0;z-index:9501;background:var(--paper,#F7F8FA);' +
        'border-top:3px solid var(--green,#464C8C);box-shadow:0 -14px 36px rgba(23, 26, 33,.18);' +
        'padding-bottom:calc(14px + env(safe-area-inset-bottom,0px));max-height:86vh;overflow-y:auto;' +
        'transform:translateY(100%);transition:transform .28s cubic-bezier(.22,.61,.36,1);}' +
      '.bn-sheet.open{transform:translateY(0);}' +
      '.bn-sheet-head{display:flex;align-items:center;justify-content:space-between;gap:12px;' +
        'padding:16px 16px 12px;border-bottom:1px solid var(--rule,#171a2622);' +
        'position:sticky;top:0;background:var(--paper,#F7F8FA);z-index:1;}' +
      '.bn-sheet-head h2{font-family:\'Fraunces\',Georgia,serif;font-weight:400;font-size:21px;letter-spacing:-0.01em;margin:0;}' +
      '.bn-sheet-close{display:inline-flex;align-items:center;justify-content:center;width:40px;height:40px;flex:0 0 auto;' +
        'border:1px solid var(--rule,#171a2622);background:transparent;color:var(--ink-2,#2E323C);' +
        'font-size:22px;line-height:1;cursor:pointer;}' +
      '.bn-sheet-close:hover{border-color:var(--green,#464C8C);color:var(--green-deep,#2F3463);}' +
      '.bn-sheet-list{display:grid;grid-template-columns:1fr 1fr;gap:8px;padding:14px;}' +
      '.bn-sheet-list .bn-btn{display:flex !important;flex-direction:row;align-items:center;gap:12px;' +
        'padding:16px 14px;min-width:0;background:#fff;border:1px solid var(--rule,#171a2622);' +
        'color:var(--ink,#171A21);text-decoration:none;cursor:pointer;text-align:left;' +
        'font-family:\'Inter\',system-ui,sans-serif;font-size:14px;font-weight:500;letter-spacing:0;text-transform:none;}' +
      '.bn-sheet-list .bn-btn .bn-ico{display:flex !important;margin:0;flex:0 0 auto;color:var(--green-deep,#2F3463);' +
        'font-size:18px;line-height:1;}' +
      '.bn-sheet-list .bn-btn:hover{border-color:var(--green-soft,#7A80B8);}' +
      '.bn-sheet-list .bn-btn.active{border-color:var(--green,#464C8C);background:var(--green-tint,#E9EAF4);color:var(--green-deep,#2F3463);}' +
      /* ---- Konto-seksjon: header-handlingene flyttet inn i menyen ---- */
      '.bn-acct{padding:14px 14px 6px;display:flex;flex-direction:column;gap:10px;}' +
      '.bn-acct>*{min-width:0;}' +
      /* Rolle-rad (identitet) — divider under skiller fra handlingene */
      '.bn-acct #whoChip,.bn-acct #roleBadge{display:block !important;width:100%;box-sizing:border-box;' +
        'background:transparent !important;color:var(--ink,#171A21) !important;border:0 !important;' +
        'font-family:\'JetBrains Mono\',monospace;font-size:11px;letter-spacing:0.14em;text-transform:uppercase;' +
        'padding:2px 2px 12px;margin:0;border-bottom:1px solid var(--rule,#171a2622) !important;}' +
      /* Varsling-mount får egen rad med god tap-høyde (≥44px) */
      '.bn-acct #varslingMount{display:flex !important;align-items:center;min-height:48px;padding:2px;}' +
      /* Lenker + logg ut som fulle rader */
      '.bn-acct #topActions,.bn-acct #topbarRight{display:flex;flex-direction:column;gap:8px;margin:0;}' +
      '.bn-acct #topActions a,.bn-acct #topActions button,' +
      '.bn-acct #topbarRight a,.bn-acct #topbarRight button{display:flex;align-items:center;gap:10px;' +
        'width:100%;box-sizing:border-box;min-height:48px;margin:0;padding:13px 14px;' +
        'border:1px solid var(--rule,#171a2622);background:#fff;border-radius:0;' +
        'font-family:\'Inter\',system-ui,sans-serif;font-size:14px;font-weight:500;letter-spacing:0;' +
        'color:var(--ink,#171A21);text-decoration:none;text-align:left;cursor:pointer;}' +
      '.bn-acct #topActions a:hover,.bn-acct #topActions button:hover,' +
      '.bn-acct #topbarRight a:hover,.bn-acct #topbarRight button:hover{border-color:var(--green-soft,#7A80B8);}' +
      '.bn-acct #topActions #logoutBtn,.bn-acct #topbarRight #logoutBtn{' +
        'color:#7d2418;border-color:#e2c6c0;font-weight:600;}' +
      /* ---- Sentrer logoen i topp-headeren på mobil. Headeren er ryddet
         (konto-nodene flyttet til menyen ≤760px), så kun .brand står igjen.
         Tving row + center deterministisk på tvers av begge header-mønstre
         (.topbar-inner og .container), overstyr ev. lokal column-layout. ---- */
      '@media (max-width:760px){' +
        '.topbar .topbar-inner,.topbar .container{display:flex !important;flex-direction:row !important;' +
          'justify-content:center !important;align-items:center !important;}' +
        '.topbar .brand{text-align:center;}' +
      '}';
    document.head.appendChild(st);

    // ---- Grønn stripe: tittel + «Meny»-knapp ----
    var bar = document.createElement('div');
    bar.className = 'bn-bar';
    var title = document.createElement('span');
    title.className = 'bn-bar-title';
    title.textContent = pageTitle;                       // textContent = trygt (egne etiketter)
    var menuBtn = document.createElement('button');
    menuBtn.type = 'button';
    menuBtn.className = 'bn-menu-btn';
    menuBtn.setAttribute('aria-haspopup', 'true');
    menuBtn.setAttribute('aria-expanded', 'false');
    menuBtn.setAttribute('aria-label', 'Åpne meny');
    menuBtn.innerHTML = '<span class="bn-menu-ico"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg></span>Meny';
    bar.appendChild(title);
    bar.appendChild(menuBtn);
    nav.appendChild(bar);

    // ---- Popup-ark med ALLE destinasjonene ----
    var ov = document.createElement('div'); ov.className = 'bn-sheet-ov';
    var sheet = document.createElement('div'); sheet.className = 'bn-sheet'; sheet.setAttribute('role', 'menu');

    var head = document.createElement('div'); head.className = 'bn-sheet-head';
    var h2 = document.createElement('h2'); h2.textContent = 'Meny';
    var closeBtn = document.createElement('button'); closeBtn.type = 'button';
    closeBtn.className = 'bn-sheet-close'; closeBtn.setAttribute('aria-label', 'Lukk'); closeBtn.innerHTML = '&times;';
    head.appendChild(h2); head.appendChild(closeBtn);

    var list = document.createElement('div'); list.className = 'bn-sheet-list';
    var pairs = btns.map(function (b) { var c = b.cloneNode(true); list.appendChild(c); return [b, c]; });

    // ---- Konto-seksjon: flytt header-handlingene (rolle, varsling,
    //      lenker, logg ut) inn i menyen på mobil; tilbake i headeren på
    //      desktop. Vi flytter de EKSISTERENDE nodene (samme id-er) så all
    //      side-JS (setWhoChip/setTopActions, varsling-mount på
    //      #varslingMount, #logoutBtn-handler) virker uendret — kun ny
    //      plassering. Støtter begge header-mønstrene:
    //        #whoChip|#roleBadge (rolle), #varslingMount (varsling),
    //        #topActions|#topbarRight (lenker + logg ut).
    var acct = document.createElement('div'); acct.className = 'bn-acct';
    var slots = [];
    ['#whoChip', '#roleBadge', '#varslingMount', '#topActions', '#topbarRight'].forEach(function (sel) {
      var el = document.querySelector(sel);
      if (el) slots.push({ el: el, parent: el.parentNode, next: el.nextSibling });
    });

    sheet.appendChild(head); sheet.appendChild(acct); sheet.appendChild(list);
    ov.appendChild(sheet);
    document.body.appendChild(ov);

    // Responsiv plassering: ≤760px = nodene i menyen, ellers i headeren.
    var mq = window.matchMedia('(max-width:760px)');
    function placeAccount() {
      if (mq.matches) {
        slots.forEach(function (s) { acct.appendChild(s.el); });
        acct.style.display = slots.length ? '' : 'none';
      } else {
        slots.forEach(function (s) {
          if (s.next && s.next.parentNode === s.parent) s.parent.insertBefore(s.el, s.next);
          else s.parent.appendChild(s.el);
        });
      }
    }
    if (mq.addEventListener) mq.addEventListener('change', placeAccount);
    else if (mq.addListener) mq.addListener(placeAccount);
    placeAccount();

    function syncRole() {
      pairs.forEach(function (p) { p[1].style.display = (p[0].style.display === 'none') ? 'none' : ''; });
    }
    function open() { syncRole(); ov.classList.add('open'); sheet.classList.add('open'); menuBtn.setAttribute('aria-expanded', 'true'); }
    function close() { sheet.classList.remove('open'); menuBtn.setAttribute('aria-expanded', 'false'); setTimeout(function () { ov.classList.remove('open'); }, 240); }

    menuBtn.addEventListener('click', function (e) { e.stopPropagation(); if (sheet.classList.contains('open')) close(); else open(); });
    closeBtn.addEventListener('click', close);
    ov.addEventListener('click', function (e) { if (e.target === ov) close(); });
    sheet.addEventListener('click', function (e) { var el = e.target.closest('.bn-btn'); if (el && el.tagName !== 'A') close(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && sheet.classList.contains('open')) close(); });

    // ---- Logg ut-bekreftelse (gjelder alle admin-sider; #logoutBtn er
    //      universell). Fanges i CAPTURE-fasen FØR sidens egen delegerte
    //      bubble-handler. Viser appens bekreftelsesmodal (aldri native
    //      confirm()) og slipper klikket gjennom på nytt KUN ved bekreft.
    document.addEventListener('click', function (e) {
      var lb = (e.target && e.target.closest) ? e.target.closest('#logoutBtn') : null;
      if (!lb) return;
      if (lb.getAttribute('data-ta-confirmed') === '1') { lb.removeAttribute('data-ta-confirmed'); return; }
      e.preventDefault();
      e.stopImmediatePropagation();
      if (sheet.classList.contains('open')) close();
      var A = window.WestengenKlinikkAuth;
      if (!A || typeof A.confirmDestructive !== 'function') {
        // Fallback: ingen modal tilgjengelig → utfør logout direkte.
        lb.setAttribute('data-ta-confirmed', '1'); lb.click(); return;
      }
      A.confirmDestructive({
        title: t('logout_confirm_title', 'Logge ut?'),
        message: t('logout_confirm_msg', 'Er du sikker på at du vil logge ut?'),
        confirmLabel: t('logout_confirm_yes', 'Logg ut'),
        cancelLabel: t('logout_confirm_no', 'Avbryt')
      }).then(function (ok) {
        if (ok) { lb.setAttribute('data-ta-confirmed', '1'); lb.click(); }
      });
    }, true);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
