// supabase/functions/send-booking-email/index.ts
//
// Edge Function som sender booking-relaterte e-poster via Resend.
// Kalles fra database-trigger trg_notify_booking_change (migrasjon 0007).
//
// Forventer:
//   - Header X-Webhook-Secret med samme verdi som env WEBHOOK_SECRET
//   - Body: { event: 'confirmation' | 'cancellation' | 'reminder', booking: {...} }
//
// Env vars (settes i Supabase Dashboard → Edge Functions → Secrets):
//   - RESEND_API_KEY    (fra resend.com/api-keys)
//   - WEBHOOK_SECRET    (random string, samme som app.webhook_secret i DB)
//   - RESEND_FROM       (verifisert avsender, f.eks. "Westengen Klinikk <ingen-svar@westengenklinikk.example>")
//   - CLINIC_PHONE      (telefon for avbestilling i e-post-footer)

// Deno globals — type-stubs så TypeScript ikke klager lokalt.
declare const Deno: { env: { get(k: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

const RESEND_API = 'https://api.resend.com/emails';

type Booking = {
  id?: string; ref?: string;
  staff_name?: string; service_name?: string;
  date?: string; time?: string;
  name?: string; email?: string; phone?: string;
  duration?: number; price?: number; status?: string;
  notes?: string;
};

type Payload = {
  event: 'confirmation' | 'cancellation' | 'reminder';
  booking: Booking;
};

function escapeHtml(s: string): string {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c] as string));
}

