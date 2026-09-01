/* ============================================================
   Westengen Klinikk — Shared auth helpers
   ------------------------------------------------------------
   Eksponerer:
     window.WestengenKlinikkAuth = {
       installSessionTimeout(sb, opts?),
       auditLog(sb, user, payload),
       confirmDestructive(opts) → Promise<boolean>
     }

   Brukes av: kalender.html, booking-admin.html, innstillinger.html
   ============================================================ */
(function (root) {
  'use strict';

  // ----- Konfig (kan overstyres per side om nødvendig) -----
  // Idle-grense: 60 min AKTIV inaktivitet → signOut. Hevet fra 15 min
  // fordi 15 min ga aggressiv utlogging på ansatt-PWA-en (telefon i lomme).
  // Bakgrunnstid teller IKKE — visibilitychange fryser nedtellingen når
  // appen er skjult og starter den på nytt ved retur (se under). 60 min
  // aktiv-idle er fortsatt forsvarlig for helsedata (Normen): en
  // uovervåket ÅPEN sesjon logges ut, men appen i bakgrunn gjør det ikke.
  // Push er frikoblet fra sesjon (service_role), så lengre timeout er trygt.
  var DEFAULTS = {
    timeoutMs: 60 * 60 * 1000,   // 60 min aktiv-idle → signOut
    warnBeforeMs: 60 * 1000,     // 60 s warning før timeout
    activityEvents: ['mousemove', 'keydown', 'touchstart', 'click', 'scroll']
  };

  // ============================================================
  // Session timeout
  // ------------------------------------------------------------
  // Per-tab inaktivitetsteller. Tracker timer i closures, ikke
  // i en singleton — installSessionTimeout kan trygt kalles flere
  // ganger (returnerer eksisterende controller hvis allerede aktiv).
  // ============================================================
  var _installed = false;
  function installSessionTimeout(sb, opts) {
    if (_installed) return; // idempotent
    _installed = true;

    var cfg = Object.assign({}, DEFAULTS, opts || {});
    var warnTimer = null;
    var logoutTimer = null;
    var countdownTimer = null;

    // ----- Modal injiseres i DOM én gang -----
    var modal = document.createElement('div');
    modal.id = '__ta_timeout_modal';
    modal.setAttribute('aria-hidden', 'true');
    modal.style.cssText = [
      'position:fixed', 'inset:0', 'z-index:9999',
      'background:rgba(11, 26, 43,.7)',
      'display:none', 'align-items:center', 'justify-content:center',
      'padding:20px'
    ].join(';');
    modal.innerHTML =
      '<div style="background:#fff;max-width:380px;width:100%;padding:24px;border:1px solid rgba(11,26,43,.16);font-family:Inter,system-ui,sans-serif;">' +
        '<h3 style="font-family:Fraunces,serif;font-weight:400;font-size:22px;margin:0 0 8px;color:#0b1a2b;">Inaktivitet oppdaget</h3>' +
        '<p style="margin:0 0 18px;color:#26384b;font-size:14px;line-height:1.5;">' +
          'Du blir logget ut om <strong id="__ta_countdown">60</strong> sekunder.' +
        '</p>' +
        '<button id="__ta_keepalive" style="background:#064789;color:#fff;border:0;padding:11px 18px;font-family:inherit;font-size:14px;font-weight:500;cursor:pointer;width:100%;">' +
          'Bli værende innlogget' +
        '</button>' +
      '</div>';
    document.body.appendChild(modal);
    var countdownEl = modal.querySelector('#__ta_countdown');
    var keepaliveBtn = modal.querySelector('#__ta_keepalive');

    function hideModal() {
      modal.style.display = 'none';
      if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
    }
    function showModal() {
      var remaining = Math.ceil(cfg.warnBeforeMs / 1000);
      countdownEl.textContent = String(remaining);
      modal.style.display = 'flex';
      countdownTimer = setInterval(function () {
        remaining -= 1;
        if (remaining <= 0) { clearInterval(countdownTimer); countdownTimer = null; return; }
        countdownEl.textContent = String(remaining);
      }, 1000);
    }

    function doLogout() {
      hideModal();
      try { sessionStorage.setItem('__ta_logout_reason', 'timeout'); } catch (_) {}
      sb.auth.signOut().finally(function () {
        // Hard reload til samme side viser login-skjermaet
        window.location.reload();
      });
    }

    function reset() {
      hideModal();
      if (warnTimer)   { clearTimeout(warnTimer);   warnTimer = null; }
      if (logoutTimer) { clearTimeout(logoutTimer); logoutTimer = null; }
      warnTimer = setTimeout(showModal,    cfg.timeoutMs - cfg.warnBeforeMs);
      logoutTimer = setTimeout(doLogout,   cfg.timeoutMs);
    }

    keepaliveBtn.addEventListener('click', reset);

    // ----- Lytte på aktivitet -----
    // Debounce: ikke reset på hvert mousemove, bare hvis det er
    // gått minst 1 sekund siden forrige reset. Forhindrer perf-tap
    // ved mye mus-bevegelse.
    var lastReset = 0;
    function onActivity() {
      // Hvis modalen vises trenger brukeren å trykke knappen for å
      // bekrefte tilstedeværelse — aktivitet alene resetter ikke.
      if (modal.style.display === 'flex') return;
      var now = Date.now();
      if (now - lastReset < 1000) return;
      lastReset = now;
      reset();
    }
    cfg.activityEvents.forEach(function (ev) {
      document.addEventListener(ev, onActivity, { passive: true });
    });

    // ----- Bakgrunns-pause (visibilitychange) -----
    // Når appen er skjult (telefon låst / app byttet) fryser vi
    // nedtellingen helt — vi nuller timerne uten å logge ut. Ved retur
    // til forgrunn starter vi en FULL nedtelling på nytt (akkumulerer
    // ikke bakgrunnstid). Dette løser at en PWA i lomma logget ansatte
    // ut. Den aktive idle-grensen (60 min med åpen, ubrukt app) består.
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) {
        // Frys: stopp timerne uten doLogout.
        if (warnTimer)      { clearTimeout(warnTimer);      warnTimer = null; }
        if (logoutTimer)    { clearTimeout(logoutTimer);    logoutTimer = null; }
        if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
      } else {
        // Tilbake i forgrunn: skjul evt. warning-modal og start på nytt.
        reset();
      }
    });

    // Start nedtelling
    reset();
  }

  // ============================================================
  // Audit log helper (fire-and-forget)
  // ------------------------------------------------------------
  // Bruker:
  //   WestengenKlinikkAuth.auditLog(sb, user, {
  //     action: 'journal_view',
  //     target_type: 'patient',
  //     target_id: 'patient@example.com',
  //     metadata: { source: 'kalender' }
  //   });
  //
  // PII-regel: metadata skal aldri inneholde rådata. Bare
  // ID-er og status-transisjoner. Helperen overholder dette
  // ved ikke å gjøre noe spesielt — det er kallerens ansvar.
  // Vi advarer i koden hvis metadata ser ut til å inneholde
  // sensitive nøkler.
  // ============================================================
  var SENSITIVE_KEYS = ['name', 'email', 'phone', 'content', 'notes', 'navn', 'epost', 'telefon'];
  function auditLog(sb, user, payload) {
    if (!user) return Promise.resolve(); // ikke logg når ingen er innlogget
    // Sanity-sjekk: ikke send pasientdata i metadata
    if (payload.metadata && typeof payload.metadata === 'object') {
      for (var k in payload.metadata) {
        if (SENSITIVE_KEYS.indexOf(String(k).toLowerCase()) !== -1) {
          // Strip silently — bedre å logge tom metadata enn å lekke
          delete payload.metadata[k];
        }
      }
    }
    var staffId   = user.staffId   || (user.role === 'admin' ? 'admin' : 'unknown');
    var staffName = user.staffName || (user.role === 'admin'
                                         ? ('Admin (' + (user.email || '') + ')')
                                         : 'Ukjent');
    return sb.from('audit_log').insert({
      actor_staff_id: staffId,
      actor_staff_name: staffName,
      action: payload.action,
      target_type: payload.target_type,
      target_id: payload.target_id || null,
      metadata: payload.metadata || null
    }).then(function (res) {
      // Ikke kast feilen videre — audit-feil skal ikke bryte UI-flyten.
      // Men i utvikling vil vi gjerne se det.
      if (res && res.error) {
        // Teknisk log, ikke pasientdata — trygt å logge.
        // (action er en konstant streng, ingen PII.)
        try { window.dispatchEvent(new CustomEvent('westengen-klinikk:audit-failed', { detail: { action: payload.action, error: res.error.message } })); } catch (_) {}
      }
      return res;
    }).catch(function () { /* swallow */ });
  }

  // ============================================================
  // Bekreftelses-modal (kan kreve typing av "SLETT")
  // ------------------------------------------------------------
  // confirmDestructive({
  //   title: 'Slett notat?',
  //   message: 'Dette kan ikke angres.',
  //   confirmLabel: 'Slett',
  //   cancelLabel: 'Avbryt',
  //   requireTyping: 'SLETT'   // optional
  // }) → Promise<true|false>
  // ============================================================
  function confirmDestructive(opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var wrap = document.createElement('div');
      wrap.style.cssText = [
        'position:fixed','inset:0','z-index:10000',
        'background:rgba(11, 26, 43,.7)',
        'display:flex','align-items:center','justify-content:center','padding:20px'
      ].join(';');
      var typeInputHtml = '';
      if (opts.requireTyping) {
        typeInputHtml =
          '<p style="margin:14px 0 6px;font-size:13px;color:#26384b;">' +
            'Skriv <strong>' + escapeHtml(opts.requireTyping) + '</strong> for å bekrefte:' +
          '</p>' +
          '<input type="text" id="__ta_confirm_typed" autocomplete="off" ' +
            'style="width:100%;padding:10px 12px;border:1px solid rgba(11,26,43,.16);background:#ebf2fa;font-family:JetBrains Mono,monospace;font-size:14px;letter-spacing:0.1em;text-transform:uppercase;" />';
      }
      wrap.innerHTML =
        '<div style="background:#fff;max-width:420px;width:100%;padding:24px;border:1px solid rgba(11,26,43,.16);font-family:Inter,system-ui,sans-serif;">' +
          '<h3 style="font-family:Fraunces,serif;font-weight:400;font-size:22px;margin:0 0 8px;color:#0b1a2b;">' +
            escapeHtml(opts.title || 'Er du sikker?') +
          '</h3>' +
          '<p style="margin:0;color:#26384b;font-size:14px;line-height:1.5;white-space:pre-wrap;">' +
            escapeHtml(opts.message || '') +
          '</p>' +
          typeInputHtml +
          '<div style="display:flex;gap:10px;margin-top:18px;justify-content:flex-end;">' +
            '<button id="__ta_cancel" style="background:transparent;border:1px solid rgba(11,26,43,.16);padding:9px 16px;font:inherit;cursor:pointer;color:#26384b;">' +
              escapeHtml(opts.cancelLabel || 'Avbryt') +
            '</button>' +
            '<button id="__ta_confirm" disabled style="background:#a4262c;color:#fff;border:0;padding:9px 16px;font:inherit;cursor:pointer;font-weight:500;opacity:0.5;">' +
              escapeHtml(opts.confirmLabel || 'Bekreft') +
            '</button>' +
          '</div>' +
        '</div>';
      document.body.appendChild(wrap);

      var confirmBtn = wrap.querySelector('#__ta_confirm');
      var cancelBtn  = wrap.querySelector('#__ta_cancel');
      var typedInput = wrap.querySelector('#__ta_confirm_typed');

      function enable() { confirmBtn.disabled = false; confirmBtn.style.opacity = '1'; confirmBtn.style.cursor = 'pointer'; }
      function disable() { confirmBtn.disabled = true; confirmBtn.style.opacity = '0.5'; confirmBtn.style.cursor = 'not-allowed'; }

      if (!opts.requireTyping) {
        enable();
      } else {
        typedInput.addEventListener('input', function () {
          if (typedInput.value.trim().toUpperCase() === String(opts.requireTyping).toUpperCase()) enable();
          else disable();
        });
        setTimeout(function () { typedInput.focus(); }, 30);
      }

      function close(result) {
        document.body.removeChild(wrap);
        resolve(!!result);
      }
      confirmBtn.addEventListener('click', function () { if (!confirmBtn.disabled) close(true); });
      cancelBtn.addEventListener('click', function () { close(false); });
      wrap.addEventListener('click', function (e) { if (e.target === wrap) close(false); });
      document.addEventListener('keydown', function onKey(e) {
        if (e.key === 'Escape') {
          document.removeEventListener('keydown', onKey);
          if (document.body.contains(wrap)) close(false);
        }
      });
    });
  }

  // ----- minimal escapeHtml for modal-tekst -----
  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c];
    });
  }

  // ============================================================
  // Auth-gateway
  // ------------------------------------------------------------
  // requireAuth(): synchronous fast-path — sjekk LS-token. Hvis ingen,
  // redirect umiddelbart til ansatt.html. Returnerer false hvis bruker
  // ikke er innlogget (slik at scriptet kan stoppe videre arbeid).
  //
  // ensureValidSession(sb): async verifikasjon med Supabase — kalles etter
  // SDK-en er lastet. Hvis sesjonen er ugyldig/utgått: redirect til ansatt.html.
  //
  // logoutAndRedirect(sb): standardisert utlogging. Etter signOut: redirect
  // til ansatt.html (eneste vei inn).
  // ============================================================
  var AUTH_REDIRECT = 'ansatt.html';

  // ============================================================
  // Demokontoer og auto-innlogging
  // ------------------------------------------------------------
  // Adminpanelet er halvparten av det som er verdt aa se, og et
  // innloggingsskjema foran det er en doerstokk uten hensikt naar
  // passordene uansett staar aapent paa forsiden. Et besoek paa en
  // adminside logger derfor inn som administrator av seg selv.
  //
  // Innloggingssiden er fortsatt naabar og fungerer som foer, slik
  // at selve innloggingsflyten kan demonstreres. Den er bare ikke
  // lenger noe man MAA gjennom.
  //
  // Passordene er ikke hemmeligheter: de staar paa forsiden, og
  // sikkerheten ligger i skrivesperren mot seed-data (0066) og den
  // nattlige nullstillingen (0067), ikke i dem.
  // ============================================================
  var DEMO_ACCOUNTS = {
    admin: {
      email: 'admin@westengenklinikk.example',
      password: 'demo-admin-2026',
      label: 'Administrator'
    },
    therapist: {
      email: 'terapeut@westengenklinikk.example',
      password: 'demo-terapeut-2026',
      label: 'Terapeut'
    }
  };

  function demoAccount(role) {
    return DEMO_ACCOUNTS[role === 'therapist' ? 'therapist' : 'admin'];
  }

  // Logger inn som oppgitt rolle og laster siden paa nytt. Brukes
  // baade av auto-innloggingen og av rollebytteren.
  function signInAs(sb, role, nextUrl) {
    var acct = demoAccount(role);
    return sb.auth.signOut().catch(function () {}).then(function () {
      return sb.auth.signInWithPassword({ email: acct.email, password: acct.password });
    }).then(function (res) {
      if (res && res.error) throw res.error;
      try { window.location.replace(nextUrl || window.location.pathname.split('/').pop() || 'kalender.html'); } catch (_) {}
      return true;
    });
  }

  function hasSupabaseAuthToken() {
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && /^sb-.*-auth-token$/.test(k)) {
          var v = localStorage.getItem(k);
          if (v && v.length > 20) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  function requireAuth() {
    if (hasSupabaseAuthToken()) return true;
    // Ingen sesjon: send innom innloggingssiden, som logger inn som
    // administrator og sender deg tilbake hit. Sida du ba om er
    // fortsatt maalet, saa lenker inn i panelet virker direkte.
    var here = window.location.pathname.split('/').pop() || 'kalender.html';
    try {
      window.location.replace(AUTH_REDIRECT + '?auto=admin&next=' + encodeURIComponent(here + window.location.search));
    } catch (_) {}
    return false;
  }

  function ensureValidSession(sb) {
    return sb.auth.getSession().then(function (res) {
      var ok = !!(res && res.data && res.data.session);
      if (!ok) {
        try { window.location.replace(AUTH_REDIRECT); } catch (_) {}
      }
      return ok;
    }).catch(function () {
      try { window.location.replace(AUTH_REDIRECT); } catch (_) {}
      return false;
    });
  }

  function logoutAndRedirect(sb) {
    var done = function () { try { window.location.replace(AUTH_REDIRECT); } catch (_) {} };
    try {
      sb.auth.signOut().then(done, done);
    } catch (_) { done(); }
  }

  // ============================================================
  // Role-gating av UI-elementer
  // ------------------------------------------------------------
  // applyRoleGates(role): finn alle [data-admin-only]-elementer på
  // siden og sett display etter rollen. Brukes til å skjule admin-
  // eksklusive bottom-nav-piller for terapeuter uten å duplisere
  // logikk i hver side.
  //
  // Kalles fra handleSession etter at rollen er parsed.
  // ============================================================
  function applyRoleGates(role) {
    var isAdmin = role === 'admin';
    var els = document.querySelectorAll('[data-admin-only]');
    for (var i = 0; i < els.length; i++) {
      els[i].style.display = isAdmin ? '' : 'none';
    }
    mountRoleSwitcher(role);
  }

  // ============================================================
  // Rollebytter
  // ------------------------------------------------------------
  // Rolleskillet er det mest interessante i panelet, men det er
  // usynlig hvis man bare ser én rolle: man legger ikke merke til
  // menypunktene som IKKE er der. Bytteren gjor forskjellen til noe
  // man kan se ved aa klikke fram og tilbake.
  //
  // Rollen ligger i app_metadata paa brukeren og kan ikke endres fra
  // nettleseren — den er ikke et bryter man vipper. Bytteren logger
  // derfor faktisk inn som den andre kontoen. Det er ogsaa aerligere:
  // det er slik et rollebytte foregaar.
  // ============================================================
  function mountRoleSwitcher(role) {
    if (document.getElementById('wkRoleSwitch')) return;
    if (!document.body) return;

    var st = document.createElement('style');
    st.textContent =
      '#wkRoleSwitch{position:fixed;right:16px;bottom:16px;z-index:9997;display:flex;' +
        'align-items:stretch;border:1px solid var(--green,#064789);border-radius:2px;' +
        'background:var(--paper,#ebf2fa);overflow:hidden;' +
        'box-shadow:0 6px 18px -8px rgba(11,26,43,.45);font-family:Inter,system-ui,sans-serif;}' +
      '#wkRoleSwitch .wk-rs-lab{display:flex;align-items:center;padding:0 10px;font-size:10px;' +
        'letter-spacing:.12em;text-transform:uppercase;color:var(--muted,#4a5c6f);' +
        'font-family:"JetBrains Mono",ui-monospace,monospace;' +
        'border-right:1px solid rgba(11,26,43,.18);white-space:nowrap;}' +
      '#wkRoleSwitch button{border:0;background:transparent;cursor:pointer;padding:9px 13px;' +
        'font-size:13px;font-weight:500;color:var(--green,#064789);white-space:nowrap;' +
        'font-family:inherit;transition:background .15s ease,color .15s ease;}' +
      '#wkRoleSwitch button:hover:not([aria-current]){background:var(--green-tint,#cfe0f0);}' +
      '#wkRoleSwitch button[aria-current]{background:var(--green,#064789);color:#fff;cursor:default;}' +
      '#wkRoleSwitch button:focus-visible{outline:2px solid var(--green,#064789);outline-offset:-3px;}' +
      '#wkRoleSwitch button[disabled]{opacity:.55;cursor:progress;}' +
      '@media (max-width:760px){#wkRoleSwitch{right:10px;bottom:64px;}' +
        '#wkRoleSwitch .wk-rs-lab{display:none;}}';
    document.head.appendChild(st);

    var box = document.createElement('div');
    box.id = 'wkRoleSwitch';
    box.setAttribute('role', 'group');
    box.setAttribute('aria-label', 'Bytt rolle i demoen');

    var lab = document.createElement('span');
    lab.className = 'wk-rs-lab';
    lab.textContent = 'Vis som';
    box.appendChild(lab);

    [['admin', 'Administrator'], ['therapist', 'Terapeut']].forEach(function (pair) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = pair[1];
      var active = (pair[0] === 'admin') === (role === 'admin');
      if (active) {
        b.setAttribute('aria-current', 'true');
        b.title = 'Du ser panelet som ' + pair[1].toLowerCase() + ' na';
      } else {
        b.title = 'Logg inn som ' + pair[1].toLowerCase() + ' og last siden pa nytt';
        b.addEventListener('click', function () {
          var all = box.querySelectorAll('button');
          for (var i = 0; i < all.length; i++) all[i].disabled = true;
          b.textContent = 'Bytter\u2026';
          var CFG = window.WestengenKlinikkBackend || {};
          if (!window.supabase || !CFG.supabaseUrl || !CFG.supabaseAnonKey) {
            b.textContent = pair[1];
            for (var j = 0; j < all.length; j++) all[j].disabled = false;
            return;
          }
          var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey, {
            auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false }
          });
          signInAs(sb, pair[0], window.location.pathname.split('/').pop() + window.location.search)
            .catch(function () {
              b.textContent = pair[1];
              for (var k = 0; k < all.length; k++) all[k].disabled = false;
            });
        });
      }
      box.appendChild(b);
    });

    document.body.appendChild(box);
  }

  // ----- Eksporter -----
  root.WestengenKlinikkAuth = {
    DEMO_ACCOUNTS: DEMO_ACCOUNTS,
    demoAccount: demoAccount,
    signInAs: signInAs,
    installSessionTimeout: installSessionTimeout,
    auditLog: auditLog,
    confirmDestructive: confirmDestructive,
    requireAuth: requireAuth,
    ensureValidSession: ensureValidSession,
    logoutAndRedirect: logoutAndRedirect,
    applyRoleGates: applyRoleGates,
    mountRoleSwitcher: mountRoleSwitcher,
    escapeHtml: escapeHtml
  };
})(window);
