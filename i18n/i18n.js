/* ============================================================
   Westengen Klinikk — Static-UI i18n runtime
   ------------------------------------------------------------
   Public API on window.WestengenKlinikkI18n:
     setLanguage(code)      → load JSON, swap DOM, persist
     getLanguage()          → 'no' | 'en' | 'de' | 'es' | 'ar' | 'fa'
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

  var SUPPORTED = ['no', 'en', 'de', 'es', 'ar', 'fa'];
  var RTL = ['ar', 'fa'];
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
          if (code) setLanguage(code);
          sw.classList.remove('open');
          btn.setAttribute('aria-expanded', 'false');
        });
      });
    });
  }

  function updateDropdownState(root) {
    var lang = current || DEFAULT_LANG;
    var FLAGS = { no: '🇳🇴', en: '🇬🇧', de: '🇩🇪', es: '🇪🇸', ar: '🇸🇦', fa: '🇮🇷' };
    (root || document).querySelectorAll('[data-current-lang]').forEach(function (n) {
      n.textContent = FLAGS[lang] || FLAGS[DEFAULT_LANG];
    });
    (root || document).querySelectorAll('.lang-menu button[data-lang]').forEach(function (b) {
      if (b.getAttribute('data-lang') === lang) b.classList.add('active');
      else b.classList.remove('active');
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
    if (lang !== DEFAULT_LANG) jobs.push(fetchDict(lang));

    return Promise.all(jobs).then(function () {
      current = lang;
      try { localStorage.setItem(STORAGE_KEY, lang); } catch (_) {}

      // <html> attributes for screen readers + RTL CSS hooks.
      document.documentElement.setAttribute('lang', lang);
      document.documentElement.setAttribute('dir', RTL.indexOf(lang) !== -1 ? 'rtl' : 'ltr');

      // Run translation over whole body.
      translate(document.body);

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
    if (/^de/.test(nav)) return 'de';
    if (/^es/.test(nav)) return 'es';
    if (/^ar/.test(nav)) return 'ar';
    if (/^fa|^per/.test(nav)) return 'fa';
    return DEFAULT_LANG;
  }

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
    translate: translate,
    onLanguageChange: onLanguageChange,
    SUPPORTED: SUPPORTED,
    RTL: RTL
  };
})();
