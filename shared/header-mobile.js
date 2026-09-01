/* ============================================================
   Westengen Klinikk — Mobil-meny toggle (hamburger overlay)
   ------------------------------------------------------------
   Aktiverer hamburger-knapp + full-screen overlay-meny på
   mobil (CSS-breakpoint ≤900px styrer synlighet av knappen).

   Forventet markup:
     <button class="nav-hamburger" aria-controls="navMobile" ...>
     <div class="nav-mobile" id="navMobile" hidden>
       <button class="nav-mobile-close">×</button>
       <nav class="nav-mobile-links"> ... <a/>... </nav>
       <div class="nav-mobile-cta"> ... <a/>... </div>
     </div>

   Lukke-mekanikker: hamburger-toggle, ESC, klikk på overlay-
   bakgrunn, klikk på lukke-knapp, klikk på et nav-item.
   ============================================================ */
(function () {
  'use strict';

  function init() {
    var hamburger = document.querySelector('.nav-hamburger');
    var menu = document.getElementById('navMobile');
    if (!hamburger || !menu) return;
    var closeBtn = menu.querySelector('.nav-mobile-close');
    var links = menu.querySelectorAll('.nav-mobile-links a, .nav-mobile-cta a');
    var lastFocus = null;

    function openMenu() {
      if (menu.classList.contains('open')) return;
      lastFocus = document.activeElement;
      menu.removeAttribute('hidden');
      // Force reflow så opacity-fade trigges (ellers hopper den til 1).
      void menu.offsetWidth;
      menu.classList.add('open');
      hamburger.setAttribute('aria-expanded', 'true');
      document.body.style.overflow = 'hidden';
      // Vent på fade før fokus så skjermlesere ikke kunngjør et
      // usynlig element.
      setTimeout(function () {
        var first = menu.querySelector('.nav-mobile-links a');
        if (first) first.focus();
      }, 160);
    }
    function closeMenu() {
      if (!menu.classList.contains('open')) return;
      menu.classList.remove('open');
      hamburger.setAttribute('aria-expanded', 'false');
      document.body.style.overflow = '';
      setTimeout(function () { menu.setAttribute('hidden', ''); }, 160);
      if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus();
      else hamburger.focus();
    }
    hamburger.addEventListener('click', function () {
      if (menu.classList.contains('open')) closeMenu();
      else openMenu();
    });
    if (closeBtn) closeBtn.addEventListener('click', closeMenu);
    menu.addEventListener('click', function (e) {
      if (e.target === menu) closeMenu();
    });
    links.forEach(function (a) { a.addEventListener('click', closeMenu); });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && menu.classList.contains('open')) closeMenu();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
