# Resend-integrasjon, manuelt oppsett

Edge Function `send-booking-email` og database-trigger `trg_notify_booking_change`
sender e-post til pasienten ved:
- **Confirmation**. INSERT på `bookings`
- **Cancellation**. UPDATE der `status` endres til `cancelled`
- **Reminder**, 24h før timen (separat cron-job, se nederst)

Denne fila dokumenterer det du må gjøre selv (Claude kan ikke deploye eller
sette secrets for deg). Følg punkt for punkt.

## 1. Resend-konto

1. Opprett konto på <https://resend.com>.
2. Verifiser avsender-domene. To valg:
   - **Produksjon**: `westengenklinikk.example` (eller hvilket som helst domene du eier).
     Resend gir deg DNS-records (SPF + DKIM), legg dem inn hos domene-registrar.
   - **Sandbox** (rask test): bruk `onboarding@resend.dev` som avsender. Da kan
     du bare sende til e-posten som er logget inn på Resend.
3. Generér en API-nøkkel under **API Keys** → **Create API Key**. Kopier den.

## 2. Edge Function, secrets

I Supabase Dashboard → **Edge Functions** → **Settings** → **Secrets**:

| Key                | Verdi                                                   |
| ------------------ | ------------------------------------------------------- |
| `RESEND_API_KEY`   | Nøkkelen fra punkt 1.3                                  |
| `WEBHOOK_SECRET`   | Generer en random streng, f.eks. `openssl rand -hex 32`|
| `RESEND_FROM`      | F.eks. `Westengen Klinikk <ingen-svar@westengenklinikk.example>`           |
| `CLINIC_PHONE`     | Klinikkens telefon (vises i e-post-footer)              |

## 3. Database-parametere

I Supabase Dashboard → **Database** → **Settings** → **Custom Postgres Parameters**
(eller via SQL):

```sql
alter database postgres set app.edge_function_url = 'https://<project-ref>.supabase.co/functions/v1/send-booking-email';
alter database postgres set app.webhook_secret = 'samme verdi som WEBHOOK_SECRET over';
```

Du finner project-ref i Settings → API. Den ligger også i `supabase.co`-URL-en.

> **Viktig**: `app.webhook_secret` i DB-en MÅ matche `WEBHOOK_SECRET` i Edge
> Function-secrets. Edge Function avviser requests som ikke har riktig header.

## 4. Deploy Edge Function

Krever Supabase CLI (lokalt på din maskin):

```bash
# Installer CLI hvis du ikke har den
brew install supabase/tap/supabase   # macOS
# eller: scoop install supabase      # Windows

# Logg inn
supabase login

# Link til prosjektet (engang-jobb)
cd /path/to/westengen-klinikk
supabase link --project-ref <din-project-ref>

# Deploy
supabase functions deploy send-booking-email
```

Verifiser at den er live:
```bash
curl -X POST \
  -H "X-Webhook-Secret: <din-secret>" \
  -H "Content-Type: application/json" \
  -d '{"event":"confirmation","booking":{"name":"Test","email":"din@e-post.example","ref":"TA-TEST","date":"2026-06-01","time":"10:00","service_name":"Konsultasjon","staff_name":"Markus","duration":30}}' \
  https://<project-ref>.supabase.co/functions/v1/send-booking-email
```

## 5. Kjør migrasjon 0007

Migrasjon 0007 oppretter triggeren som kaller Edge Function-en. Kjør i
Supabase SQL Editor:

```sql
-- Lim inn hele innholdet av supabase/migrations/0007_booking_email_trigger.sql
```

## 6. End-to-end-test

1. Logg inn som admin i `booking-admin.html`.
2. Klikk **"+ Ny booking"** og opprett en booking med din egen e-post.
3. Sjekk innboksen, confirmation skal ankomme innen ~30 sek.
4. Endre status på samme booking til **"Avlyst"**. Cancellation skal komme.
5. I Supabase Dashboard → Edge Functions → `send-booking-email` → Logs:
   verifiser at request-en har status 200 og at Resend ikke returnerte feil.

