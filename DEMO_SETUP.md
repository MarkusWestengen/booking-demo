# Oppsett av demoen

Westengen Klinikk er en oppdiktet klinikk. Demoen viser bookingsystemet, ikke
klinikken: den kundevendte bestillingsflyten med avbestilling og venteliste, og
hele adminpanelet bak innlogging. Klinikkens markedsføringssider er ikke med.

Dette er et frittstaaende repo: alt demoen trenger ligger her, og det har ingen
historikk eller avhengighet til noe annet prosjekt. Dokumentet forklarer hvordan
du setter opp en fungerende kopi i et tomt Supabase-prosjekt, og hvorfor den er
bygget som den er.

Kommandoene under bruker prosjekt-ref `pfyidlnztpwjnpxpoheu`. Bruker du et annet
prosjekt, bytt ut den strengen overalt.

Regn med 15 minutter.

---

## Før du begynner

**Ikke bruk et prosjekt som inneholder ekte data.** Migrasjon `0065` oppretter
to innloggingskontoer med passord som står åpent på forsiden av nettstedet.
Demoen forutsetter et eget, tomt prosjekt.

---

## Hva demoen består av

**Kundevendt**

| Side | Hva den viser |
|---|---|
| `index.html` | Systemforside: hva dette er, to dører, publisert innlogging |
| `bestilling.html` | Bestillingsflyten med ledig-tid-oppslag |
| `avbestill.html` | Avbestilling via referanse eller lenke |
| `venteliste.html` | Påmelding til venteliste |
| `anmeldelser.html` | Innsending av anmeldelse, token-gatet |
| `kontakt.html` | Kontaktskjema → innboksen i admin |
| `personvern.html`, `vilkar.html` | Lastbærende: samtykkesteget og cookie-banneret viser hit |

**Bak innlogging:** `ansatt.html` (innlogging), `kalender.html`,
`booking-admin.html`, `kunder.html`, `kunde-detalj.html`, `tjenester.html`,
`behandlere.html`, `meldinger.html`, `dokumenter.html`, `stengte-tider.html`,
`audit-logg.html`, `innstillinger.html`, `set-password.html`.

**Ikke med.** Klinikkens markedsføringssider, forside med filosofi og
kundehistorier, ansattoversikt, behandlingsmetode og nettbutikk, er fjernet.
Demoen skal vise systemet, ikke kulissen.

---

## Steg 1. Nytt Supabase-prosjekt

