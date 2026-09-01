/* ============================================================
   Westengen Klinikk — Delte GDPR-handlinger (V7 + V8)
   ------------------------------------------------------------
   Eksporterer:
     window.WestengenKlinikkGdpr = {
       exportPatient(sb, user, email, opts),
       pseudonymizePatient(sb, user, email, opts)
     }

   opts er valgfri: { onSuccess(msg), onError(msg) } — kalles av UI for
   å vise toast/feedback. Funksjonene returnerer Promise<void> så kallere
   kan kjede ferdig-state-håndtering.

   Sikkerhetsmodell (revisjon 2026-06-12, migrasjon 0053): begge
   handlingene går via SECURITY DEFINER-RPC-er som krever role='admin'
   i app_metadata og kjører atomisk i DB (alt-eller-ingenting på tvers
   av bookings, journal_entries, waitlist, contact_messages,
   document_sends, reviews og audit_log.target_id). Audit-logging skjer
   i samme DB-transaksjon — ingen klient-side auditLog her lenger.
   Klient-side rollesjekkene i kallerne er kun UX; DB er grensen.

   Brukes av: booking-admin.html (booking-detalj-modal), kunde-detalj.html
   ============================================================ */
(function (root) {
  'use strict';

  function triggerJsonDownload(filename, dataObj) {
    var blob = new Blob([JSON.stringify(dataObj, null, 2)], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function normalizeEmail(email) { return String(email || '').trim().toLowerCase(); }

  // ----- Export (GDPR art. 15) -----
  function exportPatient(sb, user, email, opts) {
    opts = opts || {};
    var ok = opts.onSuccess || function () {};
    var err = opts.onError || function () {};
    var lower = normalizeEmail(email);
    if (!lower) { err('Mangler e-post'); return Promise.resolve(); }

    return sb.rpc('gdpr_export_patient', { p_email: lower }).then(function (res) {
      if (res.error) throw res.error;
      var data = res.data || {};

      var payload = {
        exported_at: new Date().toISOString(),
        exported_by: user ? { staff_id: user.staffId, staff_name: user.staffName, role: user.role } : null,
        patient_email: lower,
        bookings: data.bookings || [],
        journal_entries: data.journal_entries || [],
        audit_log: data.audit_log || [],
        waitlist: data.waitlist || [],
        contact_messages: data.contact_messages || [],
        document_sends: data.document_sends || [],
        reviews: data.reviews || []
      };

      var safeName = lower.replace(/[^a-z0-9]+/gi, '_');
      var stamp = new Date().toISOString().slice(0, 10);
      triggerJsonDownload('gdpr_export_' + safeName + '_' + stamp + '.json', payload);

      ok('Eksport fullført (' + payload.bookings.length + ' bookinger, ' +
         payload.journal_entries.length + ' journaler)');
    }).catch(function (e) {
      console.error('gdpr_export failed', e);
      err('Eksport feilet: ' + ((e && e.message) || e));
    });
  }

  // ----- Pseudonymize (GDPR art. 17) -----
  function pseudonymizePatient(sb, user, email, opts) {
    opts = opts || {};
    var ok = opts.onSuccess || function () {};
    var err = opts.onError || function () {};
    var lower = normalizeEmail(email);
    if (!lower) { err('Mangler e-post'); return Promise.resolve(); }

    var doConfirm;
    if (opts.skipConfirm) {
      doConfirm = Promise.resolve(true);
    } else if (window.WestengenKlinikkAuth && window.WestengenKlinikkAuth.confirmDestructive) {
      doConfirm = window.WestengenKlinikkAuth.confirmDestructive({
        title: 'Pseudonymiser pasient?',
        message: 'Dette kan ikke reverseres. Navn, e-post, telefon og notater fjernes fra bookinger, journaler, venteliste, meldinger, dokumentutsendinger og audit-loggen for ' + lower + '.\n\nJournal-innholdet beholdes (helsepersonelloven § 39 krever 10 års oppbevaring).\n\nSkriv PSEUDONYMISER for å bekrefte.',
        confirmLabel: 'Pseudonymiser',
        cancelLabel: 'Avbryt',
        requireTyping: 'PSEUDONYMISER'
      });
    } else {
      doConfirm = Promise.resolve(window.confirm('Pseudonymisere pasient ' + lower + '?'));
    }

    return doConfirm.then(function (confirmed) {
      if (!confirmed) return;

      return sb.rpc('gdpr_erase_patient', { p_email: lower }).then(function (res) {
        if (res.error) throw res.error;
        var r = res.data || {};
        ok('Pasient pseudonymisert (' + (r.bookings_updated || 0) + ' bookinger, ' +
           (r.journals_updated || 0) + ' journaler, ' +
           ((r.waitlist_updated || 0) + (r.contact_messages_updated || 0) +
            (r.document_sends_updated || 0) + (r.reviews_updated || 0)) +
           ' øvrige rader). ID: ' + (r.pseudonym_id || '–'));
      });
    }).catch(function (e) {
      console.error('gdpr_pseudonymize failed', e);
      err('Pseudonymisering feilet: ' + ((e && e.message) || e));
    });
  }

  root.WestengenKlinikkGdpr = {
    exportPatient: exportPatient,
    pseudonymizePatient: pseudonymizePatient,
    _normalizeEmail: normalizeEmail
  };
})(window);
