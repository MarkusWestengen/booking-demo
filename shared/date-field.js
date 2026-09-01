/* ============================================================
   date-field.js — hele datofeltet åpner kalenderen
   ------------------------------------------------------------
   PROBLEMET
   Et <input type="date"> viser et lite kalenderikon i høyre kant.
   I Chrome er det bare det ikonet som åpner datovelgeren; treffer
   du feltet noen piksler ved siden av, skjer ingenting. Feltet ser
   ut som en knapp i hele sin bredde, men oppfører seg som en knapp
   bare i de siste tjue pikslene. Folk klikker, ingenting skjer, og
   de klikker igjen.

   LØSNINGEN
   showPicker() er standardisert (HTML Living Standard) og åpner
   den samme native velgeren. Vi kaller den når feltet klikkes, så
   hele flaten gjør det den ser ut som den skal gjøre.

   HVORFOR BARE KLIKK
   Tastaturet er allerede i orden uten hjelp fra oss: piltaster
   endrer segmentene, og feltet er fokuserbart. Å binde Enter eller
   mellomrom ville tatt over taster som allerede har en jobb, og
   Enter i et skjema skal sende det.

   showPicker() krever en brukerhandling og kaster hvis den kalles
   uten, eller hvis velgeren allerede står åpen. Begge deler er
   ufarlige, så kallet står i en try/catch og feiler stille: da
   oppfører feltet seg som før, ikke dårligere.

   Nye felt som rendres inn etterpå (adminpanelet bygger rader
   dynamisk) fanges av en MutationObserver.
   ============================================================ */
(function () {
  'use strict';

  var SEL = 'input[type="date"], input[type="time"], input[type="datetime-local"], ' +
            'input[type="month"], input[type="week"]';

  function openPicker(el) {
    if (!el || el.disabled || el.readOnly) return;
    try {
      if (typeof el.showPicker === 'function') el.showPicker();
    } catch (_) {
      /* Ingen brukerhandling, eller allerede åpen. Native oppførsel
         tar over; feltet blir ikke verre enn det var. */
    }
  }

  function onClick(e) { openPicker(e.currentTarget); }

  function wire(root) {
    var els;
    try { els = (root || document).querySelectorAll(SEL); } catch (_) { return; }
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (el.getAttribute('data-wk-picker')) continue;
      el.setAttribute('data-wk-picker', '1');
      el.addEventListener('click', onClick);
    }
  }

  function boot() {
    // Peker-markør på hele feltet, så det ser klikkbart ut i hele
    // bredden og ikke bare der ikonet står.
    var st = document.createElement('style');
    st.textContent =
      'input[type="date"],input[type="time"],input[type="datetime-local"],' +
      'input[type="month"],input[type="week"]{cursor:pointer;}' +
      'input[type="date"]:disabled,input[type="time"]:disabled{cursor:not-allowed;}' +
      /* Ikonet beholdes, men det er ikke lenger den eneste veien inn. */
      'input[type="date"]::-webkit-calendar-picker-indicator,' +
      'input[type="time"]::-webkit-calendar-picker-indicator{cursor:pointer;}';
    document.head.appendChild(st);

    wire(document);

    if (typeof MutationObserver === 'function') {
      new MutationObserver(function (muts) {
        for (var i = 0; i < muts.length; i++) {
          var added = muts[i].addedNodes;
          for (var j = 0; j < added.length; j++) {
            if (added[j].nodeType === 1) wire(added[j]);
          }
        }
      }).observe(document.documentElement, { childList: true, subtree: true });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