function formatDateNo(s?: string): string {
  if (!s) return '—';
  const d = new Date(s + 'T00:00:00');
  if (isNaN(d.getTime())) return s;
  return d.toLocaleDateString('no-NO', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
}

function shellHtml(title: string, body: string, clinicPhone: string): string {
  // Enkel responsiv HTML — bare grunnstrukturer, mailers tåler ikke mye CSS.
  return `<!doctype html>
<html lang="no">
<head><meta charset="utf-8"><title>${escapeHtml(title)}</title></head>
<body style="margin:0;padding:0;font-family:-apple-system,Helvetica,Arial,sans-serif;background:#FAF7F1;color:#15191A;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FAF7F1;">
    <tr><td align="center" style="padding:32px 16px;">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#fff;border:1px solid #1d211e22;">
        <tr><td style="background:#15191A;color:#FAF7F1;padding:22px 28px;border-bottom:3px solid #3E6B47;">
          <div style="font-family:Georgia,serif;font-size:22px;">Westengen Klinikk</div>
        </td></tr>
        <tr><td style="padding:28px;">${body}</td></tr>
        <tr><td style="padding:18px 28px;background:#F2EDE3;font-size:12px;color:#76776F;line-height:1.5;">
          Spørsmål eller endringer? Ring oss på ${escapeHtml(clinicPhone)}.<br>
          Westengen Klinikk — fysioterapi i Oslo.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

function bookingDetailsHtml(b: Booking): string {
  return `
    <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;font-size:14px;line-height:1.6;">
      <tr><td style="padding:6px 0;color:#76776F;width:120px;">Referanse</td><td style="padding:6px 0;font-family:'JetBrains Mono',monospace;">${escapeHtml(b.ref || b.id || '')}</td></tr>
      <tr><td style="padding:6px 0;color:#76776F;">Dato</td><td style="padding:6px 0;">${escapeHtml(formatDateNo(b.date))}</td></tr>
      <tr><td style="padding:6px 0;color:#76776F;">Tid</td><td style="padding:6px 0;">kl. ${escapeHtml((b.time || '').slice(0,5))}</td></tr>
      <tr><td style="padding:6px 0;color:#76776F;">Tjeneste</td><td style="padding:6px 0;">${escapeHtml(b.service_name || '—')}${b.duration ? ' · ' + b.duration + ' min' : ''}</td></tr>
      <tr><td style="padding:6px 0;color:#76776F;">Behandler</td><td style="padding:6px 0;">${escapeHtml(b.staff_name || '—')}</td></tr>
    </table>
  `;
}

function renderConfirmation(b: Booking, clinicPhone: string): { subject: string; html: string } {
  const subject = `Bekreftet time hos Westengen Klinikk · ${formatDateNo(b.date)}`;
  const body = `
    <h1 style="font-family:Georgia,serif;font-weight:400;font-size:24px;margin:0 0 8px;">Timen din er bekreftet</h1>
    <p style="margin:0 0 18px;color:#2D3330;">Vi ser frem til å ta imot deg ${escapeHtml(b.name || '')}!</p>
    ${bookingDetailsHtml(b)}
    <p style="margin:22px 0 0;font-size:13px;color:#76776F;">
      Trenger du å avbestille? Ring oss senest 24 timer før timen på ${escapeHtml(clinicPhone)}.
    </p>
  `;
  return { subject, html: shellHtml(subject, body, clinicPhone) };
}

function renderCancellation(b: Booking, clinicPhone: string): { subject: string; html: string } {
  const subject = `Time avlyst · ${formatDateNo(b.date)}`;
  const body = `
    <h1 style="font-family:Georgia,serif;font-weight:400;font-size:24px;margin:0 0 8px;">Timen din er avlyst</h1>
    <p style="margin:0 0 18px;color:#2D3330;">Vi bekrefter at følgende time er avlyst:</p>
    ${bookingDetailsHtml(b)}
    <p style="margin:22px 0 0;font-size:13px;color:#76776F;">
      Ønsker du å booke ny time, gjør du det enklest via westengenklinikk.example/bestilling eller på telefon ${escapeHtml(clinicPhone)}.
    </p>
  `;
  return { subject, html: shellHtml(subject, body, clinicPhone) };
}

function renderReminder(b: Booking, clinicPhone: string): { subject: string; html: string } {
  const subject = `Påminnelse: time i morgen · ${formatDateNo(b.date)}`;
  const body = `
    <h1 style="font-family:Georgia,serif;font-weight:400;font-size:24px;margin:0 0 8px;">Påminnelse om timen din i morgen</h1>
    <p style="margin:0 0 18px;color:#2D3330;">Hei ${escapeHtml(b.name || '')}, vi minner om at du har en avtale i morgen:</p>
    ${bookingDetailsHtml(b)}
    <p style="margin:22px 0 0;font-size:13px;color:#76776F;">
      Trenger du å endre? Ring oss på ${escapeHtml(clinicPhone)} så fort som mulig.
    </p>
  `;
  return { subject, html: shellHtml(subject, body, clinicPhone) };
}

async function sendViaResend(apiKey: string, from: string, to: string, subject: string, html: string): Promise<{ ok: boolean; status: number; body: string }> {
  const res = await fetch(RESEND_API, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ from, to, subject, html })
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, body: text };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const expectedSecret = Deno.env.get('WEBHOOK_SECRET');
  const incomingSecret = req.headers.get('X-Webhook-Secret');
  if (!expectedSecret || incomingSecret !== expectedSecret) {
    return new Response('Forbidden', { status: 403 });
  }

  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('RESEND_FROM') || 'Westengen Klinikk <onboarding@resend.dev>';
  const clinicPhone = Deno.env.get('CLINIC_PHONE') || '+47 XX XX XX XX';
  if (!apiKey) {
    return new Response('Resend API key not configured', { status: 500 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }
  if (!payload || !payload.event || !payload.booking) {
    return new Response('Missing event/booking', { status: 400 });
  }
  const booking = payload.booking;
  if (!booking.email) {
    return new Response(JSON.stringify({ skipped: 'no_email' }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
  // Hopp over pseudonymiserte adresser
  if (booking.email.endsWith('@anon.local')) {
    return new Response(JSON.stringify({ skipped: 'pseudonymized' }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  let rendered: { subject: string; html: string };
  switch (payload.event) {
    case 'confirmation':  rendered = renderConfirmation(booking, clinicPhone); break;
    case 'cancellation':  rendered = renderCancellation(booking, clinicPhone); break;
    case 'reminder':      rendered = renderReminder(booking, clinicPhone); break;
    default: return new Response('Unknown event type', { status: 400 });
  }

  const result = await sendViaResend(apiKey, from, booking.email, rendered.subject, rendered.html);
  return new Response(JSON.stringify({
    ok: result.ok,
    status: result.status,
    resend_body: result.body
  }), {
    status: result.ok ? 200 : 502,
    headers: { 'Content-Type': 'application/json' }
  });
});
