// supabase/functions/submit-contact/index.ts
//
// Offentlig gateway for KONTAKTSKJEMAET (contact_messages). Erstatter den
// tidligere direkte anon REST-inserten fra kontakt.html. Kalles fra
// NETTLESEREN, så i motsetning til notify-push/send-booking-email må denne
// håndtere CORS (preflight + Access-Control-Allow-Origin).
//
// Lag (i rekkefølge):
//   1. CORS-preflight + origin-allowlist (reflekterer origin hvis tillatt).
//   2. Honeypot («company» utfylt → falsk suksess, ingen insert).
//   3. Server-validering (speiler den gamle RLS WITH CHECK: lengder + e-post).
//   4. IP-rate-limit i funksjonen — gjenbruker public.anon_insert_events
//      (bucket='contact', 3/IP/t + 15 globalt/t). Den gamle DB-triggeren
//      trg_anon_quota_contact fyrer IKKE for service_role, så limiteringen
//      er flyttet hit uten dobbelttelling.
//   5. Cloudflare Turnstile-verifisering (TURNSTILE_SECRET_KEY).
//   6. Insert via service_role (BYPASSRLS). AFTER-INSERT-triggerne
//      (send_contact_message_email + notify-push-webhook) fyrer uendret.
//
// Sikkerhet:
//   - verify_jwt = false (config.toml): mennesket verifiseres via Turnstile,
//     ikke via JWT. anon-apikey kan følge med for gateway-ruting, men brukes
//     ikke til autentisering her.
//   - Turnstile-secret leses fra env og forlater aldri serveren.
//
// Env vars (Supabase Dashboard → Edge Functions → Secrets):
//   - TURNSTILE_SECRET_KEY   (Cloudflare Turnstile «Secret Key»)
//   Injisert automatisk (IKKE sett som secret):
//   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Deno-global type-stub så TypeScript ikke klager lokalt.
declare const Deno: {
  env: { get(k: string): string | undefined };
};

// ----- CORS: reflekter origin kun hvis den står i allowlisten -----
const ALLOWED_ORIGINS = new Set<string>([
  // Legg inn deployens faktiske origin her (f.eks.
  // "https://<ditt-prosjekt>.vercel.app") for at kontaktskjemaet
  // skal virke derfra. En origin du IKKE kontrollerer skal aldri
  // staa i denne lista - da kan den sida poste paa dine vegne.
  "https://booking-demo-rosy.vercel.app",  // den publiserte demoen
  "http://localhost:8000",                 // lokal testing
  "http://127.0.0.1:8766",                 // lokal testing
]);

// Plassholderen «https://demo.westengenklinikk.example» sto her i
// stedet for den faktiske adressen. Curl bryr seg ikke om CORS, saa
// funksjonen saa riktig ut i alle tester som ikke gikk gjennom en
// nettleser. Fra den publiserte sida feilet den med «Failed to
// fetch» — foer den i det hele tatt naadde funksjonens egen logikk.
//
// Preview-deployene fra Vercel («...-git-...vercel.app») staar med
// vilje ikke her. De faar ny adresse per gren, og et jokertegn ville
// aapnet for enhver vercel.app-side.

function corsHeaders(origin: string | null): Record<string, string> {
  const h: Record<string, string> = {
    "Vary": "Origin",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, apikey, authorization",
    "Access-Control-Max-Age": "86400",
  };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    h["Access-Control-Allow-Origin"] = origin;
  }
  return h;
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
  });
}

// Speiler frontend-regexen i kontakt.html (EMAIL_RE).
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