## 7. Reminder (24h før timen). IMPLEMENTERT I KODE 2026-05-12

Implementert i migrasjon 0013 + 0014:

- **0013** legger til `reminder_sent_at timestamptz`-kolonne på `bookings`
  + partial index for effektive cron-spørringer.
- **0014** definerer helper-funksjon `process_pending_reminders()` og
  scheduler den via `cron.schedule()` til å kjøre hver time på minutt :05.
  Funksjonen finner bookinger 22-26 timer frem i tid og kaller Edge
  Function `send-booking-email` med `event='reminder'` for hver.

### Manuelle forutsetninger før 0014 kan kjøre

1. **Enable pg_cron extension** (krever Pro-plan):
   Dashboard → Database → Extensions → søk "pg_cron" → Enable.

   Hvis du er på Free-plan: bruk Supabase Cron i stedet (Dashboard →
   Integrations → Cron → New cron job med `select public.process_pending_reminders();`
   som SQL-snippet, schedule `5 * * * *`). Migrasjon 0014's helper-funksjon
   `process_pending_reminders()` er kompatibel, bare la cron-schedule-
   blokken (b) i 0014 være eller hopp over den.

2. **Sett Postgres-parametere** for Edge Function-kall:
   ```sql
   alter database postgres set app.edge_function_url =
     'https://<project-ref>.supabase.co/functions/v1/send-booking-email';
   alter database postgres set app.webhook_secret = '<verdi>';
   ```
   `app.webhook_secret`-verdien må matche Edge Function-secret `WEBHOOK_SECRET`.

3. **Verifiser etter applisering** at jobben er schedulert:
   ```sql
   select jobid, schedule, jobname, active
     from cron.job
    where jobname = 'westengen-klinikk-24h-reminders';
   ```

### Manuell test før vi venter en time

```sql
-- Sett en testbooking 24 timer frem (juster dato/tid):
insert into public.bookings(
  id, ref, staff_id, staff_name, service_id, service_name,
  price, duration, date, time, name, email, phone, status, journal_consent
) values (
  'bk_reminder_test', 'TA-REMIND', 'markus', 'Markus', 'markus-konsult', 'Test',
  100, 30,
  (now() + interval '24 hours')::date,
  (now() + interval '24 hours')::time,
  'Test Reminder', 'din-egen@e-post.example', '00000000', 'confirmed', false
);

-- Kjør reminder-funksjonen manuelt
select public.process_pending_reminders();

-- Sjekk at den ble markert som sendt
select id, reminder_sent_at from public.bookings where id = 'bk_reminder_test';

-- Rydd opp
delete from public.bookings where id = 'bk_reminder_test';
```

E-posten skal komme til "din-egen@e-post.example" innen ~30 sek (Resend sandbox
tillater kun sending TIL kontoinnehaverens e-post, bytt til verifisert
domene for å sende til andre, se RESEND_SETUP.md punkt 1.2).

## 8. Anti-misuse

- **Anon-rate-limiting**: Edge Function-en sjekker bare webhook-secret.
  Hvis den lekker, kan en angriper sende e-post i din konto. Beskytt secret-en
  som en API-nøkkel. Roter den ved mistanke (oppdater både Edge-secret og
  `app.webhook_secret` i DB samtidig).
- **Resend dashboard** har innebygd send-volum-rate-limit per konto.
- **Bounce-håndtering**: Resend retter automatisk hard bounces. Sjekk Webhooks
  i Resend-dashboardet for å fange opp problemer.

## 9. Pseudonymiserte pasienter

Edge Function-en hopper over alle e-poster som slutter på `@anon.local`
(disse er pseudonymiserte etter V8). Bookings som UPDATE-es til pseudonyme
verdier vil dermed ikke trigge confirmation-e-post.
