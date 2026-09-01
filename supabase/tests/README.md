# RLS-tester

Verifiserer at Row-Level-Security-policyene i `supabase/migrations/0001`-`0010`
faktisk gjør det de sier. Tester er skrevet som rene SQL DO-blokker med
`_test_assert` — pgTAP ikke nødvendig (men koden kan upgrades trivielt om
ønskelig).

Alt kjøres i én transaksjon som rolles tilbake, så testfilen er trygg å kjøre
mot prod uten å forurense data.

## Kjøre testene

### Mot lokal Supabase (Docker)

```bash
# Hvis du har Supabase CLI og kjører lokalt
supabase db reset                       # kjør alle migrasjoner
psql "$(supabase status | grep -oP 'DB URL: \K.*')" \
     -f supabase/tests/01_rls_policies.sql
```

### Mot prod (read-only, transaksjon rolles tilbake)

```bash
psql "postgres://postgres.<project-ref>:<password>@aws-0-eu-north-1.pooler.supabase.com:5432/postgres" \
     -f supabase/tests/01_rls_policies.sql
```

Connection-string finner du i Supabase Dashboard → Settings → Database →
Connection string → URI (bruk **Session pooler** eller **Direct connection**;
ikke transaction-pooler, siden testene bruker `set_config` med `is_local=true`).

## Tolke output

```
NOTICE:  PASS: anon journal_entries SELECT returns 0 rows (RLS blocks)
NOTICE:  PASS: anon audit_log SELECT returns 0 rows (RLS blocks)
...
NOTICE:  PASS: anon can INSERT login_failed with correct shape
```

Hver assert printer `PASS:` eller raiser med `FAIL:`. En enkelt FAIL stopper
hele transaksjonen (som likevel rolles tilbake — ingen effekt på prod).

## Oppgradere til pgTAP

Hvis du senere vil ha bedre tooling (xUnit-stil rapportering, CI-integrasjon):

```sql
create extension if not exists pgtap;
```

Erstatt så hver `_test_assert(cond, descr)` med `perform ok(cond, descr)`,
og pakk fil-en med `plan(N)` på toppen og `finish()` på bunnen. Resten av
strukturen er kompatibel.

## Kjente begrensninger

- **JWT-claims-simulering**: Vi setter `request.jwt.claims` via `set_config`.
  Det dekker de fleste policy-uttrykk som leser `auth.jwt()`. For
  spesialiserte funksjoner som leser `auth.uid()` direkte må du erstatte
  med ekte test-bruker.
- **`auth.jwt()` returnerer claims-jsonb** akkurat slik vi setter dem; ingen
  faktisk JWT-signering trengs for denne testen.

## Bookings-lockdown (migrasjon 0010 → 0012 → 0016)

Test 4-serien verifiserer lockdown av PII-eksponering på bookings:

- **Test 4** — anon SELECT på `public.bookings` returnerer 0 rader (RLS deny
  per migrasjon 0010 + 0012).
- **Test 4b** — anon kan kalle `public.get_booked_slots()` (RPC som erstattet
  `booked_slots`-view i 0016) og får tilbake confirmed bookinger. Filter-
  argumentene `p_staff_id`/`p_from`/`p_to` respekteres.
- **Test 4c** — `get_booked_slots()`-funksjonens `RETURNS TABLE`-signatur
  garanterer kolonne-whitelist (kun `staff_id, date, time, duration`).
  Verifiseres via `pg_get_function_result()` med eksplisitte LIKE-asserter
  som blokkerer PII-kolonner som `name`, `email`, `phone`, `notes`, `price`,
  `status`, `ref`.
- **Test 4d** — anon INSERT på `public.bookings` fortsatt mulig (kunde-flyt
  intakt via `anon insert bookings`-policy + bevart INSERT-grant). NB: 0016
  strammet WITH CHECK-en — alle PII-felter må være ikke-tomme + `status='confirmed'`.
- **Test 4e** — authenticated admin og therapist kan SELECT `public.bookings`.
  Etter 0012 har therapist `staff_id`-filter, men test-oppsettet inserter
  `staff_id='erik'` + autentiserer som therapist `tom`, så assertion-en passerer
  fortsatt. Admin-policyen "Admin read all bookings" gir admin full read.

Tidligere "kjente begrensning" om åpen anon-SELECT er nå fjernet — strammet
inn i migrasjon 0010 per audit-rapport 2026-05-11 punkt 4. `booked_slots`-
view-en ble droppet og erstattet med funksjon i 0016 for å lukke Supabase
Database Linter sin `security_definer_view`-ERROR.
