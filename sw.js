/* ============================================================
   Westengen Klinikk — Minimal service worker
   ------------------------------------------------------------
   Strategi:
     - cache-first for ADMIN-skall (ansatt/kalender/booking-admin/
       kunder/kunde-detalj/audit-logg/stengte-tider/innstillinger/
       tjenester.html + /shared/* + /icons/* + manifest)
     - network-only for KUNDE-ruter (index/bestilling/avbestill/
       venteliste/anmeldelser/kontakt/personvern/vilkar).
       SW registreres kun fra
       ansatt.html, men default scope='/' betyr at fetch-events
       fyrer for hele origin — vi BAIL-er ut tidlig for kunde-
       ruter slik at de alltid hentes via nett. Forhindrer at en
       ansatt med installert PWA serverer en stale index.html
       til kunder som bruker samme enhet.
     - network-only for Supabase REST/auth (alltid friske data,
       og pasientdata SKAL aldri caches per CLAUDE.md-regelverk)
     - gammel cache fjernes ved aktivering (versjons-bumping)

   Pasientdata-merknad: vi cacher KUN appens admin-skall. Ingen
   rader fra bookings/journal_entries/audit_log går i cache-objektet.
   ============================================================ */
'use strict';

// Bump ved hver release så ansatte får siste admin-skall etter aktivering.
// P2-4 fra audit 2026-05-15.
var CACHE_VERSION = 'westengen-klinikk-shell-v79';

// Statiske assets som tilhører ADMIN-skallet. Holdes kort så
// versjons-bumping er trygt; alt annet fanges av runtime-cache
// via isAdminShellRequest(). Kunde-ruter er bevisst utelatt —
// './' (= index.html) ble fjernet i audit #6-fiksen.
//
// P3-8 fra audit 2026-05-15: de kundevendte HTML-sidene er bevisst
// IKKE på allow-listen. De skal alltid hentes via nett, samme prinsipp
// som index.html/bestilling.html. Skulle kunde-sidene PWA-installeres
// en gang, bør de caches i en SEPARAT cache-versjon, ikke i admins skall.
//
// MERK: shared/public.css er kundevendt, men ligger under /shared/ og
// fanges derfor av asset-regelen under. Det er akseptert — SW-en gjør
// bakgrunnsoppfriskning, så en stale kopi lever maks én lasting.
var SHELL_ASSETS = [
  './ansatt.html',
  './kalender.html',
  './booking-admin.html',
  './innstillinger.html',
  './kunder.html',
  './kunde-detalj.html',
  './audit-logg.html',
  './stengte-tider.html',
  './tjenester.html',
  './meldinger.html',
  './dokumenter.html',
  './behandlere.html',
  './set-password.html',
  './manifest.json',
  './shared/auth.js',
  './shared/demo-mode.js',
  './shared/booking-config.js',
  './shared/booking-engine.js',
  './shared/booking-flow.js',
  './shared/booking-flow.css',
  './shared/components.js',
  './shared/components.css',
  './shared/gdpr.js',
  './shared/admin-booking.js',
  './shared/admin-nav.js',
  './shared/services.js',
  './icons/icon.svg'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(function (cache) {
      // addAll bryter hele cachen hvis én feiler. Vi vil heller cache
      // det som fungerer og logge resten.
      return Promise.allSettled(SHELL_ASSETS.map(function (url) {
        return cache.add(url).catch(function (err) {
          console.warn('[sw] failed to cache', url, err);
        });
      }));
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (k) {
        if (k !== CACHE_VERSION) return caches.delete(k);
      }));
    }).then(function () { return self.clients.claim(); })
  );
});

