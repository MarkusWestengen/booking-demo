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
      'background:rgba(23, 26, 33,.7)',
      'display:none', 'align-items:center', 'justify-content:center',
      'padding:20px'
    ].join(';');
    modal.innerHTML =
      '<div style="background:#fff;max-width:380px;width:100%;padding:24px;border:1px solid #171a2622;font-family:Inter,system-ui,sans-serif;">' +
        '<h3 style="font-family:Fraunces,serif;font-weight:400;font-size:22px;margin:0 0 8px;color:#171A21;">Inaktivitet oppdaget</h3>' +
        '<p style="margin:0 0 18px;color:#2E323C;font-size:14px;line-height:1.5;">' +
          'Du blir logget ut om <strong id="__ta_countdown">60</strong> sekunder.' +
        '</p>' +
        '<button id="__ta_keepalive" style="background:#464C8C;color:#fff;border:0;padding:11px 18px;font-family:inherit;font-size:14px;font-weight:500;cursor:pointer;width:100%;">' +
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
        'background:rgba(23, 26, 33,.7)',
        'display:flex','align-items:center','justify-content:center','padding:20px'
      ].join(';');
      var typeInputHtml = '';
      if (opts.requireTyping) {
        typeInputHtml =
          '<p style="margin:14px 0 6px;font-size:13px;color:#2E323C;">' +
            'Skriv <strong>' + escapeHtml(opts.requireTyping) + '</strong> for å bekrefte:' +
          '</p>' +
          '<input type="text" id="__ta_confirm_typed" autocomplete="off" ' +
            'style="width:100%;padding:10px 12px;border:1px solid #171a2622;background:#F7F8FA;font-family:JetBrains Mono,monospace;font-size:14px;letter-spacing:0.1em;text-transform:uppercase;" />';
      }
      wrap.innerHTML =
        '<div style="background:#fff;max-width:420px;width:100%;padding:24px;border:1px solid #171a2622;font-family:Inter,system-ui,sans-serif;">' +
          '<h3 style="font-family:Fraunces,serif;font-weight:400;font-size:22px;margin:0 0 8px;color:#171A21;">' +
            escapeHtml(opts.title || 'Er du sikker?') +
          '</h3>' +
          '<p style="margin:0;color:#2E323C;font-size:14px;line-height:1.5;white-space:pre-wrap;">' +
            escapeHtml(opts.message || '') +
          '</p>' +
          typeInputHtml +
          '<div style="display:flex;gap:10px;margin-top:18px;justify-content:flex-end;">' +
            '<button id="__ta_cancel" style="background:transparent;border:1px solid #171a2622;padding:9px 16px;font:inherit;cursor:pointer;color:#2E323C;">' +
              escapeHtml(opts.cancelLabel || 'Avbryt') +
            '</button>' +
            '<button id="__ta_confirm" disabled style="background:#c0392b;color:#fff;border:0;padding:9px 16px;font:inherit;cursor:pointer;font-weight:500;opacity:0.5;">' +
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
    try { window.location.replace(AUTH_REDIRECT); } catch (_) {}
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
  }

  // ----- Eksporter -----
  root.WestengenKlinikkAuth = {
    installSessionTimeout: installSessionTimeout,
    auditLog: auditLog,
    confirmDestructive: confirmDestructive,
    requireAuth: requireAuth,
    ensureValidSession: ensureValidSession,
    logoutAndRedirect: logoutAndRedirect,
    applyRoleGates: applyRoleGates,
    escapeHtml: escapeHtml
  };
})(window);
