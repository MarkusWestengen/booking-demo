/* ============================================================
   Westengen Klinikk — Admin manual booking
   ------------------------------------------------------------
   Brukes av booking-admin.html ("+ Ny booking"-modalen) og
   kalender.html (FAB-bottom-sheet).

   Eksporterer:
     window.WestengenKlinikkAdminBooking = {
       create(sb, payload): Promise<{ok, booking?, reason?, message?, error?}>
     }

   Krever at booking-engine.js er lastet (STAFF/SERVICES-katalog).
   Krever en authenticated Supabase-klient (sb).
   Konflikt-håndtering: pre-check + 23505 fra unique-index.
   ============================================================ */
(function (root) {
  'use strict';

  function create(sb, payload) {
    var E = root.WestengenKlinikkBookingEngine;
    if (!E) return Promise.resolve({ ok: false, error: 'Booking-engine ikke lastet.' });

    // Tjeneste-katalogen er nå async — vent på første last før validering.
    // (Etter første kall er ensureLoaded en cachet promise.)
    return E.ensureLoaded().then(function () {
      var service = E.getServiceById(payload.staffId, payload.serviceId);
      if (!service) return { ok: false, error: 'Ugyldig tjeneste.' };
      var staff = E.STAFF.find(function (s) { return s.id === payload.staffId; });
      if (!staff) return { ok: false, error: 'Ugyldig behandler.' };

      return E.getBookedSlots().then(function (bookedSlots) {
        var conflict = bookedSlots.some(function (b) {
          return b.staffId === payload.staffId && b.date === payload.date && b.time === payload.time;
        });
        if (conflict) {
          return { ok: false, reason: 'slot_taken', message: 'Denne tiden er allerede booket. Velg en annen tid.' };
        }

        var nowIso = new Date().toISOString();
        var booking = {
          id: 'bk_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
          ref: 'TA-' + Math.random().toString(36).slice(2, 6).toUpperCase() + '-' + Date.now().toString().slice(-4),
          staffId: payload.staffId, staffName: staff.name,
          serviceId: service.id, serviceName: service.name,
          price: service.price, duration: service.duration,
          date: payload.date, time: payload.time,
          // E-post/telefon er valgfrie i admin-flyten (0047): lagres
          // som '' når de mangler — kolonnene er NOT NULL.
          name: payload.name, email: payload.email || '', phone: payload.phone || '',
          notes: payload.notes || '',
          status: 'confirmed',
          journalConsent: !!payload.journalConsent,
          journalConsentAt: payload.journalConsent ? (payload.journalConsentAt || nowIso) : null,
          createdAt: nowIso
        };
        var row = {
          id: booking.id, ref: booking.ref,
          staff_id: booking.staffId, staff_name: booking.staffName,
          service_id: booking.serviceId, service_name: booking.serviceName,
          price: booking.price, duration: booking.duration,
          date: booking.date, time: booking.time,
          name: booking.name, email: booking.email, phone: booking.phone,
          notes: booking.notes, status: booking.status,
          journal_consent: booking.journalConsent,
          journal_consent_at: booking.journalConsentAt,
          created_at: booking.createdAt
        };
        // Uten e-post kan verken bekreftelse eller påminnelse sendes:
        // 0047-triggeren hopper over bekreftelsen, og reminder-cronen
        // (0014) skal aldri plukke raden — marker som «håndtert».
        if (!booking.email) {
          row.reminder_sent_at = nowIso;
        }

        return sb.from('bookings').insert(row).then(function (res) {
          if (res.error) throw res.error;
          return { ok: true, booking: booking };
        });
      }).catch(function (err) {
        var code = err && err.code;
        var msg = (err && err.message) ? String(err.message) : '';
        if (code === '23505' || msg.indexOf('23505') !== -1 || msg.indexOf('bookings_active_slot_unique') !== -1) {
          return { ok: false, reason: 'slot_taken', message: 'Denne tiden er allerede booket. Velg en annen tid.' };
        }
        return { ok: false, error: 'Kunne ikke lagre booking: ' + (msg || err) };
      });
    });
  }

  root.WestengenKlinikkAdminBooking = { create: create };
})(window);
