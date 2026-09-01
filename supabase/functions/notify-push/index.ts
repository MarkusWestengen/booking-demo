// supabase/functions/notify-push/index.ts
//
// Edge Function som sender EKTE web-push-varsler til ansatte når det
// kommer en ny booking eller en ny kontaktmelding. Kalles av en
// DB-trigger (notify_push_booking / notify_push_message) via pg_net.
//
// Sikkerhet:
//   - Kjører UTEN JWT-verifisering (verify_jwt = false i config.toml) —
//     triggeren har ingen bruker-JWT. Vi autentiserer i stedet via
//     header `x-webhook-secret` mot env WEBHOOK_SECRET. Feil/mangler → 401.
//   - Bruker service_role (BYPASSRLS) for ALLE oppslag (auth.users +
//     push_subscriptions). Service-nøkkelen injiseres automatisk av
//     Supabase. Push er dermed helt frikoblet fra mottakerens session.
//
// ───────────────────────────────────────────────────────────────────
// PERSONVERN — PAYLOAD-NIVÅ B (ufravikelig):
//   Varselet vises på LÅSESKJERM. Vi tar derfor BEVISST IKKE med
//   pasientnavn, behandlingstype eller meldingsinnhold i teksten
//   (GDPR / Normen for informasjonssikkerhet i helse- og omsorg).
//   - Booking: kun «Ny time booket» / «Du har blitt tildelt en time»
//     + dato/tid. INGEN behandlingstype, INGEN pasientnavn.
//   - Melding: kun «Ny melding» + generisk body. INGEN avsendernavn,
//     INGEN utdrag av innholdet.
//   Detaljer ser ansatte først når de åpner appen (bak innlogging).
// ───────────────────────────────────────────────────────────────────
//
// Ruting:
//   - bookings → tildelt ansatt (auth.users.raw_app_meta_data.staff_id =
//     record.staff_id) får «tildelt»-varselet; admin(er) (role='admin')
//     får «ny time»-varselet. Er en admin selv den tildelte (f.eks. Ingrid),
//     får vedkommende KUN det tildelte (mest relevante) — ingen dobbel.
//   - contact_messages → admin(er) (mottaker av henvendelser).
//   push_subscriptions.staff_id (uuid) = auth.users.id.
//
// Env vars (Supabase Dashboard → Edge Functions → Secrets):
//   - WEBHOOK_SECRET     (samme verdi som DB-parameter app.webhook_secret)
//   - VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT
//   Injisert automatisk (IKKE sett som secret):
//   - SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY

