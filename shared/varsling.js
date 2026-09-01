/* ============================================================
   Westengen Klinikk — Ansatt-varsling (in-app lyd/toast + web push)
   ------------------------------------------------------------
   Eksponerer window.WestengenKlinikkVarsling:
     mountButton({ sb, container })   → «Slå på/av varsler»-knapp
     watch({ sb, tables, onEvent })   → realtime INSERT → lyd + toast
     pushSupported()                  → boolean

   To nivåer:
     Nivå 1 (watch): når en admin-fane er ÅPEN spiller vi en kort
       Web-Audio-tone + viser toast ved ny rad i bookings/contact_messages.
       Realtime filtrerer events gjennom abonnentens RLS, så bare ansatte
       med SELECT mottar dem.
     Nivå 2 (mountButton): registrerer et ekte push-abonnement slik at
       edge-funksjonen notify-push kan sende varsel selv når PWA-en er
       HELT lukket. Abonnementet lagres i public.push_subscriptions.

   PERSONVERN: push-teksten settes server-side i notify-push og er alltid
   generisk. Denne modulen sender ALDRI pasientdata til abonnementsraden —
   kun endpoint + krypteringsnøkler + user agent.

   Brukes av: kalender.html (bookings) og meldinger.html (contact_messages).
   ============================================================ */