1. Gå til [supabase.com](https://supabase.com) og lag et nytt prosjekt.
2. Region: **Europe (Stockholm)** eller **Europe (Frankfurt)**. Demoen skriver
   navn og e-post fra besøkende til databasen, og de skal ligge i EU.
3. Lagre databasepassordet et sted du finner igjen.

---

## Steg 2. Slå på pg_cron FØR migrasjonene

Dashboard → **Database** → **Extensions** → søk `pg_cron` → **Enable**.

Dette må gjøres før `0067`. Den migrasjonen registrerer den nattlige
nullstillingen som en cron-jobb. Er extensionen ikke på når `0067` kjører,
hopper den over jobben med en `notice`, alt annet virker, men demoen
nullstiller seg aldri av seg selv, og kalenderen ligger i fortiden etter et
par uker. Slår du på pg_cron senere, kjør `0067` en gang til; den er
idempotent.

---

## Steg 3. Kjør migrasjonene

Alt skjemaet trenger ligger i `supabase/migrations/`, 67 filer, nummerert
`0000` til `0067` (`0021` finnes ikke). Kjør dem i rekkefølge; flere bygger på
hverandre, og noen forutsetter en tabell en tidligere migrasjon opprettet.

```bash
npm install -g supabase          # hvis du ikke har CLI-en
supabase login
supabase link --project-ref pfyidlnztpwjnpxpoheu
supabase db push
```

Uten CLI: åpne **SQL Editor** i dashbordet og lim inn filene én for én, i
rekkefølge. Alle er idempotente, så en fil du kjører to ganger gjør ingen skade.

De fire som er verdt å kjenne til:

| Migrasjon | Hva den gjør |
|---|---|
| `0000_base_schema.sql` | Grunntabellene: `bookings`, `blocked_slots`, `holidays`. Slår på RLS og oppretter én policy, anon kan sette inn en bestilling, ingenting mer. |
| `0065_demo_users.sql` | Oppretter admin- og terapeutkontoen med rolle i `app_metadata`. |
| `0066_demo_mode.sql` | Skrivesperren. Legger til `is_demo_seed` og en trigger som avviser endring og sletting av seed-rader med `PT403 demo_readonly`. |
| `0067_demo_seed_and_reset.sql` | Genererer innholdet relativt til dagens dato og setter opp nattlig nullstilling. |

Kontroller at alle kom gjennom:

```bash
supabase migration list --project-ref pfyidlnztpwjnpxpoheu
```

---

## Steg 4. Koble frontend til prosjektet

Project Settings → **API**. Kopier **Project URL** og **anon public**, og lim
dem inn i `shared/booking-config.js`:

```js
window.WestengenKlinikkBackend = {
  supabaseUrl: 'https://pfyidlnztpwjnpxpoheu.supabase.co',
  supabaseAnonKey: 'eyJhbGciOi...'   // anon public, ikke service_role
};
```

Filen ligger tom i repoet med vilje, se kommentaren øverst i den. Så lenge den
er tom sier hver side tydelig fra om at nøklene mangler, i stedet for å henge.

Bruk **anon public**, aldri `service_role`. Anon-nøkkelen er ment å ligge i
frontend og er beskyttet av RLS; service_role-nøkkelen omgår RLS fullstendig.

Server så mappa lokalt, `file://` virker ikke, fordi service workeren og
`fetch` krever http:

```bash
python -m http.server 8000
```

---

## Steg 5. Verifiser

1. Åpne <http://localhost:8000/index.html> og gå videre til `bestilling.html`.
   Bestill en time gjennom flyten. Du skal få en referanse av typen
   `WK-X4F2-1042`.
2. Åpne `ansatt.html` og logg inn som **admin@westengenklinikk.example** /
   `demo-admin-2026`. Kalenderen skal være full for inneværende uke, og
   bestillingen din skal ligge der.
3. Prøv å endre en av de forhåndsgenererte bestillingene. Knappen skal virke,
   dialogen skal åpne seg, og lagringen skal avvises med en toast som forklarer
   hvorfor. Endre deretter *din egen* bestilling, den skal lagres.
4. Logg inn som **terapeut@westengenklinikk.example** / `demo-terapeut-2026` og
   se at audit-logg og behandleradministrasjon er borte fra menyen.

---

## Slik er demoen beskyttet

Innloggingen er publisert. Sikkerheten ligger derfor ikke i passordet, men i to
mekanismer som virker sammen:

**Skrivesperre på seed-data (`0066`).** Hver beskyttet tabell har kolonnen
`is_demo_seed`. Radene som fulgte med demoen har `true`, og en trigger avviser
`UPDATE` og `DELETE` mot dem. Rader en besøkende oppretter har `false` og
oppfører seg helt normalt, hele CRUD-syklusen kan demonstreres på ekte data.

Ingenting skjules og ingenting deaktiveres. Skillet går mellom rader, ikke
mellom lese og skrive. En grå «Slett»-knapp demonstrerer ingenting; en knapp
som virker helt fram til databasen, og der får et forklarende avslag,
demonstrerer både funksjonen og at oppsettet er beskyttet.

Avvisningen bruker SQLSTATE `PT403`. PostgREST oversetter `PT`-prefikset til en
HTTP-status, så klienten får `403` med `demo_readonly` i meldingen.
`shared/demo-mode.js` lytter på alle 403-svar, kjenner igjen strengen og viser
en toast, ett sted i frontend, uten at et eneste kallsted er endret.

**Nattlig nullstilling (`0067`).** `demo_reset()` sletter alt besøkende har lagt
inn, tømmer driftsloggene og genererer innholdet på nytt med dagens dato som
utgangspunkt. Kalenderen har derfor alltid noe i forrige uke, noe i dag og noe
neste uke, uansett når demoen åpnes.

Trenger du å rydde umiddelbart:

```sql
select public.demo_reset();
```

---

## Fiktive data

Alle personer i demoen er oppdiktet. E-postadressene ligger på `.example`, et
toppdomene som per RFC 2606 aldri kan registreres. Telefonnumrene er varianter
av `400 00 000`. Adressen `Storgata 1, 0155 Oslo` er en plassholder.

Nettstedet er merket permanent: en pille i headeren på hver side, en linje i
bunnteksten, og et varsel på kontakt-, vilkårs- og personvernsiden. `robots.txt` avviser
alle crawlere og hver side bærer `noindex`, en oppdiktet klinikk med oppdiktet
adresse skal ikke ligge i et søkeresultat.

---

## Hvis noe ikke virker

| Symptom | Sannsynlig årsak | Fiks |
|---|---|---|
| Bestillinger lagres bare i din egen nettleser | `booking-config.js` er tom | Steg 3 |
| `Invalid login credentials` på riktig passord | `auth.identities`-raden mangler | Kjør `0065` på nytt; se verifikasjon B i filen |
| 404 mot en tabell | En migrasjon er hoppet over | Kjør migrasjonene i rekkefølge fra `0000` |
| Alt kan endres, ingenting avvises | `0066` er ikke kjørt, eller du er logget inn som `postgres` i SQL-editoren | Test fra nettleseren, ikke fra dashbordet |
| Kalenderen er tom | `0067` er ikke kjørt | `select public.demo_seed();` |
| Kalenderen er full av gamle datoer | Nullstillingen kjører ikke | Aktiver pg_cron, eller kjør `demo_reset()` manuelt |

---

## Videre til en ekte installasjon

Skal systemet settes opp for en virkelig klinikk, er det tre ting som må endres
utover navn og innhold:

1. **Ikke kjør `0065`, `0066` og `0067`.** De hører demoen til. Brukere opprettes
   i Dashboard → Authentication → Users, med genererte passord.
2. **Skriv en ekte personvernerklæring.** `personvern.html` beskriver demoen, ikke
   en helsetjeneste. Systemet har allerede teknikken en slik erklæring
   forutsetter, rollestyrt tilgang, samtykke registrert ved bestilling, og
   audit-logg over all journaltilgang, men teksten må skrives.
3. **Bytt Turnstile-nøkkelen.** `kontakt.html` bruker Cloudflares offentlige
   testnøkkel, som alltid godkjenner. Den skal erstattes med en ekte sitekey.
