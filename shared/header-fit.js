(function (root, doc) {
  'use strict';

  // ============================================================
  // Naar skal headeren kollapse til hamburgermeny?
  // ------------------------------------------------------------
  // Svaret laa i et tall: 1024 px. Tallet var valgt for den norske
  // teksten. Paa engelsk er lenkene bredere («Book an appointment»,
  // «Cancel appointment», «Waiting list», «Contact», «Admin panel»),
  // og et fast tall kan ikke vite det. Det kan heller ikke vite hvor
  // lang en oversettelse blir neste gang.
  //
  // Her maales det i stedet. Faar lenkene plass ved siden av
  // merkenavnet og knappene, blir de staaende. Ellers gaar de inn i
  // menyen, som allerede finnes og allerede inneholder dem.
  //
  // Media-spoerringen i CSS-en staar urort og er fortsatt gulvet:
  // paa telefon kollapser headeren uansett hva denne fila mener.
  // Dette er bare et tillegg over det gulvet.
  // ============================================================

  var KLASSE = 'wk-nav-trang';

  function leggInnStil() {
    if (doc.getElementById('wkNavFitCss')) return;
    var st = doc.createElement('style');
    st.id = 'wkNavFitCss';
    // .nav.wk-nav-trang .nav-links er (0,3,0) og slaar sidenes egen
    // .nav-links { display: flex } uten !important.
    st.textContent =
      '.nav.' + KLASSE + '{grid-template-columns:1fr auto;}' +
      '.nav.' + KLASSE + ' .nav-links{display:none;}' +
      '.nav.' + KLASSE + ' .nav-hamburger{display:inline-flex;}';
    doc.head.appendChild(st);
  }

  function tall(v) { var n = parseFloat(v); return n === n ? n : 0; }

  // Summen av barna pluss mellomrommene mellom dem: det lenkene
  // trenger, uavhengig av hvor mye plass de har faatt.
  function naturligBredde(boks) {
    var barn = boks.children, sum = 0, n = 0;
    for (var i = 0; i < barn.length; i++) {
      var cs = root.getComputedStyle(barn[i]);
      if (cs.display === 'none') continue;
      sum += barn[i].offsetWidth + tall(cs.marginLeft) + tall(cs.marginRight);
      n++;
    }
    var bs = root.getComputedStyle(boks);
    return sum + (n > 1 ? tall(bs.columnGap || bs.gap) * (n - 1) : 0);
  }

  function vurder() {
    var nav = doc.querySelector('.nav');
    if (!nav) return;
    var lenker = nav.querySelector('.nav-links');
    if (!lenker) return;

    // Maal alltid i utgangsstilling, ellers maaler vi vaar egen
    // forrige beslutning.
    nav.classList.remove(KLASSE);

    // Har CSS-en alt kollapset headeren (telefonbredde), er det
    // ingenting aa vurdere.
    if (root.getComputedStyle(lenker).display === 'none') return;

    var merke = nav.querySelector('.wk-brand-group') || nav.querySelector('.brand');
    var cta = nav.querySelector('.nav-cta');
    var cs = root.getComputedStyle(nav);
    var mellomrom = tall(cs.columnGap || cs.gap);

    var opptatt = (merke ? merke.offsetWidth : 0) +
                  (cta ? cta.offsetWidth : 0) +
                  mellomrom * 2;
    var plass = nav.clientWidth - tall(cs.paddingLeft) - tall(cs.paddingRight) - opptatt;

    // Foerste forsoek her leste lenker.scrollWidth. Det var feil:
    // naar innholdet er smalere enn boksen, gir scrollWidth boksen,
    // ikke innholdet. Lenkecella er «1fr» og altsaa akkurat saa bred
    // som det som er igjen — sammenligningen ble «plass > plass», og
    // avrunding avgjorde. Headeren kollapset paa 1920 px.
    //
    // Vi maaler barna i stedet. De har ingen flex-grow, saa bredden
    // deres ER innholdsbredden.
    // De 8 pikslene er pusterom mot avrunding, ikke et valgt
    // bruddpunkt: uten dem kan en halv piksel avgjoere.
    if (naturligBredde(lenker) > plass - 8) nav.classList.add(KLASSE);
  }

  var planlagt = null;
  function planlegg() {
    if (planlagt) root.cancelAnimationFrame(planlagt);
    planlagt = root.requestAnimationFrame(function () { planlagt = null; vurder(); });
  }

  function start() {
    leggInnStil();
    vurder();
    root.addEventListener('resize', planlegg);
    // Spraakbytte endrer lengden paa lenkene. i18n-laget bytter
    // lang-attributtet paa <html> naar det er ferdig, saa den er et
    // paalitelig signal — og det virker ogsaa hvis oversettelsene
    // lastes ferdig etter oss.
    if (root.MutationObserver) {
      new root.MutationObserver(planlegg).observe(doc.documentElement, {
        attributes: true, attributeFilter: ['lang']
      });
    }
    // Skriften kan komme etter at vi har maalt foerste gang.
    if (doc.fonts && doc.fonts.ready && doc.fonts.ready.then) {
      doc.fonts.ready.then(planlegg);
    }
    root.setTimeout(planlegg, 400);
  }

  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})(window, document);