(function (root) {
  'use strict';

  // Offentlig VAPID-nøkkel. Trygt å committe — kun den PRIVATE nøkkelen
  // (satt som edge-secret VAPID_PRIVATE_KEY) er hemmelig. Må matche den.
  var VAPID_PUBLIC_KEY = 'BHf3Xo09YSbKhpTKGMvBVbr-Yzl9uuIvL40lsOz7_hr-I9i39FgT7Vw-n4lAmGPtUYpH5GYJPjImqH-kVweROj4';

  // i18n-helper: bruk runtime hvis siden har lastet den, ellers fallback.
  function t(key, fallback) {
    if (root.WestengenKlinikkI18n && typeof root.WestengenKlinikkI18n.t === 'function') {
      return root.WestengenKlinikkI18n.t(key, fallback);
    }
    return fallback;
  }

  function pushSupported() {
    return ('serviceWorker' in navigator) &&
           ('PushManager' in window) &&
           ('Notification' in window);
  }

  function isIOS() { return /iphone|ipad|ipod/i.test(navigator.userAgent || ''); }
  function isStandalone() {
    return (root.matchMedia && root.matchMedia('(display-mode: standalone)').matches) ||
           root.navigator.standalone === true;
  }

  // base64url (VAPID public) → Uint8Array (applicationServerKey).
  function urlBase64ToUint8Array(base64String) {
    var padding = '='.repeat((4 - base64String.length % 4) % 4);
    var base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    var raw = atob(base64);
    var out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  // SW registreres normalt fra ansatt.html, men admin-sider kan åpnes
  // direkte → registrer (idempotent: samme URL/scope) og vent til klar.
  function ensureRegistration() {
    try { navigator.serviceWorker.register('sw.js'); } catch (_) {}
    return navigator.serviceWorker.ready;
  }

  // ----- Lettvekts-toast (uavhengig av sidens egne helpers) -----
  function toast(msg, type) {
    var el = document.createElement('div');
    el.textContent = msg;
    el.setAttribute('role', 'status');
    el.style.cssText = [
      'position:fixed', 'left:50%', 'bottom:84px', 'transform:translateX(-50%)',
      'z-index:10050', 'max-width:90vw', 'padding:12px 18px',
      'background:' + (type === 'error' ? '#9e2b1f' : '#2e2320'),
      'color:#efe5dc', 'font-family:Inter,system-ui,sans-serif', 'font-size:14px',
      'box-shadow:0 6px 24px rgba(0,0,0,.28)',
      'border-left:3px solid ' + (type === 'error' ? '#fff' : '#1f4e4a')
    ].join(';');
    document.body.appendChild(el);
    setTimeout(function () { el.style.transition = 'opacity .4s'; el.style.opacity = '0'; }, 3600);
    setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 4100);
  }

  // ----- Lyd via Web Audio (ingen lydfil) -----
  var _audioCtx = null;
  function beep() {
    try {
      var Ctx = root.AudioContext || root.webkitAudioContext;
      if (!Ctx) return;
      if (!_audioCtx) _audioCtx = new Ctx();
      if (_audioCtx.state === 'suspended') _audioCtx.resume();
      var now = _audioCtx.currentTime;
      // To korte, diskrete toner (C6 → E6).
      [[1046.5, 0], [1318.5, 0.13]].forEach(function (pair) {
        var osc = _audioCtx.createOscillator();
        var gain = _audioCtx.createGain();
        osc.type = 'sine';
        osc.frequency.value = pair[0];
        var start = now + pair[1];
        gain.gain.setValueAtTime(0.0001, start);
        gain.gain.exponentialRampToValueAtTime(0.18, start + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.12);
        osc.connect(gain); gain.connect(_audioCtx.destination);
        osc.start(start); osc.stop(start + 0.14);
      });
    } catch (_) {}
  }

  // ----- Abonnement -----
  // localStorage-flagg: husk at brukeren har skrudd PÅ varsler, så vi kan
  // re-abonnere STILLE hvis nettleserens abonnement forsvinner (rotert
  // nøkkel, nettleser-opprydding). Settes ved «på», fjernes ved «av».
  // Brukes ALDRI til å slette ved utlogging.
  var ENABLED_KEY = 'ta-varsling-paa';
  function setEnabledFlag(on) {
    try { if (on) localStorage.setItem(ENABLED_KEY, '1'); else localStorage.removeItem(ENABLED_KEY); } catch (_) {}
  }
  function getEnabledFlag() {
    try { return localStorage.getItem(ENABLED_KEY) === '1'; } catch (_) { return false; }
  }

  function currentSubscription() {
    return ensureRegistration().then(function (reg) {
      return reg.pushManager.getSubscription();
    });
  }

  // Lagre/oppdater abonnementsraden. insert-or-ignore på endpoint (UNIQUE);
  // krever kun INSERT-grant. staff_id utelates → DB-default auth.uid() fyller
  // den, og RLS-insert-policyen håndhever staff_id = auth.uid().
  function upsertSub(sb, sub) {
    var json = sub.toJSON();
    var row = {
      endpoint: json.endpoint,
      p256dh: json.keys.p256dh,
      auth: json.keys.auth,
      user_agent: (navigator.userAgent || '').slice(0, 400)
    };
    return sb.from('push_subscriptions')
      .upsert(row, { onConflict: 'endpoint', ignoreDuplicates: true })
      .then(function (res) { if (res.error) throw res.error; return sub; });
  }

  function subscribe(sb) {
    return ensureRegistration().then(function (reg) {
      return reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
      });
    }).then(function (sub) {
      return upsertSub(sb, sub).then(function () { setEnabledFlag(true); return sub; });
    });
  }

  // Eksplisitt «skru av» — eneste vei som fjerner abonnementet.
  function unsubscribe(sb) {
    return currentSubscription().then(function (sub) {
      setEnabledFlag(false);
      if (!sub) return null;
      var endpoint = sub.endpoint;
      return sub.unsubscribe().catch(function () { return true; }).then(function () {
        return sb.from('push_subscriptions').delete().eq('endpoint', endpoint);
      });
    });
  }

  // ----- Synk ved app-åpning (overlever utlogging) -----
  // Kalles for innlogget ansatt hver gang appen åpnes. Holder
  // push_subscriptions friskt og re-abonnerer STILLE hvis brukeren hadde
  // varsler på men nettleser-abonnementet er borte. Sletter ALDRI noe —
  // utlogging skal aldri fjerne abonnementet (kun eksplisitt «skru av»).
  // Returnerer Promise<boolean> = er varsler aktive nå.
  function syncSubscription(sb) {
    if (!sb || !pushSupported()) return Promise.resolve(false);
    return currentSubscription().then(function (sub) {
      if (sub) {
        // Finnes i nettleseren → sørg for at raden finnes (kan ha blitt
        // ryddet bort serverside), og marker som på.
        return upsertSub(sb, sub)
          .then(function () { setEnabledFlag(true); return true; })
          .catch(function () { return true; });
      }
      // Ingen abonnement i nettleseren. Hadde brukeren det på + fortsatt
      // tillatelse? Re-abonner stille (ingen prompt — permission er gitt).
      if (getEnabledFlag() && ('Notification' in window) && Notification.permission === 'granted') {
        return subscribe(sb).then(function () { return true; }).catch(function () { return false; });
      }
      return false;
    }).catch(function () { return false; });
  }

  // ----- Knapp («Slå på/av varsler») -----
  function mountButton(opts) {
    opts = opts || {};
    var sb = opts.sb;
    var container = typeof opts.container === 'string'
      ? document.querySelector(opts.container) : opts.container;
    if (!container || !sb) return;
    // Vis KUN hvis nettleseren støtter push.
    if (!pushSupported()) return;
    // Idempotent: ikke monter to ganger.
    if (container.querySelector('#varslingBtn')) return;
    // Popover-hint posisjoneres relativt til containeren.
    if (!container.style.position) container.style.position = 'relative';

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.id = 'varslingBtn';
    // Eksplisitt, tydelig «merket» pille-stil — uavhengig av sidens header-CSS
    // (begge admin-sider får identisk, godt synlig knapp).
    var BASE_CSS = [
      'display:inline-flex', 'align-items:center', 'gap:6px',
      'border:0', 'border-radius:999px', 'cursor:pointer',
      'font-family:Inter,system-ui,sans-serif', 'font-size:12px', 'font-weight:600',
      'letter-spacing:0.01em', 'padding:7px 13px', 'white-space:nowrap',
      'box-shadow:0 1px 3px rgba(0,0,0,.18)'
    ];
    function paint(on) {
      // på = grønn (aktiv), av = lys men tydelig kontrast mot mørk header.
      var color = on ? 'background:#1f4e4a;color:#fff;' : 'background:#efe5dc;color:#2e2320;';
      btn.style.cssText = BASE_CSS.join(';') + ';' + color;
    }
    container.appendChild(btn);

    // ----- iOS-hjelpetekst som popover (bryter ikke header-layouten) -----
    var hint = null;
    function showIosHint() {
      if (hint || !isIOS() || isStandalone()) return;
      hint = document.createElement('div');
      hint.textContent = t('notif_ios_hint',
        'På iPhone/iPad: legg appen til på Hjem-skjerm (iOS 16.4+) for at varsler skal virke.');
      hint.style.cssText = [
        'position:absolute', 'top:calc(100% + 6px)', 'right:0', 'z-index:10060',
        'max-width:240px', 'background:#2e2320', 'color:#efe5dc',
        'font-family:Inter,system-ui,sans-serif', 'font-size:11px', 'line-height:1.45',
        'padding:9px 11px', 'border-left:3px solid #1f4e4a',
        'box-shadow:0 6px 20px rgba(0,0,0,.3)'
      ].join(';');
      container.appendChild(hint);
    }
    function clearHint() {
      if (hint && hint.parentNode) { hint.parentNode.removeChild(hint); hint = null; }
    }

    // Rene inline-SVG-ikoner (samme konvensjon som bottom-nav: stroke,
    // currentColor, ingen fyll) i stedet for emoji. Bjelle = varsler på,
    // bjelle-med-strek = av. Arver knappens tekstfarge via currentColor.
    var BELL_ON = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>';
    var BELL_OFF = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.73 21a2 2 0 0 1-3.46 0"/><path d="M18.63 13A17.89 17.89 0 0 1 18 8"/><path d="M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14"/><path d="M18 8a6 6 0 0 0-9.33-5"/><line x1="1" y1="1" x2="23" y2="23"/></svg>';

    function setState(on, busy) {
      btn.disabled = !!busy;
      paint(!!on);
      if (busy) { btn.textContent = '…'; btn.style.opacity = '0.7'; return; }
      btn.style.opacity = '1';
      // Ikon (SVG) + label som tekstnode; flex gap:6px gir mellomrommet.
      btn.innerHTML = on ? BELL_ON : BELL_OFF;
      btn.appendChild(document.createTextNode(
        on ? t('notif_on', 'Varsler på') : t('notif_enable', 'Slå på varsler')));
      btn.setAttribute('aria-pressed', on ? 'true' : 'false');
      btn.title = on ? t('notif_on', 'Varsler på') : t('notif_enable', 'Slå på varsler');
      btn.dataset.on = on ? '1' : '0';
    }

    // Init: synk abonnement (overlever utlogging) og vis riktig tilstand.
    setState(false, true);
    syncSubscription(sb).then(function (on) {
      setState(on, false);
      if (!on) showIosHint();
    }).catch(function () { setState(false, false); });

    btn.addEventListener('click', function () {
      var turningOn = btn.dataset.on !== '1';
      if (turningOn) {
        if (Notification.permission === 'denied') {
          toast(t('notif_blocked',
            'Varsler er blokkert i nettleserinnstillingene. Skru dem på for dette nettstedet.'), 'error');
          showIosHint();
          return;
        }
        setState(false, true);
        Notification.requestPermission().then(function (perm) {
          if (perm !== 'granted') {
            setState(false, false);
            showIosHint();
            toast(t('notif_denied', 'Du må tillate varsler for å få push.'), 'error');
            return;
          }
          subscribe(sb).then(function () {
            setState(true, false);
            clearHint();
            beep();
            toast(t('notif_enabled_ok', 'Varsler er slått på.'));
          }).catch(function (err) {
            setState(false, false);
            console.warn('[varsling] subscribe feilet', err);
            toast(t('notif_error', 'Kunne ikke endre varselinnstilling. Prøv igjen.'), 'error');
          });
        }).catch(function () { setState(false, false); });
      } else {
        setState(false, true);
        unsubscribe(sb).then(function () {
          setState(false, false);
          toast(t('notif_disabled_ok', 'Varsler er slått av.'));
        }).catch(function () {
          setState(true, false);
          toast(t('notif_error', 'Kunne ikke endre varselinnstilling. Prøv igjen.'), 'error');
        });
      }
    });
  }

  // ----- Realtime in-app (lyd + toast på åpen admin-fane) -----
  function watch(opts) {
    opts = opts || {};
    var sb = opts.sb;
    var tables = opts.tables || [];
    if (!sb || !tables.length || typeof sb.channel !== 'function') return null;
    var onEvent = opts.onEvent;

    var channel = sb.channel('ta-varsling-' + tables.join('-'));
    tables.forEach(function (tbl) {
      channel.on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: tbl },
        function (payload) {
          beep();
          var msg = (tbl === 'bookings')
            ? t('notif_new_booking', 'Ny booking mottatt')
            : t('notif_new_message', 'Ny melding mottatt');
          toast(msg);
          if (typeof onEvent === 'function') {
            try { onEvent(tbl, payload); } catch (_) {}
          }
        });
    });
    channel.subscribe();
    return channel;
  }

  root.WestengenKlinikkVarsling = {
    mountButton: mountButton,
    watch: watch,
    syncSubscription: syncSubscription,
    pushSupported: pushSupported
  };
})(window);
