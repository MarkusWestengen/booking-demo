/* ============================================================
   Westengen Klinikk — Cookie consent banner
   ------------------------------------------------------------
   GDPR-rammeverk (Markus-feedback 2026-05-30). Per i dag har siden
   INGEN ikke-essensielle cookies/tracking, så banneret er primært
   strukturen som må være på plass før vi evt. legger til
   Google Analytics, Meta Pixel, e.l.

   - Vises kun ved første besøk (sjekker localStorage)
   - 3 valg: Aksepter alle / Kun nødvendige / Tilpass
   - "Tilpass" linker til personvern.html#cookies inntil videre
     (ingen full toggle-UI ennå — kommer når vi har tracking å toggle)
   - Lagres som JSON med { value, ts } så vi senere kan re-prompt
     ved policy-endringer

   Lastet inn på alle kunde-fasende sider via vanlig script-tag
   (defer). Ikke i admin-skall — admin-brukere får ikke banner.
   ============================================================ */
(function () {
  'use strict';

  var STORAGE_KEY = 'tas-cookie-consent';

  // Hvis brukeren allerede har valgt, vis ikke banner.
  try {
    if (localStorage.getItem(STORAGE_KEY)) return;
  } catch (_) {
    // localStorage utilgjengelig (privacy/incognito-edge-cases) — vis
    // banner men aksepter at valg ikke kan persisteres mellom besøk.
  }

  function t(key, fb) {
    return (window.WestengenKlinikkI18n && typeof window.WestengenKlinikkI18n.t === 'function')
      ? window.WestengenKlinikkI18n.t(key, fb)
      : fb;
  }

  function setConsent(value) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ value: value, ts: Date.now() }));
    } catch (_) {}
    var b = document.querySelector('.tas-cookie-banner');
    if (!b) return;
    b.classList.add('tas-cookie-hidden');
    setTimeout(function () {
      if (b.parentNode) b.parentNode.removeChild(b);
    }, 300);
  }

  function renderBanner() {
    var banner = document.createElement('div');
    banner.className = 'tas-cookie-banner';
    banner.setAttribute('role', 'dialog');
    banner.setAttribute('aria-labelledby', 'tas-cookie-title');
    banner.setAttribute('aria-describedby', 'tas-cookie-body');

    // innerHTML er trygt her — alt innhold er repo-kontrollert. i18n.js
    // overskriver tekst via data-i18n etter at translate(banner) kalles.
    banner.innerHTML =
      '<div class="tas-cookie-inner">' +
      '  <div class="tas-cookie-text">' +
      '    <h3 id="tas-cookie-title" data-i18n="cookie.title">Vi respekterer ditt personvern</h3>' +
      '    <p id="tas-cookie-body" data-i18n-html="cookie.body">Vi bruker kun nødvendige cookies for at booking og språkvalg skal fungere. Vi har ingen sporing eller markedsføringsverktøy. <a href="personvern.html#cookies">Les mer i personvernerklæringen.</a></p>' +
      '  </div>' +
      '  <div class="tas-cookie-actions">' +
      '    <button type="button" class="tas-cookie-btn tas-cookie-btn-secondary" data-action="customize" data-i18n="cookie.customize">Tilpass</button>' +
      '    <button type="button" class="tas-cookie-btn tas-cookie-btn-secondary" data-action="essential_only" data-i18n="cookie.essential_only">Kun nødvendige</button>' +
      '    <button type="button" class="tas-cookie-btn tas-cookie-btn-primary" data-action="accept_all" data-i18n="cookie.accept_all">Aksepter alle</button>' +
      '  </div>' +
      '</div>';

    document.body.appendChild(banner);

    banner.addEventListener('click', function (e) {
      var btn = e.target && e.target.closest ? e.target.closest('[data-action]') : null;
      if (!btn) return;
      var action = btn.getAttribute('data-action');
      if (action === 'customize') {
        // Inntil videre: redirect til personvern.html#cookies. Full
        // toggle-UI legges til når vi har faktiske ikke-essensielle
        // cookies å toggle (Google Analytics, Meta Pixel, e.l.).
        window.location.href = 'personvern.html#cookies';
        return;
      }
      setConsent(action); // 'accept_all' eller 'essential_only'
    });

    // Oversett umiddelbart hvis i18n er klar.
    if (window.WestengenKlinikkI18n && typeof window.WestengenKlinikkI18n.translate === 'function') {
      window.WestengenKlinikkI18n.translate(banner);
    } else {
      // i18n er ikke klar ennå — den fyrer 'westengen-klinikk:language-changed'
      // ved boot, da plukker translate() også opp banneret (det er i body).
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', renderBanner);
  } else {
    renderBanner();
  }
})();
