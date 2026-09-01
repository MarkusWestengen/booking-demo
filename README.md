# Bookingsystem med journal og adminpanel

Et komplett booking- og klientsystem for en liten klinikk: kundevendt
bestillingsflyt, og et adminpanel med kalender, klientregister, journal,
dokumentutsending, meldinger og audit-logg.

Klinikken i demoen er oppdiktet. Alle personer, bestillinger og journalnotater
er konstruert. Det som er ekte er systemet.

**Innloggingen til adminpanelet er publisert åpent på forsiden.** Det er et
bevisst valg — hele poenget er at halvparten som er interessant ligger bak
innlogging. Hvordan det lar seg gjøre uten at demoen kan ødelegges, står under
[Skrivesperre på seed-data](#skrivesperre-på-seed-data).

---

## Hva det gjør

**Kundevendt.** Bestillingsflyt med ledig-tid-oppslag mot databasen,
avbestilling via token-lenke, venteliste med preferanser for dato og tidsrom,
kontaktskjema og token-gatet anmeldelsesinnsending. Bekreftelse på e-post og
SMS, med påminnelse 24 timer før.

**Bak innlogging.** Ukeskalender per behandler, bestillingsadministrasjon med
tildeling av ufordelte timer, klientregister med klientkort, journalføring med
samtykkesporing, dokumentutsending fra privat lagring, innboks for
kontakthenvendelser, moderasjonskø for anmeldelser, tjeneste- og
behandleradministrasjon, stengte tider og helligdager, og audit-logg.

Seks språk (norsk, engelsk, tysk, spansk, arabisk, persisk) med RTL-støtte.
Installerbar som PWA med push-varsling ved ny bestilling.

---

## Arkitektur

```
Nettleser ──► PostgREST ──► PostgreSQL
   │           (RLS på hver tabell)      │
   │                                     ├── pg_cron: påminnelser, nattlig nullstilling
   ├──► Supabase Auth (JWT + app_metadata.role)
   │                                     │
   └──► Edge Functions (Deno) ───────────┘
          send-booking-email · send-sms · submit-contact · notify-push
```

**Frontend er vanilla JavaScript.** Ingen rammeverk, ingen byggesteg, ingen
`node_modules`. Statiske HTML-filer, delte moduler i `shared/`, og Supabase
JS SDK fra CDN. Det er et bevisst valg for et system som skal driftes av noen
andre enn den som skrev det: en `.html`-fil kan åpnes, leses og endres om ti år
uten at en toolchain må rekonstrueres først.

**Databasen er autoritativ.** Priser, tjenester, behandlere, arbeidstider og
tilgjengelighet leses fra Postgres — ikke fra hardkodede lister i frontend.
Endrer en administrator prisen på en tjeneste, slår det gjennom uten deploy.
Frontend har kode-fallback for behandlerlisten, slik at en tom eller
utilgjengelig tabell aldri gir kunden en tom bestillingsside.

**67 migrasjoner** i `supabase/migrations/`, nummerert `0000`–`0067`. Alle er
idempotente og skrevet for å kunne kjøres om igjen. De bygger 18 relasjoner og
126 RLS-policyer. Hver fil har en overskriftsblokk som forklarer *hvorfor*
endringen ble gjort, ikke bare hva den gjør, og en verifikasjonsblokk nederst
med spørringer som bekrefter at den virket.

---

## Sikkerhet og personvern

Systemet håndterer helseopplysninger. Det er den vanskeligste delen av
oppgaven, og det meste av arbeidet ligger der.

### Row-Level Security

RLS er på for hver tabell, og standardsvaret er nekt. Det finnes ingen
vidåpen `using (true)`-policy noe sted.

Anon-rollen kan tre ting: opprette en bestilling, melde seg på venteliste, og
sende inn en anmeldelse — som alltid lagres `pending` og aldri kan
selvgodkjennes. Kontaktskjemaet hadde opprinnelig anon-INSERT, men fikk den
trukket tilbake i en senere migrasjon og går nå gjennom en Edge Function med
Turnstile-validering i stedet.

Anon kan ikke lese `bookings` i det hele tatt. Ledige tider hentes gjennom en
`SECURITY DEFINER`-funksjon som filtrerer serverside og returnerer fire
kolonner uten personopplysninger.

Der en policy måtte se på JWT-en, er `auth.jwt()` pakket i en subquery slik at
planleggeren evaluerer den én gang per spørring i stedet for én gang per rad.

Kolonnenivå brukes der radnivå ikke er nok: anon har `SELECT` på
`(staff_id, date, time)` i `blocked_slots`, men ikke på beskrivelsesfeltet —
en behandlers «tannlege 14:00» skal ikke være offentlig.

### Rollestyrt tilgang

Rollen ligger i `app_metadata.role` i JWT-en, satt serverside ved
brukeropprettelse. Den kan ikke endres av brukeren selv, slik `user_metadata`
kan. To roller:

| | `admin` | `therapist` |
|---|---|---|
| Egen kalender og egne bestillinger | ✅ | ✅ |
| Klientregister og journal | ✅ | ✅ |
| Behandleradministrasjon | ✅ | ❌ |
| Audit-logg | ✅ | ❌ |
| GDPR-eksport og -sletting | ✅ | ❌ |

Skillet håndheves i policyene, ikke i menyen. En terapeut som kaller
GDPR-funksjonene direkte mot API-et får avslag fra databasen.

### Audit-logging av journaltilgang

`journal_audit` er en dedikert, append-only logg. Den fanger ikke bare
endringer, men også **oppslag** — hvem som *leste* en journal, ikke bare hvem
som skrev i den. Det er den delen som pleier å mangle, og den som betyr noe når
noen spør hvem som har sett på en pasients opplysninger.

Endringer fanges av en trigger på `journal_entries`. Lesninger fanges ved at
journaloppslag går gjennom en RPC (`get_journal_entries`) i stedet for et
direkte `SELECT` — funksjonen returnerer radene og skriver samtidig en
`select`-hendelse. Hver rad har tidspunkt, aktørens bruker-ID og rolle,
pasientnøkkel, journal-ID og en `jsonb` med kontekst. Kun `admin` kan lese
tabellen, og ingen rolle kan endre eller slette fra den.

### GDPR-eksport og -sletting

To `SECURITY DEFINER`-funksjoner, begge admin-only:

**`gdpr_export_patient(email)`** — artikkel 15, innsyn og dataportabilitet.
Samler alt systemet vet om én person på tvers av bestillinger, journalnotater,
venteliste, meldinger og dokumentutsendinger, og returnerer det som strukturert
JSON.

**`gdpr_erase_patient(email)`** — artikkel 17. Pseudonymiserer i stedet for å
slette hardt: personopplysningene erstattes med en stabil, ikke-reverserbar
nøkkel på `@anon.local`, mens radene består. Det er et bevisst valg.
Regnskapsplikten krever at en gjennomført behandling kan dokumenteres, og en
`DELETE` ville brutt fremmednøkler og etterlatt hull i audit-loggen. Etter
pseudonymisering kan ingen knytte raden til en person, men klinikken kan
fortsatt vise at timen fant sted.

Selve slettingen føres også i audit-loggen — handlingen registreres, aktøren
bevares.

### Skrivesperre på seed-data

Innloggingen er publisert. Sikkerheten kan derfor ikke ligge i passordet.

Den nærliggende løsningen er å skru av knappene, men det ødelegger demoen: en
grå «Slett»-knapp demonstrerer ingenting. Skillet er derfor lagt et annet sted
enn mellom lese og skrive — det går mellom **rader**.

Hver beskyttet tabell har kolonnen `is_demo_seed`. Radene som fulgte med
demoen har `true`, og en trigger avviser `UPDATE` og `DELETE` mot dem. Rader en
besøkende oppretter selv har `false` og oppfører seg helt normalt — hele
CRUD-syklusen kan demonstreres på ekte data, uten at grunnoppsettet kan rives.

Avvisningen bruker SQLSTATE `PT403`. PostgREST tolker `PT`-prefikset som «sett
HTTP-status til dette tallet», så klienten får `403` med `demo_readonly` i
meldingen. Én lytter i frontend kjenner igjen strengen og viser en toast som
forklarer hva som ville skjedd i drift. Ingen kallsteder er endret.

Triggeren tvinger også `is_demo_seed` til `false` ved `INSERT` og `UPDATE`, så
ingen kan gi sine egne rader beskyttelse og dermed låse dem for neste besøkende.

En nattlig `pg_cron`-jobb sletter alt besøkende har lagt igjen og genererer
innholdet på nytt med dagens dato som utgangspunkt. Kalenderen har derfor
alltid noe i forrige uke, noe i dag og noe neste uke — uansett når demoen
åpnes. Rot som legges oppå forsvinner av seg selv innen et døgn.

### Øvrig herding

Anonyme innsettinger er kvotert per IP i en glidende tidsluke, slik at
bestillingsendepunktet ikke kan brukes til å fylle kalenderen eller til å
utløse e-post fra klinikkens domene til vilkårlige adresser. Kontaktskjemaet
går gjennom en Edge Function med Turnstile-validering, ikke direkte til
databasen. Dokumentlagringen er en privat bucket med størrelses- og
MIME-begrensning, re-assertert idempotent i en egen migrasjon fordi det ikke
lot seg bevise fra kode at den faktisk var privat. All HTML i utgående e-post
escapes. Sikkerhetsheadere settes både i `vercel.json` og `_headers`.

---

## Tekniske valg verdt å nevne

**Samtidighet ved bestilling.** To kunder kan klikke samme tidspunkt
samtidig. En delvis unik indeks hindrer dobbeltbooking i databasen, og
klienten oversetter `23505` til en forståelig melding i stedet for en
stacktrace. Innsettingen har eksponentiell backoff for transiente feil, med
bookings-IDen generert klientside én gang — treffer et gjentatt forsøk
primærnøkkelen, betyr det at det første forsøket faktisk gikk gjennom og at
bare svaret gikk tapt. Da regnes det som suksess, ikke som en kollisjon.

**Ufordelte bestillinger.** Bestiller kunden «en terapeut» framfor en navngitt
person, lagres raden uten behandler og tildeles senere i admin.
Tilgjengelighet blir da et kapasitetsspørsmål — antall opptatte plasser i
terapeutpoolen — og en databasetrigger håndhever taket, slik at grensen ikke
kan omgås ved å kalle API-et direkte.

**Denormalisering med hensikt.** `bookings` fryser behandlernavn, tjenestenavn,
pris og varighet på bestillingstidspunktet. Endrer klinikken prisen i morgen,
skal gårsdagens kvittering fortsatt vise det kunden faktisk betalte.

**Tid som funksjon av dagens dato.** Demoinnholdet genereres relativt til
`current_date`, ikke som faste datoer. En håndskrevet liste er ferskvare — tre
uker etter oppsett står kalenderen tom igjen fordi alt ligger i fortiden.

---

## Repoet

```
*.html              21 sider: 8 kundevendte, 13 for ansatte
shared/             delte moduler — bookingmotor, auth, GDPR, komponenter, i18n
i18n/               6 språk, identisk nøkkelsett (521 nøkler), RTL for ar/fa
supabase/
  migrations/       67 idempotente migrasjoner, 0000–0067
  functions/        4 Deno Edge Functions
  tests/            RLS-policytester
icons/              PWA-ikoner
DEMO_SETUP.md       oppsett fra tomt Supabase-prosjekt, ~15 minutter
```

## Kom i gang

Se **[DEMO_SETUP.md](DEMO_SETUP.md)**. Kort fortalt: opprett et tomt
Supabase-prosjekt i EU, slå på `pg_cron`, kjør migrasjonene i rekkefølge, og
lim Project URL og anon-nøkkel inn i `shared/booking-config.js`.

Så lenge den filen er tom sier hver side tydelig fra om at nøklene mangler,
i stedet for å henge.

---

## Fiktive data

Alle personer er oppdiktet. E-postadressene ligger på `.example`, et
toppdomene som per RFC 2606 aldri kan registreres. Telefonnumrene er varianter
av `400 00 000`, og adressen er en plassholder. `robots.txt` avviser alle
crawlere og hver side bærer `noindex` — en oppdiktet klinikk med oppdiktet
adresse hører ikke hjemme i et søkeresultat.
