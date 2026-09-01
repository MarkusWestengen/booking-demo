/* ============================================================
   Westengen Klinikk — shared modals + chatbot
   Drop on any page after the page's own DOM. Self-mounts.
   Auto-wires:
     - <a data-book="markus"> / data-book="henrik" / data-book="general"
       → opens booking modal
     - <a data-contact="open"> → opens contact modal
   Also exposes window.WestengenKlinikk.openBooking(who),
     window.WestengenKlinikk.openContact(prefill), window.WestengenKlinikk.openChat()
   ============================================================ */
(function () {
  'use strict';

  // P1-5: leses fra WestengenKlinikkConfig hvis booking-config.js er lastet før
  // dette scriptet (vanlig page-load-rekkefølge). Fallback bevarer
  // tidligere hardkodede verdier slik at standalone-bruk fortsatt funker.
  var CFG = window.WestengenKlinikkConfig || {};
  var EMAIL = CFG.CLINIC_EMAIL || 'post@westengenklinikk.example';
  var PHONE = CFG.CLINIC_PHONE || '+47 400 00 000';

  // Timing-konstanter for UI-effekter (P3-2 fra audit 2026-05-15).
  // Eksplisitt navngitt slik at fremtidig justering ikke trenger å gjette
  // hva «1800»/«2400» betyr.
  var CHAT_PULSE_DELAY_MS = 1800;        // første-besøk-puls på chat-knapp
  var CONTACT_THANKS_DURATION_MS = 2400; // hvor lenge "Takk!"-meldingen vises før lukking

  // ----- helpers --------------------------------------------------
  function el(html) {
    var d = document.createElement('div');
    d.innerHTML = html.trim();
    return d.firstChild;
  }
  function on(node, ev, sel, fn) {
    if (typeof sel === 'function') { node.addEventListener(ev, sel); return; }
    node.addEventListener(ev, function (e) {
      var t = e.target.closest(sel);
      if (t && node.contains(t)) fn.call(t, e, t);
    });
  }
  function trapFocus(container) {
    var focusables = container.querySelectorAll('button,[href],input,textarea,select,[tabindex]:not([tabindex="-1"])');
    if (!focusables.length) return;
    var first = focusables[0], last = focusables[focusables.length - 1];
    container.addEventListener('keydown', function (e) {
      if (e.key !== 'Tab') return;
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    });
  }

  // i18n-helper: live oppslag via WestengenKlinikkI18n, faller tilbake til
  // norsk streng hvis i18n ikke er lastet.
  function bt(key, fb) {
    return (window.WestengenKlinikkI18n && typeof window.WestengenKlinikkI18n.t === 'function')
      ? window.WestengenKlinikkI18n.t(key, fb) : fb;
  }

  // ============ BOOKING MODAL =====================================
  var bookingHTML = ''
    + '<div class="tas-modal-overlay booking-overlay" role="dialog" aria-modal="true" aria-labelledby="booking-title">'
    + '  <div class="tas-modal booking-modal">'
    + '    <div class="tas-modal-head">'
    + '      <h2 class="tas-modal-title" id="booking-title">Bestill <em>time</em></h2>'
    + '      <button class="tas-modal-close" aria-label="Lukk booking" data-i18n-aria-label="booking.modal.close_aria" data-close>×</button>'
    + '    </div>'
    + '    <div class="tas-modal-body">'
    + '      <div class="booking-flow-host" data-flow-host></div>'
    + '    </div>'
    + '  </div>'
    + '</div>';

  var bookingNode = el(bookingHTML);
  document.body.appendChild(bookingNode);
  var bookingFlowHost = bookingNode.querySelector('[data-flow-host]');
  var bookingTitle = bookingNode.querySelector('#booking-title');

  // Bygger modal-tittelen via i18n-keys (pre + emfasert del). DOM-bygget
  // i stedet for innerHTML — pre/em er repo-kontrollerte i18n-verdier.
  function setBookingTitle(variant, fbPre, fbEm) {
    var pre = bt('booking.modal.title_' + variant + '_pre', fbPre);
    var em = bt('booking.modal.title_' + variant + '_em', fbEm);
    bookingTitle.textContent = pre + ' ';
    var emEl = document.createElement('em');
    emEl.textContent = em;
    bookingTitle.appendChild(emEl);
  }

  function openBooking(who) {
    who = who || 'general';
    // Map old 'henrik' alias to new 'terapeut' staff id
    var initialStaff = null;
    if (who === 'markus') {
      initialStaff = 'markus';
      setBookingTitle('markus', 'Bestill', 'time med Markus');
    } else if (who === 'henrik' || who === 'terapeut') {
      initialStaff = 'terapeut';
      setBookingTitle('terapeut', 'Bestill', 'time med terapeut');
    } else {
      setBookingTitle('general', 'Bestill', 'time');
    }

    if (window.WestengenKlinikkBookingFlow) {
      window.WestengenKlinikkBookingFlow.mount(bookingFlowHost, { initialStaff: initialStaff });
    } else {
      bookingFlowHost.innerHTML = '<div style="padding:40px;text-align:center;color:#5c4d46;">' + bt('booking.system_unavailable', 'Booking-systemet kunne ikke lastes. Ring oss på ' + PHONE + '.') + '</div>';
    }

    bookingNode.classList.add('open');
    document.body.style.overflow = 'hidden';
    setTimeout(function () { bookingNode.querySelector('[data-close]').focus(); }, 50);
  }
  function closeBooking() {
    bookingNode.classList.remove('open');
    document.body.style.overflow = '';
  }
  on(bookingNode, 'click', '[data-close]', closeBooking);
  bookingNode.addEventListener('click', function (e) {
    if (e.target === bookingNode) closeBooking();
  });
  trapFocus(bookingNode);

  // ============ CONTACT MODAL =====================================
  var contactHTML = ''
    + '<div class="tas-modal-overlay contact-overlay" role="dialog" aria-modal="true" aria-labelledby="contact-title">'
    + '  <div class="tas-modal contact-modal">'
    + '    <div class="tas-modal-head">'
    + '      <h2 class="tas-modal-title" id="contact-title">Send <em>melding</em></h2>'
    + '      <button class="tas-modal-close" aria-label="Lukk skjema" data-close>×</button>'
    + '    </div>'
    + '    <div class="tas-modal-body">'
    + '      <p class="contact-form-intro">Send en melding direkte til Markus. Han svarer så snart han kan, vanligvis innen et døgn.</p>'
    + '      <form data-contact-form>'
    + '        <div class="tas-form-row row-2">'
    + '          <div><label for="ct-name">Navn</label><input id="ct-name" name="name" required /></div>'
    + '          <div><label for="ct-phone">Telefon</label><input id="ct-phone" name="phone" type="tel" /></div>'
    + '        </div>'
    + '        <div class="tas-form-row"><label for="ct-email">E-post</label><input id="ct-email" name="email" type="email" required /></div>'
    + '        <div class="tas-form-row"><label for="ct-message">Melding</label><textarea id="ct-message" name="message" required placeholder="Beskriv kort hva du sliter med, så svarer Markus deg."></textarea></div>'
    + '        <button type="submit" class="tas-form-submit">Send melding <span aria-hidden="true">→</span></button>'
    + '      </form>'
    + '      <div class="tas-form-thanks" data-thanks>Takk! Markus har mottatt meldingen din og svarer så snart han kan.</div>'
    + '    </div>'
    + '  </div>'
    + '</div>';
  var contactNode = el(contactHTML);
  document.body.appendChild(contactNode);
  var contactForm = contactNode.querySelector('[data-contact-form]');
  var contactThanks = contactNode.querySelector('[data-thanks]');

  function openContact(prefill) {
    if (prefill && prefill.message) {
      contactNode.querySelector('#ct-message').value = prefill.message;
    }
    contactThanks.classList.remove('show');
    contactForm.style.display = '';
    contactNode.classList.add('open');
    document.body.style.overflow = 'hidden';
    setTimeout(function () { contactNode.querySelector('#ct-name').focus(); }, 50);
  }
  function closeContact() {
    contactNode.classList.remove('open');
    document.body.style.overflow = '';
  }
  on(contactNode, 'click', '[data-close]', closeContact);
  contactNode.addEventListener('click', function (e) {
    if (e.target === contactNode) closeContact();
  });
  contactForm.addEventListener('submit', function (e) {
    e.preventDefault();
    // In production this POSTs to a backend. For demo: mailto fallback + thanks state.
    var data = new FormData(contactForm);
    var body = 'Navn: ' + data.get('name') + '\nTelefon: ' + (data.get('phone') || '(ikke oppgitt)') + '\nE-post: ' + data.get('email') + '\n\n' + data.get('message');
    // Best-effort: open mailto in background tab; not strictly needed for prototype
    try {
      window.open('mailto:' + EMAIL + '?subject=' + encodeURIComponent('Henvendelse via westengenklinikk.example') + '&body=' + encodeURIComponent(body), '_blank');
    } catch (_) {}
    contactForm.style.display = 'none';
    contactThanks.classList.add('show');
    setTimeout(closeContact, CONTACT_THANKS_DURATION_MS);
  });
  trapFocus(contactNode);

  // ============ ESC KEY ==========================================
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    if (bookingNode.classList.contains('open')) closeBooking();
    else if (contactNode.classList.contains('open')) closeContact();
    else if (chatNode && chatNode.classList.contains('open')) closeChat();
  });

  // ============ AUTO-WIRE TRIGGERS ===============================
  document.addEventListener('click', function (e) {
    var bk = e.target.closest('[data-book]');
    if (bk) {
      e.preventDefault();
      openBooking(bk.getAttribute('data-book'));
      return;
    }
    var ct = e.target.closest('[data-contact="open"]');
    if (ct) {
      e.preventDefault();
      openContact();
    }
  });

  // ============ CHATBOT WIDGET ===================================
  var chatHTML = ''
    + '<div class="tas-chat" id="tasChat">'
    + '  <div class="tas-chat-panel" role="dialog" aria-label="Demoguide">'
    + '    <div class="tas-chat-head">'
    + '      <div class="tas-chat-head-text">'
    + '        <h3 class="tas-chat-head-title">Demoguide</h3>'
    + '        <div class="tas-chat-head-status">Forhåndsdefinerte svar</div>'
    + '      </div>'
    + '      <button class="tas-chat-close" aria-label="Lukk chat" data-chat-close>×</button>'
    + '    </div>'
    + '    <div class="tas-chat-disclaimer" role="note">'
    + '      Skriv ikke personopplysninger her. Dette er en demo, og alt du sender er synlig for alle som logger inn.'
    + '    </div>'
    + '    <div class="tas-chat-body" data-chat-body></div>'
    + '    <div class="tas-quick-replies" data-quick></div>'
    + '    <form class="tas-chat-input" data-chat-form>'
    + '      <input type="text" placeholder="Skriv et spørsmål…" data-chat-input aria-label="Skriv et spørsmål" />'
    + '      <button type="submit" class="tas-chat-send" aria-label="Send" data-chat-send>'
    + '        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M22 2L11 13"/><path d="M22 2l-7 20-4-9-9-4 20-7z"/></svg>'
    + '      </button>'
    + '    </form>'
    + '  </div>'
    + '  <button class="tas-chat-btn" aria-expanded="false" aria-label="Åpne demoguide" data-chat-toggle>'
    + '    <svg class="icon-chat" viewBox="0 0 24 24" fill="none" aria-hidden="true">'
    +      '<path d="M20.4 14.9a2.1 2.1 0 0 1-2.1 2.1H8.7L4.2 20.6V5.9a2.1 2.1 0 0 1 2.1-2.1h12a2.1 2.1 0 0 1 2.1 2.1z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>'
    +      '<circle cx="8.8" cy="10.4" r="1.05" fill="currentColor"/>'
    +      '<circle cx="12.3" cy="10.4" r="1.05" fill="currentColor"/>'
    +      '<circle cx="15.8" cy="10.4" r="1.05" fill="currentColor"/>'
    +      '</svg>'
    + '    <span class="pulse" data-pulse></span>'
    + '  </button>'
    + '</div>';
  var chatNode = el(chatHTML);
  document.body.appendChild(chatNode);
  var chatBody = chatNode.querySelector('[data-chat-body]');
  var chatQuick = chatNode.querySelector('[data-quick]');
  var chatForm = chatNode.querySelector('[data-chat-form]');
  var chatInput = chatNode.querySelector('[data-chat-input]');
  var chatSend = chatNode.querySelector('[data-chat-send]');
  var chatToggle = chatNode.querySelector('[data-chat-toggle]');
  var chatPulse = chatNode.querySelector('[data-pulse]');

  // First-visit pulse
  try {
    if (!sessionStorage.getItem('tas_chat_seen')) {
      setTimeout(function () { chatPulse.classList.add('show'); }, CHAT_PULSE_DELAY_MS);
    }
  } catch (_) {}

  // System prompt — kept here so prototype works with window.claude.complete().
  // In production, this same string lives server-side.
  var SYSTEM_PROMPT = [
    'Du er "Markus\' assistent", en hjelpsom kundeservice-bot for Westengen Klinikk, en muskel- og nervebehandlingsklinikk i Oslo, drevet av Markus Westengen (40 års erfaring) og sønnen Henrik.',
    '',
    'NØKKELFAKTA:',
    '• Adresse: Storgata 1, 0155 Oslo.',
    '• Telefon: ' + PHONE + '. E-post: ' + EMAIL + '.',
    '• Åpningstider klinikk: Man–Fre 07:00–15:00. Lørdag/Søndag stengt.',
    '• Telefontid: Man–Fre 09:00–15:00.',
    '• Avbestilling senest 24 timer før timen. No-show faktureres.',
    '',
    'TJENESTER:',
    '• Time med Markus: konsultasjon kr 4 000, videre behandling kr 3 000. 30 min.',
    '• Time med terapeut: konsultasjon kr 2 000, videre behandling kr 1 500. 30 min. Markus\' terapeuter, opplært i Markus\' metode.',
    '',
    'MARKUS\' FILOSOFI:',
    'Kroppen er ett sammenkoblet system. Smerter ett sted skyldes nesten alltid spenninger et annet sted. Markus finner årsaken, ikke bare symptomet.',
    '',
    'PLAGER KLINIKKEN BEHANDLER:',
    'Rygg-, nakke- og skulderspenninger, hodepine, muskelskader hos idrettsutøvere, stive hofter, kne- og ankelproblemer, mageplager forårsaket av spenninger, nervesmerter, søvnproblemer knyttet til kroppslig stress.',
    '',
    'DEMO: Westengen Klinikk er en oppdiktet klinikk. Alle behandlere, kunder og bestillinger er fiktive. '
      + 'Sier brukeren noe som tyder på at de tror klinikken er ekte, si det rett ut.',
    '',
    'TONE: profesjonell, varm, kortfattet. Svar på samme språk som brukeren skriver (norsk standard).',
    '',
    'REGLER:',
    '• Aldri gi medisinske råd. Ved spesifikke plager: "Det beste er å bestille en time så Markus kan vurdere deg direkte."',
    '• Hvis du ikke kan svare: foreslå at brukeren sender melding via kontaktskjemaet.',
    '• Hold svar korte (2–4 setninger maks).',
    '• For booking: foreslå at de klikker "Bestill time"-knappen på siden.'
  ].join('\n');

  function appendMessage(text, who) {
    var msg = document.createElement('div');
    msg.className = 'tas-msg tas-msg-' + (who || 'bot');
    // Convert links + line breaks
    // Escape også " og ' FØR linkify — ellers kan en URL som inneholder
    // anførselstegn bryte ut av href-attributtet (self-XSS, revisjon
    // 2026-06-12 D-LAV). Etter escaping kan $1 ikke inneholde attributt-
    // brytende tegn.
    var html = (text || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
      .replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br/>');
    msg.innerHTML = '<p>' + html + '</p>';
    chatBody.appendChild(msg);
    chatBody.scrollTop = chatBody.scrollHeight;
    return msg;
  }
  function showTyping() {
    var t = document.createElement('div');
    t.className = 'tas-typing';
    t.innerHTML = '<span></span><span></span><span></span>';
    t.dataset.typing = '1';
    chatBody.appendChild(t);
    chatBody.scrollTop = chatBody.scrollHeight;
    return t;
  }

  // Quick replies — both prefilled answers AND a fallback path for fri tekst
  // Hurtigsvarene navigerer DEMOEN, ikke en klinikks tjenestemeny.
  // Den som apner denne chatten vurderer et system; sporsmalene deres
  // handler om hva de ser pa og hvordan de kommer videre.
  var QUICK_REPLIES = [
    { label: 'Hva er dette?', q: 'Hva er dette?' },
    { label: 'Hvordan logger jeg inn?', q: 'Hvordan logger jeg inn?' },
    { label: 'Er dataene ekte?', q: 'Er dataene ekte?' },
    { label: 'Bestill time', action: 'book' }
  ];
  function renderQuickReplies(list) {
    chatQuick.innerHTML = '';
    list.forEach(function (qr) {
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = qr.label;
      b.addEventListener('click', function () {
        if (qr.action === 'book') {
          closeChat();
          openBooking('general');
          return;
        }
        appendMessage(qr.q, 'user');
        chatQuick.innerHTML = '';
        handleUserMessage(qr.q);
      });
      chatQuick.appendChild(b);
    });
  }

  // Conversation memory (session only, privacy)
  var conversation = [];
  var failedAttempts = 0;

  function loadHistory() {
    try {
      var saved = sessionStorage.getItem('tas_chat_history');
      if (saved) {
        conversation = JSON.parse(saved);
        conversation.forEach(function (m) { appendMessage(m.content, m.role === 'user' ? 'user' : 'bot'); });
      }
    } catch (_) {}
  }
  function saveHistory() {
    try { sessionStorage.setItem('tas_chat_history', JSON.stringify(conversation.slice(-20))); } catch (_) {}
  }

  // Static fallback answers for when Claude API isn't available.
  // Keyed by simple keyword match.
  function staticAnswer(q) {
    var s = q.toLowerCase();
    if (/(hva er dette|hva du|demo|arbeidspr|portef)/.test(s)) {
      return 'Dette er et bookingsystem vist fram som arbeidsprove. Kundeflyten kan du klikke gjennom her; resten \u2014 kalender, kunderegister, journal og audit-logg \u2014 ligger bak innloggingen, og den er publisert pa forsiden.';
    }
    if (/(logg|innlogg|passord|konto|bruker|admin)/.test(s)) {
      return 'Innloggingen star apent pa forsiden. Det er to kontoer: en administrator og en terapeut. Logg inn med begge \u2014 forskjellen mellom dem er poenget, ikke en detalj.';
    }
    if (/(ekte|virkelig|fiktiv|oppdiktet|data|personer|finnes)/.test(s)) {
      return 'Nei. Klinikken, behandlerne, kundene og alle bestillinger er oppdiktet. E-postadressene ligger pa .example, et toppdomene som aldri kan registreres. Skriv likevel ikke inn noe ekte \u2014 det du legger inn er synlig for alle som logger inn.';
    }
    if (/(pris|kost|hva.+koster|hvor mye)/.test(s)) {
      return 'Prisene ligger i databasen, ikke i koden: konsultasjon kr 4 000 eller kr 2 000 avhengig av behandler, videre behandling kr 3 000 eller kr 1 500. Alle timer er 30 minutter. En administrator kan endre dem i adminpanelet uten ny utrulling.';
    }
    if (/(apning|apent|nar|tid|time.+lang)/.test(s)) {
      return 'Bookingmotoren regner med mandag\u2013fredag 07:00\u201315:00, i luker pa 30 minutter. Helger er stengt. Ledige tider genereres fra disse rammene og fra det som allerede er booket.';
    }
    if (/(avbest|kansell)/.test(s)) {
      return 'Avbestilling gar inntil 24 timer for timen, med referansekoden fra bekreftelsen. Du kan prove det: bestill en time, og bruk koden pa avbestillingssiden.';
    }
    if (/(bestil|book|reserv)/.test(s)) {
      return 'Bruk \u00abBestill time\u00bb. Du velger behandler, tjeneste og tidspunkt, og far en referansekode til slutt. Bestillingen din blir en helt vanlig rad du kan endre og slette \u2014 i motsetning til radene som fulgte med demoen.';
    }
    if (/(nullstill|slett|reset|forsvinner|lagres)/.test(s)) {
      return 'Alt du legger inn slettes ved den nattlige nullstillingen. Radene som fulgte med demoen er skrivebeskyttet i databasen: knappene virker, men lagringen avvises med en forklaring, slik at panelet ser likt ut for neste besokende.';
    }
    return null;
  }

  function handleUserMessage(text) {
    conversation.push({ role: 'user', content: text });
    var typing = showTyping();

    function reply(answer, isStatic) {
      typing.remove();
      appendMessage(answer, 'bot');
      conversation.push({ role: 'assistant', content: answer });
      saveHistory();
      // After answer, restore quick replies
      renderQuickReplies(QUICK_REPLIES);
    }

    function escalate() {
      typing.remove();
      var msg = 'Jeg vil gjerne hjelpe deg, men dette spørsmålet er litt utenfor det jeg kan svare på direkte. Vil du sende en melding direkte til Markus?';
      appendMessage(msg, 'bot');
      conversation.push({ role: 'assistant', content: msg });
      // Custom CTA quick reply
      chatQuick.innerHTML = '';
      var b = document.createElement('button');
      b.type = 'button';
      b.textContent = 'Send melding til Markus →';
      b.addEventListener('click', function () {
        closeChat();
        openContact({ message: 'Spørsmål fra chatbot:\n\n' + text });
      });
      chatQuick.appendChild(b);
      saveHistory();
    }

    // 1) Try window.claude.complete() if available
    if (window.claude && typeof window.claude.complete === 'function') {
      var messages = [{
        role: 'user',
        content: 'Systeminstruksjon (følg dette strikt):\n' + SYSTEM_PROMPT + '\n\n--- Samtale ---\n' +
          conversation.map(function (m) { return (m.role === 'user' ? 'Bruker' : 'Assistent') + ': ' + m.content; }).join('\n')
      }];
      window.claude.complete({ messages: messages }).then(function (answer) {
        if (!answer || !answer.trim()) {
          // Fallback path
          var st = staticAnswer(text);
          if (st) { failedAttempts = 0; reply(st); }
          else { failedAttempts++; if (failedAttempts >= 2) escalate(); else reply('Kan du formulere spørsmålet litt annerledes? Jeg kan svare på pris, åpningstider, plager Markus behandler og bestilling.'); }
        } else {
          failedAttempts = 0;
          reply(answer.trim());
        }
      }).catch(function () {
        var st = staticAnswer(text);
        if (st) { failedAttempts = 0; reply(st); }
        else { failedAttempts++; if (failedAttempts >= 2) escalate(); else reply('Beklager, jeg fikk ikke hentet svar akkurat nå. Prøv en av forslagene nedenfor.'); }
      });
      return;
    }

    // 2) No Claude: static lookup
    var st = staticAnswer(text);
    setTimeout(function () {
      if (st) { failedAttempts = 0; reply(st); }
      else { failedAttempts++; if (failedAttempts >= 2) escalate(); else reply('Jeg er ikke helt sikker. Kan du prøve å spørre om pris, plager Markus behandler, åpningstider eller hvor klinikken ligger?'); }
    }, 700);
  }

  function welcome() {
    if (conversation.length === 0) {
      appendMessage('Hei! Jeg er Markus\' assistent. Jeg kan hjelpe deg med spørsmål om behandling, priser, åpningstider eller hvordan du booker time. Hva lurer du på?', 'bot');
    }
    renderQuickReplies(QUICK_REPLIES);
  }

  function openChat() {
    chatNode.classList.add('open');
    chatToggle.setAttribute('aria-expanded', 'true');
    chatToggle.setAttribute('aria-label', 'Lukk chat');
    chatPulse.classList.remove('show');
    try { sessionStorage.setItem('tas_chat_seen', '1'); } catch (_) {}
    setTimeout(function () { chatInput.focus(); }, 300);
  }
  function closeChat() {
    chatNode.classList.remove('open');
    chatToggle.setAttribute('aria-expanded', 'false');
    chatToggle.setAttribute('aria-label', 'Åpne chat');
  }
  chatToggle.addEventListener('click', function () {
    if (chatNode.classList.contains('open')) closeChat();
    else openChat();
  });
  chatNode.querySelector('[data-chat-close]').addEventListener('click', closeChat);
  chatForm.addEventListener('submit', function (e) {
    e.preventDefault();
    var v = chatInput.value.trim();
    if (!v) return;
    appendMessage(v, 'user');
    chatInput.value = '';
    chatQuick.innerHTML = '';
    handleUserMessage(v);
  });

  // V5: rens lagret chat-historikk ved hver page load så helse-relaterte
  // detaljer fra forrige besøk ikke leses tilbake. In-memory historikk lever
  // som normalt mens fanen er åpen.
  try { sessionStorage.removeItem('tas_chat_history'); } catch (_) {}

  loadHistory();
  welcome();

  // ============ EXPORT ===========================================
  window.WestengenKlinikk = {
    openBooking: openBooking,
    closeBooking: closeBooking,
    openContact: openContact,
    closeContact: closeContact,
    openChat: openChat,
    closeChat: closeChat
  };
})();
