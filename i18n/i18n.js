/* ============================================================
   Westengen Klinikk — Static-UI i18n runtime
   ------------------------------------------------------------
   Public API on window.WestengenKlinikkI18n:
     setLanguage(code)      → load JSON, swap DOM, persist
     getLanguage()          → 'no' | 'en'
     t(key, fallback)       → string for JS code
     translate(root)        → mutate DOM under root (default body)
     onLanguageChange(cb)   → register re-render callback

   Markup hooks (matched per-call to translate()):
     data-i18n="key"               → textContent
     data-i18n-html="key"          → innerHTML (only for repo-controlled
                                     keys containing safe markup)
     data-i18n-placeholder="key"   → placeholder
     data-i18n-aria-label="key"    → aria-label
     data-i18n-title="key"         → title
     data-i18n-alt="key"           → alt

   Lookup order:
     1) selected lang JSON
     2) no.json (canonical fallback)
     3) t() fallback param (only via t())
     4) [key] debug marker

   Service-worker: i18n/*.json paths are customer-facing and fall
   through sw.js → network-only (see sw.js isAdminShellRequest()).
   ============================================================ */
(function () {
  'use strict';

  var SUPPORTED = ['no', 'en'];
  // Ingen RTL-sprak igjen. Konstanten beholdes fordi resten av
  // runtime-en spor dir-attributtet gjennom den; den er tom, ikke fjernet.
  var RTL = [];
  var DEFAULT_LANG = 'no';
  var STORAGE_KEY = 'westengen-klinikk-lang';
  var EVENT = 'westengen-klinikk:language-changed';

  // Module-level dictionary cache. Each entry: { ...keys } once loaded.
  var dicts = Object.create(null);
  // Active language code, lazily resolved on first setLanguage call.
  var current = null;
  // External re-render listeners (booking-flow.js wires here).
  var listeners = [];

  // ----- internal: path resolution -----------------------------------
  // We always serve i18n/*.json relative to the document root. Both
  // Pages in the root and in subfolders load this script with the
  // SAME absolute or root-relative URL, but linking strategies differ
  // per page. We compute the base by inspecting the <script>-tag src.
  function resolveBase() {
    var scripts = document.getElementsByTagName('script');
    for (var i = 0; i < scripts.length; i++) {
      var src = scripts[i].src || '';
      var m = src.match(/^(.*\/)i18n\.js(?:\?.*)?$/);
      if (m) return m[1];
    }
    return 'i18n/';
  }
  var BASE = resolveBase();

  function fetchDict(lang) {
    if (dicts[lang]) return Promise.resolve(dicts[lang]);
    return fetch(BASE + lang + '.json', { cache: 'no-cache' })
      .then(function (r) {
        if (!r.ok) throw new Error('i18n: ' + lang + ' HTTP ' + r.status);
        return r.json();
      })
      .then(function (json) { dicts[lang] = json; return json; })
      .catch(function (err) {
        console.warn('[i18n] failed to load', lang, err);
        return null;
      });
  }

  // ----- resolution --------------------------------------------------
  function lookup(lang, key) {
    var d = dicts[lang];
    if (d && Object.prototype.hasOwnProperty.call(d, key)) return d[key];
    return null;
  }

  function t(key, fallback) {
    if (!key) return fallback || '';
    var lang = current || DEFAULT_LANG;
    var v = lookup(lang, key);
    if (v != null) return v;
    if (lang !== DEFAULT_LANG) {
      v = lookup(DEFAULT_LANG, key);
      if (v != null) return v;
    }
    if (fallback != null) return fallback;
    return '[' + key + ']';
  }

  // ----- Tekstkatalog: norsk kildetekst -> engelsk --------------------
  // Nøklene over dekker sider som er bygget med data-i18n. Tre ting er
  // det ikke:
  //   1. tekst fra databasen (tjenestenavn, roller, statuser), som
  //      kopieres inn i bookingradene og ikke har noen id å slå opp på
  //   2. adminpanelet, der teksten står i sidens egen JavaScript
  //   3. demoguiden og andre komponenter som bygger DOM selv
  // Alt det går gjennom i18n/en-tekst.json. Nøkkelen er den norske
  // teksten slik den står, som i gettext. Oppslaget skjer på
  // tekstnoder og attributter mens siden bygges (MutationObserver), og
  // via tekst() fra kode som vil ha svaret direkte.
  //
  // Tekst fra brukere (meldinger, notater, anmeldelser) og tekniske id-er
  // står under translate="no", HTML-standardens eget merke for tekst som
  // ikke skal oversettes. Den røres ikke.
  var katalog = null;       // { norsk: engelsk }
  var moenstre = [];        // [[RegExp, erstatning]]
  var fraser = null;        // RegExp over alle nøkler, lengst først
  var katalogLastet = Object.create(null);

  function normaliser(s) { return String(s).replace(/\s+/g, ' ').trim(); }

  var raaKatalog = Object.create(null);

  function lastKatalog(lang) {
    if (lang === DEFAULT_LANG) return Promise.resolve(null);
    if (katalogLastet[lang]) return katalogLastet[lang];
    katalogLastet[lang] = fetch(BASE + lang + '-tekst.json', { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (json) { raaKatalog[lang] = json; return json; })
      .catch(function (err) { console.warn('[i18n] tekstkatalog', lang, err); return null; });
    return katalogLastet[lang];
  }

  // Bygges når både nøkkelfilene og katalogen er lastet. Hver nøkkel i
  // no.json gir en oppføring norsk -> engelsk, så en tekst som står
  // hardkodet ett sted og som nøkkel et annet, bare trenger nøkkelen.
  // Katalogens egne oppføringer vinner.
  function byggKatalog(lang) {
    var json = raaKatalog[lang];
    katalog = Object.create(null);
    moenstre = [];
    var no = dicts[DEFAULT_LANG] || {}, en = dicts[lang] || {};
    Object.keys(no).forEach(function (k) {
      var fra = no[k], til = en[k];
      if (typeof fra !== 'string' || typeof til !== 'string') return;
      if (fra.indexOf('<') !== -1 || fra.indexOf('{') !== -1) return;
      katalog[normaliser(fra)] = til;
    });
    if (json) {
      Object.keys(json).forEach(function (k) {
        if (k === '_meta') return;
        if (k === '_moenstre') {
          json[k].forEach(function (p) { moenstre.push([new RegExp(p[0], 'u'), p[1]]); });
          return;
        }
        katalog[normaliser(k)] = json[k];
      });
    }
    var noekler = Object.keys(katalog)
      // Fraser inne i en lengre tekst: bare nøkler som ikke kan være et
      // engelsk ord. Et kort enkeltord («time», «Tid») kunne ellers truffet
      // engelsk tekst som allerede er oversatt. Nøkler som er lik
      // oversettelsen («Westengen Klinikk») er med, så det lengste treffet
      // vinner og merkenavnet ikke blir til «Westengen Clinic».
      .filter(function (k) {
        return k.length >= 3 && (/\s/.test(k) || k.length >= 6 || /[æøåÆØÅ]/.test(k));
      })
      .sort(function (a, b) { return b.length - a.length; })
      .map(function (k) { return k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); });
    fraser = noekler.length
      ? new RegExp('(?<![\\p{L}\\p{N}])(?:' + noekler.join('|') + ')(?![\\p{L}\\p{N}])', 'gu')
      : null;
  }

  // Engelsk for en norsk tekst, eller teksten selv hvis katalogen ikke
  // har den. Hel tekst først, så mønstre (tekst med tall i), og til sist
  // kjente fraser inne i en lengre tekst som er satt sammen i kode.
  function tekst(s) {
    if (s == null) return s;
    var str = String(s);
    if ((current || DEFAULT_LANG) === DEFAULT_LANG || !katalog) return str;
    var n = normaliser(str);
    if (!n) return str;
    var foran = str.match(/^\s*/)[0], bak = str.match(/\s*$/)[0];
    if (katalog[n] != null) return foran + katalog[n] + bak;
    for (var i = 0; i < moenstre.length; i++) {
      if (moenstre[i][0].test(n)) {
        var ut = n.replace(moenstre[i][0], function () {
          var g = arguments;
          return moenstre[i][1].replace(/\$(\d)/g, function (_, d) {
            var v = g[+d] == null ? '' : g[+d];
            return katalog[normaliser(v)] != null ? katalog[normaliser(v)] : v;
          });
        });
        return foran + ut + bak;
      }
    }
    if (fraser && /[\p{L}]/u.test(n)) {
      var byttet = n.replace(fraser, function (m) { return katalog[m]; });
      if (byttet !== n) return foran + byttet + bak;
    }
    return str;
  }

  // Locale for Intl etter valgt språk. Datoer og beløp formateres med
  // denne, aldri med hardkodede norske navn på ukedager og måneder.
  // Før språkfilene er lastet, gjelder det lagrede valget. En side som
  // rendrer datoer før fetch er ferdig, skal ikke få norske ukedager.
  function locale() { return (current || resolveInitialLang()) === 'en' ? 'en-GB' : 'nb-NO'; }

  // Beløp i kroner. Norsk: «kr 1 290». Engelsk: «NOK 1,290».
  function beloep(n) {
    n = Number(n) || 0;
    return locale() === 'en-GB' ? 'NOK ' + n.toLocaleString('en-GB') : 'kr ' + n.toLocaleString('nb-NO');
  }

  // ----- DOM-oversetting med katalogen --------------------------------
  var ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];
  var originalTekst = new WeakMap();   // Text -> norsk original
  var originalAttr = new WeakMap();    // Element -> { attr: norsk original }
  var oversatt = new WeakMap();        // Text -> engelsk vi selv satte
  var observer = null;
  var HOPP_TAGGER = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, TEMPLATE: 1 };

  function hoppOver(el) {
    for (var p = el; p; p = p.parentElement) {
      if (HOPP_TAGGER[p.tagName]) return true;
      if (p.isContentEditable) return true;
      if (p.getAttribute && p.getAttribute('translate') === 'no') return true;
    }
    return false;
  }

  function oversettTekstnode(node) {
    var el = node.parentElement;
    if (!el || hoppOver(el)) return;
    var v = node.nodeValue;
    if (oversatt.get(node) === v) return;
    var en = tekst(v);
    if (en !== v) {
      originalTekst.set(node, v);
      oversatt.set(node, en);
      node.nodeValue = en;
    }
  }

  function oversettAttr(el) {
    // Et tekstfelt har ingen tekstnoder vi skal røre, men plassholderen
    // og tittelen er grensesnitt. Derfor sjekkes forelderen her.
    if (el.getAttribute('translate') === 'no' || (el.parentElement && hoppOver(el.parentElement))) return;
    var liste = ATTRS.slice();
    if (el.tagName === 'INPUT' && /^(button|submit|reset)$/i.test(el.type)) liste.push('value');
    liste.forEach(function (a) {
      var v = el.getAttribute(a);
      if (!v) return;
      var o = originalAttr.get(el);
      if (o && o['_en_' + a] === v) return;
      var en = tekst(v);
      if (en !== v) {
        o = o || {};
        o[a] = v; o['_en_' + a] = en;
        originalAttr.set(el, o);
        el.setAttribute(a, en);
      }
    });
  }

  function oversettTre(root) {
    if (!root) return;
    if (root.nodeType === 3) { oversettTekstnode(root); return; }
    if (root.nodeType !== 1 && root.nodeType !== 11) return;
    if (root.nodeType === 1) {
      oversettAttr(root);
      if (hoppOver(root)) return;
    }
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    for (var n = w.nextNode(); n; n = w.nextNode()) oversettTekstnode(n);
    if (root.querySelectorAll) {
      var els = root.querySelectorAll('[placeholder],[title],[aria-label],[alt],input[type=button],input[type=submit]');
      for (var i = 0; i < els.length; i++) oversettAttr(els[i]);
    }
  }

  function oversettTittel() {
    var t0 = document.querySelector('title');
    if (!t0) return;
    var v = t0.textContent;
    var en = tekst(v);
    if (en !== v) { if (!originalTekst.has(t0)) originalTekst.set(t0, v); t0.textContent = en; }
  }

  function startObserver() {
    if (observer || !window.MutationObserver) return;
    observer = new MutationObserver(function (list) {
      if ((current || DEFAULT_LANG) === DEFAULT_LANG || !katalog) return;
      for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) oversettTre(m.addedNodes[j]);
        } else if (m.type === 'characterData') {
          oversettTekstnode(m.target);
        } else if (m.type === 'attributes') {
          oversettAttr(m.target);
        }
      }
    });
    observer.observe(document.documentElement, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ATTRS.concat(['value'])
    });
  }

  // Tilbake til norsk: sett inn originalene vi byttet ut. Noder som er
  // bygget på nytt siden, er norske fra før.
  function gjenopprett() {
    var w = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT, null);
    for (var n = w.nextNode(); n; n = w.nextNode()) {
      if (originalTekst.has(n) && oversatt.get(n) === n.nodeValue) {
        n.nodeValue = originalTekst.get(n);
        originalTekst.delete(n); oversatt.delete(n);
      }
    }
    var els = document.querySelectorAll('[placeholder],[title],[aria-label],[alt],input');
    for (var i = 0; i < els.length; i++) {
      var o = originalAttr.get(els[i]);
      if (!o) continue;
      Object.keys(o).forEach(function (a) {
        if (a.indexOf('_en_') === 0) return;
        if (els[i].getAttribute(a) === o['_en_' + a]) els[i].setAttribute(a, o[a]);
      });
      originalAttr.delete(els[i]);
    }
    var t0 = document.querySelector('title');
    if (t0 && originalTekst.has(t0)) { t0.textContent = originalTekst.get(t0); originalTekst.delete(t0); }
  }

  // ----- DOM application ---------------------------------------------
  // Each hook is (attr, applyFn). The translator iterates once per hook.
  var HOOKS = [
    ['data-i18n',              function (el, val) { el.textContent = val; }],
    ['data-i18n-html',         function (el, val) { el.innerHTML = val; }],
    ['data-i18n-placeholder',  function (el, val) { el.setAttribute('placeholder', val); }],
    ['data-i18n-aria-label',   function (el, val) { el.setAttribute('aria-label', val); }],
    ['data-i18n-title',        function (el, val) { el.setAttribute('title', val); }],
    ['data-i18n-alt',          function (el, val) { el.setAttribute('alt', val); }]
  ];

  function translate(root) {
    root = root || document.body;
    if (!root || !root.querySelectorAll) return;
    HOOKS.forEach(function (h) {
      var attr = h[0];
      var apply = h[1];
      var nodes = root.querySelectorAll('[' + attr + ']');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var key = el.getAttribute(attr);
        if (!key) continue;
        var val = t(key);
        // Skip if dict missing AND no fallback found — keep the
        // pre-rendered Norwegian content rather than showing [key].
        if (val === '[' + key + ']') continue;
        apply(el, val);
      }
    });
    // Re-bind language dropdowns each call so dynamically inserted
    // dropdowns (e.g. inserted by booking-flow) also work.
    wireDropdowns(root);
    updateDropdownState(root);
  }

  // ----- dropdown wiring ---------------------------------------------
  // Mark wired containers so we don't double-bind. We bind on the
  // parent .lang container so toggle/outside-click logic stays local.
  function wireDropdowns(root) {
    var switchers = (root || document).querySelectorAll('.lang[id="langSwitcher"], .lang.tas-lang');
    switchers.forEach(function (sw) {
      if (sw.dataset.i18nWired === '1') return;
      sw.dataset.i18nWired = '1';
      var btn = sw.querySelector('.lang-btn');
      var menu = sw.querySelector('.lang-menu');
      if (!btn || !menu) return;

      btn.addEventListener('click', function (e) {
        e.stopPropagation();
        var open = sw.classList.toggle('open');
        btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      });
      document.addEventListener('click', function () {
        sw.classList.remove('open');
        btn.setAttribute('aria-expanded', 'false');
      });
      menu.addEventListener('click', function (e) { e.stopPropagation(); });
      menu.querySelectorAll('button[data-lang]').forEach(function (b) {
        b.addEventListener('click', function () {
          var code = b.getAttribute('data-lang');
          // Adminsidene bygger datoer, beløp og tabeller i egen kode
          // ved lasting. Der er en ny lasting den eneste måten å få alt
          // over på det nye språket; kundesidene bytter på stedet.
          if (code && sw.hasAttribute('data-last-paa-nytt') && code !== getLanguage()) {
            try { localStorage.setItem(STORAGE_KEY, code); } catch (_) {}
            location.reload();
            return;
          }
          if (code) setLanguage(code);
          sw.classList.remove('open');
          btn.setAttribute('aria-expanded', 'false');
        });
      });
    });
  }

  // Språkene står med sitt eget navn, ikke med flagg. Et flagg er et
  // land, ikke et språk, og Windows viser dem som to bokstaver.
  var NAVN = { no: 'Norsk', en: 'English' };

  function updateDropdownState(root) {
    var lang = current || DEFAULT_LANG;
    (root || document).querySelectorAll('[data-current-lang]').forEach(function (n) {
      n.textContent = NAVN[lang] || NAVN[DEFAULT_LANG];
    });
    (root || document).querySelectorAll('.lang-menu button[data-lang]').forEach(function (b) {
      if (b.getAttribute('data-lang') === lang) { b.classList.add('active'); b.setAttribute('aria-current', 'true'); }
      else { b.classList.remove('active'); b.removeAttribute('aria-current'); }
    });
    (root || document).querySelectorAll('.lang-menu').forEach(function (m) {
      m.setAttribute('dir', RTL.indexOf(lang) !== -1 ? 'rtl' : 'ltr');
    });
  }

  // ----- public: setLanguage -----------------------------------------
  function setLanguage(lang) {
    if (!lang || SUPPORTED.indexOf(lang) === -1) lang = DEFAULT_LANG;

    // Pre-load default + selected so fallback chain always resolves.
    var jobs = [fetchDict(DEFAULT_LANG)];
    if (lang !== DEFAULT_LANG) { jobs.push(fetchDict(lang)); jobs.push(lastKatalog(lang)); }

    return Promise.all(jobs).then(function () {
      var forrige = current;
      current = lang;
      if (lang !== DEFAULT_LANG) byggKatalog(lang);
      try { localStorage.setItem(STORAGE_KEY, lang); } catch (_) {}

      // <html> attributes for screen readers + RTL CSS hooks.
      document.documentElement.setAttribute('lang', lang);
      document.documentElement.setAttribute('dir', RTL.indexOf(lang) !== -1 ? 'rtl' : 'ltr');

      if (lang === DEFAULT_LANG && forrige && forrige !== DEFAULT_LANG) gjenopprett();

      // Run translation over whole body.
      translate(document.body);
      if (lang !== DEFAULT_LANG) {
        oversettTre(document.body);
        oversettTittel();
        startObserver();
      }
      ferdig();

      // Notify external code (booking-flow etc.) to re-render.
      try {
        window.dispatchEvent(new CustomEvent(EVENT, { detail: { lang: lang } }));
      } catch (_) {
        // Older browser fallback: synthetic event.
        var ev = document.createEvent('Event');
        ev.initEvent(EVENT, true, true);
        ev.detail = { lang: lang };
        window.dispatchEvent(ev);
      }
      listeners.forEach(function (cb) {
        try { cb(lang); } catch (e) { console.error('[i18n] listener error', e); }
      });
      return lang;
    });
  }

  function getLanguage() { return current || DEFAULT_LANG; }

  function onLanguageChange(cb) {
    if (typeof cb === 'function') listeners.push(cb);
  }

  // ----- initial language resolution ---------------------------------
  function resolveInitialLang() {
    try {
      var stored = localStorage.getItem(STORAGE_KEY);
      if (stored && SUPPORTED.indexOf(stored) !== -1) return stored;
    } catch (_) {}
    var nav = (navigator.language || navigator.userLanguage || '').toLowerCase();
    if (/^nb|^nn|^no/.test(nav)) return 'no';
    if (/^en/.test(nav)) return 'en';
    // Demoen har bare norsk og engelsk. Alt annet lander paa norsk.
    return DEFAULT_LANG;
  }

  // ----- Ingen norsk blaff før engelsk -------------------------------
  // Står et annet språk enn norsk lagret, skjules siden til katalogen er
  // på plass, høyst 1,5 sekund. Skjer det noe med katalogen, vises siden
  // likevel: norsk tekst er bedre enn en blank side.
  var venter = false;
  function ferdig() {
    if (!venter) return;
    venter = false;
    document.documentElement.classList.remove('i18n-venter');
  }
  (function () {
    var lagret = null;
    try { lagret = localStorage.getItem(STORAGE_KEY); } catch (_) {}
    if (!lagret || lagret === DEFAULT_LANG || SUPPORTED.indexOf(lagret) === -1) return;
    venter = true;
    var st = document.createElement('style');
    st.textContent = 'html.i18n-venter body{visibility:hidden}';
    (document.head || document.documentElement).appendChild(st);
    document.documentElement.classList.add('i18n-venter');
    setTimeout(ferdig, 1500);
  })();

  // ----- bootstrap ---------------------------------------------------
  function boot() {
    var initial = resolveInitialLang();
    // Always also wire dropdowns + update visual state immediately so
    // the UI isn't dead while JSON is fetched.
    wireDropdowns(document.body);
    updateDropdownState(document.body);
    setLanguage(initial);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  // Export.
  window.WestengenKlinikkI18n = {
    setLanguage: setLanguage,
    getLanguage: getLanguage,
    t: t,
    tekst: tekst,
    locale: locale,
    beloep: beloep,
    translate: translate,
    onLanguageChange: onLanguageChange,
    SUPPORTED: SUPPORTED,
    RTL: RTL
  };
})();