// Skulle npm:-importen feile i edge-runtime, bytt til en esm.sh-variant:
//   import webpush from "https://esm.sh/web-push@3.6.7";
import webpush from "npm:web-push@3.6.7";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Deno-global type-stub så TypeScript ikke klager lokalt.
declare const Deno: {
  env: { get(k: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

type PushRow = {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  staff_id: string;
};

type WebhookPayload = {
  table?: string;
  record?: Record<string, unknown>;
};

type Notification = { title: string; body: string; url: string };

// ----- Norsk dato/tid-format: "ons 18. juni 14:00" -----
const WEEKDAYS = ["søn", "man", "tir", "ons", "tor", "fre", "lør"];
const MONTHS = [
  "januar", "februar", "mars", "april", "mai", "juni",
  "juli", "august", "september", "oktober", "november", "desember",
];
function formatNo(dateStr: unknown, timeStr: unknown): string {
  const date = typeof dateStr === "string" ? dateStr : "";
  const hm = (typeof timeStr === "string" ? timeStr : "").slice(0, 5);
  const d = new Date(date + "T00:00:00");
  if (isNaN(d.getTime())) {
    // Fall tilbake til rådata hvis datoen ikke kan parses.
    return [date, hm].filter(Boolean).join(" ");
  }
  return `${WEEKDAYS[d.getDay()]} ${d.getDate()}. ${MONTHS[d.getMonth()]}${hm ? " " + hm : ""}`;
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  // ----- 1. Delt-hemmelighet-sjekk (triggeren har ingen JWT) -----
  const expectedSecret = Deno.env.get("WEBHOOK_SECRET");
  const incomingSecret = req.headers.get("x-webhook-secret");
  if (!expectedSecret || incomingSecret !== expectedSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  // ----- 2. Parse webhook-payload { table, record } -----
  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }
  const table = String(payload?.table || "");
  const record = (payload?.record && typeof payload.record === "object")
    ? payload.record as Record<string, unknown>
    : {};
  if (table !== "bookings" && table !== "contact_messages") {
    // Ikke en tabell vi varsler på — kvitter 200 så triggeren ikke retry-er.
    return jsonResponse({ skipped: "unhandled_table", table }, 200);
  }

  // ----- 3. VAPID + Supabase service-klient -----
  const vapidPublic = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivate = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:post@westengenklinikk.example";
  if (!vapidPublic || !vapidPrivate) return new Response("VAPID keys not configured", { status: 500 });
  webpush.setVapidDetails(vapidSubject, vapidPublic, vapidPrivate);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return new Response("Supabase env not injected", { status: 500 });
  const sb = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ----- 4. Slå opp mottakere (auth.users → rolle/staff_id) -----
  // Faa ansatte (~8) → én side holder. service_role kreves.
  const { data: usersData, error: usersErr } = await sb.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (usersErr) return jsonResponse({ error: usersErr.message }, 500);
  const users = usersData?.users ?? [];

  const adminIds: string[] = [];
  const assignedIds: string[] = [];
  const assignedStaff = typeof record.staff_id === "string" ? record.staff_id : "";
  for (const u of users) {
    const meta = (u.app_metadata ?? {}) as Record<string, unknown>;
    if (table === "bookings" && assignedStaff && meta.staff_id === assignedStaff) {
      assignedIds.push(u.id);
    }
    if (meta.role === "admin") adminIds.push(u.id);
  }
  // Dedup: en admin som selv er tildelt får KUN det tildelte varselet.
  const assignedSet = new Set(assignedIds);
  const adminTargetIds = adminIds.filter((id) => !assignedSet.has(id));

  // Bygg (mottaker-uid-er → payload)-grupper for denne hendelsen.
  type Group = { ids: string[]; notif: Notification };
  const groups: Group[] = [];

  if (table === "bookings") {
    const when = formatNo(record.date, record.time);
    if (assignedIds.length) {
      groups.push({
        ids: assignedIds,
        notif: { title: "Du har blitt tildelt en time", body: when, url: "/kalender.html" },
      });
    }
    if (adminTargetIds.length) {
      groups.push({
        ids: adminTargetIds,
        notif: { title: "Ny time booket", body: when, url: "/kalender.html" },
      });
    }
  } else {
    // contact_messages → admin(er). Generisk, ingen avsender/utdrag.
    if (adminIds.length) {
      groups.push({
        ids: adminIds,
        notif: { title: "Ny melding", body: "Du har mottatt en ny henvendelse", url: "/meldinger.html" },
      });
    }
  }

  // ----- 5. Send per gruppe; samle døde abonnement -----
  const recordId = typeof record.id === "string" || typeof record.id === "number"
    ? String(record.id) : "";
  let sent = 0;
  const deadIds: string[] = [];

  for (const g of groups) {
    if (!g.ids.length) continue;
    const { data: subs, error: subErr } = await sb
      .from("push_subscriptions")
      .select("id, endpoint, p256dh, auth, staff_id")
      .in("staff_id", g.ids);
    if (subErr) {
      console.error("[notify-push] henting av abonnement feilet", subErr.message);
      continue;
    }
    const rows = (subs || []) as PushRow[];
    if (!rows.length) continue; // mottaker uten abonnement → hopp over stille

    const messageBody = JSON.stringify({
      title: g.notif.title,
      body: g.notif.body,
      url: g.notif.url,
      tag: table + (recordId ? ":" + recordId : ""),
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-192-maskable.png",
    });

    await Promise.all(rows.map(async (row) => {
      try {
        await webpush.sendNotification(
          { endpoint: row.endpoint, keys: { p256dh: row.p256dh, auth: row.auth } },
          messageBody,
        );
        sent++;
      } catch (err) {
        const status = (err && typeof err === "object" && "statusCode" in err)
          ? Number((err as { statusCode?: number }).statusCode) : 0;
        if (status === 404 || status === 410) deadIds.push(row.id);
        else console.error("[notify-push] send feilet", status, String(err));
      }
    }));
  }

  // ----- 6. Rydd døde abonnement (404/410) -----
  let removed = 0;
  if (deadIds.length) {
    const { error: delErr } = await sb.from("push_subscriptions").delete().in("id", deadIds);
    if (delErr) console.error("[notify-push] sletting av døde abonnement feilet", delErr.message);
    else removed = deadIds.length;
  }

  return jsonResponse({
    table,
    sent,
    removed,
    groups: groups.map((g) => ({ title: g.notif.title, recipients: g.ids.length })),
  }, 200);
});