// Allow-list approach: kun stier som hører til ADMIN-skallet caches
// og intercepteres. Alt annet (kunde-ruter, kunde-assets, legal-sider,
// kontakt/personvern/vilkar) faller gjennom til nettverk. Forhindrer at SW
// serverer stale customer-facing HTML når en ansatt har PWA installert.
function isAdminShellRequest(url) {
  if (url.origin !== self.location.origin) return false;
  var path = url.pathname;

  // Admin-HTML-sider (positive match — alle andre .html faller gjennom).
  // set-password.html er auth-flow-landings-siden (invite + recovery)
  // og hører til admin-skallet, så den caches sammen med resten.
  if (/\/(ansatt|kalender|booking-admin|innstillinger|kunder|kunde-detalj|audit-logg|stengte-tider|tjenester|meldinger|dokumenter|behandlere|set-password)\.html$/.test(path)) {
    return true;
  }

  // Delte admin-assets (JS/CSS)
  if (path.indexOf('/shared/') !== -1) return true;

  // PWA-infrastruktur
  if (path.indexOf('/icons/') !== -1) return true;
  if (/\/manifest\.json$/.test(path) || path === '/manifest.json') return true;

  // Alt annet (inkludert '/', '/index.html', '/bestilling.html',
  // '/avbestill.html', '/venteliste.html', '/anmeldelser.html',
  // '/kontakt.html', '/personvern.html',
  // '/vilkar.html', '/i18n/*.json' (språkpakker — alltid fra nett så
  // oppdaterte oversettelser ikke blokkeres av en gammel admin-cache),
  // '/assets/*', '/uploads/*', '/sitemap.xml',
  // '/robots.txt') → falses → nettverk-håndteres direkte.
  return false;
}

self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);

  // Supabase-anrop: alltid network-only. Aldri cache pasientdata.
  if (/\.supabase\.co$/.test(url.hostname) || /supabase\.co$/.test(url.hostname)) {
    return;
  }

  // CDN-fetch (Supabase JS, fonts): la nettleseren håndtere via HTTP-cache
  if (url.origin !== self.location.origin) return;

  // Admin-skall: cache-first med network-fallback.
  // Kunde-ruter (index/bestilling/avbestill/...) returnerer
  // false → vi gjør ingenting → browser håndterer normalt via nett.
  if (isAdminShellRequest(url)) {
    event.respondWith(
      caches.match(req).then(function (cached) {
        if (cached) {
          // Background refresh — ikke vent på den
          fetch(req).then(function (fresh) {
            if (fresh && fresh.ok) {
              caches.open(CACHE_VERSION).then(function (c) { c.put(req, fresh); });
            }
          }).catch(function () {});
          return cached;
        }
        return fetch(req).then(function (fresh) {
          if (fresh && fresh.ok) {
            var copy = fresh.clone();
            caches.open(CACHE_VERSION).then(function (c) { c.put(req, copy); });
          }
          return fresh;
        }).catch(function () { return cached; });
      })
    );
  }
});

// ============================================================
// Web Push — ekte varsler når PWA-en er lukket
// ------------------------------------------------------------
// Payload sendes fra edge-funksjonen notify-push og er ALLTID
// persondata-fri (generisk tittel/body — se notify-push/index.ts
// og personvern-regelen i CLAUDE.md). Vi viser bare det vi får.
// ============================================================
self.addEventListener('push', function (event) {
  var payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (e) { payload = {}; }

  var title = payload.title || 'Westengen Klinikk';
  var options = {
    body:  payload.body || 'Du har et nytt varsel. Åpne appen for detaljer.',
    icon:  payload.icon || '/icons/icon-192.png',
    badge: payload.badge || '/icons/icon-192-maskable.png',
    // Vibrasjon hjelper ansatte å merke varselet på mobil.
    vibrate: [120, 60, 120],
    // tag samler/atskiller varsler; renotify gjør at nytt varsel med
    // samme tag fortsatt gir lyd/vibrasjon.
    tag: payload.tag || 'westengen-klinikk',
    renotify: true,
    data: { url: payload.url || '/ansatt.html' }
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Klikk på varsel → fokuser en åpen admin-fane på riktig side, eller
// åpne den. Faller tilbake til ansatt.html.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var target = (event.notification.data && event.notification.data.url) || '/ansatt.html';
  var targetPath = target.replace(/^\.?\//, ''); // normaliser for sammenligning

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        // Allerede en fane på riktig admin-side? Fokuser den.
        if (client.url.indexOf(targetPath) !== -1 && 'focus' in client) {
          return client.focus();
        }
      }
      // Ellers: fokuser en hvilken som helst åpen admin-fane og naviger,
      // eller åpne et nytt vindu.
      for (var j = 0; j < clientList.length; j++) {
        var c = clientList[j];
        if ('focus' in c && 'navigate' in c) {
          return c.focus().then(function () { return c.navigate(target); }).catch(function () {});
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    })
  );
});