// Rate-limit-parametre — identiske med den gamle 0052-kvoten for 'contact'.
const RL_BUCKET = "contact";
const RL_WINDOW_MIN = 60;
const RL_IP_LIMIT = 3;
const RL_GLOBAL_LIMIT = 15;

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  // ----- 1. CORS-preflight -----
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405, origin);
  }

  // ----- Parse body -----
  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400, origin);
  }

  const name = String(payload.name ?? "").trim();
  const email = String(payload.email ?? "").trim();
  const message = String(payload.message ?? "").trim();
  const company = String(payload.company ?? "").trim(); // honeypot
  const token = String(payload.turnstileToken ?? "").trim();

  // ----- 2. Honeypot: bot fylte skjult felt → falsk suksess, ingen insert -----
  if (company) {
    return json({ ok: true }, 200, origin);
  }

  // ----- 3. Server-validering (speiler gammel WITH CHECK) -----
  if (
    name.length < 1 || name.length > 200 ||
    email.length < 3 || email.length > 320 || !EMAIL_RE.test(email) ||
    message.length < 1 || message.length > 2000
  ) {
    return json({ error: "invalid_input" }, 422, origin);
  }

  if (!token) {
    return json({ error: "captcha_required" }, 403, origin);
  }

  // Supabase service-klient (BYPASSRLS) — kreves for rate-limit + insert.
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "server_misconfigured" }, 500, origin);
  }
  const sb = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ----- 4. IP-rate-limit (teller fullførte innsendinger per IP + globalt) -----
  const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "unknown";
  const sinceIso = new Date(Date.now() - RL_WINDOW_MIN * 60 * 1000).toISOString();

  const ipCountRes = await sb
    .from("anon_insert_events")
    .select("*", { count: "exact", head: true })
    .eq("bucket", RL_BUCKET).eq("ip", ip).gt("created_at", sinceIso);
  const globalCountRes = await sb
    .from("anon_insert_events")
    .select("*", { count: "exact", head: true })
    .eq("bucket", RL_BUCKET).gt("created_at", sinceIso);

  if (ipCountRes.error || globalCountRes.error) {
    console.error("[submit-contact] rate-limit-oppslag feilet",
      ipCountRes.error?.message, globalCountRes.error?.message);
    return json({ error: "server_error" }, 500, origin);
  }
  if ((ipCountRes.count ?? 0) >= RL_IP_LIMIT || (globalCountRes.count ?? 0) >= RL_GLOBAL_LIMIT) {
    return json({ error: "rate_limited" }, 429, origin);
  }

  // ----- 5. Cloudflare Turnstile-verifisering -----
  const secret = Deno.env.get("TURNSTILE_SECRET_KEY");
  if (!secret) {
    console.error("[submit-contact] TURNSTILE_SECRET_KEY mangler");
    return json({ error: "server_misconfigured" }, 500, origin);
  }
  const verifyForm = new URLSearchParams();
  verifyForm.append("secret", secret);
  verifyForm.append("response", token);
  if (ip !== "unknown") verifyForm.append("remoteip", ip);

  let verifyOk = false;
  try {
    const vr = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST", body: verifyForm,
    });
    const vj = await vr.json();
    verifyOk = !!vj.success;
    if (!verifyOk) console.warn("[submit-contact] turnstile avvist", vj["error-codes"]);
  } catch (err) {
    console.error("[submit-contact] siteverify-kall feilet", String(err));
    return json({ error: "captcha_unavailable" }, 502, origin);
  }
  if (!verifyOk) {
    return json({ error: "captcha_failed" }, 403, origin);
  }

  // ----- 6. Insert via service_role + registrer rate-limit-hendelse -----
  const { error: insErr } = await sb
    .from("contact_messages")
    .insert({ name, email, message, status: "new" });
  if (insErr) {
    console.error("[submit-contact] insert feilet", insErr.message);
    return json({ error: "insert_failed" }, 500, origin);
  }

  // Tell først ETTER vellykket insert (rate-limit på reelle meldinger).
  const { error: evErr } = await sb
    .from("anon_insert_events")
    .insert({ bucket: RL_BUCKET, ip });
  if (evErr) {
    // Ikke-fatalt: meldingen er lagret. Logg og fortsett.
    console.error("[submit-contact] kunne ikke registrere rate-limit-hendelse", evErr.message);
  }

  return json({ ok: true }, 200, origin);
});
