// supabase/functions/send-sms/index.ts
//
// Edge Function som sender SMS via SMS-leverandør (default: Sveve, norsk/EU).
// Kalles fra database — registrert-time-trigger (migrasjon 0061) og
// 24t-påminnelse-cron (migrasjon 0062) — via pg_net, IDENTISK mønster som
// e-post-påminnelsen (send-booking-email, kalt fra 0014).
//
// Forventer:
//   - Header X-Webhook-Secret med samme verdi som env WEBHOOK_SECRET
//     (samme hemmelighet som e-post-løsningen / app.webhook_secret i DB).
//   - Body: { to: string, message: string }
//
// Env vars (settes i Supabase Dashboard → Edge Functions → Secrets):
//   - WEBHOOK_SECRET   (random string, samme som app.webhook_secret i DB)
//   - SVEVE_USER       (Sveve-brukernavn)
//   - SVEVE_API_KEY    (Sveve API-nøkkel / passord)
//   - SMS_SENDER       (valgfri; avsendernavn, default "Westengen Klinikk")
//
// Hemmeligheter leses KUN fra miljøvariabler — aldri hardkodet.
// Pasientdata (telefonnummer, meldingstekst) logges ALDRI.

// Deno globals — type-stubs så TypeScript ikke klager lokalt.
declare const Deno: { env: { get(k: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

type Payload = { to?: string; message?: string };

type SendResult = { ok: boolean; status: number; detail: string };

// ============================================================
// LEVERANDØR-ISOLASJON
// ------------------------------------------------------------
// All Sveve-spesifikk kode bor HER. For å bytte leverandør:
// skriv en ny sendViaX(...) med samme signatur og bytt kallet
// nederst i handleren. Ingenting annet i fila trenger endring.
// ============================================================
const SVEVE_API = 'https://sveve.no/SMS/SendMessage';

async function sendViaSveve(to: string, message: string, sender: string): Promise<SendResult> {
  const user = Deno.env.get('SVEVE_USER');
  const apiKey = Deno.env.get('SVEVE_API_KEY');
  if (!user || !apiKey) {
    return { ok: false, status: 500, detail: 'provider_not_configured' };
  }

  // POST med form-encoded body (holder nummer/nøkkel ute av URL/query-logger).
  // f=json gir strukturert respons fra Sveve.
  const form = new URLSearchParams({
    user,
    passwd: apiKey,
    to,
    from: sender,
    msg: message,
    f: 'json',
  });

  const res = await fetch(SVEVE_API, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  });

  // Tolk Sveve-respons. errors > 0 = leveringsproblem. Vi logger KUN
  // status/antall — aldri nummer eller meldingstekst.
  let ok = res.ok;
  let detail = `http_${res.status}`;
  try {
    const data = await res.json();
    const r = data && data.response ? data.response : data;
    const fatal = r && typeof r.fatalError !== 'undefined' && r.fatalError !== null;
    const errs = r && typeof r.errors === 'number' ? r.errors : 0;
    if (fatal || errs > 0) {
      ok = false;
      detail = fatal ? 'provider_fatal' : `provider_errors_${errs}`;
    } else {
      detail = 'sent';
    }
  } catch {
    // Ikke-JSON respons — behold http-status som signal.
  }
  return { ok, status: res.status, detail };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Samme secret-gate som send-booking-email.
  const expectedSecret = Deno.env.get('WEBHOOK_SECRET');
  const incomingSecret = req.headers.get('X-Webhook-Secret');
  if (!expectedSecret || incomingSecret !== expectedSecret) {
    return new Response('Forbidden', { status: 403 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const to = (payload && typeof payload.to === 'string') ? payload.to.trim() : '';
  const message = (payload && typeof payload.message === 'string') ? payload.message.trim() : '';
  if (!to) {
    return new Response(JSON.stringify({ skipped: 'no_recipient' }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }
  if (!message) {
    return new Response('Missing message', { status: 400 });
  }

  const sender = Deno.env.get('SMS_SENDER') || 'Westengen Klinikk';

  let result: SendResult;
  try {
    result = await sendViaSveve(to, message, sender);
  } catch (err) {
    // Logg feil UTEN pasientdata — kun en nøytral markør.
    console.error('send-sms: provider call failed', err instanceof Error ? err.name : 'unknown');
    return new Response(JSON.stringify({ ok: false, detail: 'provider_exception' }), {
      status: 502, headers: { 'Content-Type': 'application/json' }
    });
  }

  if (!result.ok) {
    // Nøytral feillogg (ingen nummer/tekst).
    console.error('send-sms: not delivered', result.detail);
  }
  return new Response(JSON.stringify({ ok: result.ok, detail: result.detail }), {
    status: result.ok ? 200 : 502,
    headers: { 'Content-Type': 'application/json' }
  });
});
