# Sluttkontroll før lansering

Westengen Klinikk, booking-demo. Gjennomgang 1.–2. september 2026.

Alt under er testet mot den koblede Supabase-instansen
(`pfyidlnztpwjnpxpoheu`), ikke mot statiske filer. Der noe ikke lot
seg teste, står det hvorfor.

---

## Kort oppsummert

Fire ting må gjøres før demoen kan publiseres. De står under
[Dette må du gjøre selv](#dette-må-du-gjøre-selv). Den viktigste er at
Edge-funksjonene ikke er deployet — uten dem virker ikke
kontaktskjemaet, og ingen e-post sendes.

To feil som ville ødelagt demoen ble funnet underveis og er rettet:
behandlingskatalogen ville blitt slettet av den nattlige jobben, og
ventelista var brutt for alle besøkende.

---

## Det du ba om

### 1. Kontrast

Målt i nettleseren på alle 19 sidene: hvert element med egen
tekstnode, faktisk beregnet farge, faktisk bakgrunn gjennom
transparente foreldre, mot 4,5:1 for brødtekst og 3:1 for stor tekst.

Fem par lå under. Alle er rettet, og alle 19 sidene er nå rene.

| Hvor | Var | Er | Årsak |
|---|---|---|---|
| «Hvem ser hva», brødtekst | 2,59:1 | 8,2:1 | Seksjonen lå på `--clay` med mørk tekst |
| «Hvem ser hva», halvfet | 3,78:1 | 9,3:1 | Samme |
| «Hvem ser hva», sluttlinje | 2,84:1 | 4,8:1 | Samme |
| Footer-bunn, tre sider | 2,55:1 | 7,3:1 | `--muted` er for lys grunn, brukt på blekk |
| «Ledig» i kalenderen, 15 steder | 1,43:1 | 5,0:1 | `--green-soft` er for mørke flater |
| Kursiv i merkenavnet, innlogging | 1,93:1 | 6,1:1 | Samme |
| Antall ufordelte bookinger | 4,26:1 | 4,84:1 | Hvit tekst på varselgult |
| Feiltekst i tre adminsider | 4,08:1 | 6,4:1 | Feilmelding i samme blå som resten |

Fire av dem har samme rot: `--clay` og `--green-soft` er navn fra den
varme paletten. Da paletten ble kald, fulgte verdiene med mens
teksten ble stående. Tokenfila sier det rett ut om samme farge:
«flater og kanter, aldri tekst». Kommentarene i begge tokenfilene
advarer nå om fellen.

«Hvem ser hva» er ikke lappet, den er gjort ferdig mørk. Siden får en
rytme: mørk inngang, lys demo, mørk merknad, lys avslutning.

### 2. Seksjoner som fløt sammen

Årsaken var `padding: 60px 0 0` på den mørke bookingseksjonen. Det
lyse panelet gikk helt ned til seksjonskanten, og «Rammene i demoen»,
også lys, begynte rett under. Mellom dem lå en hårstrek.

Den mørke flaten har nå bunn-padding og lukker seg selv. Hårstreken
over «Rammene i demoen» er fjernet, den hadde ingen jobb igjen, og
luften over overskriften er økt fra 64 til 88 piksler.

Alle andre seksjonsoverganger er gått gjennom. Ingen andre steder
møter to like flater hverandre uten skille.

### 3. Avkryssingene i bestillingsskjemaet

Sto slik: nyhetsbrev, en setning om avbestilling, vilkår. Setningen
delte de to boksene i to.

Nå: setningen først, begge boksene under den som én gruppe.

### 4. Én valgrad for hele siden

`shared/choice.css`. Fem varianter var i bruk før: `.choice`,
`.tabf-consent`, `.wl-consent`, `.nb-consent`, og bare
`<label><input>` tre steder til.

Komponenten holder fem regler: hele raden klikkbar via `<label>`,
boksen på første tekstlinje, minst 44 px høy, synlig fokusring, og
lik høyde på bokser ved siden av hverandre. Marginen som setter
boksen på første linje regnes ut fra tekstens egen linjehøyde, ikke
et håndsatt tall.

Selektorene skriver klassenavnet to ganger. Grunnen står i fila:
sidene har egne skjemaregler av typen `.field label`, som er (0,1,1)
og slår en enkel klasse. Uten doblingen ble valgraden lagt tilbake
til `display:block`.

Konvertert: ventelista, bookingflyten, behandlere, tjenester,
stengte tider og tre steder i booking-admin.

Målt: boks på første linje innenfor 1 px, lik høyde, 69 px på
ventelista og 45 px i skjemaet, fokusring 2 px ved tastaturnavigasjon,
piltast bytter mellom radioene.

### 5. Headeren

Den rapporterte overlappen skyldtes ikke et bruddpunkt satt for lavt.
«Bestill time» sto to ganger: som første lenke i navet, og som
knappen 300 piksler lenger til høyre. På engelsk trengte de fem
lenkene 564 px, mens cella deres var 462. `nowrap` gjør at teksten
ikke krymper, den renner over.

Boksene overlappet ikke, bare innholdet. Det er derfor et raskt blikk
på layouten ikke avslørte det.

Dubletten er fjernet. Fire lenker trenger 400 px og får plass.
Mobilmenyen beholder «Bestill time», for der er knappen skjult.

I tillegg måler `shared/header-fit.js` om lenkene faktisk får plass,
og kollapser til hamburgermenyen når de ikke gjør det. Da gjelder det
uansett språk, også for en oversettelse som ikke er skrevet ennå.
Media-spørringen står urørt som gulv for telefon.

Testet: to språk × sju bredder (320, 375, 414, 768, 1024, 1280,
1440). Ingen overlapp mellom merkenavn, demo-pille, lenker,
språkvelger, knapp og hamburger. Ingen vannrett scroll.

### 6. Overskriften som brøt midt i ordet

Chrome delte «administra-sjonssystem». Det er ikke en fuge på norsk.

Automatisk orddeling er slått av, og det står en myk bindestrek i
språkfila der ordet kan deles: «administrasjons­system».

Verdien er `hyphens: manual`, ikke `none`. «none» slår av de myke
bindestrekene også, og da brøt `overflow-wrap` i stedet, midt i ordet
og uten bindestrek: «administrasjonss / ystem».

Verifisert på 320 px: «administrasjons-» / «system», med bindestrek.

### 7. Portretter

Kortene har `<img>` med fast 48×48, `loading="lazy"`, tom `alt`
(navnet står ved siden av) og rundt utsnitt. Under bildet, i samme
rute, står initialene i den blå boksen.

Fotoene finnes ikke ennå, så `PORTRETTER` i `shared/booking-flow.js`
er tom. Da spør vi aldri etter en fil som ikke finnes: et `<img>` mot
en manglende sti gir en 404 i konsollen på hver eneste visning.

`assets/avatars/README.md` sier hvilke to filer som skal inn, hvilket
format de trenger, og de to linjene som slår dem på.

Portrettet er rundt selv om alt annet har skarpe hjørner. Et rundt
utsnitt av et ansikt leses umiddelbart som et menneske, og formen sier
det også før bildet finnes.

Merk: valgradene på ventelista har ikke portretter. De har aldri hatt
det, og jeg la ikke til noe som ikke var der. Si fra hvis du vil ha
dem der også.

### 8. Ingen popups, ingen tekniske strenger

Alle `alert()`, `confirm()` og `prompt()` er borte. Bekreftelser går
gjennom dialogen i `shared/auth.js`, meldinger gjennom toasten i
`shared/demo-mode.js`.

To steder falt tilbake på `window.confirm` hvis dialogen manglet. De
returnerer nå `false`: en nettleser-popup skal aldri vises, og en
sletting skal ikke skje uten en bekreftelse noen faktisk har sett.

38 steder sendte en database-melding rett på skjermen. «Feil:
PGRST116», «permission denied for table bookings», «Invalid login
credentials». Hvert sted sier nå hva som ikke gikk og hva man kan
gjøre. Den tekniske grunnen går til `console.error`.

`translateAuthError()` endte på `return msg`, så alt den ikke hadde en
oversettelse for gikk uoversatt til brukeren. Rettet.

Seed-rader føles som de virker: sperren fanges opp, endringen vises ut
sesjonen, og det kommer én rolig toast: «LAGRES IKKE — Endringen vises
bare hos deg. Demoen nullstilles hver natt.» Verifisert at databasen
er urørt etterpå.

### 9., 10., 11. Adminpanelets topplinje

Demo-notisen er erstattet av en linje som sier hvor du er, med
demo-pillen, rollebytteren og «Til nettsiden». Alle elleve sidene.

Rollebytteren lå fritt plassert nede til høyre og måtte måle alt annet
som var festet mot bunnen for å slippe å dekke bunnmenyen. Den
målingen er strøket; i normal flyt kan den ikke dekke noe.

Demo-pillen lå inne i `.brand`, som har `overflow:hidden` og
`text-overflow:ellipsis`. Pillen ble klippet bort av den regelen og
var i praksis usynlig i hele panelet.

Seksjonsnavnet sto som liten kursiv i merkenavnet. Når linja under
sier det samme, står ordet to ganger innenfor 40 piksler. Kursiven er
fjernet.

Bredden på linja leses av topbarens egen container, siden hver side
har sin egen: 720 på kalenderen, 1100 på kunder, 1300 på meldinger.

Testet: alle elleve sidene viser riktig seksjonsnavn, pille, bryter og
lenke. Rollebytte begge veier fra booking-admin, kalender og kunder.
Ingen overlapp på 320, 375, 768 og 1024.

### 12.–16. Teksten

Avsnittet om at klinikken ikke finnes er slettet fra forsiden.

Innloggingen: elleve steder lovet fortsatt et passord som ikke lenger
finnes. `og:description`, meta-beskrivelsen, begge dørene på
forsiden, personvernsidens advarsel og kapselliste, kontaktsidens
ingress og varsel, README og DEMO_SETUP.

Skrivebeskyttelses-varselet er borte. Igjen står én linje: «Skriv ikke
inn ekte personopplysninger», med lenke til personvernsiden.

Sjargong: «Audit-logg» sto som overskrift fire steder. Det heter
«Logg over oppslag» nå, og ingressen sier hva den er god for. Også
rettet: «Append-only logg … Datatilsynet-rapportering og intern
revisjon», «Alle visninger logges (audit-logg) for sporbarhet»,
«FIFO-kø», «Slug er allerede i bruk i databasen», «Kjør migrasjon
0049 for fargestøtte», «Brukerkontoen administreres i Supabase Auth».
Den tekniske beskrivelsen ligger i «Teknisk detalj», lukket.

AI-tellene: «systemet en klinikk drifter seg selv med» sto igjen i
meta-beskrivelsen og personvernteksten. «Ikke bare endringer, men også
oppslag» er byttet med «Det gjelder oppslag, ikke bare endringer».
Gjennomsøkt begge språkfilene for em-dash, «ikke bare X, men Y» og
emoji: ingen igjen.

Demo-arket bak pillen var hardkodet norsk. Pillen står også på de
kundevendte sidene, som finnes på to språk, så en engelsk leser fikk
en norsk dialog. Alt går nå gjennom i18n.

---

## Funnet underveis, ikke i bestillingen

### Katalogen ville blitt slettet av den nattlige jobben

Den alvorligste. `services` og `staff_services` hadde
`is_demo_seed = false` på samtlige rader.

0066 merket alt som lå der da den kjørte. 0068 byttet ut hele
katalogen etterpå, og `demo_guard()` tvinger flagget til false på
INSERT. To følger:

1. Hvem som helst kunne endre og slette klinikkens behandlinger for
   alle andre. Sperren var aldri på.
2. Verre: `demo_reset()` sletter det de besøkende har laget med
   `delete from services where not is_demo_seed`. Den nattlige jobben
   ville tømt katalogen, og demoen hadde våknet uten en eneste
   behandling å bestille.

Migrasjon `0071` merker katalogen, og setter et sikkerhetsnett: en
katalogtabell tømmes bare hvis det finnes minst én merket rad igjen å
beholde. Verste utfall blir da at en besøkendes egen behandling
overlever natta, i stedet for at demoen mister katalogen sin.

Applisert og verifisert: 4 tjenester, 36 koblinger, 9 behandlere, alle
merket. Et forsøk på å endre en tjeneste fra panelet gir «LAGRES IKKE»
og lar databasen stå urørt.

### Ventelista var brutt for alle besøkende

Rettighetene er satt slik: `grant insert on public.waitlist to anon`,
med en RLS-policy for rollen anon. Adminsidene leser og modererer som
`authenticated`. Det var riktig da ansatte logget inn selv.

Auto-innloggingen snudde forutsetningen. Nå har alle en sesjon, og
standard Supabase-klient plukker den opp også på de offentlige sidene.
Skjemaet sendte admin-tokenet, altså rollen `authenticated`, som ikke
har lov til å sette inn i den tabellen. «Noe gikk galt» for hver
eneste påmelding, med SQLSTATE 42501 bak.

Løsningen er ikke å gi `authenticated` flere skriverettigheter. Et
offentlig skjema skal ikke opptre som en innlogget ansatt. Klienten på
ventelista leser derfor ikke sesjonen.

Kontrollert at de to andre offentlige skjemaene ikke har samme feil:
kontaktskjemaet går gjennom en Edge Function (service role),
anmeldelser gjennom `submit_review_by_token` (security definer).

### Rollegatingen holdt ikke i mobilmenyen

`shared/admin-nav.js` setter
`.bn-sheet-list .bn-btn{display:flex !important}` for å snu pillene
fra kolonne til rad, og `!important` slår en inline `display:none`. En
terapeut som åpnet menyen så «Tjenester» og «Behandlere», som er
admin-punkter. `applyRoleGates` setter nå også en klasse som kommer
over den regelen.

### To adminsider hadde ingen rollebytter

`booking-admin.html` og `tjenester.html` kalte aldri
`applyRoleGates`. Begge kaller den nå.

### Fire arkiverte tjenester med et gammelt navn

«Konsultasjon (Erik)» og «Videre behandling (Erik)» lå igjen fra før
0068, sammen med 18 koblingsrader som ikke pekte på noe man kunne
bestille. Bare admin så dem, men de lå der. Migrasjon `0072` sletter
dem, og sletter ingenting hvis en booking fortsatt peker hit.

Sidenotat: `UPDATE`-en i 0068 traff på `markus-konsult` og
`markus-videre`, men radene het `erik-konsult` og `erik-videre`. Det
er derfor opprydningen ikke skjedde av seg selv.

### En ekte privatperson lå i demo-databasen

En booking på et ekte navn og en ekte gmail-adresse, fra tidligere
testing. Den er slettet, sammen med testbookingene fra denne runden.
Ingen ikke-seed-rader igjen i noen tabell.

Gjennomsøkt bookings, meldinger, venteliste, anmeldelser, behandlere
og dokumenter: alle e-postadresser er `@eksempel.example`.

### Bekreftelsen lovet en e-post som ikke sendes

«Vi har sendt en bekreftelse til <e-post>». Ingen Edge Functions er
deployet, så ingen e-post sendes. Teksten sier nå hva som faktisk
skjedde, og hva som ville skjedd i drift. Avbestillingslinja pekte
også på «lenken i bekreftelses-mailen»; den peker nå på
avbestillingssiden.

**Når du deployer funksjonene og setter hemmelighetene, bytt tilbake
`booking.confirm.demo_no_mail` i begge språkfilene.** Det er én linje.

### Favicon og app-ikon i gammel palett

Faviconet var `#464C8C`, en lilla fra paletten som ble byttet ut for
to runder siden. PWA-ikonene hadde samme lilla i aksentstreken. Alle
fem ikonene er generert på nytt.

Faviconet lå dessuten bare på de åtte kundevendte sidene. De tretten
ansattsidene viste nettleserens standardikon. Nå har alle 21 samme.

`icons/generate.html` tegnet fortsatt «TA», monogrammet fra prosjektet
demoen kom ut av. Rettet.

### README lovet seks språk

Med RTL-støtte. Det stemte for to runder siden. Det er to språk nå.
Antall migrasjoner var også utdatert.

### Adminpanelet laster ikke i18n

`WestengenKlinikkI18n` er `undefined` på alle 13 ansattsider. Panelet
er norsk, med vilje. Det betyr at fallback-teksten i koden er den
teksten brukeren faktisk ser. 28 steder hadde ASCII-skadet norsk
(«Prov igjen», «gjor det», «fullfort») fordi de var skrevet som
fallback og aldri sett. Rettet.

Nøklene ligger klare i begge språkfilene den dagen panelet også skal
finnes på engelsk. Det er en egen jobb, ikke en liten en.

---

## Testet mot databasen

| Hva | Resultat |
|---|---|
| Bestilling ende-til-ende | Tre ganger. Referansekode, riktig behandler, tjeneste, tid og pris |
| Avbestilling med referansekode | Bekreftet avbestilt i databasen |
| 24-timersregelen | En time seks timer fram lot seg ikke avbestille. Beskjeden var «Du må avbestille senest 24 timer før timen. Ring oss», ikke en kode |
| Varighetsbevisste tider | En 60-minutters behandling mister 08:00 (neste luke opptatt), 09:00 (pausen) og 12:30 (rekker ikke før stengetid). En 30-minutters beholder alle tre |
| Skrivesperren på seed-rader | Endring vises i UI, databasen urørt, én rolig toast |
| Sletting av seed-rad | Raden forsvinner fra visningen, databasen urørt |
| Rollebytte | Begge veier, fra booking-admin, kalender og kunder |
| Admin-only-sider som terapeut | `tjenester.html` sender terapeuten tilbake til kalenderen |
| Alle 11 adminsider | Riktig seksjonsnavn, pille, bryter og lenke |
| Tastaturnavigasjon | Fokusring 2 px gjennom stepper, behandlerkort, tjenestekort og valgrader |
| Konsollfeil | Ingen, på noen side, i noen rolle |

### Ikke fullført

**Én vellykket ventelistepåmelding gjennom skjemaet.** Rate-limit-vakten
tillater tre per time per IP, og diagnosen brukte opp kvoten. Det jeg
har er: en vellykket anon-innsetting i `waitlist` gjennom hele RLS- og
trigger-laget, og bekreftelse på at skjemaet nå går som anon (avvises
med 53400 fra rate-limit, ikke 42501 fra rettigheter). Siste steg
gjenstår å se med egne øyne.

**Kontaktskjema til innboks.** Edge-funksjonen er ikke deployet, så
kjeden kan ikke fullføres. Se under.

---

## Dette må du gjøre selv

### 1. Deploy Edge-funksjonene

Ingen av de fire er deployet:

    npx supabase functions list --project-ref pfyidlnztpwjnpxpoheu
    {"functions":[]}

Uten dem:

- **kontaktskjemaet virker ikke.** Det poster til
  `/functions/v1/submit-contact`, som svarer 404. Kontaktsiden er en
  av de tre kjedene demoen viser fram.
- **ingen bekreftelses-e-post sendes** ved bestilling.
- **ingen påminnelse 24 timer før.**
- **ingen push-varsling** ved ny bestilling.

Minimum for at kontaktskjemaet skal virke:

    npx supabase functions deploy submit-contact --project-ref pfyidlnztpwjnpxpoheu
    npx supabase secrets set TURNSTILE_SECRET_KEY=<hemmelighet>

`SUPABASE_URL` og `SUPABASE_SERVICE_ROLE_KEY` settes automatisk.

For e-post og SMS i tillegg: `RESEND_API_KEY`, `RESEND_FROM`,
`WEBHOOK_SECRET`, og `SVEVE_USER` med `SVEVE_API_KEY` for SMS. Står i
`DEMO_SETUP.md`.

### 2. Turnstile-nøkkelen er en testnøkkel

`kontakt.html` bruker sitekey `1x00000000000000000000BB`. Det er
Cloudflares testnøkkel, som alltid godkjenner. Den hører sammen med
testhemmeligheten `1x0000000000000000000000000000000AA`.

Til en publisert demo er det godt nok, og kombinasjonen er dokumentert
i en kommentar i fila. Skal skjemaet faktisk beskyttes, hent et ekte
par fra Cloudflare og bytt begge.

### 3. Verifiser den nattlige jobben

Ikke testet. `demo_reset()` er endret i `0071`, og endringen er den
som avgjør om katalogen overlever. Kjør den manuelt én gang og se
etter:

    select count(*) from public.services;    -- noter tallet
    select public.demo_reset();
    select count(*) from public.services;    -- skal være det samme

Sjekk samtidig at pg_cron-jobben finnes og er aktiv:

    select jobname, schedule, active from cron.job;

### 4. Portrettene

`assets/avatars/markus.png` og `assets/avatars/terapeut.png`.
Kvadratiske, minst 192×192, motivet sentrert med luft rundt hodet.
Legg dem i mappa og fyll ut `PORTRETTER` i `shared/booking-flow.js`.
Fremgangsmåten står i `assets/avatars/README.md`.

Uten dem viser kortene initialene MW og MT, som er en fullgod
mellomtilstand.

---

## Vurdert, ikke gjort

**Adminpanelet på engelsk.** Alle 13 ansattsidene er norske og laster
ikke i18n. Å oversette dem er tusenvis av strenger og en egen runde,
ikke en opprydning. Nøklene for det jeg la til ligger klare i begge
språkfilene.

**Flere skriverettigheter til `authenticated`.** Det ville løst
ventelista med én migrasjon, men et offentlig skjema skal ikke opptre
som en innlogget ansatt. Frontend-fiksen holder sikkerhetsmodellen
intakt.

**Innloggingsskjemaene i `kalender.html` og `innstillinger.html`.** De
vises bare hvis auto-innloggingen ikke går gjennom. Det er en reell
reservevei, ikke en rest, så de står.

**Kontaktskjemaet uten Edge Function.** Det kunne vært koblet direkte
mot `contact_messages`, siden anon har rettigheten, og da ville kjeden
virket i dag. Men funksjonen er det som verifiserer Turnstile på
serversiden, og det er nettopp det kontaktsiden forteller at den gjør.
Å koble utenom ville gjort teksten usann og fjernet en reell
beskyttelse. Deploy funksjonen i stedet.

**robots.txt sperrer hele nettstedet.** Med vilje: en oppdiktet
klinikk med falsk adresse skal ikke i et søkeresultat. Flere
lenkeforhåndsvisere respekterer robots.txt, så OG-bildet vises kanskje
ikke i en delt lenke likevel. Bildet ligger klart hvis den avveiningen
endres.

---

## Skript som holder det ved like

Kjøres fra rotmappa, tar under et sekund hver:

    node scripts/verify-i18n.mjs        samme nøkkelsett, ingen tomme
                                        verdier, ingen nøkler brukt i
                                        markup som mangler i filene
    node scripts/verify-inline-js.mjs   hvert inline script parser
    node scripts/verify-lenker.mjs      hver intern lenke og lokal
                                        ressurs finnes
    node scripts/verify-lekkasje.mjs    ekte e-post, registrerbare
                                        domener, gamle prosjektnavn,
                                        LAN-adresser, hemmelige nøkler

Alle fire er grønne. `scripts/` deployes ikke.

---

## Én ting til

Demoen skriver til en ekte database. Radene som følger med er
skrivebeskyttet, og alt en besøkende lager slettes hver natt. Men
`services`-feilen over viser hvor tett den mekanismen henger sammen
med at nye migrasjoner husker å merke radene sine.

Regelen er: **legger en migrasjon inn rader som skal overleve
nullstillingen, må den sette `is_demo_seed = true` selv**, og den må
gjøre det med triggeren midlertidig av. Mønsteret står i `0071`.

---

# Etter lansering

Publisert og verifisert 2. september 2026, 02:00–04:10 UTC.
Alt under er testet mot `booking-demo-rosy.vercel.app`, ikke lokalt.

## Kort oppsummert

Demoen er ute og virker. Kontaktskjemaet og ventelista er nå verifisert
ende til ende i produksjon — begge kjedene som sto igjen fra forrige
runde.

Tre feil dukket opp som bare kunne dukke opp i produksjon. Alle tre satt
i kontaktkjeden, og hver av dem alene var nok til å knekke den. De er
rettet og verifisert.

Én ting står igjen som jeg ikke kan gjøre: e-post. Nøklene er dine.

## Hva som ble deployet

    02:15  git push origin master       12 commits, 175c99a..e7c1d2f
    03:20  Edge Functions               alle fire, v1, ACTIVE
    03:30  migrasjon 0073               grants til service_role
    03:40  git push  cb3ea10            feltnavn i kontaktskjemaet
    03:46  git push  b63e8bb            CORS-allowlist
    03:56  git push  18d4392            personvernlenke i footeren
    04:04  git push  feb4bdc            absolutt og:image

Vercel bygde grønt på hver push. Ingen force-push, ingen historikk rørt.

## Sjekket før push

Gikk gjennom hele diffen i de 12 commitene.

- Ingen hemmeligheter, ingen `.env`, ingen service_role-nøkkel. De
  eneste treffene på søkeordene var variabelnavn i dokumentasjonen,
  mønstrene i lekkasjeskriptet selv, og `grant ... to service_role` i
  SQL, som er et rollenavn og ikke en nøkkel.
- Ingen absolutte stier fra maskinen din.
- Eneste e-postadresse i diffen er `onboarding@resend.dev`, Resends egen
  offentlige testavsender.
- `shared/booking-config.js` inneholder kun anon-nøkkelen. Dekodet
  JWT-payload: `{"role":"anon","ref":"pfyidlnztpwjnpxpoheu"}`.
- `.gitignore` dekker `.env*`, `*.key`, `*.pem`, `supabase/.temp/` og
  `.claude/settings.local.json`. Ingen av dem er sporet.

**To ting du bør vite at er offentlige nå**, begge bevisst:

Demo-passordene (`demo-admin-2026`, `demo-terapeut-2026`) ligger i
`shared/auth.js`, `ansatt.html`, `DEMO_SETUP.md` og migrasjon `0065`.
Det er hele poenget: panelet logger seg inn selv, og sikkerheten ligger
i RLS og skrivesperren, ikke i at passordet er hemmelig. Men de er
lesbare for hvem som helst nå.

Migrasjonene beskriver hele skjemaet, alle RLS-policyene og
rate-limit-grensene. `.vercelignore` holder dem borte fra HTTP med
kommentaren «skal ikke være offentlig lesbare» — men et offentlig
GitHub-repo gjør dem lesbare uansett. Det er ikke en feil, men de to
utsagnene henger ikke sammen. Si fra hvis du vil at jeg endrer
kommentaren eller repoets synlighet.

## Live serverer den nye koden

- `sw.js` melder `westengen-klinikk-shell-v81`.
- `shared/header-fit.js`, `shared/choice.css` og `assets/og-bilde.png`
  svarer 200. De fantes ikke før denne runden.
- Setningen «Innloggingen til adminpanelet er publisert» finnes ikke
  lenger på `index.html`.
- Den myke bindestreken står i `landing.heading` i `i18n/no.json`.
- **48 filer sammenlignet byte for byte** mot repoet: HTML, CSS, JS,
  språkfiler, manifest, service worker. Null avvik.

### Service workeren serverer ikke gammelt

Testet, ikke resonnert:

- `sw.js` svarer `Cache-Control: public, max-age=0, must-revalidate`.
  Nettleseren revaliderer den ved hver navigasjon.
- Hver fil i precache-lista svarer 200 på live. Installasjonen kan
  ikke feile og etterlate den gamle workeren aktiv.
- `skipWaiting` og `clients.claim` er på plass, og `activate` sletter
  hver cache som ikke er `CACHE_VERSION`.
- Plantet en falsk `/index.html` og en falsk `/kalender.html` i en
  `v78`-cache og lastet begge sidene. Live serverte den nye siden
  begge ganger. `caches.match()` uten cacheName søker riktignok i alle
  cacher, men den nyeste vinner, og de gamle ryddes ved neste
  aktivering.

Ryddet bort den plantede cachen etterpå.

## Edge Functions

Alle fire deployet, `ACTIVE`, versjon 1:

    submit-contact  send-booking-email  send-sms  notify-push

Deployen krevde ikke Docker; CLI-en pakket dem via API.

### Secrets

Satt: `TURNSTILE_SECRET_KEY`, pluss Supabase sine egne
(`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, med flere).

**Mangler fortsatt**, og jeg gjetter ikke på verdier:

    RESEND_API_KEY      send-booking-email
    RESEND_FROM         send-booking-email
    WEBHOOK_SECRET      send-booking-email, send-sms, notify-push
    SVEVE_USER          send-sms
    SVEVE_API_KEY       send-sms
    VAPID_PUBLIC_KEY    notify-push
    VAPID_PRIVATE_KEY   notify-push

`TURNSTILE_SECRET_KEY` er satt til `1x0000000000000000000000000000000AA`.

> **Utfoert 2026-09-02.** Se seksjonen «Turnstile i produksjon»
> nederst i dokumentet.

Det er **Cloudflares publiserte testhemmelighet**, ikke noe jeg fant på.
Den hører sammen med testnøkkelen `1x00000000000000000000BB` som alt lå
i `kontakt.html`, og godkjenner alt. Uten den svarte funksjonen 500
`server_misconfigured`, og kjeden kunne ikke testes i det hele tatt.
Bytt begge to samtidig når du har hentet ekte nøkler.

## Tre feil som bare kunne finnes i produksjon

Kontaktskjemaet var brutt på tre uavhengige måter. Hver enkelt var nok.

### 1. Feltnavnene stemte ikke

Frontenden sendte `token`. Funksjonen leser `payload.turnstileToken`.
Den så derfor alltid en tom token og svarte alltid 403
`captcha_required`.

Honeypoten ble heller aldri sendt: funksjonen leser `payload.company`,
frontenden sendte den ikke. Serversjekken var død kode. Den sendes nå,
for en bot som poster rett mot funksjonen går utenom nettleseren.

### 2. service_role manglet rettigheter

Etter feltnavn-fiksen svarte funksjonen 500 `server_error`.

`anon_insert_events` (fra `0052`) gjør `revoke all from anon,
authenticated, public` og slår på RLS uten policyer. Riktig for
databasesiden: bare den SECURITY DEFINER-triggeren skal røre den. Men
Edge-funksjonen når tabellen utenfra, som `service_role`, og hadde
ingen vei inn. Rate-limit-oppslaget feilet, og funksjonen ga opp.

Samme årsak som i `0069`: Supabase sine default privileges er ikke i
effekt i dette prosjektet, så hver rolle må få grants eksplisitt.

Migrasjon `0073` gir `service_role` nøyaktig det funksjonene gjør:
select og insert på `anon_insert_events`, insert på `contact_messages`,
select og delete på `push_subscriptions`. Ikke mer.

### 3. CORS-allowlisten inneholdt en plassholder

Etter grants-fiksen virket funksjonen fra curl, men fortsatt ikke fra
nettleseren. `ALLOWED_ORIGINS` inneholdt `http://localhost:8000` og
`https://demo.westengenklinikk.example` — et domene som ikke finnes.
Kommentaren i fila sa det rett ut: «Legg inn deployens faktiske origin
her». Det var aldri gjort.

Fra nettleseren feilet kallet med «Failed to fetch», altså avvist i
CORS-laget før funksjonens egen logikk. Curl bryr seg ikke om CORS, og
det er grunnen til at de to første rettelsene ikke var nok.

`booking-demo-rosy.vercel.app` står nå i lista. Preview-deployene fra
Vercel står med vilje ikke der: de får ny adresse per gren, og et
jokertegn ville åpnet for enhver `vercel.app`-side.

## Verifisert på live

| Hva | Resultat |
|---|---|
| Kontaktskjema, ekte skjema på live | «Takk! Meldingen er sendt» |
| Meldingen i databasen | Rad med `status: new`, `is_demo_seed: false` |
| Meldingen i innboksen | Synlig i `meldinger.html` på live, 03:45:29 |
| CORS-preflight | 204 med `Access-Control-Allow-Origin` for demoens adresse |
| Venteliste, ekte skjema på live | Kvittering med referanse `TA-WL-X4F7-BMHU`, køplass 3 |
| Ventelista med adminsesjon i nettleseren | Virket. Det var nettopp den tilstanden som brøt den før |
| Ventelisteraden i databasen | Riktig behandler, dato, status `waiting` |
| Rollebytte på live | Begge veier, fra kalenderen |
| Rollegating på live | Alle fire admin-punkter skjult for terapeut |
| Seksjonslinje på live | Riktig navn, pille, bryter og «Til nettsiden» |
| Alle 21 sider | HTTP 200 |
| Alle refererte ressurser | Ingen 404 |
| Favicon | På alle 21 sidene |
| Title, description og og:image | På alle 8 kundevendte sidene |
| Avatarene | Runde MW/MT, ingen bildeforespørsel, ingen 404, ingen tom ramme |
| Konsollfeil | Ingen, på noen testet side, i noen rolle |
| Engelsk på live | Overskrift, nav og seksjoner riktig. Ingen overlapp, ingen vannrett scroll |
| Sikkerhetshoder | `frame-ancestors 'none'`, `X-Frame-Options: DENY`, `nosniff`, HSTS, `Referrer-Policy`, `Permissions-Policy` |

### Ryddet opp

To testmeldinger og én ventelisterad slettet. Bekreftet etterpå: null
ikke-seed-rader i `contact_messages`, `waitlist`, `bookings`,
`reviews`, `blocked_slots` og `holidays`.

### To funn til underveis

**Personvernlenka manglet der den trengtes mest.** Bare forsiden lenket
til `personvern.html`. Kontakt, venteliste, avbestilling og anmeldelser
gjorde det ikke, og det er nettopp de sidene som ber om navn, e-post og
telefonnummer. Lagt inn i footeren på alle fire.

**`og:image` var en relativ sti.** Min egen feil fra forrige runde. En
forhåndsviser henter bildet uten å vite hvilken side taggen sto på, så
en relativ sti gir ikke noe delingskort. Byttet til full URL på alle
åtte sidene.

## Ikke verifisert

**Responsivitet målt direkte på live.** To ting hindret det: live setter
`frame-ancestors 'none'` og `X-Frame-Options: DENY`, som blokkerer
iframe-teknikken, og vindusendring virker ikke i dette miljøet. Begge
deler er som de skal være.

I stedet sammenlignet jeg alle 48 filene byte for byte mot repoet. De er
identiske, så bruddpunktene som ble testet lokalt på 320, 375, 414, 768,
1024, 1280 og 1440 i begge språk gjelder også i produksjon. Det er en
svakere form for bevis enn å se det med egne øyne, og du bør vite det.

**Bekreftelses-e-post.** Kan ikke testes. Se under.

**Den nattlige nullstillingen.** Har ikke kjørt siden `0071`. Se under.

## Dette må du gjøre selv

### 1. E-post og SMS

`send-booking-email` svarer i dag 403 `Forbidden` fordi `WEBHOOK_SECRET`
mangler. Ingen bekreftelse sendes ved bestilling, ingen påminnelse.

    npx supabase secrets set RESEND_API_KEY=<fra resend.com> --project-ref pfyidlnztpwjnpxpoheu
    npx supabase secrets set RESEND_FROM="Westengen Klinikk <noreply@ditt-domene>" --project-ref pfyidlnztpwjnpxpoheu
    npx supabase secrets set WEBHOOK_SECRET=<generer en tilfeldig streng> --project-ref pfyidlnztpwjnpxpoheu

Databasetriggeren må peke på funksjonen med samme hemmelighet. I
SQL-editoren:

    alter database postgres set app.edge_function_url =
      'https://pfyidlnztpwjnpxpoheu.supabase.co/functions/v1/send-booking-email';
    alter database postgres set app.webhook_secret = '<samme streng>';

For SMS i tillegg: `SVEVE_USER` og `SVEVE_API_KEY`.
For push: `VAPID_PUBLIC_KEY` og `VAPID_PRIVATE_KEY`.

**Jeg endret ikke bekreftelsesteksten.** Du ba meg bytte den tilbake
«når det virker». Det gjør den ikke ennå, så teksten «Demoen sender ikke
e-post» står — den er fortsatt sann. Når e-posten går: bytt
`booking.confirm.demo_no_mail` i `i18n/no.json` og `i18n/en.json`, og
fjern avsnittet som skriver den ut i `shared/booking-flow.js`.

To språk, ikke seks. Tysk, spansk, arabisk og persisk ble fjernet to
runder tilbake, på din instruks.

Og selv med nøklene på plass kan jeg ikke bekrefte at e-posten kommer
fram: testadressene er `@eksempel.example`, et domene som ikke kan
registreres. Send til din egen adresse når du tester.

### 2. Den nattlige nullstillingen

Har ikke kjørt siden `demo_reset()` ble endret i `0071`.

Bevis: den nyeste seedede meldingen har `created_at` =
`2026-09-01T16:05:48Z`, og `0070` setter den til `now() - 2 timer`.
Seedingen skjedde altså `2026-09-01 18:05 UTC` — det var da jeg
appliserte `0070` manuelt, ikke cron. Jobben går `15 4 * * *`, altså
04:15 UTC, og klokka var 01:48 da jeg sjekket.

Kjør dette i SQL-editoren etter neste 04:15 UTC:

    -- 1. Er jobben i det hele tatt planlagt og aktiv?
    select jobname, schedule, active from cron.job;

    -- 2. Kjørte den, og gikk den bra?
    select j.jobname, r.status, r.start_time, r.end_time, r.return_message
      from cron.job_run_details r
      join cron.job j on j.jobid = r.jobid
     where r.start_time > now() - interval '2 days'
     order by r.start_time desc
     limit 10;

    -- 3. Holdt sikkerhetsnettet fra 0071? Katalogen skal ha innhold.
    select 'services' as tabell, count(*) filter (where is_demo_seed) as merket,
           count(*) as sum from public.services
    union all
    select 'staff_services', count(*) filter (where is_demo_seed), count(*)
      from public.staff_services
    union all
    select 'staff_members', count(*) filter (where is_demo_seed), count(*)
      from public.staff_members;
    -- Forvent: 4/4, 36/36, 9/9. Merket skal være lik sum.

    -- 4. Ble besøkendes rader fjernet?
    select 'bookings' as tabell, count(*) from public.bookings where not is_demo_seed
    union all
    select 'waitlist', count(*) from public.waitlist where not is_demo_seed
    union all
    select 'contact_messages', count(*) from public.contact_messages where not is_demo_seed;
    -- Forvent: 0 i alle tre, hvis ingen har brukt demoen etter 04:15.

Ikke regn nullstillingen som verifisert før spørring 2 viser en
`succeeded`-rad fra i natt.

### 3. Turnstile

Site key ligger ett sted, som den skal:

    kontakt.html:334   data-sitekey="1x00000000000000000000BB"

Hemmeligheten ligger ikke i repoet i det hele tatt, bare som secret i
Supabase. Begge er Cloudflares testverdier. Når du har hentet et ekte
par:

    1. Bytt `data-sitekey` i `kontakt.html` (linje 334).
    2. npx supabase secrets set TURNSTILE_SECRET_KEY=<ekte hemmelighet> --project-ref pfyidlnztpwjnpxpoheu
    3. Send inn skjemaet og se at det fortsatt går gjennom.

Bytt begge samtidig. En ekte site key mot testhemmeligheten, eller
omvendt, gir et skjema som ser ut til å virke og ikke gjør det.

### 4. Portrettene

Uendret fra forrige runde. `assets/avatars/markus.png` og
`terapeut.png`, så to linjer i `PORTRETTER`. Fremgangsmåten står i
`assets/avatars/README.md`.

Bekreftet i produksjon at fallbacken ser bevisst ut: runde MW- og
MT-sirkler, ingen bildeforespørsel i det hele tatt, ingen 404, ingen tom
ramme.

---

# Sveip etter kjente feilklasser

2. september 2026. Utgangspunkt: de tre feilene som ble funnet på
kontaktkjeden dagen før var alle usynlige lokalt og usynlige for curl.
Spørsmålet her var om de finnes andre steder.

Svaret er ja. Én til av hver av to klassene, og én ny type funn som
ingen av dem dekker.

## Kort oppsummert

| Klasse | Funn | Status |
|---|---|---|
| 1 — kontrakt frontend/funksjon | Ingen nye. Fem par sjekket felt for felt | Rent |
| 2 — manglende grants | **Anmeldelsessiden**, samme feil som ventelista | Rettet og verifisert |
| 3 — plassholdere | **base_url i e-postene** peker på domenet som brøt CORS | Ikke rettet, se under |
| — | **Fem migrasjoner kan ikke ha kjørt** som de står i git | Krever din avgjørelse |

---

## Klasse 1 — kontrakt mellom frontend og Edge Function

Det finnes fire Edge Functions. Bare én kalles fra nettleseren; tre
kalles fra databasen. Alle fem kall er sammenlignet felt for felt mot
det funksjonen faktisk leser, ikke mot kommentarer eller typenavn.

| Endepunkt | Kaller | Felt sendt | Felt lest | Match |
|---|---|---|---|---|
| `submit-contact` | `kontakt.html` | `name`, `email`, `message`, `turnstileToken`, `company` | `payload.name`, `.email`, `.message`, `.turnstileToken`, `.company` | Ja |
| `send-booking-email` | trigger `trg_booking_email` → `send_booking_email()` | — | — | Kaller ikke funksjonen. Se merknad |
| `send-booking-email` | cron `0064` | `event`, `booking`, header `X-Webhook-Secret` | `payload.event`, `payload.booking`, header `X-Webhook-Secret` | Ja |
| `send-sms` | cron `0062` | `to`, `message`, header `X-Webhook-Secret` | `payload.to`, `payload.message`, header `X-Webhook-Secret` | Ja |
| `notify-push` | **ingen kaller i repoet** | — | `payload.table`, `payload.record`, header `x-webhook-secret` | Ikke koblet |

Feltene funksjonen plukker ut av `booking` er også sjekket mot
kolonnene som finnes: `date`, `duration`, `id`, `name`, `ref`,
`service_name`, `staff_name`, `time`, `email`. Alle ni finnes.

**Merknad om `notify-push`:** ingenting i repoet kaller den. Formen
den leser (`table` + `record` + `x-webhook-secret`) er formen Supabase
sine Database Webhooks sender, så den er sannsynligvis koblet i
Dashboard — altså konfigurasjon som ikke ligger i git og som jeg ikke
kan se herfra. Uten `WEBHOOK_SECRET` svarer den uansett 401.

**Merknad om bekreftelses-e-post:** dette korrigerer gårsdagens
rapport. Jeg skrev at `send-booking-email` trenger `WEBHOOK_SECRET`.
Det stemmer for påminnelsen, men ikke for bekreftelsen: triggeren
`trg_booking_email` (fra `0047`) kaller databasefunksjonen
`send_booking_email()`, som poster rett til Resend og aldri rører
Edge-funksjonen. Det er to uavhengige e-postveier med hver sin
manglende hemmelighet.

### Honeypot

Fire skjemaer har et honeypot-felt. Bare ett av dem har en
serverkontroll å svare på:

| Skjema | Felt | Serverkontroll | Sendes? |
|---|---|---|---|
| `kontakt.html` | `company` | Ja, `submit-contact` leser `payload.company` | Ja, siden i går |
| `venteliste.html` | `website` | Nei — går rett i tabellen | Ikke relevant |
| `anmeldelser.html` | `website` | Nei — `submit_review_by_token` har ingen slik parameter | Ikke relevant |
| bookingflyten | `website` | Nei — går rett i tabellen | Ikke relevant |

Det betyr at tre av fire honeypoter bare virker i nettleseren. En bot
som poster rett mot API-et går utenom dem. Ratelimit er forsvaret der,
og det virker (se under). Dette er en observasjon, ikke en feil jeg
har rettet.

---

## Klasse 2 — manglende grants

Spurte databasen i stedet for å lese migrasjonene: hver tabell testet
med ekte forespørsler i hver rolle. `42501` betyr manglende grant. Tom
liste betyr at RLS gjorde jobben sin, som er noe annet.

### Tabeller

`anon`, med nøyaktig de kolonnene bookingmotoren ber om: `services`,
`staff_services`, `staff_members`, `holidays`, `blocked_slots`,
`special_open_days` — alle OK. `blocked_slots` og `special_open_days`
har kolonne-grants (`0057`, `0059`), så et `select=*` gir 42501 mens
det motoren faktisk spør om går gjennom. Verdt å vite før man tester.

`authenticated`, alle 17 tabeller: to gir 42501, begge med vilje.
`journal_entries` går bare gjennom `get_journal_entries()` som logger
hvert oppslag (`0069` sier det rett ut), og `anon_insert_events` er
kvotetabellen som bare triggeren og `service_role` skal røre.

Skriverettigheter testet med filtre som ikke treffer noen rad, og
innsettinger med ugyldige verdier, så ingenting ble endret. To DELETE
mangler for `authenticated`: `reviews` og `staff_members`. Begge er
riktige — ingenting i frontenden sletter dem. Behandlere deaktiveres,
anmeldelser modereres.

`service_role` er ikke testet ved introspeksjon (jeg har ikke nøkkelen)
men ved kjøring: `submit-contact` gjør select og insert på
`anon_insert_events` og insert på `contact_messages`, og den svarer
200 på live. `0073` ga dem i går. `push_subscriptions` hadde dem
allerede fra `0063` — min grant der var overflødig, men harmløs.

### RPC-er: her lå hullet

Åtte offentlige RPC-er, begge roller:

| RPC | anon | authenticated |
|---|---|---|
| `get_booked_slots` | 200 | 200 |
| `cancel_booking_by_ref` | 200 | 200 |
| `cancel_booking_by_token` | 200 | 200 |
| `lookup_booking_by_token` | 200 | 200 |
| `cancel_waitlist_by_ref` | 200 | 200 |
| `get_waitlist_position` | 200 | 200 |
| `lookup_review_by_token` | 200 | **403** |
| `submit_review_by_token` | 200 | **403** |

`0042` gir EXECUTE på begge review-funksjonene til `anon` alene.
Anmeldelsessiden sendte adminsesjonen, så alle som hadde vært innom
adminpanelet først — og panelet logger inn av seg selv — fikk 403 og
et skjema som ikke virket.

Det er nøyaktig ventelistefeilen, i et annet endepunkt.

Bekreftet i nettleseren på live: `403 rpc/submit_review_by_token`.
Samme kall som anon fra curl: `200 {"ok": true}`. Forskjellen er
rollen, ikke kallet.

**Rettet med samme grep som ventelista:** klienten på
`anmeldelser.html` leser ikke sesjonen. Rettighetene i databasen er
ikke rørt. Et offentlig skjema skal ikke opptre som en innlogget
ansatt. Verifisert etterpå på live med adminsesjon i nettleseren:
`200 rpc/submit_review_by_token`.

**Ingen migrasjon skrevet.** Det fantes ingen grants som manglet for
noe en ekte kaller gjør. Hullet var på klientsiden.

---

## Klasse 3 — plassholdere som ser ekte ut

251 treff totalt. De fleste er ufarlige og hører hjemme: 137 `.example`
er den oppdiktede klinikkens eget domene, og 72 `placeholder` er
`placeholder=`-attributter på skjemafelt.

| Treff | Sted | Vurdering |
|---|---|---|
| `demo.westengenklinikk.example` som `base_url` | `0048` linje 49, `0056` linje 47 | **Reelt. Se under** |
| `REDACTED_RESEND_KEY` | `0048` linje 45, `0056` linje 45 | **Reelt.** Plassholder der en API-nøkkel skal stå |
| `MARKUS'&nbsp;A****` | `0026`, `0028`, `0039`, `0040`, `0048` | **Reelt.** Gammelt prosjektnavn i e-post til kunder |
| `http://localhost:8000`, `http://127.0.0.1:8766` | `submit-contact` CORS-liste | Ufarlig. Lokale utvikleradresser, med vilje |
| `http://localhost:5500` | `0026`, `0028` | Ufarlig. Historiske filer, erstattet av `0029` |
| `onboarding@resend.dev` | e-postmaler, `0011` m.fl. | Ufarlig, men se merknad |
| `post@westengenklinikk.example` | `0048` (`notify_to`, `reply_to`) | Ufarlig. Den oppdiktede klinikkens adresse |
| `test@example.com` o.l. | kommentarer i `0051`, `0053`, `0060`, `0054` | Ufarlig. Eksempler i dokumentasjon |
| `*@example.com` | `supabase/tests/01_rls_policies.sql` | Ufarlig. Testdata i RLS-tester |
| `patient@example.com` | `shared/auth.js` linje 152, i kommentar | Ufarlig |
| 6 × `TODO` | spredt | Ufarlig, sjekket enkeltvis |
| 6 × `din-` | tekst på norsk («din-» i ord) | Falske treff |

### base_url peker på domenet som brøt CORS

De to funksjonene som bygger lenker inn i e-post har begge

    base_url text := 'https://demo.westengenklinikk.example';

Det er samme plassholderdomene som sto i CORS-allowlisten og gjorde at
kontaktskjemaet aldri kunne virke. Domenet finnes ikke.

Hver avbestillingslenke i hver bekreftelse, og hver lenke i hver
anmeldelses-e-post, peker altså ingen steder. Det ville ikke vist seg
før e-posten begynte å gå ut — altså i det øyeblikket nøkkelen kom på
plass og alt så ut til å virke.

**Jeg har ikke rettet det.** Grunnen står i neste avsnitt.

> **Rettet i ettertid.** Se seksjonen «0074 — base_url og gammelt
> prosjektnavn» nederst i dokumentet.

### Fem migrasjoner kan ikke ha kjørt som de står i git

Da jeg skrev migrasjonen som skulle bytte `base_url`, ble den avvist:

    ERROR: unterminated quoted string (SQLSTATE 42601)

Årsaken er denne linja, som står ordrett i `0048`:

    ||   '<div style="...">MARKUS'&nbsp;A****</div>'

Apostrofen i `MARKUS'` er ikke escapet. I PostgreSQL lukker den
strengen, og resten er søppel. Det er ikke en teori: `supabase db push`
avviste nøyaktig de bytene mot nøyaktig denne databasen.

Samme linje finnes i fem migrasjoner: `0026`, `0028`, `0039`, `0040`
og `0048`. Alle fem definerer funksjoner som sender e-post.

Og alle fem står som appliserte:

    npx supabase migration list --linked
    → 0026, 0028, 0039, 0040, 0048: local = remote

Begge deler kan ikke være sanne om det som står i git. Den mest
sannsynlige forklaringen står i `0048` sin egen kommentar: nøkkelen
«settes manuelt i SQL Editor». Da er funksjonen limt inn for hånd, med
apostrofen og nøkkelen ordnet der, og migrasjonsloggen stemplet
etterpå.

Konsekvensen er at **repoet ikke er en tro kopi av databasen for
e-postfunksjonene**. Jeg vet ikke hva som faktisk kjører, og derfor har
jeg ikke skrevet en migrasjon som overskriver dem: den ville i verste
fall slettet en ekte Resend-nøkkel du har limt inn for hånd, og byttet
ut en funksjonskropp jeg ikke har sett.

To ting følger av det, og begge er dine:

**1. Finn ut hva som faktisk kjører.** I SQL-editoren:

    select proname,
           position('demo.westengenklinikk.example' in prosrc) > 0 as har_dodt_domene,
           position('REDACTED_RESEND_KEY'          in prosrc) > 0 as har_plassholder_nokkel,
           position('MARKUS'                       in prosrc) > 0 as har_gammelt_navn
      from pg_proc
     where proname in ('send_booking_email', 'process_pending_review_emails');

**2. Rett det som er galt, der.** Byttet er én linje per funksjon:

    base_url text := 'https://booking-demo-rosy.vercel.app';

Si fra hvis du vil at jeg skriver migrasjonen når du har sagt hva som
står der. Da gjør jeg det på ti minutter.

> **Rettet i ettertid.** Se seksjonen «0074 — base_url og gammelt
> prosjektnavn» nederst i dokumentet.

### Gammelt prosjektnavn i e-post til kunder

Samme linje inneholder `MARKUS'&nbsp;A****` — monogrammet fra
prosjektet demoen kom ut av. Står i toppen av bekreftelsen kunden får,
i varselet til klinikken, i kontaktmeldingsvarselet og i
dokumentutsendingen.

E-postene bruker også den gamle varme paletten (`#3E6B47` grønn,
`#FAF7F1` krem), som ble byttet ut for to runder siden.

Jeg har ikke rørt det. Du ba meg ikke skrive om tekst denne runden, og
det henger uansett sammen med spørsmålet over: jeg vet ikke om det som
kjører i databasen har den samme teksten.

> **Rettet i ettertid.** Se seksjonen «0074 — base_url og gammelt
> prosjektnavn» nederst i dokumentet.

### onboarding@resend.dev

`from_email` er satt til Resends egen testavsender. Den virker bare til
adressen som eier Resend-kontoen. Skal demoen sende til andre, må
domenet verifiseres hos Resend og `from_email` byttes.

---

## Nettlesertester på live

Curl bommet på alle tre feilene i går. Alt under er derfor gjort
gjennom det ekte skjemaet på `booking-demo-rosy.vercel.app`, med en
adminsesjon liggende i nettleseren — den tilstanden som avslørte både
ventelistefeilen og anmeldelsesfeilen.

| Endepunkt | Nettverkssvar | Rad i basen | Synlig der den skal |
|---|---|---|---|
| Bestilling | `201 POST bookings` | Ja, ref `TA-FEYI-6107` | Kvittering med referanse, behandler, tid, pris |
| Avbestilling | `200 rpc/cancel_booking_by_ref` | Status satt til `cancelled` | «Timen din er avbestilt» med referanse |
| Venteliste | `201 POST waitlist` + `200 rpc/get_waitlist_position` | Ja, riktig behandler og dato | Kvittering med referanse og køplass |
| Kontakt | `200 submit-contact` | Ja, `status: new` | «Takk! Meldingen er sendt» |
| Anmeldelse | `200 rpc/submit_review_by_token` | Ja, `status: pending` | «Takk for anmeldelsen!» |

Anmeldelse var `403` før fiksen i denne runden. De fire andre virket.

### Opprydding

Slettet: 5 bookinger, 3 ventelisterader, 3 kontaktmeldinger.
Bekreftet 0 ikke-seed-rader igjen i `bookings`, `waitlist`,
`contact_messages`, `blocked_slots`, `holidays` og
`special_open_days`.

**To testanmeldelser står igjen.** `authenticated` har ikke DELETE på
`reviews`, med vilje — anmeldelser modereres, de slettes ikke. Jeg satte
dem til `rejected`, som er det systemet selv tillater. De er ikke
synlige for publikum: anon ser fem anmeldelser, alle `approved`, ingen
av dem mine. Den nattlige nullstillingen fjerner dem helt.

---

## Ratelimit

Turnstile står på testhemmeligheten og godkjenner alt, så kvotetabellen
er eneste reelle forsvar mot en bot akkurat nå. Den er verifisert ved å
sende nok forsøk til at grensen slo inn.

| Endepunkt | Grense per IP | Globalt | Vindu | Håndhevet av | Verifisert |
|---|---|---|---|---|---|
| Bestilling | 5/time | 20/time | 60 min | DB-trigger `trg_anon_quota_bookings` | Ja — 5. forsøk: `500` med `53400` |
| Kontakt | 3/time | 15/time | 60 min | Edge Function **og** DB-trigger | Ja — 3. forsøk: `429 rate_limited` |
| Venteliste | 3/time | 15/time | 60 min | DB-trigger `trg_anon_quota_waitlist` | Ja — 3. forsøk: `500` med `53400` |
| Anmeldelse | ingen kvote | — | — | Token-gating i stedet (`0042`) | Én token, én anmeldelse |

Forsøkene ble sendt rett mot API-et, ikke gjennom skjemaet. Det er
slik en bot ville gjort det, og det er kvoten som er forsvaret mot
nettopp det.

Kontakt har to lag: Edge-funksjonen teller selv før den setter inn og
svarer `429`, og DB-triggeren ville uansett stoppet innsettingen. Det
er grunnen til at kontakt gir en pen HTTP-kode mens de to andre gir
`500` — de går rett i tabellen, og PostgREST oversetter `53400` til
`500`.

**Ikke verifisert:** at kvoten slipper gjennom igjen etter vinduet.
Det krever å vente ut timen. Mekanismen er en glidende
60-minuttersperiode i trigger-funksjonen
(`created_at > now() - v_window`), og tabellen ryddes for hendelser
eldre enn 24 timer. Jeg observerte blokkeringen, ikke frigivelsen.

---

# 0074 — base_url og gammelt prosjektnavn

Sveipen over fant to plassholdere i e-postfunksjonene og lot dem stå,
fordi repoet ikke er en tro kopi av databasen og jeg ikke hadde sett
hva som faktisk kjørte. Denne runden fikk jeg lest kroppene ut av
produksjon. De er nå rettet.

**Metoden.** Ingen funksjonskropp er skrevet for hånd. Definisjonen
leses ut av katalogen med `pg_get_functiondef()`, to strenger byttes i
minnet, og resultatet kjøres tilbake med `execute`. Da er det som
faktisk kjører fasit, og alt annet i kroppen står urørt: tekst, farger,
logikk, og verdier som er satt for hånd i SQL-editoren.

Kopien av kroppene slik de kjørte før endringen ligger i
`docs/db-funksjoner-før-0074.sql`, committet før noe ble rørt.

## Hva som faktisk sto i produksjon

| Funksjon | Plassholder-`base_url` | Gammelt prosjektnavn |
|---|---|---|
| `send_booking_email` | Ja | Ja |
| `process_pending_review_emails` | Ja | Nei |
| `send_contact_message_email` | Nei | Ja |
| `send_document_email` | Nei | Ja |

To ting stemte ikke med det oppdraget forutsatte.

**Navnet var ikke det git sier.** Git har `MARKUS'&nbsp;A****`.
Produksjon hadde `ERIKS&nbsp;A****` — null treff på «MARKUS» som
merkenavn i noen av kroppene. Kroppen som kjører er altså eldre enn
den i git, fra før navnebyttet Erik → Markus. Det er samme observasjon
som avsnittet «Fem migrasjoner kan ikke ha kjørt som de står i git»,
sett fra den andre siden.

**To funksjoner til var rammet.** Sluttkontrollen skulle bekrefte at
ingen andre funksjoner i `public` hadde navnet. Den slo feil:
`send_contact_message_email` og `send_document_email` hadde det også.
`send_document_email` sender til `new.customer_email`, altså til kunden
selv. De to er rettet i `0075` med samme metode.

## Hva som ble byttet

Eksakte strenger, ingenting annet:

| Fra | Til | Hvor |
|---|---|---|
| `https://demo.westengenklinikk.example` | `https://booking-demo-rosy.vercel.app` | `0074`, 2 funksjoner |
| `ERIKS&nbsp;A****` | `WESTENGEN&nbsp;KLINIKK` | `0074`, 1 funksjon · `0075`, 2 funksjoner |

`&nbsp;` er HTML-entiteten, ikke et hardt mellomrom. Byteformen ble
lest ut av dumpen før erstatningen ble skrevet.

**Urørt med vilje.** `resend_key` står fortsatt som
`REDACTED_RESEND_KEY` i alle fire. E-postene bruker fortsatt den gamle
varme paletten. Og `notify_to` i `send_booking_email` er en ekte privat
e-postadresse — den er operatørens eget valg og er ikke tatt i. Fordi
repoet er offentlig er nøyaktig den ene linja maskert i den committede
dumpen; verdien i databasen er uendret.

## Sluttkontroll

| Kontroll | Resultat |
|---|---|
| Ingen av de gamle strengene igjen | `dodt_domene=false`, `gammelt_navn=false`, `ny_url=true` for begge i `0074` |
| Ingen andre funksjoner i `public` har det gamle navnet | 0 treff (`prokind = 'f'`, hele skjemaet) |
| Diff før/etter, `process_pending_review_emails` | 1 endret linje — `base_url` |
| Diff før/etter, `send_booking_email` | 2 endrede linjer — `base_url` og navnet |
| Diff før/etter, `0075`-funksjonene | 1 endret linje hver — navnet |
| Eier, `SECURITY DEFINER`, `search_path` | Uendret på alle fire: `postgres`, `true`, `{search_path=public, extensions}` |
| Lenkene funksjonene nå bygger | `200` — `/avbestill.html?token=…` og `/anmeldelser.html?token=…` på live |

Ingen uventede linjer i noen av diffene.

## Repoet mot databasen etter dette

De fem migrasjonene som ikke kunne kjøre — `0026`, `0028`, `0039`,
`0040`, `0048` — er gjort kjørbare. Ett tegn per fil: apostrofen i
`MARKUS'&nbsp;A****` er escapet til `''`. Ingenting annet er endret.
`git diff` er fem linjer.

**Forutsetningen ble bekreftet før filene ble rørt.** Alle fem står
registrert i `supabase_migrations.schema_migrations` — 0026
`email_brand_redesign`, 0028 `email_html_escape`, 0039
`contact_messages`, 0040 `exercise_documents`, 0048
`customer_confirmation_email`, 5 av 5. En `db push` kan derfor ikke
kjøre dem på nytt mot produksjon.

Det som er i sync nå: databasen er riktig, og prosjektet kan bygges opp
fra bunn uten å stoppe på `0026`.

**Det som fortsatt ikke er i sync:**

- Filene beskriver en eldre tilstand enn den som kjører. Bygges
  prosjektet fra bunn, gjenoppstår både plassholder-`base_url` og det
  gamle navnet i `0026`–`0048`, og forsvinner først når `0074` og
  `0075` kjører etterpå. Sluttresultatet blir riktig; mellomtilstanden
  er det ikke.
- Ingen migrasjon i git gjengir kroppene slik de faktisk sto i
  produksjon. `docs/db-funksjoner-før-0074.sql` er den eneste kopien,
  og den er dokumentasjon, ikke en migrasjon.
- `resend_key` er fortsatt plassholderen. Ingen e-post går ut før den
  er satt i SQL-editoren, og da må den settes i alle fire funksjonene.
- Den private adressen i `notify_to` ligger fortsatt i en
  `SECURITY DEFINER`-funksjon i en demo som er åpen. Den er ikke min å
  bytte, men du bør bestemme om den skal stå der.

---

# Sveip av databasen

Alle tidligere lekkasjesveip har gått over filer. `0074`/`0075` viste at
funksjonskroppene i produksjon er eldre enn repoet, og at fire av dem bar
et navn fra før omdøpingen. Denne runden går derfor over databasen selv.

Rent lese- og rapportoppdrag. Ingenting er endret.

**Flater som ble sett på:** funksjonskropper i alle skjemaer jeg har
tilgang til, view- og matview-definisjoner, RLS-policyer (`USING` og
`WITH CHECK`), kolonne-defaults, constraints, triggerdefinisjoner,
kommentarer på tabeller og kolonner, egendefinerte typer, `cron.job`,
seed-data i alle 17 tabeller i `public`, storage-buckets og -objekter,
`auth.users`, `vault.secrets`, `net`-tabellene og
`supabase_migrations.schema_migrations`.

---

## Hastegrad 1 — lesbart for publikum akkurat nå

### «Erik» står i behandlerbiografiene

`public.staff_members.bio`, 8 av 9 rader:

| `staff_id` | Tekst |
|---|---|
| `sofie`, `henrik`, `jonas`, `amina`, `nora`, `lena`, `petter` | «Opplært direkte av **Erik**. Samme metodikk, samme grundighet.» |
| `terapeut` | «Vi tildeler en av våre erfarne terapeuter, alle opplært direkte i **Eriks** metoder. Samme filosofi, samme grundighet.» |

**Lesbart for publikum: ja.** `anon` har `SELECT` på kolonnen `bio`, og
policyen `staff_members read active: anon` slipper gjennom alt med
`aktiv = true`. Alle åtte radene er aktive. Én forespørsel mot
`/rest/v1/staff_members?select=name,bio` gir dem ut, og behandlerlista
på forsiden leser fra samme tabell.

Dette er samme rest som `0074` fant i e-postmalene, på en flate ingen
har sett på. Navnet på et tidligere kundeprosjekt står i klartekst i en
offentlig arbeidsprøve.

**Foreslått rettelse:** `update` av de åtte `bio`-verdiene. Verdt å
merke seg: `demo_seed()` rører ikke `staff_members` i det hele tatt, og
`demo_reset()` sletter bare rader med `is_demo_seed = false` der. En
endring av teksten overlever altså den nattlige nullstillingen. Et
forslag er «Opplært direkte av Markus. Samme metodikk, samme
grundighet.» — men dette er din tekst, så si hva den skal være.

---

## Hastegrad 2 — forlater systemet, men er ikke lesbart via API-et

### Privat e-postadresse i `send_booking_email`

    notify_to text := '<privat gmail-adresse, maskert>';

**Lesbart for publikum: nei.** Verken `anon` eller `authenticated` kan
nå funksjonskropper gjennom PostgREST. Men adressen er mottaker for
hvert bookingvarsel, så den forlater systemet hver gang noen bestiller.

Kjent fra `0074`, som lot den stå etter regelen om å ikke røre noe
annet i kroppene. Tas med her fordi sveipen skal være komplett.

**Foreslått rettelse:** bytt til `post@westengenklinikk.example`, som de
tre andre funksjonene allerede bruker, eller til en adresse du faktisk
vil ha varsler på. Din avgjørelse.

### Ekte gateadresse i e-postbunnteksten

`send_booking_email`, `send_document_email` og
`process_pending_review_emails` har alle

    Westengen Klinikk · <ekte gateadresse i Oslo, maskert>

og `send_document_email` i tillegg `+47 400 00 0**`.

Adressen er en ekte adresse i Oslo som tilhører noen andre. Den står i
bunnteksten på e-post fra en oppdiktet klinikk. Telefonnummeret ser
oppdiktet ut, men ligger i et gyldig norsk mobilnummerområde.

**Lesbart for publikum: nei** — men det går ut i hver e-post.

**Foreslått rettelse:** enten en åpenbart oppdiktet adresse, eller drop
adresselinja. Nummeret bør merkes som demo eller fjernes.

### Tre av fire e-postfunksjoner mangler plassholdervakten

| Funksjon | Vakt mot plassholdernøkkel | Kaller `api.resend.com` |
|---|---|---|
| `process_pending_review_emails` | Ja | Ja |
| `send_booking_email` | **Nei** | Ja |
| `send_contact_message_email` | **Nei** | Ja |
| `send_document_email` | **Nei** | Ja |

Alle fire har fortsatt `resend_key = 'REDACTED_RESEND_KEY'`. De tre uten
vakt sender likevel HTTP-kallet, med plassholderstrengen som
bearer-token. `net._http_response` har 13 svar fra i dag mellom 10:45 og
10:54 UTC, alle

    {"statusCode":401,"name":"validation_error","message":"API key is invalid"}

Tidsvinduet er nøyaktig nettlesertestene i forrige runde. Hver
bestilling, kontaktmelding og dokumentutsending gjør altså i dag et
utgående kall som garantert feiler.

Ingen hemmelighet lekker — plassholderen er ikke en nøkkel. Men det er
et utgående kall per hendelse, og svarene logges.

**Lesbart for publikum: nei.** `net._http_response` har ingen grants til
`anon` eller `authenticated`.

**Foreslått rettelse:** samme vakt som `process_pending_review_emails`
allerede har, i de tre andre.

---

## Hastegrad 3 — internt

### Kolonnekommentaren avslører hvordan omdøpingen ble gjort

`public.staff_members.color`:

> Hex-farge (#RRGGBB) for behandlerens fargebar i admin-UI. **Erik
> streng** = bruk frontend-fallback. Migrasjon 0049.

Det skal stå «Tom streng». Et blindt søk-og-erstatt av `Tom` → `Erik`
har truffet det norske ordet «tom». Kommentaren er den eneste plassen
skaden er synlig i databasen, men den forklarer hvorfor
`ERIKS&nbsp;A****` sto i produksjon mens git sa `MARKUS'&nbsp;A****`:
navnet er byttet minst to ganger med tekstsøk, ikke med omtanke.

**Lesbart for publikum: nei.** Kolonnekommentarer eksponeres ikke
gjennom PostgREST.

**Foreslått rettelse:** `comment on column` med «Tom streng».

### Seed-telefonnumre i pasientdata

`+47 400 00 0**`-serien (20 numre) står i `bookings.phone`,
`journal_entries.patient_phone`, `waitlist.phone` og
`contact_messages`, parvis med `@eksempel.example`-adresser.

Numrene er systematiske og åpenbart oppdiktede, men ligger i et gyldig
norsk mobilnummerområde og kan i prinsippet tilhøre en abonnent.

**Lesbart for publikum: nei.** Ingen av de fire tabellene har `SELECT`
for `anon`. `journal_entries` har ingen `SELECT`-grant i det hele tatt.

**Foreslått rettelse:** ingen hast. Vil du ha full sikkerhet, bytt
seriene i `demo_seed()` til noe utenfor tildelt nummerserie.

### `cron.job.nodename` har default `'localhost'`

Det er pg_cron sin egen kolonnedefault, ikke en plassholder noen har
glemt. Alle fire jobbene kjører mot `localhost:5432`, som er riktig.
Ingen handling.

---

## Flater som var rene

| Flate | Funn |
|---|---|
| `auth.users` | 2 kontoer, `admin@` og `terapeut@westengenklinikk.example`. Ingen ekte adresse. |
| Storage | Én bucket, `exercise-documents`, **ikke** offentlig. Null objekter. |
| `vault.secrets` | Tom. `process_pending_reminders` og `process_pending_sms_reminders` henter URL og webhook-secret derfra, og er derfor no-ops. |
| `net._http_response` | 13 rader, alle 401-svar. Ingen nøkkel i innholdet. Ikke lesbar for `anon`/`authenticated`. |
| `supabase_migrations.schema_migrations` | 75 rader med full migrasjons-SQL. Verken `anon` eller `authenticated` har `USAGE` på skjemaet. |
| Views og matviews | Finnes ikke i `public`. |
| Triggerdefinisjoner, constraints, defaults, enum-verdier | Null treff. |
| Ordet «test» | Null treff i funksjoner, null i data. Kommentartreffene er PostgreSQLs egne. |
| `localhost`, `127.0.0.1`, private IP-er | Kun pg_cron-defaulten over. |
| Organisasjonsnumre | Null treff. |
| «T*** A****», «A****» | Null treff noe sted i databasen. |
| `.example`-domener | Kun `westengenklinikk.example` og `eksempel.example`. Begge er reservert TLD og kan ikke registreres. |

Merk at `blocked_slots` og `special_open_days` har `SELECT` for `anon`
på kolonnenivå (`date, staff_id, time` og `date, staff_id, open_time,
close_time`), ikke på tabellnivå. Ingen av kolonnene inneholder tekst.

---

## Cron-status

`cron.job` — fire aktive jobber:

| jobid | Navn | Plan | Kommando |
|---|---|---|---|
| 1 | `westengen-klinikk-24h-reminders` | `5 * * * *` | `select public.process_pending_reminders();` |
| 3 | `westengen-klinikk-review-emails` | `15 * * * *` | `select public.process_pending_review_emails();` |
| 4 | `westengen-klinikk-24h-sms-reminders` | `7 * * * *` | `select public.process_pending_sms_reminders();` |
| 5 | `demo-nightly-reset` | `15 4 * * *` | `select public.demo_reset();` |

`jobid = 2` finnes ikke. Ingen jobbnavn eller kommando inneholder rester.

`cron.job_run_details`, rått:

| Jobb | Status | Antall | Første | Siste |
|---|---|---|---|---|
| `demo-nightly-reset` | succeeded | 1 | 2026-09-02 04:15 UTC | 2026-09-02 04:15 UTC |
| `westengen-klinikk-24h-reminders` | succeeded | 38 | 2026-09-01 01:05 UTC | 2026-09-02 14:05 UTC |
| `westengen-klinikk-24h-sms-reminders` | succeeded | 38 | 2026-09-01 01:07 UTC | 2026-09-02 14:07 UTC |
| `westengen-klinikk-review-emails` | succeeded | 38 | 2026-09-01 01:15 UTC | 2026-09-02 14:15 UTC |

Null rader med annen status enn `succeeded`. Ingen feilmeldinger; alle
`return_message` er `1 row`.

**Den nattlige nullstillingen har kjørt.** Runid 84, 2026-09-02
04:15:00 UTC, `succeeded`. Det er første bekreftede kjøring.

Ett tall er tvetydig, og jeg lar det stå som det er: loggen starter
2026-09-01 01:05 UTC, altså før 2026-09-01 04:15, men det finnes ingen
kjøring av jobb 5 den natta. Enten ble jobben opprettet i løpet av
2026-09-01, eller så uteble den kjøringen. Jeg kan ikke skille de to
fra dataene som ligger der.

### Innhold og etterlatte rader

| Tabell | Totalt | Seed | Ikke seed |
|---|---|---|---|
| `services` | 4 | 4 | 0 |
| `staff_services` | 36 | 36 | 0 |
| `staff_members` | 9 | 9 | 0 |
| `bookings` | 80 | 80 | 0 |
| `journal_entries` | 54 | 54 | 0 |
| `contact_messages` | 8 | 8 | 0 |
| `exercise_documents` | 8 | 8 | 0 |
| `blocked_slots` | 6 | 6 | 0 |
| `waitlist` | 5 | 5 | 0 |
| `holidays` | 2 | 2 | 0 |
| `special_open_days` | 1 | 1 | 0 |
| `reviews` | 10 | 8 | **2** |

`services` og `staff_services` har innhold. De to ikke-seed-radene er
mine testanmeldelser fra forrige runde, opprettet 2026-09-02 10:48 og
10:51 UTC, begge satt til `rejected`. De er ikke synlige for `anon`, som
bare ser `status = 'approved'`. `demo_reset()` sletter `reviews where
not is_demo_seed`, så de forsvinner ved neste kjøring 04:15. Grunnen til
at de fortsatt står er at de ble opprettet etter nattens nullstilling,
ikke at nullstillingen lot dem være.

---

# 0076 — rester etter navnebytte

De fire funnene fra sveipen av databasen er rettet. Migrasjon
`0076_rester_etter_navnebytte.sql`, applisert 2026-09-02.

Metoden er den samme som i `0074`/`0075` der funksjonskropper er
involvert: definisjonen leses ut av katalogen med
`pg_get_functiondef()`, endres i minnet, og kjøres tilbake. Ingen kropp
er skrevet for hånd. Kopi av alle fire kropper før endringen ligger i
`docs/db-funksjoner-før-0076.sql`, committet før noe ble rørt, med den
private adressen maskert.

## Hva som sto der, og hva som ble byttet

### 1. Biografiene

`staff_members.bio`, 8 av 9 rader:

| Før | Etter | Rader |
|---|---|---|
| «Opplært direkte av **Erik**. Samme metodikk, samme grundighet.» | «Opplært direkte av **Markus**. …» | 7 |
| «…alle opplært direkte i **Eriks** metoder.» | «…alle opplært direkte i **Markus'** metoder.» | 1 |

Genitiven måtte tas først. Byttes `Erik` før `Eriks`, blir «Eriks» til
«Markuss». Norsk genitiv av et navn som ender på s er apostrof alene.

Erstatningen gikk mot verdiene som faktisk lå i radene, ikke mot
strengene i oppdraget. `services` ble sjekket for samme formulering:
null treff i `name`, `description` og `slug`. `staff_members.name` og
`.role` var også rene — `terapeut` hadde allerede «Opplært av Markus
selv» som rolle.

**Presisering av gårsdagens rapport.** Jeg skrev at «behandlerlista på
forsiden leser fra samme tabell». Det er upresist. Bioene var lesbare
gjennom `anon`-API-et — det stemmer — men de ble ikke gjengitt på noen
offentlig side: `behandlere.html` er adminsiden og viser ikke bio, og
bestillingsflyten viser bare de to som er `bookable`, med teksten hentet
fra `i18n` (`booking.staff.<id>.bio`) og databaseverdien kun som
fallback. Begge i18n-filene sa allerede «Markus'». Eksponeringen var
altså reell, men gikk gjennom API-et alene.

### 2. Kolonnekommentaren

`staff_members.color`:

> Hex-farge (#RRGGBB) for behandlerens fargebar i admin-UI. **Tom
> streng** = bruk frontend-fallback. Migrasjon 0049.

Lest ut av katalogen, «Erik streng» byttet til «Tom streng», resten
urørt.

### 3. `notify_to`

`send_booking_email` pekte på en privat gmail-adresse. Byttet til
`post@westengenklinikk.example`, samme som de tre andre bruker.

Adressen står ikke i migrasjonsfila. Den ble matchet med et mønster mot
det som faktisk lå i katalogen — repoet er offentlig.

### 4. Plassholdervakten

Vakten ble lest ut av `process_pending_review_emails` og speilet inn i
de tre andre, spleiset rett etter funksjonens egen `begin`:

    if resend_key = 'REDACTED_RESEND_KEY' then
      raise warning '<funksjon>: Resend-nøkkel er placeholder — hopper over (sandbox-modus).';
      return new;
    end if;

To tilpasninger, begge nødvendige: funksjonsnavnet i meldingen, og
`return new` i stedet for `return`, fordi de tre er trigger-funksjoner
og ikke `void`. Kommentarlinja om cron-tikk er utelatt — den gjelder
bare den køstyrte funksjonen. Funksjonene avslutter stille; de kaster
ikke feil.

## Verifisering

| Kontroll | Resultat |
|---|---|
| «Erik» borte fra `bio` | 8 rader oppdatert, 0 treff igjen i `bio`, `name` og `role` |
| Genitiv | `terapeut` har «Markus' metoder» med apostrof |
| Kolonnekommentaren | «Tom streng = bruk frontend-fallback» |
| `notify_to` byttet | Ja, og ingen `@gmail.com` igjen i noen funksjon i `public` |
| Resten av kroppene | Diff mot sikkerhetskopien: `send_booking_email` 1 endret linje + 8 nye (vakten); `send_contact_message_email` og `send_document_email` 8 nye hver; `process_pending_review_emails` identisk. Null uventede linjer. |
| Alle fire har vakten | Ja |
| Eier / `SECURITY DEFINER` / `search_path` | Uendret på alle fire: `postgres`, `true`, `{search_path=public, extensions}` |
| Returtyper | Uendret: `trigger` på de tre, `void` på den fjerde |

### Ingen nye kall til Resend

Alle tre kodeveiene ble utløst med ekte innsettinger: en booking, en
kontaktmelding og en dokumentutsending.

| Måling | Før | Etter |
|---|---|---|
| Rader i `net._http_response` | 13 | 13 |
| Høyeste id | 693 (2026-09-02 10:54) | 693 |
| Rader i `net.http_request_queue` | 0 | 0 |

Lest to ganger, 14 sekunder fra hverandre. Null nye kall, null nye
401-er, ingenting i kø. Til sammenligning ga de samme tre kodeveiene 13
× `401 API key is invalid` før endringen.

Testradene er slettet igjen og bekreftet borte: 0 igjen i `bookings`,
`contact_messages` og `document_sends` på testadressen.

### På live

Hentet gjennom `anon`-API-et fra selve `booking-demo-rosy.vercel.app`,
med sidens egen anon-nøkkel:

    GET /rest/v1/staff_members?select=staff_id,name,bio&order=sortering
    → 200, 9 rader, 0 treff på «Erik», «Markus' metoder» på plass

Bestillingsflyten ble åpnet på live og de to behandlerkortene gjengir
riktig tekst. Null forekomster av «Erik» i sidens tekst.

---

## Ordgrense-sveip

Kolonnekommentaren beviste at et søk-og-erstatt uten ordgrense har
truffet det norske ordet «tom». Jeg lette etter samme skade i begge
retninger, over funksjonskropper, kommentarer, seed-data i alle
tabeller, RLS-policyer, constraints, kolonne-defaults og `cron.job`.

**Søkt etter:** et navn (`Markus`, `Erik`, `Toms`, `Tom`) med en
bokstav rett foran eller en liten bokstav rett etter — altså navnet
inne i et ord; feilformene `Markuss` og `Erikss` fra en genitiv som er
byttet i feil rekkefølge; `Klinikk` og `Westengen` inne i et annet ord,
som er samme feil den motsatte veien; og løsrevet «a****».

**Funn: null.** Ingen ødelagte ord noe sted i databasen utenom
kolonnekommentaren, som nå er rettet.

Det som derimot finnes, er stedene der de samme ordene står helt
legitimt. De er ikke feil, men de er nøyaktig det et nytt navnebytte
uten ordgrense vil ødelegge. Denne lista er til å ta stilling til, ikke
til å rette:

| Sted | Tekst | Vurdering |
|---|---|---|
| `create_journal_entry()` | «Notatet kan ikke være **tomt**» | Vanlig norsk ord. Vil bli ødelagt av `tom` → et navn. |
| `demo_seed()`, 4 steder | «audit-siden er **tom**», «en **tom** respons», «ikke er **tom**», «enn en **tom** liste» | Samme. Fire treff. |
| `staff_members.color` | «**Tom** streng = bruk frontend-fallback» | Nettopp rettet. Var «Erik streng». |
| `demo_seed()` og `journal_entries`, 11 rader | «**Symptom**fri ved siste kontroll» | Inneholder «tom». Ville blitt «Symp\<navn\>fri». |
| `send_booking_email()` | «Westengen Klinikk — **automatisk** varsel» | Inneholder «tom». |
| `send_contact_message_email()` | «**AUTOMATISK** VARSEL — WESTENGEN KLINIKK» | Samme, i versaler. |
| `blocked_slots`, `holidays` (kommentar) | «Hele-**klinikken**-stenging», «Datoer hele **klinikken** er stengt» | Vanlig ord, ikke merkenavn. |
| `send_booking_sms()`, `send_document_email()` | «kontakt **klinikken**» | Samme. |
| Fire e-postfunksjoner | `post@westengen**klinikk**.example` | Domenet til den oppdiktede klinikken. Riktig som det er. |
| `staff_members`, `waitlist`, `demo_seed()` | «**Markus'** terapeuter» | Riktig genitiv, fire steder. Ingen `Markuss`. |

Ett funn til, som ikke er en navnerest men kom fram i samme sveip:

| Sted | Tekst | Vurdering |
|---|---|---|
| `enforce_anon_insert_quota()` | «Vent litt og prøv igjen, eller ring klinikken på **+47 400 00 000**.» | Denne feilmeldingen går til `anon` når kvoten slår inn, altså rett til en besøkende. Nummeret er det oppdiktede demonummeret, samme som i e-postbunnteksten, men det er den ene plassen det faktisk vises til publikum. Vurder om det skal stå der. |

**Ikke rettet.** Ingenting i disse to listene er endret.

---

# Turnstile i produksjon

Både frontenden og Edge-funksjonen sto på Cloudflares testnøkler.
Testnøkkelen godkjenner alt, så hver positive test som noen gang er
kjørt mot kontaktskjemaet beviste ingenting om valideringen. Begge er
byttet, og valideringen er bevist med tester som må feile hvis den ikke
virker.

## Hva som ble byttet

### Site key

Testnøkkelen i repoet var `1x00000000000000000000BB`, ikke
`1x00000000000000000000AA`. Samme testnøkkelfamilie, men den usynlige
varianten — den rendrer ingen widget og produserer likevel et gyldig
token.

Den sto **ett sted i kode**: `data-sitekey` i `kontakt.html`. Sveipet
gjennom hele repoet bekreftet at den ikke lå igjen i i18n-filene, i
`sw.js`, i en kommentar med funksjonell virkning eller i en gammel kopi
av siden. `kontakt.html` er dessuten holdt utenfor service
worker-cachen — allowlisten i `sw.js` dekker kun admin-skallet — så
ingen stale kopi kan serveres fra en installert PWA.

Ny verdi: `0x4AAAAAAElCRZstoX978mDR`. Site key er offentlig og hører
hjemme i markup.

`data-size="invisible"` er fjernet sammen med testnøkkelen. Verdien
hørte til den usynlige testnøkkelen og er ikke en gyldig `data-size` —
Turnstile godtar `normal`, `compact` og `flexible`, mens synlighet
styres av widget-modus i Cloudflare-dashbordet.

Live ble kontrollert etter deploy: `kontakt.html` serverer den nye
nøkkelen, og det gamle `data-sitekey`-attributtet er borte.

### Secret

`TURNSTILE_SECRET_KEY` er satt med `supabase secrets set`. Verdien står
ikke i noen fil i repoet, ikke i en migrasjon og ikke her.

At testhemmeligheten er borte er bevist uten å røre verdien.
`supabase secrets list` returnerer SHA-256-digester, ikke verdier:

| | |
|---|---|
| Digest på funksjonen før | `fb8f3512…c0aae` |
| SHA-256 av `1x0000000000000000000000000000000AA` | `fb8f3512…c0aae` — **identisk** |
| Digest på funksjonen etter | `b47585f1…db053` |

Den satte verdien *var* altså testhemmeligheten, og er det ikke lenger.
De sju andre secrets er urørt.

## Bevis for at den faktisk validerer

Alle fire testene er kjørt mot live, fra sidens eget origin.

| Test | Token | Status | Kropp |
|---|---|---|---|
| **Positiv** — skjemaet på live, adminsesjon liggende | Ekte, fra widgeten | **200** | `{"ok":true}` |
| **Negativ 1** — tom token | `''` | **403** | `{"error":"captcha_required"}` |
| **Negativ 2** — tullete token | `dette-er-ikke-et-token-…` | **403** | `{"error":"captcha_failed"}` |
| **Negativ 3** — token fra annet domene | `XXXX.DUMMY.TOKEN.XXXX`, utstedt på `https://example.com` | **403** | `{"error":"captcha_failed"}` |

Den positive ble sendt gjennom det ekte skjemaet med
`admin@westengenklinikk.example` liggende i `localStorage` — samme
tilstand som avslørte både venteliste- og anmeldelsesfeilen tidligere.
Bekreftelsesteksten «Takk! Meldingen er sendt» ble vist, og raden lå i
`contact_messages` med `status = 'new'`.

De to første negative skiller seg i feilkode fordi de fanges på hvert
sitt sted: tom token stoppes av serversidevalideringen i steg 3, mens
et ugyldig token først faller på `siteverify` i steg 5. Begge er
avvisninger.

### Widgeten er domenebundet

Et forsøk på å rendre demoens ekte site key på `https://example.com` ble
**avvist ved utstedelse**, med Cloudflare-feilkode `110200` — domenet
står ikke på widgetens hostname-liste. En angriper på et annet domene
får altså ikke engang et token å prøve med. Det er derfor negativ 3
måtte bruke et token utstedt med Cloudflares testnøkkel: det var det
eneste ekte, fremmede tokenet som lot seg skaffe.

## Ratelimit

Uendret og fortsatt i kraft.

| Forsøk | Status | Kropp |
|---|---|---|
| 1 (positiv test) | 200 | `{"ok":true}` |
| 2 | 200 | `{"ok":true}` |
| 3 | 200 | `{"ok":true}` |
| 4 | **429** | `{"error":"rate_limited"}` |

Det fjerde forsøket ble sendt med et ugyldig token med vilje. Det fikk
likevel `429`, ikke `403` — fordi kvoten sjekkes i steg 4, før
Turnstile i steg 5. Det bekrefter både grensen på 3/time og
rekkefølgen i funksjonen.

Merk at kvoten kun telles etter en vellykket insert. De tre negative
testene brukte derfor ingen kvote, og en bot som spammer med ugyldige
tokens spiser ikke opp kvoten for reelle brukere.

## De tre andre offentlige endepunktene

Ingen av dem bruker Turnstile. Kontrollert, ikke antatt:

| Endepunkt | Hvordan | Resultat |
|---|---|---|
| Bestilling | `createBooking()` i bookingmotoren på live | `ok: true`, ref `TA-3QWE-3192`, rad i `bookings` |
| Avbestilling | `avbestill.html?token=…` med tokenet fra bookingen over, bekreftet i UI | RPC `cancel_booking_by_token` → **200** `{"ok":true}`, kvitteringsskjerm vist |
| Venteliste | Skjemaet på `venteliste.html` | Rad i `waitlist` med `status = 'waiting'`, `get_waitlist_position` → **200**, posisjon 3 |

## Hostname-konsekvensen for lokal utvikling

Widgeten er bundet til `booking-demo-rosy.vercel.app`. `localhost` og
`127.0.0.1` står ikke på hostname-lista. Konsekvensen er konkret:

Åpner du siden lokalt, får widgeten feilkode `110200` og utsteder
**ingen** token. Skjemaet sender da tom token, og Edge-funksjonen
svarer `403 captcha_required`. **Kontaktskjemaet kan ikke fullføres i
lokal utvikling.** Resten av siden er upåvirket — bestilling,
avbestilling og venteliste bruker ikke Turnstile og virker lokalt som
før.

Fire veier videre. Jeg har ikke valgt noen:

1. **Legg `localhost` til på widgetens hostname-liste i Cloudflare.**
   Enklest. Cloudflare støtter det eksplisitt. Svekker bindingen i
   teorien, men i praksis lite: `localhost` peker på angriperens egen
   maskin, så et token utstedt der er like vanskelig å skaffe seg som
   før. Ett dashbord-felt, ingen kodeendring.
2. **Egen widget for utvikling** — eget sitekey/secret-par med
   `localhost` på lista, valgt ut fra `location.hostname` i
   `kontakt.html`. Holder produksjonswidgeten helt ren, men krever at
   to nøkkelpar holdes i live og en betinget i markup.
3. **Bruk Cloudflares testnøkkel lokalt**, byttet inn på samme måte som
   over. Da validerer ingenting lokalt, men skjemaet lar seg klikke
   gjennom. Farlig hvis betingelsen noen gang feiler i produksjon.
4. **La det stå.** Kontaktskjemaet testes mot deployet versjon, ikke
   lokalt. Null endring, null risiko, men en lokal utvikler møter et
   skjema som ser ødelagt ut uten forklaring.

Alternativ 1 er det jeg ville valgt, men det er din avgjørelse.

## Widget, konsoll og layout

Widgeten kjører i usynlig modus fra Cloudflare-dashbordet: den rendrer
ingen iframe, men produserer et ekte token på 773–794 tegn. Konsollen
er tom ved fersk last — null feil, null advarsler.

Beholderen tar ~73 px høyde, gjennomsiktig, uten ramme eller bakgrunn.
Den har ingen inline bredde: plassert i en 320 px container krymper den
til 320 px, så den kan ikke sprekke layouten på smale skjermer. Målt i
container, ikke i et ekte smalt vindu.

## Én ting til, som du bør vite

Med testnøkkelen kom tokenet momentant. Med ekte nøkkel tar det
**6–10 sekunder** fra sidelast til tokenet finnes. I det vinduet vil et
klikk på «Send melding» sende tom token og få `403`, og brukeren ser
«Meldingen kunne ikke sendes. Prøv igjen.» — uten å få vite at det bare
var for tidlig.

Jeg klarte ikke å instrumentere den kodeveien rent: mine egne prober
overstyrte `window.fetch` og forstyrret skjemaet. Det er kontrollert at
submit-lytteren er påkoblet ved last og at den kaller `preventDefault()`
som den skal, så den native GET-innsendingen jeg så underveis var et
artefakt av automasjonen, ikke en produktfeil. **Selve tidsvinduet er
reelt og målt**, og bør sjekkes manuelt: last siden og klikk «Send
melding» med én gang.

Er det et problem, er det billig å fikse — hold knappen deaktivert til
`cf-turnstile-response` har verdi, eller si «Vent litt, sikkerhetssjekk
pågår» i stedet for den generiske feilen.

Cloudflare sluttet dessuten å utstede tokens til nettleseren min etter
fire–fem raske, automatiserte løsninger på få minutter, og begynte
igjen etter noen minutters pause. Det er Cloudflares egen
misbruksbeskyttelse og rammer ikke vanlige besøkende, men det gjør
automatisert testing av skjemaet tregt.

## Opprydding

Alle testrader er slettet og fraværet bekreftet: null ikke-seed-rader i
`bookings`, `contact_messages`, `waitlist`, `reviews`,
`journal_entries`, `blocked_slots`, `holidays` og `special_open_days`.

De to gamle testanmeldelsene fra sveiperunden er ryddet med i samme
slengen.

Kvotehendelsene i `anon_insert_events` står igjen — 3 på `contact`, 1
på `bookings`, 1 på `waitlist`. De er selve ratelimit-sporet, de er
uten personopplysninger, og den nattlige nullstillingen tømmer tabellen
kl. 04:15.

## Hva som gjenstår

- **Hostname for lokal utvikling** — de fire alternativene over.
- **Resend-nøkkelen.** Fortsatt plassholder i alle fire
  e-postfunksjonene. Ingen e-post går ut, heller ikke for meldinger som
  nå kommer gjennom det ekte kontaktskjemaet.
- **`onboarding@resend.dev`** som avsender virker bare til adressen som
  eier Resend-kontoen.

---

# 06:00-funnet: ikke tidssone

Bookingmotoren tilbød 06:00 mens åpningstidene er 07:00–15:00.
Mistanken var UTC mot Europe/Oslo. **Den stemmer ikke.** Det finnes
ingen tidssoneforskyvning noe sted i bookingkjeden.

Dette er et rent diagnoseoppdrag. Ingenting er endret.

## Hvorfor det ikke er tidssone

Sporet hele veien, fra kolonnetype til visning:

| Lag | Funn |
|---|---|
| Databasens sone | `UTC`. Oslo ligger `+02:00` nå. |
| Timekolonnene | `bookings.date` er `date`, `bookings.time` er `time without time zone`. Samme for `blocked_slots` og `special_open_days`. **Vegg-klokke uten sone** — en konvertering er umulig. |
| Metadatakolonnene | `created_at`, `reminder_sent_at` osv. er `timestamptz`. Riktig for hendelser. |
| Åpningstider | Ikke i databasen i det hele tatt. Konstanter i `shared/booking-engine.js`. |
| Slot-generering | Frontend, ren minutt-aritmetikk på strenger: `timeToMinutes` → `minutesToTime`. Ingen `Date` involvert. |
| `ymd()` | Bruker `getFullYear/getMonth/getDate`, **ikke** `toISOString()`. Det er nettopp den fellen som ville forskjøvet datoen — den er unngått. |
| `parseYMD()` | Bygger en lokal `Date` av delene. `new Date('2026-09-16')` ville gitt UTC-midnatt; det er unngått. |
| Ved lagring | `to_char(new.time, …)` i e-post og SMS. Verdien går ut slik den står. |

Den eneste sonekonverteringen i hele systemet er

    ((b.date + b.time) at time zone 'Europe/Oslo') < (now() + interval '24 hours')

i `cancel_booking_by_token` og `cancel_booking_by_ref`, pluss tilsvarende
i påminnelses- og anmeldelsesfunksjonene. Den er korrekt: vegg-klokka
tolkes som Oslo-tid via sonedatabasen.

**Ingen hardkodet `+1` eller `+2` noen steder.** Alle `interval '1 hour'`
og `interval '2 hours'` i basen er noe annet — ratelimit-vinduer,
seed-tidsstempler og et 72-timers vindu for anmeldelses-e-post.
Sommertidsskiftet 25. oktober 2026 knekker derfor ingenting;
kontrollregnet over skiftet: `08:00 Oslo 26. oktober = 07:00 UTC`,
riktig for vintertid.

**Eksisterende data er ikke forskjøvet.** Alle 80 bookinger ligger
mellom 07:00 og 13:30, mandag–fredag. Null før 07:00, null fra 15:00.

## Hva 06:00 faktisk er

Én linje i `shared/booking-engine.js`:

    var STAFF_HOURS = {
      markus: { open: '06:00', close: '13:00', breaks: ['09:30'] }
    };

En bevisst per-behandler-overstyring med egen fast pause. Den er
dokumentert fem steder: i sin egen kommentar, i `stengte-tider.html`,
og i kommentarene til migrasjon `0067` og `0068`. Dette er altså en
produktbeslutning, ikke en rest og ikke en feil.

Målt mot live, 2026-09-22:

| Behandler | 30 min | 60 min |
|---|---|---|
| Markus | 06:00 → 12:30, 13 slots (09:30 mangler = pausen) | 06:00 → 12:00, 11 slots |
| Sofie (og resten) | 07:00 → 14:30, 16 slots | 07:00 → 14:00, 15 slots |
| «Markus' terapeuter» (pool) | 07:00 → 14:30 | 07:00 → 14:00 |

Varighetslogikken er korrekt overalt: en 60-minutters time får ikke
starte 12:30 hos Markus, og ikke 14:30 hos de andre. `fits()` sjekker
`m + need * 30 > endMin` før slotet merkes ledig.

> Underveis trodde jeg et øyeblikk at varighetslogikken var ødelagt for
> Markus. Det var min egen målefeil: `generateSlotsForDay` tar
> **varighet i minutter** som tredje argument, og jeg sendte en
> tjeneste-UUID. `blocksFor()` ga da `NaN`, og alt så ledig ut. Koden
> var riktig hele tiden.

## Den ekte feilen: åpningstidene finnes tre steder

Motoren vet om per-behandler-timer. To av tre admin-flater gjør det
ikke.

| Fil | Kilde | Kjenner per-behandler-timer? |
|---|---|---|
| `shared/booking-engine.js` | `HOURS` + `STAFF_HOURS`, via `getHoursForStaff()` | **Ja** — fasit |
| `stengte-tider.html:586` | Kaller `E.getHoursForStaff(sid, 1)` | **Ja** — gjør det riktig |
| `kalender.html:912` | `CLINIC_OPEN_MIN = 7*60, CLINIC_CLOSE_MIN = 15*60` | **Nei** |
| `booking-admin.html:2608` | `HOURS_BY_DOW`, egen hardkodet kopi | **Nei** |

`kalender.html` sin kommentar sier at vinduet «speiler HOURS i
shared/booking-engine.js». Det gjør det for de sju behandlerne uten
overstyring, og ikke for den ene som har den.

Verre: `freeSlotTimes(dateStr, staffId)` **mottar** `staffId` og bruker
den til å filtrere bookinger og finne lørdagsåpning — men vinduet er
`openMin = CLINIC_OPEN_MIN` ubetinget på hverdager. Behandleren er i
hånda; timene hennes blir aldri spurt om.

Konsekvensen for Markus, hver hverdag, i adminkalenderen:

| Rad | Kunden ser | Admin ser |
|---|---|---|
| 06:00, 06:30 | Ledig | **Vises ikke** |
| 09:30 | Aldri (fast pause) | **Ledig** |
| 13:00, 13:30, 14:00, 14:30 | Aldri (stengt 13:00) | **Ledig** |

Sju rader per dag som ikke stemmer, for klinikkens hovedbehandler. En
booking kunden faktisk legger 06:00 blir lagret riktig og vises som
kort, men rutenettet rundt den er feil.

## Hva jeg foreslår, og hvorfor jeg ikke gjorde det

Rettelsen er ikke å fjerne 06:00. Den er å la de to admin-flatene spørre
motoren, slik `stengte-tider.html` allerede gjør:

- `kalender.html`: bytt `CLINIC_OPEN_MIN`/`CLINIC_CLOSE_MIN` i
  `freeSlotTimes()` mot `E.getHoursForStaff(staffId, dow)`, og hopp over
  `hrs.breaks` i slot-løkka. Konstantene beholdes som fallback hvis
  motoren ikke er lastet.
- `booking-admin.html`: samme for `HOURS_BY_DOW`.

To filer, ett mønster som allerede finnes i kodebasen, ingen
databaseendring og ingen migrasjon. Men det er **to lag** og det endrer
hva admin tegner, så jeg stoppet og la det fram i stedet for å gjøre
det.

Det motsatte valget — å fjerne `STAFF_HOURS.markus` slik at alt blir
07:00–15:00 — ville vært én linje, men det ville overkjørt en beslutning
som er dokumentert fem steder, inkludert to appliserte migrasjoner. Det
er ikke min avgjørelse.

## Sidefunn

**Den nattlige nullstillingen er ikke nattlig.** Cron står på
`15 4 * * *` i UTC:

| | Lokal tid i Oslo |
|---|---|
| Nå (sommertid) | **06:15** |
| Etter 25. oktober (vintertid) | **05:15** |

I sommerhalvåret kjører den altså 15 minutter *etter* at Markus åpner
06:00. En booking en kunde legger 06:00–06:15 blir slettet minutter
senere. Og selve tidspunktet flytter seg en time ved skiftet, fordi
cron er UTC-fast. Vil du at den skal ligge fast klokka 03:00 norsk tid
hele året, må jobben planlegges om — eller så må den tåle å flytte seg.

**«I dag» regnes i besøkendes egen sone.** `isToday()` og
60-minutters-bufferet i motoren bruker nettleserens lokale klokke, ikke
Oslo. En besøkende i en annen tidssone får derfor «i dag» og
«for sent å booke» regnet ut på sin egen klokke. For en norsk klinikk er
det marginalt, men det er reelt.

**Spesielle åpningsdager slår av pausen.** I `generateSlotsForDay`
overstyrer en `special_open_days`-rad hele timevinduet med
`breaks: []`. På en åpen lørdag er Markus' faste 09:30-pause dermed
bookbar. Sannsynligvis utilsiktet, men det er en egen liten sak.

## Ikke rammet

Blokkerte tider (`stengte-tider.html`) leser fra motoren og er riktige.
Varighetslogikken er riktig. Avbestillingsfristen på 24 timer er riktig
og sommertidssikker. Ingen testrader ble opprettet i denne runden; null
ikke-seed-rader i alle åtte tabeller.

---

# Siste runde: én kilde, klinikkens klokke, og full sluttkontroll

Diagnosen i forrige seksjon fant at 06:00 ikke var tidssone, men en
bevisst overstyring som to av tre admin-flater ikke kjente til.
Overstyringen står. Det som er rettet, er alt som ikke visste om den —
pluss det sluttkontrollen selv avdekket underveis.

## Hva som ble rettet

### 1. Åpningstidene finnes ett sted

`shared/booking-engine.js` eier dem. `stengte-tider.html` spurte
allerede motoren; nå gjør de tre andre det også.

| Fil | Før | Nå |
|---|---|---|
| `kalender.html` | `CLINIC_OPEN_MIN = 7*60`, `CLINIC_CLOSE_MIN = 15*60` | `getHoursForStaff(staffId, dow)`, hopper over `hrs.breaks`. Konstantene beholdt som fallback. |
| `booking-admin.html` | `HOURS_BY_DOW`, egen kopi | `staffHours(staffId, dow)` fra motoren, pauser hoppes over. Kopien beholdt som fallback. |
| `venteliste.html` | `OPEN_FROM_MIN/TO_MIN` hardkodet 07:00–15:00 | Unionen av alle behandleres tider, fra motoren. Tidsvelgeren dekker nå 06:00–15:00, så man kan be om en tidlig time hos Markus. |

`freeSlotTimes()` i kalenderen fikk `staffId` inn allerede, men brukte
den bare til å filtrere bookinger. Nå styrer den også vinduet.

### 2. Pauser gjelder også på engangsåpninger

En `special_open_days`-rad overstyrte hele timevinduet med `breaks: []`,
så Markus' faste 09:30-pause var bookbar på en åpen lørdag. Ny
`breaksForStaff()` gir behandlerens pauser uavhengig av ukedag — de er
hennes, ikke ukedagens.

### 3. Klinikkens klokke, ikke besøkendes

`isToday()` og 60-minutters-bufferet regnet i nettleserens lokale sone.
Ny `osloNow()` i motoren regner i `Europe/Oslo` via `Intl`, med lokal
klokke som fallback. Rettet fire steder i motoren og
`todayStr`/`todayISO` i kalender, booking-admin og venteliste.
`stengte-tider.html` brukte i tillegg **UTC-datoen** fem steder, som var
feil hver kveld hele året.

### 4. Nullstillingen ut av åpningstiden

Migrasjon `0077`. Cron sto på `15 4 * * *` UTC = 06:15 norsk sommertid,
et kvarter etter at Markus åpner. Flyttet til `0 1 * * *`:

| | Lokal tid |
|---|---|
| Sommertid | 03:00 |
| Vintertid | 02:00 |

Kun `schedule` er endret. `command`, `database`, `username`, `nodename`,
`nodeport` og `active` er verifisert uendret, og de tre andre jobbene er
urørt.

### 5. Tidsvinduet på kontaktskjemaet

Turnstile bruker 6–10 sekunder på å utstede token. Send-knappen står nå
deaktivert med «Sikkerhetssjekken kjører. Knappen åpner om et par
sekunder», og låses igjen etter innsending til det nye tokenet er
utstedt. Teksten er i i18n på begge språk.

## Tre feil sluttkontrollen selv avdekket

Disse fantes ikke før denne runden — jeg lagde dem, og fant dem ved å
teste mot live i stedet for å lese min egen kode.

**`osloNow()` frøs bestillingsflyten.** Den bygde en ny
`Intl.DateTimeFormat` ved hvert kall, og `isToday()` kalles per dag i
dag-løkkene. 28 dager × behandlere × slots ble til tusenvis av
formatter-konstruksjoner. Formattereren bygges nå én gang og resultatet
caches i 30 sekunder — langt kortere enn den 60-minutters bufferen
verdien brukes til.

**Den deaktiverte knappen var en blindvei.** Kom tokenet aldri — og
Cloudflare sluttet faktisk å utstede tokens til testnettleseren etter
mange raske løsninger — satt brukeren igjen med en låst knapp og
«kjører» i det uendelige. Det er verre enn feilmeldingen den erstattet.
En vaktbikkje bytter nå teksten til «Sikkerhetssjekken kom ikke
gjennom. Last siden på nytt og prøv igjen» etter 25 sekunder.

**Feilteksten ble stående når tokenet kom likevel.** Etter en hard feil
åpnet knappen seg igjen, men beskjeden om å laste siden på nytt ble
liggende ved siden av en knapp som virket. Ryddes nå bort. Funnet ved å
kjøre tilstandsmaskinen gjennom alle seks overgangene.

I tillegg to ting som ikke var feil i koden, men i utrullingen:

**Service worker-cachen serverte gammel kalender.** `kalender.html` og
`booking-admin.html` står på admin-skallets allowlist i `sw.js`. Uten en
versjonsbump ville ansatte med PWA installert fortsatt fått den gamle
kalenderen. Bumpet til `v82`.

**Motoren på ventelista logget en konsollfeil.** Da den ble lagt til for
åpningstidene, klaget den over at `shared/services.js` ikke var lastet.
Alle andre sider som laster motoren laster `services.js` først; nå gjør
ventelista det også.

## Sluttkontroll

### Åpningstider: alle tre flater stemmer nå

Målt på live, samme dag, 2026-09-22:

| Flate | Markus | Sofie / pool |
|---|---|---|
| Bestillingsflyten, 30 min | 06:00 → 12:30, 13 slots, ingen 09:30 | 07:00 → 14:30, 16 slots, 09:30 med |
| Bestillingsflyten, 60 min | 06:00 → 12:00, 11 slots | 07:00 → 14:00, 15 slots |
| Adminkalenderen | 06:00 → 12:30, ingen 09:30, ingen 13:00+ | 07:00 → 14:30, 09:30 med |
| booking-admin, tilgjengelighet | 06:00 → 12:30, 13 slots, ingen 09:30 | 07:00 → 14:30, 16 slots |

Varighetslogikken er intakt: en 60-minutters time får ikke starte 12:30
hos Markus eller 14:30 hos de andre.

### De fem offentlige endepunktene, i nettleser, med adminsesjon

| Endepunkt | Resultat |
|---|---|
| Bestilling | `ok: true`, ref `TA-N38C-4017`, rad opprettet |
| Avbestilling | `cancel_booking_by_token` → **200** `{"ok":true}`, kvitteringsskjerm. Andre forsøk → `already_cancelled`, altså idempotent |
| Venteliste | Rad opprettet, `get_waitlist_position` → **200**, plass 3 |
| Kontakt | **200** `{"ok":true}`, kvittering vist, rad i innboksen |
| Anmeldelse | `submit_review_by_token` → **200** `{"ok":true}` |

Alle med `admin@westengenklinikk.example` liggende i `localStorage` —
tilstanden som avslørte tre feil tidligere.

### Turnstile og ratelimit

| Test | Status | Kropp |
|---|---|---|
| Tom token | **403** | `captcha_required` |
| Ugyldig token | **403** | `captcha_failed` |
| Honeypot utfylt | **200** | `{"ok":true}` — falsk suksess, **ingen rad opprettet** |
| Kontakt 1–3 | **200** | `{"ok":true}` × 3 |
| Kontakt 4 | **429** | `rate_limited` |

Det fjerde forsøket ble sendt med ugyldig token med vilje og fikk
likevel `429`, fordi kvoten sjekkes før Turnstile.

Knappens tilstandsmaskin er kjørt gjennom alle overganger: ved last
(låst + ventetekst), token kommer (åpen, tekst ryddet), token utløper
(låst + ventetekst), hard feil (låst + «last siden på nytt»), og token
kommer likevel (åpen, feiltekst ryddet).

### Sider, lenker, konsoll og språk

- **21 HTML-sider: alle 200.** Alle delte ressurser 200.
  `sitemap.xml` gir 404 med vilje — robots.txt forklarer at den er
  fjernet fordi demoen ikke skal indekseres.
- **Ingen døde interne lenker.** Hver `href="*.html"` i repoet peker på
  en fil som finnes.
- **Ingen konsollfeil** på noen av sidene som laster motoren:
  `bestilling`, `booking-admin`, `kalender`, `stengte-tider`,
  `tjenester`, `venteliste`. Heller ingen på `kunder` eller `kontakt`.
- **Begge språk**: de nye i18n-nøklene løser riktig på norsk og engelsk,
  og språkbytte oppdaterer siden.
- **Begge roller**: administrator og terapeut. Rollebytte logger inn som
  `terapeut@westengenklinikk.example` og kalenderen viser hennes egne
  timer.

### Opprydding

Seks testrader opprettet, seks slettet, fraværet bekreftet: null
ikke-seed-rader i `bookings`, `contact_messages`, `waitlist`, `reviews`,
`journal_entries`, `blocked_slots`, `holidays`, `special_open_days` og
`exercise_documents`.

Honeypot-innsendingen etterlot seg ingen rad — som er selve poenget med
den.

`anon_insert_events` (21) og `audit_log` (163) er driftslogger uten
personopplysninger, og tømmes av den nattlige nullstillingen.

---

## Kjent og bevisst

Dette står igjen med vilje. Ingenting av det er ukjent, og ingenting av
det hindrer at demoen vises fram.

**Demoen sender ikke e-post.** `resend_key` er plassholderen
`REDACTED_RESEND_KEY` i alle fire e-postfunksjonene. Alle fire har nå
vakten som gjør at de avslutter stille i stedet for å kalle Resend, så
det logges ingen feil. Avsenderen er dessuten `onboarding@resend.dev`,
som bare virker til adressen som eier Resend-kontoen. Skal demoen sende
til andre, må et domene verifiseres hos Resend og `from_email` byttes.
SMS er tilsvarende en no-op: `process_pending_sms_reminders` henter
URL og hemmelighet fra Vault, og `vault.secrets` er tom.

**Repoets migrasjoner beskriver en eldre tilstand enn produksjon.**
Migrasjonene `0026`, `0028`, `0039`, `0040` og `0048` sto med en
uescapet apostrof og kunne ikke kjøre; de er gjort kjørbare, men
innholdet er bevisst byte-identisk ellers. Bygges databasen opp fra
bunn, gjenoppstår derfor plassholder-`base_url` og det gamle
prosjektnavnet i disse fem, og forsvinner først når `0074` og `0075`
kjører etterpå. Sluttresultatet blir riktig; mellomtilstanden er det
ikke. Ingen migrasjon i git gjengir kroppene slik de faktisk sto i
produksjon — `docs/db-funksjoner-før-0074.sql` og
`docs/db-funksjoner-før-0076.sql` er de eneste kopiene, og de er
dokumentasjon, ikke migrasjoner.

**Turnstile er bundet til `booking-demo-rosy.vercel.app`.**
Kontaktskjemaet kan derfor ikke fullføres i lokal utvikling: widgeten
gir feilkode `110200`, utsteder ingen token, og Edge-funksjonen svarer
`403`. Resten av siden virker lokalt. Fire alternativer står beskrevet
i seksjonen «Turnstile i produksjon»; ingen er valgt.

**Cloudflare struper automatisert testing.** Etter fire–fem raske
løsninger fra samme nettleser slutter widgeten å utstede tokens i noen
minutter. Det er Cloudflares egen misbruksbeskyttelse, den rammer ikke
vanlige besøkende, men den gjør automatisert testing av kontaktskjemaet
tregt.

**Markus åpner 06:00, klinikken 07:00.** Per-behandler-overstyringen er
en produktbeslutning. Den offentlige teksten «Mandag–fredag,
07:00–15:00» beskriver klinikkens rammer, ikke hver enkelt behandlers
arbeidstid. De to henger sammen, men sier ikke det samme.

**CSV-eksportene navngir filen med UTC-dato.** `audit-logg`,
`meldinger`, `booking-admin` og `shared/gdpr.js` bruker
`toISOString().slice(0,10)` i filnavnet. En eksport tatt etter midnatt
norsk tid får gårsdagens dato i navnet. Kosmetisk; ingen logikk henger
på det.

**`supabase-js` lastes fra CDN uten SRI.** Versjonen er pinnet til
`@2`, altså en flytende major, og en `integrity`-hash ville brutt siden
ved hver patch-utgivelse oppstrøms. Bevisst avveining, ikke en
forglemmelse.

**Den private adressen er ute.** `notify_to` i `send_booking_email`
peker nå på `post@westengenklinikk.example`. Adressen som sto der er
maskert i begge sikkerhetskopiene i `docs/`.

---

# Opprydding 2026-09-12

Fire oppdrag: arvet markedsføringstekst ut, et systematisk sveip etter
ekte personopplysninger, datoer som ligger fram i tid, og oppskriften
for å rotere Turnstile-hemmeligheten.

Sikkerhetstag før noe ble rørt: `pre-opprydding-2026-09-12` (pushet).

Commits: `8168cd8`, `5e597b2`, `9561746`, pluss denne rapporten.

## Det viktigste først: databasen er ikke endret

> **Oppdatert:** `0078` er kjørt og verifisert i produksjon. Se
> [0078 i produksjon, og migrasjonsloggen ryddet](#0078-i-produksjon-og-migrasjonsloggen-ryddet).

**Migrasjon `0078` er skrevet og testet, men ikke kjørt i produksjon.**
Verken Supabase-CLI-en eller Supabase-kontoen som er logget inn i
nettleseren har tilgang til prosjektet `pfyidlnztpwjnpxpoheu`. CLI-en
svarer «Your account does not have the necessary privileges», og
dashbordet sender videre til organisasjonslista, som bare inneholder to
andre prosjekter. Prosjektet ligger altså under en annen konto.

Uten den tilgangen når jeg databasen bare som `anon` og som demo-admin
gjennom PostgREST. Skrivesperren fra `0066` avviser endringer på
seed-rader for alle andre enn `postgres`, så tekst, seed-generator og
funksjonskropper kan ikke rettes derfra. Det er riktig oppførsel, ikke
en feil.

Det betyr at dette **fortsatt står i produksjon** til `0078` er kjørt:

- de gamle biografiene og rollene i `staff_members` (lesbare for anon)
- de gamle tjenestebeskrivelsene, som vises i steg 2 i bestillingsflyten
- kundesitatene i `reviews`, kundehistorien i `contact_messages` og
  metodetekstene i journalnotatene
- to ekte gateadresser i bunnteksten på e-postfunksjonene
- datovinduet på −30 til +10 dager

Frontenden er ryddet og deployet. Kortene i steg 1 henter tekst fra
i18n-filene, som vinner over databasen, så de er allerede riktige på
live.

### Slik kjøres 0078 (Markus)

1. Logg inn på supabase.com med kontoen som eier
   `pfyidlnztpwjnpxpoheu`.
2. SQL Editor → New query → lim inn hele
   `supabase/migrations/0078_opprydding_tekst_og_datoer.sql` → Run.
3. Forvent `NOTICE`-linjer med antall funksjoner som fikk ny adresse
   (produksjon: 3 eller 4), og
   `0078: N kommende bestillinger (… neste uke, … om 3–6 uker, … om 11–14 uker)`.
   Feiler en av kontrollene, ruller hele transaksjonen tilbake og
   ingenting er endret.
4. Kontroll:

        select min(date), max(date),
               count(*) filter (where date >= current_date) as kommende
          from public.bookings where is_demo_seed;
        select public.demo_reset();
        -- samme spørring igjen: samme vindu, samme antall

5. Registrer migrasjonen, så `db push` ikke prøver den igjen:
   `supabase migration repair 0078 --status applied --linked`

Migrasjonen er idempotent og kan kjøres to ganger.

## Hvordan 0078 er testet

Supabase sitt eget Postgres-image, samme versjon som prosjektet
(`public.ecr.aws/supabase/postgres:17.6.1.166`), i Docker. Et tynt
forspill legger inn det Supabase-plattformen ellers leverer
(`auth.jwt()`, noen kolonner i `auth.users`, `storage.buckets`,
publikasjonen `supabase_realtime`).

**Hele kjeden `0000`–`0078` kjører fra tom base uten en eneste feil.**
Det har den ikke gjort før denne runden (se «Fem migrasjoner kan ikke ha
kjørt som de står i git»).

Så ble produksjonstilstanden plantet i replikaen — gamle roller, gamle
biografier, gammel tjenestetekst, en funksjon med gateadresse i
bunnteksten i både store og små bokstaver — og `0078` kjørt oppå. Alt
ble rettet.

### Proben i 0078, bevist mot plantede feil

`0078` avslutter med en kontrollblokk som kaster exception og ruller
tilbake hvis noe står igjen. Hver kontroll ble tvunget til å feile:

| Plantet | Resultat |
|---|---|
| Ingenting (ren) | `NOTICE: 83 kommende bestillinger (13 / 10 / 16)` |
| Gammel biografi i `staff_members` | `ERROR: 1 rad(er) med arvet tekst står igjen` |
| Gammel rolle («Markedssjef») | `ERROR: 1 rad(er) med arvet tekst står igjen` |
| Kundesitat i `reviews` | `ERROR: 1 rad(er) med arvet tekst står igjen` |
| Alle timer etter +60 slettet | `ERROR: framtidige bestillinger mangler (uke 13, neste mnd 10, 3 mnd 0)` |
| Bekreftet time i fortiden | `ERROR: bekreftet seed-time i fortiden` |
| Gateadresse i små bokstaver (ikke tatt av erstatningen) | `ERROR: en funksjonskropp har fortsatt en gateadresse` |

Etter full kjede: `pg_dump` av hele `public`-skjemaet (funksjonskropper,
kommentarer, policyer, defaults, constraints) og alle data i replikaen
har null gateadresser utenom plassholderen, null e-postdomener utenom
`.example`, og null telefonnumre utenom `+47 400 00 0xx`.

---

## 1 — Arvet tekst

### De tre navngitte tekstene

| Tekst | Hvor den sto | Gjort |
|---|---|---|
| «Vi tildeler en av våre erfarne terapeuter, alle opplært direkte i Markus' metoder. Samme filosofi, samme grundighet.» | `booking.staff.terapeut.bio` (no/en), `shared/booking-engine.js`, `staff_members.bio`, `0041` | Erstattet med «Timen settes opp hos en av klinikkens terapeuter. Oppdiktet team i en oppdiktet klinikk.» Speiler Markus-kortets eksisterende nøytrale tekst, så kortene er symmetriske. |
| «Markus' erfarne terapeuter har vært tilknyttet klinikken i minst 2 år.» | `booking.step1.therapist_tenure` (no/en), `shared/booking-flow.js` | Nøkkelen slettet i begge språk. Elementet som rendret linja er fjernet. |
| «Behandling hos Markus selv» / «Behandling hos en av Markus' dyktige terapeuter» | `waitlist.staff_markus_sub`, `waitlist.staff_therapist_sub` (no/en), `venteliste.html` | Begge nøkler slettet. `<span class="wk-choice-sub">` fjernet. Bare navnet står igjen. |

**Om «underteksten under de to valgene i bestillingsflyten».** De to
sitatene står ordrett på ventelistesiden, ikke i steg 1 av bestillingen.
Steg 1 har en annen undertekst under hvert valg (bio-en over). Begge
flatene er ryddet.

**Valgradene uten undertekst.** `choice.css` hadde allerede en variant
for tittel alene. Målt på 320, 375, 768, 1024 og 1440, norsk og engelsk:
begge radene 49 px høye (over minstemålet på 44), like høye, radioknappen
midtstilt på tittelen (25 / 24 px fra toppen), én linje, ingen sidelengs
rulling. Ingen CSS-endring var nødvendig.

Kortene i steg 1 har `flex: 1` på bio-feltet, så bunnlinja står
fortsatt på lik høyde i begge kortene uten ansiennitetslinja. Kontrollert
visuelt på 320, 768 og 1440, begge språk.

### Sveipet

Søkt i alle HTML-filer, begge i18n-filer, all JS og CSS, alle
migrasjoner (seed-data og funksjonskropper), e-postmalene i
funksjonskroppene, produksjonskopiene i `docs/`, README, DEMO_SETUP,
RESEND_SETUP og kommentarer. I databasen: alle tabeller som er lesbare
for demo-admin (se punkt 2).

| # | Hvor | Hva sto | Gjort |
|---|---|---|---|
| 1 | `shared/components.js`, chatbotens systemprompt | «drevet av Markus Westengen (40 års erfaring) og sønnen Henrik», «Markus' terapeuter, opplært i Markus' metode», en egen blokk «MARKUS' FILOSOFI» om kroppen som sammenkoblet system, og en liste over plager klinikken behandler | **Hele prompten slettet**, sammen med grenen som brukte den. Den kalte `window.claude.complete()`, som ikke finnes i en nettleser; widgeten er merket «Demoguide / Forhåndsdefinerte svar» og svarer fra `staticAnswer()`. Største gjenværende avsnitt i repoet. |
| 2 | `shared/components.js`, velkomst, fallback, eskalering | «Hei! Jeg er Markus' assistent … spørsmål om behandling», «plager Markus behandler», «send en melding direkte til Markus» | Omskrevet til demoguidens egen tone, uten behandling. |
| 3 | `shared/components.js`, kontaktmodal | «Han svarer så snart han kan, vanligvis innen et døgn», «Beskriv kort hva du sliter med, så svarer Markus deg» | «Send en melding. Den havner i innboksen i adminpanelet.» Påstanden om svartid er borte. |
| 4 | `shared/booking-engine.js`, fallback-katalog | Rolle «Opplært av Markus selv»; seks terapeuter med «Opplært direkte av Markus. Samme metodikk, samme grundighet.» | Rolle «Terapeut-team»; bio «Oppdiktet terapeut i en oppdiktet klinikk.» |
| 5 | `staff_members` (DB, `0041`, `0069`, `0078`) | Samme biografier som 4, og roller som var organisasjonskartet til klinikken demoen kom fra: daglig leder, leder for produktutvikling, markedssjef, trainee-koordinator, pasientkoordinator, trainee | Biografier som 4. Alle navngitte terapeuter har rollen «Terapeut». Rollene gjorde oppsettet sporbart og sa ingenting om bookingsystemet. |
| 6 | `services.description` (DB, `0008`, `0068`, `0078`) | «Full gjennomgang av plagen: sykehistorie, bevegelsestester og en plan for videre forløp», «Fokusert behandling av senefeste og muskulatur som ikke har gitt seg av hvile alene», «Video- og styrketesting for deg som vil vite hvorfor plagen kommer tilbake», og i en utgått tjeneste «Grundig kartlegging av plager» | «Første time for nye kunder. Oppdiktet tjeneste i demoen.», «For kunder som har vært her før. …», «Oppdiktet tjeneste i demoen.» Tjenestenavnene står; et bookingsystem trenger noe å booke. |
| 7 | `reviews` (DB, `0067`, `0068`, `0070`, `demo_seed()`) | Åtte kundesitater med resultater: «Fant årsaken på første time etter to sesonger med ryggsmerter», «Hodepinen … er nesten borte», «Kom inn med lav skulder og gikk ut med en plan», «Ankelen har holdt seg i ro siden» og tilsvarende | Alle åtte byttet til tekst som starter med «Oppdiktet anmeldelse» og ikke sier noe om behandling. Stjerner og status er beholdt, så moderasjonskøen fortsatt demonstrerer seg selv. |
| 8 | `contact_messages` (samme filer) | «Takk for sist. Kjeven er mye bedre. Trenger jeg flere timer, eller holder det med øvelsene?» | «Hei. Har dere ledig time tidlig på morgenen i løpet av de neste ukene?» De sju andre er spørsmål om booking og står. |
| 9 | Journalnotater (`0067`, `0068`, `0070`, `demo_seed()`) | Fem notater som beskrev en behandlingsmåte: «Redusert utslag på motsatt side, sannsynlig kompensasjon. Behandlet mykvev og ledd», «Reduserte behandlingsfrekvens til hver tredje uke», «Prøvde annen teknikk», «Symptomfri ved siste kontroll» | Beholdt som fem notater (journalen er en funksjon demoen viser), men teksten er «Demonotat 1–5» uten behandlingsinnhold. |
| 10 | `vilkar.html` § 5 | «Markus Westengen er autorisert helsepersonell og følger gjeldende krav til faglig forsvarlighet. Behandlingen baseres på en grundig vurdering, og du blir informert om forventet effekt …» | Påstanden om autorisasjon og behandlingsmåte er fjernet. Punktet sier nå at demoen ikke tar stilling til behandlingsfaglige forhold, og hva punktet ville inneholdt i en ekte klinikk. |
| 11 | i18n, døde nøkler, no og en | `nav.philosophy` «Filosofi», `nav.stories` «Kundehistorier», `nav.treatment` «Behandlingsmåte», `nav.about` «Om Markus», `behandlere.heading_em` «varig resultat», `behandlere.markus.meta_spec_val` «Komplekse, kroniske plager», `behandlere.terapeut.meta_bg_val` «Treningsfaglig + Markus' teknikker», `final_cta.heading_em` «kroppen tilbake», `reviews.section_heading` «Det kundene sier», butikk, samarbeidspartner og resten av de samme blokkene | **54 nøkler slettet** i begge språk. Ingen ble brukt av noen side eller slått opp dynamisk (kontrollert mot `t('behandlere.' + id + '.name')`-mønstrene i `booking-flow.js`, som bruker `.name` og `.role`, som står). |
| 12 | i18n, levende nøkler | `booking.step1.intro` «To veier til samme grundige behandling», `chat.static.plager` med «Filosofien hans er å finne årsaken», to fallback-tekster, `contact.modal.intro/thanks` | Omskrevet nøytralt i begge språk. |
| 13 | `shared/public.css` | Rundt 370 linjer stil for kundehistoriesidene (`.hist-*`: sitatkort, pullquote, «bildeløse kundehistorier»), og en toppkommentar om at filen het `kundehistorier.css` | Slettet. Kontrollert først at ingen side eller JS bruker en `.hist-`-klasse, og at utsnittet ikke inneholdt andre selektorer. |
| 14 | Referansekoder | Prefikset `TA-` i bestillinger og venteliste, i hjelpetekstene og eksemplene | `WK-`, som seed-dataene allerede brukte. `TA` var initialene til klinikken demoen ble laget ut av. RPC-ene matcher hele koden, ikke prefikset. |
| 15 | Kommentarer | `DEMO_SETUP.md` («forside med filosofi og kundehistorier»), sitater i kommentarer i `0075` og `0076` | Omformulert så de ikke gjengir teksten. |

**Null treff** i repoet på eliteidrett, verdensrekord, mesterskap, NRK,
Tour de France, landslag, olympisk eller navngitte utøvere, verken før
eller etter. Den klassen var fjernet i en tidligere runde. Treffene som
fantes, var metode, opplæring, erfaring, resultater og kundesitater.

**Ikke endret, med vilje:**

- Navnene Westengen Klinikk og Markus Westengen, og gruppenavnet
  «Markus' terapeuter».
- Tjenestenavnene og prisene. Data bookingsystemet trenger.
- Kundenes «plage»-felt i seed-dataene («Ryggsmerter, sykling»). Det er
  hva en kunde skriver i bestillingsnotatet, ikke en påstand om
  behandling.
- Øvelsesdokumentenes titler («Nakkeøvelser, nivå 1»). Filnavn i et
  dokumentarkiv.
- Historiske sitater i tidligere avsnitt av denne rapporten.

### Ny kontroll: `scripts/verify-arvet-tekst.mjs`

Rent node-skript for den raske gaten. Ordlista er bygget av det som
faktisk sto i repoet. Unntar bare seg selv og denne rapporten.

Bevist: med `i18n/no.json` fra før oppryddingen lagt tilbake gir den 29
treff og exit 1. Med dagens fil: «ingen arvet markedsfoeringstekst».

---

## 2 — Personopplysninger

### Hva som ble sett på

**Repoet:** alle tekstfiler, inkludert migrasjoner, funksjonskropper,
kommentarer, tester, docs og produksjonskopiene av funksjonene.

**Databasen, det jeg når:** alle 14 tabellene demo-admin kan lese i sin
helhet (`bookings` 78, `contact_messages` 8, `reviews` 8, `waitlist` 5,
`blocked_slots`, `holidays`, `special_open_days`, `services`,
`staff_services`, `staff_members`, `exercise_documents`,
`document_sends`, `audit_log` 160, `journal_audit` 107),
journalnotatene gjennom `get_journal_entries`, egen `auth.users`-rad
gjennom `/auth/v1/user`, og storage-API-et (tomt for admin).

**Databasen, det jeg ikke når:** funksjonskropper, kommentarer, policyer,
constraints, defaults, `cron.job`, andre rader i `auth.users`, storage
som `service_role`, `anon_insert_events`. Dekket på to andre måter:
repoet er sveipet (definisjonene står i migrasjonene), og hele kjeden er
bygget og dumpet i replikaen. Der produksjon er kjent å avvike fra
repoet (e-postfunksjonene, jf. `0074`) bygger funnene på kopiene i
`docs/` fra 2026-09-02.

### Funn

| # | Hva | Hvor | Ekte? | Gjort |
|---|---|---|---|---|
| 1 | Gateadresse `S*******a 1, 01** Oslo` | Bunnteksten i `send_booking_email`, `send_document_email`, `process_pending_review_emails` i **produksjon**; kopiene i `docs/` | **Ja.** Kartverkets adresseregister: finnes, eksakt postnummer. Rapportert 2026-09-02, aldri rettet. | Erstattes i produksjon av `0078` (c). Maskert som `REDIGERT_EKTE_ADRESSE` i begge kopiene. |
| 2 | Gateadresse `R***********a 8, 03** Oslo` | Bunnteksten (store bokstaver) i `send_booking_email` i **produksjon**; kopiene i `docs/` | **Ja.** Kartverket: finnes, eksakt postnummer. **Nytt funn**: lekkasjeskriptets nye adressemønster fant den. | Som 1. |
| 3 | Gateadresse `B*********n 12` (med postnummer 0283) | Plassholderadressen: i18n (8 steder), `bestilling.html`, `vilkar.html`, `venteliste.html`, `avbestill.html`, `anmeldelser.html`, `booking-flow.js`, `DEMO_SETUP.md`, e-postmalene i seks migrasjoner | **Ja.** Kartverket: gatenummeret finnes i Oslo, med postnummer `08**`. Kombinasjonen med 0283 er ugyldig, men nummeret peker på en ekte eiendom. Siden sa «adressen peker ikke på et virkelig sted». | Byttet overalt til **`Eksempelveien 12, 0000 Oslo`**. «Eksempelveien» gir null treff i Kartverkets register for hele landet, og 0000 er ikke et postnummer. Samme prinsipp som `.example` og `400 00 000`. |
| 4 | Privat gmail-adresse | Denne rapporten, «Privat e-postadresse i send_booking_email» | Ja, allerede delvis maskert | Maskeringen matchet fortsatt lekkasjeskriptet (exit 1). Byttet til `<privat gmail-adresse, maskert>`. Adressen selv ble fjernet fra produksjon i `0076`. |

**Null funn:**

- **E-post:** alle adresser i repo og database ligger på `.example`,
  bortsett fra Resends offentlige testavsender `onboarding@resend.dev`.
- **Telefon:** bare `+47 400 00 000` og variantene `400 00 011–030`,
  pluss testnummeret `400 00 099` fra denne runden.
- **Organisasjonsnumre:** ingen.
- **Navn i kunderegister, journal, meldinger, anmeldelser, bookinger og
  venteliste:** 20 kunder satt sammen av vanlige for- og etternavn. Ingen
  kombinasjon er ført tilbake til en person. Behandlernavnene ble byttet
  i `0069`; rollene er nå nøytrale (tekstfunn 5).
- **Storage:** ingen buckets eller objekter synlige for admin;
  øvelsesdokumentene peker på `demo-prosjekt.supabase.co`, en attrapp.
- **auth.users (egen rad):** `admin@westengenklinikk.example`.

### Lekkasjeskriptet utvidet

`scripts/verify-lekkasje.mjs` har fått to mønstre for norske
gateadresser (vanlig og store bokstaver), med plassholderen unntatt.

Bevist: første versjon slo **ikke** ut på en plantet `B*********n 12`.
Årsaken var backspace-tegn i regexen fra skriptet som skrev den. Rettet;
deretter gir plantet adresse treff og exit 1, dagens repo «ingen treff».
Det var denne proben som fant funn 2.

---

## 3 — Datoer

### Hva som allerede var riktig

`demo_seed()` var relativ fra før: alt regnes som `current_date` pluss
et intervall, og `demo_reset()` kaller den hver natt kl. 01:00 UTC
(`0077`). Bekreftet i produksjon: radene i dag har `created_at`
2026-09-12 01:00 UTC. Problemet var vinduet, ikke metoden. Bestillingene
gikk fra −30 til +10 dager, så ingenting lå lenger fram enn halvannen
uke.

### Hva 0078 endrer

| Innhold | Før | Etter |
|---|---|---|
| Bestillinger | −30 … +10 | −30 … −1 historikk; 0 … +21 tett (som før); +22 … +100 annenhver hverdag, Markus og én terapeut per dag, vekselvis |
| Stengte dager | +21 og +22 (ofte en helg, altså usynlig) | Første hverdag fra og med +24 og +60. Bestillingsløkka hopper over dem. |
| Åpne lørdager | Neste lørdag | Neste lørdag og lørdagen ni uker etter |
| Blokkeringer | Seks innen +7; én (jonas 14:00) overlappet en 60-minutters time 13:30 | Samme seks, jonas flyttet til 14:30, pluss +38 og +75 |
| Venteliste | Ønsker fra −2 til +30 | Samme fem, pluss ett ønske +45 … +80 |
| `created_at` på bestillinger | `now() − (offset + 40)`: timer tre måneder fram ble «bestilt» for fire måneder siden | 3–22 dager før timen, aldri i framtiden |
| Meldinger, anmeldelser, journal, dokumenter, logg | Fortid | Uendret; fortid gir mening der |

Ingen faste datoer: `pg_proc` for `demo_seed` og `demo_reset` har null
datolitteraler.

### Bekreftet at datoene flytter seg

I replikaen, med samme `demo_reset()` som i produksjon:

| Kjøring | `current_date` | Første | Siste | Kommende |
|---|---|---|---|---|
| `demo_reset()`, UTC | 2026-09-12 | 2026-08-13 | 2026-12-21 | 83 |
| `demo_reset()` igjen | 2026-09-12 | 2026-08-13 | 2026-12-21 | 83 (idempotent) |
| `demo_reset()`, tidssone UTC+14 (i morgen) | 2026-09-13 | 2026-08-14 | 2026-12-22 | 84 |

Fordeling framover: september 35, oktober 19, november 15, desember 14.
Null timer i helg, null på stengte dager, null blokkeringer oppå en time.

I **produksjon** er dette ikke bekreftet, fordi `demo_reset()` bare kan
kjøres som `service_role` eller `postgres`. Det er steg 4 i oppskriften
over.

---

## 4 — Turnstile-hemmeligheten

Den nåværende secret har ligget i en chatlogg. Den er ikke rørt.

### Én korreksjon til premisset

At kontaktskjemaet avviser alt i sekundene mellom rotering og ny secret,
stemmer bare for én av to måter å rotere på. Cloudflare holder den gamle
nøkkelen gyldig i **to timer** når du roterer i dashbordet. Det gir intet
avvisningsvindu, men den lekkede nøkkelen virker også i to timer til.
Vil du ha den død med en gang, må du rotere gjennom API-et med
`invalidate_immediately: true`, og da får du vinduet.

Risikoen ved en lekket Turnstile-secret er lav: den lar noen verifisere
tokens mot widgeten, ikke utstede dem. **Anbefaling: dashbordvarianten.**

### A. Dashbordet (anbefalt, ingen avbrudd)

1. dash.cloudflare.com → velg kontoen → **Turnstile** i venstremenyen.
2. Velg widgeten med site key `0x4AAAAAAElCRZstoX978mDR`.
3. **Settings** → **Rotate Secret Key** → bekreft. Kopier den nye
   hemmeligheten.
4. Innen to timer, i repoet:

        npx supabase secrets set TURNSTILE_SECRET_KEY=<ny secret> --project-ref pfyidlnztpwjnpxpoheu

   Krever innlogging med kontoen som eier prosjektet.
5. Kontroller at digesten er byttet:

        npx supabase secrets list --project-ref pfyidlnztpwjnpxpoheu

   `TURNSTILE_SECRET_KEY` skal ha en annen digest enn `b47585f1…db053`.
6. Send en melding gjennom skjemaet på live. Forvent «Takk! Meldingen er
   sendt.» Slett den i innboksen.

En ny rotasjon kan ikke startes før de to timene er over.

### B. API-et (lekket nøkkel død med en gang)

    curl -X POST \
      "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/challenges/widgets/0x4AAAAAAElCRZstoX978mDR/rotate_secret" \
      -H "Authorization: Bearer <API-token med Turnstile Edit>" \
      -H "Content-Type: application/json" \
      -d '{"invalidate_immediately": true}'

Svaret inneholder `result.secret`. Kjør `supabase secrets set` (steg 4
over) **umiddelbart**. I tiden mellom de to kommandoene avviser
Edge-funksjonen **alle** meldinger med `403 captcha_failed`, og
besøkende ser «Bekreft at du ikke er en robot, og prøv igjen». Ingen
melding blir halvveis lagret, fordi ingenting skrives før valideringen er
godkjent; de blir bare aldri sendt. Ha begge kommandoene klare i hver sin
terminal før du kjører den første.

---

## 5 — Verifisering

### Sjekkliste

| | Status |
|---|---|
| De tre navngitte tekstene borte, også fra i18n i begge språk | **Ja** i repo og på live. I databasen står den ene i `staff_members.bio` til `0078` er kjørt; den vises ikke på live fordi i18n vinner. |
| Valgradene riktige uten undertekst, 320 og oppover | **Ja.** 49 px, like høye, midtstilt, ingen rulling, 320–1440, begge språk. |
| Sveipet i punkt 1 listet | **Ja**, 15 punkter over. |
| Null treff på eliteidrett, verdensrekord, Tour de France, NRK, utøvere | **Ja**, repo og lesbar database. |
| Null ekte e-post, telefon eller adresser i repo | **Ja.** `verify-lekkasje` og `verify-arvet-tekst` rene. |
| … i databasen | **Nei, ikke før `0078` er kjørt.** To ekte gateadresser står i produksjonens e-postfunksjoner. Tabellene har ingen. |
| Kommende bookinger og ledige tider fram i tid | **Delvis.** Produksjon: 19 kommende, siste 2026-09-22. Etter `0078`: 83, siste om 100 dager. |
| Datoene relative, bekreftet med `demo_reset()` | **Ja i replikaen.** Ikke kjørt i produksjon. |
| Fem offentlige endepunkter gjennom nettleseren på live, med adminsesjon | **Ja**, se under. |
| Ingen konsollfeil, begge språk, 320–1440 | **Ja**, se under. |
| Testrader ryddet og bekreftet borte | **Delvis**, se under. |

### Endepunktene

Live, Chrome, adminsesjon liggende i `localStorage`
(`sb-pfyidlnztpwjnpxpoheu-auth-token`), ekte skjemaer. Testdata:
`Testrad Opprydding`, `testrad.opprydding@westengenklinikk.example`,
`+47 400 00 099`.

| Endepunkt | Resultat |
|---|---|
| Bestilling | Markus → Førstegangsvurdering → tirsdag 22. september 06:30 → detaljer → «Timen er bekreftet», referanse `TA-TD77-6460`, adresse «Eksempelveien 12, 0000 Oslo». (Testet før `TA-` → `WK-`.) |
| Avbestilling | Referanse + e-post → «Timen din er avbestilt». Status i basen: `cancelled`. |
| Venteliste | Markus, fra 1. oktober → «Du står på ventelista», `TA-WL-JESW-8KM6`. |
| Kontakt | Turnstile utstedte token uten utfordring (794 tegn), knappen åpnet, «Takk! Meldingen er sendt.» |
| Anmeldelse | Med `review_token` fra en gjennomført seed-time → «Takk for anmeldelsen!» |

Ingen konsollfeil under noen av dem.

To av skjemaene måtte fylles ut med verktøyets `form_input` i stedet for
tastetrykk, fordi Turnstile-iframen tok tastaturfokus. Innsendingen var
et ekte klikk på sidens egen knapp i alle fem.

### Konsoll og bredder

Konsollsporingen ble bevist først: en plantet `throw` og en plantet
`console.error` ble begge fanget.

Deretter, på live: alle 8 offentlige sider og alle 10 adminsider, norsk
og engelsk, ved ekte navigasjon med sporingen aktiv. **Null feil.**

Bredder: live sender `frame-ancestors 'none'`, så sidene kan ikke legges
i iframes der, og nettleservinduet lot seg ikke gjøre smalere enn
skrivebordsbredde. Breddene er derfor målt på en lokal server med
**byte-identiske filer**: SHA-256 av 15 endrede filer på live er lik
HEAD. 320, 375, 768, 1024 og 1440, norsk og engelsk, åtte offentlige
sider: ingen sidelengs rulling.

**Målingen fant en feil som ikke var min:** `kontakt.html` rullet
sidelengs på 320 og 375 (dokumentbredde 378 px). Kontrollert mot filene
fra før oppryddingen: samme 378 px. Turnstile-widgeten i normal størrelse
er 300 px fast, og kortet rundt dyttet rutenettet til 346 px. Rettet i
`9561746`: `minmax(0, 1fr)` på rutenettet, og widgeten rendres i
`compact` under 420 px. Etter rettelsen: ingen rulling på noen bredde,
begge språk. At Cloudflare godtar `compact` med produksjonsnøkkelen er
bekreftet på live: en compact-widget utstedte gyldig token.

**Ikke verifisert:** at en besøkende med faktisk smal skjerm får token
gjennom compact-widgeten ende til ende på live. Grenen kan ikke utløses
fra et skrivebordsvindu.

### Testrader

| Tabell | Rad | Status |
|---|---|---|
| `bookings` | `TA-TD77-6460` | Slettet, bekreftet borte |
| `waitlist` | `TA-WL-JESW-8KM6` | Slettet, bekreftet borte |
| `contact_messages` | Testrad Opprydding | Slettet, bekreftet borte |
| `reviews` | «Testrad O.», 4 stjerner | **Står igjen**, satt til `rejected`. Admin har ingen delete-policy på anmeldelser (403), med vilje. Slettes av nullstillingen 01:00 UTC. |
| `audit_log`, `journal_audit` | Én rad hver fra testene | Står igjen. Tømmes av nullstillingen. |

Anmeldelsen brukte `review_token` til seed-timen
`demo-20260911-sofie-58`. Nullstillingen genererer timen og tokenet på
nytt.

### Raske gater, sist kjørt

    verify-arvet-tekst   ingen arvet markedsfoeringstekst
    verify-i18n          i18n OK (522 nøkler, var 576)
    verify-inline-js     21 inline-blokker, 0 med feil
    verify-lekkasje      ingen treff
    verify-lenker        30 filer sjekket, alle interne lenker finnes

## Sidefunn

**Linjeslutt.** Arbeidskopien bruker LF (indeksen er LF,
`core.autocrlf` er `true`). Skriptene jeg redigerte med skrev CRLF, og
det brakk `0076` i replikaen: den leter etter `\nbegin\n` i en
funksjonskropp fra `0048`, og med CRLF fantes ikke strengen. Git ville
normalisert ved commit, men SQL-editoren og `db push` leser
arbeidskopien. Alle berørte filer er satt tilbake til LF før commit, og
kjeden er kjørt på nytt.

**Seedingen fyrer e-posttriggeren.** Hver seedet bestilling kjører
`send_booking_email`, som i dag hopper over fordi Resend-nøkkelen er
plassholderen. Med `0078` blir det 142 slike per natt i stedet for 78.
Settes en ekte nøkkel, vil seedingen forsøke å sende til
`.example`-adresser. Uendret oppførsel, større volum.

**Service worker-cache** er bumpet til `v84`.

---

# 0078 i produksjon, og migrasjonsloggen ryddet

2026-09-12, kveld. Markus kjørte `0078` mot `pfyidlnztpwjnpxpoheu`.
Deretter: kontroll av at den slo gjennom, et nytt sveip av hele
databasen, og rydding av migrasjonsloggen etter funnene.

Alle funn er maskert. Tilgang var `postgres` via Management API
(`supabase db query --linked`) med et midlertidig access-token. Tokenet
er ikke skrevet ned noe sted (søkt i repo, git-historikk, scratchpad,
`~/.claude`, `~/.supabase`, shell-profiler og PowerShell-historikk; proben
bevist mot en plantet verdi). Det bør roteres.

## 1 — 0078 slo gjennom

| Kontroll | Resultat |
|---|---|
| Biografier | 9 av 9 nøytrale |
| Tjenestebeskrivelser | 4 av 4 byttet |
| Kundesitater | 8 av 8 anmeldelser starter med «Oppdiktet anmeldelse»; meldingen om bedring byttet; journalen er «Demonotat 1–5» |
| Gateadresser | Null i funksjonskropper i alle skjemaer, kommentarer, defaults, policyer, cron og migrasjonslogg. De tre e-postfunksjonene har «Eksempelveien 12, 0000 Oslo» |
| Behandlerroller | Sju «Terapeut», «Terapeut-team», Markus «Behandler» |
| Chatbot-prompten | Lå i `shared/components.js`, ikke i databasen. Live-fila er byte-identisk med HEAD; null treff i databasen |
| Datovindu | 2026-08-13 … 2026-12-21 (−30 / +100), 83 kommende, 35 / 19 / 15 / 14 per måned. Likt replikaen. Null i helg, på stengt dag eller bekreftet i fortiden |
| Registrert | `0078` står i `schema_migrations` |

`select public.demo_reset()` kjørt én gang, som i oppskriften. Samme vindu
og antall etterpå, og testanmeldelsen fra forrige runde er borte.
Nattjobben er aktiv 01:00.

## 2 — Sveipet

Definisjoner (funksjoner, views, policyer, defaults, constraints,
triggere, kommentarer, enum, rolleinnstillinger, cron, vault, `net`,
migrasjonsloggen) og data i alle tabeller i `public`, `auth`, `storage`
og `realtime`. Token- og passordkolonner utelatt ved eksport.

Tabellene appen bruker var rene. To funn:

**`auth.sessions`: ekte IP-adresser.** To offentlige adresser,
`1**.***.**.*2` og `5*.***.***.**7`, med user-agent (Windows/Chrome,
iPhone/Safari, curl, headless Chrome). 65 sesjoner, 1.–12. september, på
begge demokontoene. Ikke lesbart for `anon` eller `authenticated`.
`demo_reset()` rydder ikke tabellen. **Ikke rørt, etter beslutning.**

**`supabase_migrations.schema_migrations`: historikken var ikke ryddet.**
Loggen lagrer SQL-en slik den ble kjørt første gang. Repoet var ryddet,
loggen ikke:

| Klasse | Hvor |
|---|---|
| Privat gmail-adresse `m**************@g****.com` | 0011, 0025, 0026, 0028, 0029, 0048 |
| Ekte gateadresse `S******a 1, 0*** Oslo` | 0026, 0028, 0040, 0043, 0048, 0056 |
| Ekte gateadresse `R***********a 8, 0*** OSLO` | 0048 |
| LAN-adresse `192.168.*.***` | 0026, 0028, 0029 |
| Testadresse på registrerbart domene `k****@e*******.no` | 0022 |
| Gammelt navn `E***` (også `E****&nbsp;A****` i e-posthoder og `e***-konsult`-slugs) | 26 migrasjoner, 134 treff |
| Gammelt navn `T**` som staff-id, slug og i migrasjonsnavn (`0030 t**_flat_price`, `0044 t**_videre_price_3000`) | 0008, 0015, 0030, 0032, 0033, 0041, 0044, 0049 |
| Seks opprinnelige staff-id-er fra klinikken demoen kom fra, blant dem fornavnet i `0038 seed_d*****_staff_services` | 0015, 0038, 0041 |
| Prefikset `T*-` | 0022, 0023, 0035 |
| Arvede biografier, roller, kundesitater, behandlingsnotater, tjenestebeskrivelser | 0008, 0015, 0041, 0067, 0068, 0069, 0070 |

Verken `anon` eller `authenticated` har `SELECT` på loggen, og den kjøres
aldri igjen.

**Korreksjon til en tidligere påstand i samme økt:** at loggen avvek fra
repoet i alle 78 migrasjoner var feil. Statements i loggen er repofilene
ordrett, bare delt opp og uten semikolon; sammenligningen tok ikke
hensyn til det.

## 3 — Migrasjonsloggen skrevet om

### Backup først

`C:\Users\marku\supabase-backup\schema_migrations-pfyidlnztpwjnpxpoheu-2026-09-12-foer-rydding.json`,
78 rader, md5 `0dbd265b37a29653da25b21c1e6b23ff` regnet ut i databasen og
lokalt, lik. Ved siden av ligger `…-GJENOPPRETT.sql`, som setter loggen
tilbake. Fila ligger utenfor repoet og utenfor OneDrive fordi den
inneholder funnene i klartekst. Slett den når den ikke trengs.

Utgangspunkt: `migration list` 78 lokale = 78 remote, `db push --dry-run`
«Remote database is up to date».

### Erstatningene

Samme verdier som repoet og `0078` bruker, hentet fra diffen i
oppryddingscommitene og fra dagens migrasjonsfiler:

| Fra | Til |
|---|---|
| gmail-adressen | `post@westengenklinikk.example` |
| gateadressene | `Eksempelveien 12, 0000 Oslo` / `EKSEMPELVEIEN 12, 0000 OSLO` |
| LAN-adressen, «(M*****' Live Server» | `localhost`, «(lokal Live Server» |
| `k****@e*******.no`, og en énbokstavs `.no`-adresse i 0022, 0023 og 0053 | `kunde@eksempel.example`, `x@y.example` |
| `westengenklinikk.n*` i en kommentar i 0011 | `westengenklinikk.example` |
| `E***` / `E****s` / `e***` | `Markus` / `Markus'` / `markus` |
| `T**` som id og slug | `markus` |
| de seks opprinnelige id-ene | `sofie`, `henrik`, `jonas`, `amina`, `petter`, `lena` |
| `T*-` | `WK-` |
| `E*** streng` i kolonnekommentaren (0049) | `Tom streng`, som databasen har etter `0076` |
| biografier, roller, sitater, notater, tjenester | tekstene fra `0078` |
| migrasjonsnavnene | `markus_flat_price`, `markus_videre_price_3000`, `seed_lena_staff_services` (repoets filnavn) |

**Én bevisst avvikelse.** 0069, 0072, 0074, 0075 og 0076 handler om
selve navnebyttet. Der ville «Markus» gjort `E*** -> Markus` til
`Markus -> Markus`, og loggen sluttet å si noe. Der står
`[tidligere navn]` og `tidligere-id` i stedet.

**Ikke tatt med:** repoets senere endringer som ikke er opprydding
(`is_public` i 0068, tallene i 0015 og 0038, omformatering i 0050, 0051 og
0057). Loggen skal fortsatt vise hva som ble kjørt.

38 rader endret. Versjonsnumre og antall statements per migrasjon er
uendret.

### Kjøringen

Én `DO`-blokk, atomisk, med to vakter: loggens md5 må være backupens før
noe skrives, og resultatet må ha nøyaktig den md5-en som er regnet ut
lokalt, ellers rulles alt tilbake.

Vaktene ble bevist mot plantede feil før den ekte kjøringen:

| Plantet | Resultat |
|---|---|
| Gjenopprettingsskriptet mot feil utgangstilstand | `ERROR: schema_migrations er ikke i forventet utgangstilstand`; md5 uendret |
| Ryddeskriptet med feil forventet md5 | Alle 38 oppdateringer kjørt, så `ERROR: resultatet avviker fra forventet md5; rulles tilbake`; md5 uendret |

Ekte kjøring: md5 `bc1a4c66a5f83c3184fba71e855952a6`, som forventet. 78
rader, `0000`–`0078`.

### Etterpå

| Kontroll | Resultat |
|---|---|
| `supabase migration list --linked` | 78 lokale, 78 remote, identisk med før |
| `supabase db push --linked --dry-run` | «Remote database is up to date.» |
| Sveipet på nytt, migrasjonsloggen | Null treff i klassene over |

Sveipets nye mønstre (opprinnelige id-er, `T**` som id/slug,
registrerbare domener, `grunnlegger ·`) er bevist mot backupen: alle slår
ut på loggen slik den var.

Det sveipet fortsatt melder i loggen, og hvorfor det står:

| Treff | Hva det er |
|---|---|
| «tom», 30 steder | Det norske ordet: «tom liste», «står tom», «tom telefon» |
| Ordliste i 0078 | Kontrollblokken i `0078`, som leter etter nettopp disse ordene. Identisk med repoet; å skrive den om ville forfalsket hva proben sjekker |
| «Samme metode som 0074» (0075) | Teknisk fremgangsmåte, ikke behandling |
| `MARKUS''&nbsp;A****` (0026, 0028, 0039, 0040, 0048, 0074) | Arvet fra det gamle prosjektnavnet. **Fjernet i neste runde**, se «A**** ut, lokal utlogging og restene i repoet» |
| Fire sifre + ord («0008 var») | Migrasjonsnumre i løpende tekst |
| `000000000`, `52428800` | Pseudonymisert telefon i `gdpr_erase_patient`, filgrense i bytes |
| `https://evil/phish`, `https://phish.evil` | Oppdiktede angrepseksempler i kommentarer |

## 4 — auth.sessions endret seg underveis, ikke av oss

Etter ryddingen hadde `auth.sessions` 6 rader, mot 65 ved eksporten
tidligere samme kveld. Alle admin-sesjonene var borte; de 6 som står er
terapeutkontoens.

Ingen SQL i denne runden rørte `auth`, og de to prøvekjøringene ble
rullet tilbake. Auth-loggen i Supabase viser hva som skjedde:

| UTC | Hendelse |
|---|---|
| 19:49:43 | `POST /token` (refresh), `admin@westengenklinikk.example` |
| 19:50:21 | `POST /logout`, 204, `admin@westengenklinikk.example` |
| 19:50:59 | autovacuum på `auth.sessions` |

En nettleser med frontenden logget ut admin. `sb.auth.signOut()` uten
argument har `scope: 'global'` i supabase-js v2 og sletter **alle**
sesjoner for brukeren.

**Feil funnet av dette:** demokontoene er delt. Én besøkende som logger
ut, går tom for tid (`shared/auth.js` `doLogout`) eller åpner
`ansatt.html` (som kaller `signOut()` før innlogging), logger ut alle
andre som er inne som samme rolle. `signOut({ scope: 'local' })` på
stedene som kaller den retter det. Ikke endret.

## 5 — Repoet, ikke endret

> **Oppdatert:** ryddet i neste runde, se
> [A**** ut, lokal utlogging og restene i repoet](#a-ut-lokal-utlogging-og-restene-i-repoet).

Sveipet gjaldt databasen. Underveis viste det seg at repoet selv har:

- «E***» i 0069 og 0072–0076, og `t**-`-slugs i kommentarer i 0030,
  0032, 0033 og 0044. `verify-lekkasje` har ikke disse navnene.
- «Markus streng» i kolonnekommentaren i `0049_staff_colors.sql`. Skal
  være «Tom streng», som databasen har.
- «Pasientkoordinatoren» i en kommentar i `0015_seed_new_staff.sql`.

---

# A**** ut, lokal utlogging og restene i repoet

Natten til 2026-09-13. Tre oppdrag: det gamle monogrammet ut overalt,
`signOut()` til lokal utlogging, og restene i repoet fra forrige runde.

## 1 — A**** ut

`MARKUS'&nbsp;A****` var arvet fra det gamle prosjektnavnet.

| Flate | Før | Gjort |
|---|---|---|
| Produksjonens funksjonskropper | Allerede rene. Null treff i alle skjemaer; hodene i `send_booking_email`, `send_contact_message_email` og `send_document_email` sier `WESTENGEN&nbsp;KLINIKK` (`0074`/`0075`) | Ingenting å gjøre, kontrollert |
| Repoet, e-postmalene i 0026, 0028, 0039, 0040, 0048 | `MARKUS''&nbsp;A****` | `WESTENGEN&nbsp;KLINIKK`, samme som produksjon |
| Repoet, 0074 og 0075 | Konstanten og kommentarene siterte det gamle hodet | `[TIDLIGERE&nbsp;NAVN]`. Kommentaren i 0074 om den uescapede apostrofen er omformulert, siden den ikke lenger kan sitere linja |
| `docs/db-funksjoner-før-0074.sql` | Det gamle hodet, fire steder | `[TIDLIGERE&nbsp;NAVN]` |
| Migrasjonsloggen | Samme som repoet | Samme regler, se under |
| Denne rapporten | Sitater i tidligere avsnitt | Maskert `A****` |
| `scripts/verify-lekkasje.mjs` | Fanget bare den sammenskrevne varianten | Nytt mønster `\barena\b`. Bevist: plantet fil gir treff og exit 1 |

## 2 — Lokal utlogging

Alle sju kallene er nå `signOut({ scope: 'local' })`: `shared/auth.js`
(tidsavbrudd og `logoutAndRedirect`), `ansatt.html` (før
auto-innlogging), `booking-admin.html` (to fallbacker),
`innstillinger.html` og `kalender.html`. Service worker-cache `v85`.

### Prøven

Lokal server mot produksjonens auth, to sesjoner på admin-kontoen: A i
nettleseren, B laget direkte mot auth-API-et som «en annen besøkende».

| Steg | Resultat |
|---|---|
| Før | A og B finnes i `auth.sessions` |
| Siden har lastet ny kode | `logoutAndRedirect` inneholder `'local'` |
| «Logg ut» → bekreft i appens dialog | Forespørselen er `POST /auth/v1/logout?scope=local`, fanget med en fetch-logg som overlever redirecten |
| Nettleseren etterpå | På `ansatt.html` med innloggingsskjemaet; ingen sesjonsnøkkel i `localStorage` |
| A | Borte fra `auth.sessions` |
| B | Står, og fornyer tokenet sitt (200) |
| B logger seg ut selv (opprydding) | 204; fornyelse etterpå 400. Beviser at fornyelsesproben ser en død sesjon |

Serveren ble også isolert først: to sesjoner via API-et, den ene logget ut
med `scope=local`, den andre fornyet med 200.

### Den første prøven var ugyldig, og hvorfor

Første forsøk på `127.0.0.1:8765` tok med seg B. Siden kjørte den
**gamle** `auth.js`: kopien i service worker-cachen hadde ikke
`scope: 'local'`, mens serveren hadde det. `sw.js` precacher med
`cache.add(url)`, som kan svares fra nettleserens HTTP-cache, og Pythons
testserver sender ingen `Cache-Control`. Nettleseren hadde en gammel
kopi fra tidligere lokale runder på samme origin. En fetch-logg viste
`logout?scope=global`. Prøven ble gjentatt på `127.0.0.1:8766`, en origin
uten historikk, og besto.

De to ugyldige forsøkene sendte `scope=global` mot admin-kontoen,
21:46:23 og ca. 21:49 UTC. Admin-sesjonene ble listet rett før begge; de
eneste som fantes var testsesjonene fra prøven. Ingen andre ble logget ut.

**Sidefunn:** samme mekanisme kan i prinsippet ramme en besøkende som har
en gammel kopi i HTTP-cachen når ny `sw.js` installeres. Se kontrollen av
live under.

## 3 — Restene i repoet

| Hvor | Gjort |
|---|---|
| 0069, 0072, 0074, 0075, 0076 | «E***» → `[tidligere navn]` / `tidligere-id`, de samme reglene som migrasjonsloggen fikk. Kjører fortsatt som no-op på en fersk kjede, siden 0041 allerede seeder `markus` |
| 0030, 0044 | `slug like 't**-%'` → `'markus-%'` (kommentarer) |
| 0032, 0033 | `slug = 't**-test'` → `'markus-test'` (kommentarer) |
| 0049 | «Markus streng» → «Tom streng», som databasen har. I tillegg `t**=#3E6B47` → `markus=#3E6B47` i en kommentar, samme klasse |
| 0015 | «Pasientkoordinatoren» → «Nora» |
| `tjenester.html` | **Ikke på lista, men samme klasse:** legacy-prefikset `'t**-'` i `eligibleStaffFor` og hjelpeteksten → `'markus-'`, som er det de gamle katalograddene heter i repoet. Produksjon har null slugs med noen av prefiksene, så oppførselen endres ikke der |

Kontroll av SQL-endringene: alle endrede kodelinjer har samme antall
apostrofer før og etter, bortsett fra de fem malene der `MARKUS''` (escapet)
forsvant. PL/pgSQL-kroppene i alle 16 endrede migrasjoner er parset med
`pglast.parse_plpgsql`: ingen syntaksfeil. Proben bevist: en plantet
uescapet apostrof i 0026 gir `syntax error at or near "KLINIKK"`. Kjeden
`0000`–`0078` er ikke kjørt på nytt i replika i denne runden.

## 4 — Migrasjonsloggen

Backup først: `C:\Users\marku\supabase-backup\schema_migrations-pfyidlnztpwjnpxpoheu-2026-09-12-foer-monogram.json`,
md5 `bc1a4c66a5f83c3184fba71e855952a6`, lik i databasen og lokalt. Med
gjenopprettingsskript ved siden av.

Samme regler som repoet. I tillegg «Samme metode som 0074» → «Samme
fremgangsmåte» i 0075, repoets formulering fra `8168cd8`.

Sju rader endret (0026, 0028, 0039, 0040, 0048, 0074, 0075). Atomisk
`DO`-blokk med md5-vakt før og etter; vakten bevist mot plantet feil md5
(rullet tilbake, loggen urørt). Resultat: md5
`5c2837618336e14cac171cd79b9ca6d6`, 78 rader.

Loggen står nå ordrett i repoet for alle migrasjoner utenom de kjente
senere endringene (0015, 0038, 0041, 0050, 0051, 0053, 0063, 0065, 0068).
Før runden avvek også 0030, 0032, 0033, 0044, 0049, 0069, 0072, 0074, 0075
og 0076.

## 5 — Sveipet på nytt

Databasen, alle flater, eksportert på nytt fra produksjon.

| Klasse | Treff |
|---|---|
| `A****`, gamle navn og id-er, `T*-`, arvet tekst | 0 (utenom kontrollblokken i 0078, uendret) |
| E-post, registrerbare domener, gateadresser | 0 |
| IP og user-agent | Bare `auth.sessions`, ikke rørt |
| Gjenværende falske positiver | Som forrige runde: «tom» som norsk ord, migrasjonsnumre, pseudonymisert telefon, filgrense, to oppdiktede phishing-eksempler |

**Rettelse av eget verktøy:** oppsummeringen av sveipet delte funnøklene på
`|`, og mange mønstre inneholder `|`. Et første «sum: 0» var derfor ikke
til å stole på. Rettet og kjørt på nytt; tallene over er fra den rettede
versjonen.

Repoet: alle fem verify-skript grønne, og `git grep` finner ingen av
klassene utenom denne rapportens maskerte sitater.

## 6 — Push og live

Commits `6a239d0` (auth), `baf2e84` (opprydding), `e792da5` (denne
rapporten), pushet til `master`. Før push: `supabase migration list`
78 lokale = 78 remote, `db push --dry-run` «Remote database is up to
date».

| Kontroll på live | Resultat |
|---|---|
| `shared/auth.js` | `scope: 'local'` i begge kallene. De to gjenværende «`signOut()`» er kommentarer |
| `ansatt.html`, `booking-admin.html`, `innstillinger.html`, `kalender.html` | Null `signOut()` uten argument |
| `sw.js` | `shell-v85` |
| `tjenester.html` | Null `'t**-'` |
| Cache-headere på `shared/auth.js`, `sw.js`, admin-HTML | `Cache-Control: public, max-age=0, must-revalidate` |

Den siste raden avgjør sidefunnet over: Vercel lar ikke nettleseren bruke
en lagret kopi uten å revalidere, så `cache.add()` i `sw.js` får den nye
fila. Problemet var testserverens manglende header, ikke live.

**Står igjen:** én admin-sesjon (`332bb85b…`) opprettet da den ugyldige
prøven på 8765 lastet `innstillinger.html` på nytt. Ikke logget ut:
fanen på den origin-en kjørte gammel kode, og en utlogging derfra ville
vært global. Den utløper av seg selv.

---

# Runde 2026-09-15

Fem oppdrag: oversettelsene som manglet, språkvelgeren, mobilmenyen i
adminpanelet, toppen av adminpanelet og forsiden. Alt på branch
`runde/2026-09-15`, ikke merget.

Sikkerhetstag før noe ble rørt: `pre-runde-2026-09-15` (pushet).

## 1 — Hvor den uoversatte teksten faktisk lå

Kartlagt før noe ble endret, med en første versjon av proben mot koden
slik den var: **955 treff på norsk tekst** med engelsk valgt, fordelt på
19 sider. Teksten lå fem steder:

| Hvor | Hva | Omfang |
|---|---|---|
| **Adminpanelet, sidenes egen JavaScript og HTML** | Hele panelet. De elleve adminsidene lastet ikke `i18n/i18n.js` i det hele tatt; kommentarene sa «admin er norsk-only». Knapper, tabeller, dialoger, feilmeldinger, tomtilstander, `<title>`. | ~800 strenger, 12 000 linjer |
| **Databasen** | Tjenestenavn og -beskrivelser (`services`), roller og biografier (`staff_members`), dokumenttitler (`exercise_documents`). `bookings.service_name` og `staff_name` er *kopier* av teksten, uten id å slå opp på. | 4 tjenester, 9 behandlere, 8 dokumenter |
| **Datoformatering, hardkodet norsk** | `DAYS_NO_LONG`/`MONTHS_NO` i `booking-engine.js` (datolinja «Fredag 25. september»), egne kopier i `kalender.html` og `booking-admin.html`, og `toLocaleString('no-NO')` i ti adminsider. Beløp som `'kr ' + … toLocaleString('no-NO')` sju steder. | 21 steder |
| **Demoguiden, `shared/components.js`** | Hele innholdet hardkodet: overskrift, advarselen, velkomst, hurtigsvar, alle svar, fallback og eskalering. Nøkkelordene i svarmotoren fantes bare på norsk, så et engelsk spørsmål fikk aldri svar. | ~30 strenger |
| **Enkeltsteder på kundesidene** | Plassholdere i avbestill- og ventelisteskjemaene, demomerket og -dialogens `title`, hamburgerens `aria-label`, to avsnitt i `vilkar.html`, kontaktmodalen i `components.js`. | ~40 strenger |

Bestillingsflyten selv (trinnene, knappene) var allerede oversatt med
nøkler. Det som sto igjen der, var databaseteksten og datoene.

## 2 — Løsningen for databasetekst, og for resten

**Valgt: én oversettelsestabell i frontend, `i18n/en-tekst.json`, med den
norske teksten som nøkkel.** Det er gettext-prinsippet: kildeteksten er
nøkkelen. Ingen engelsk kolonne i databasen.

Hvorfor ikke en engelsk kolonne: bookingradene har `service_name` som
kopi av tjenestenavnet. En `name_en`-kolonne i `services` ville ikke
nådd de seedede bookingene eller noen booking laget før kolonnen
fantes, uten en migrasjon til og endret seed. Tabellen i frontend treffer
teksten hvor den enn står, og krever ingen databaseendring.

Den samme tabellen løste adminpanelet. Å legge `t('nøkkel', …)` rundt
~800 strenger i elleve siders innebygde JavaScript ville vært en
omskriving av panelet; i stedet slår `i18n.js` opp tekst i DOM-en mens
siden bygges:

| Del | Hva den gjør |
|---|---|
| `i18n/en-tekst.json` | 861 oppføringer norsk → engelsk, pluss 31 mønstre for tekst med tall og navn i («20 av 20 kunder», «Side 1 av 3», «Åpne kunde …»). Ordliste i fila: behandler = practitioner, terapeut = therapist, kunde = client, journal = record. |
| Nøklene i `no.json`/`en.json` | Legges inn i tabellen automatisk ved lasting. En tekst som står hardkodet ett sted og som nøkkel et annet, trenger bare nøkkelen. |
| Oppslaget | Hel tekst først, så mønstre, så kjente fraser inne i en lengre tekst som er satt sammen i kode. Frasene er begrenset til nøkler som ikke kan være et engelsk ord (flere ord, minst seks tegn eller æøå), så «time» og «Tid» aldri treffer engelsk tekst. |
| `MutationObserver` | Oversetter tekstnoder og `placeholder`, `title`, `aria-label`, `alt` og knappers `value` når de legges inn. Siden holdes skjult til katalogen er lastet, høyst 1,5 s, så det blir ikke norsk blaff. |
| `translate="no"` | HTML-standardens merke. Tekst fra brukere (meldinger, bookingnotater, journalnotater, anmeldelser, ventelistenotater) og tekniske id-er står under det og røres ikke. |
| Tilbake til norsk | Kundesidene setter originalene tilbake på stedet. Adminsidene laster på nytt, fordi de bygger datoer og tabeller ved lasting. |

**Datoer og beløp formateres med `Intl` etter valgt språk**, aldri med
norske navnelister: `WestengenKlinikkI18n.locale()` gir `nb-NO` eller
`en-GB`, og `beloep()` gir «kr 1 290» / «NOK 1,290». Før språkfilene er
lastet, gjelder det lagrede valget, så en side som tegner datoer tidlig
ikke får norske ukedager. Tre setninger bøyes ulikt på de to språkene og
bygges derfor i kode («Klinikken er stengt på søndager», ventelistas
«fra/kl./innen»).

Demoguiden svarer nå på engelske spørsmål: nøkkelordene står på begge
språk. Svarene er fortsatt norske i koden og går gjennom tabellen.

**Det tabellen ikke kan:** tekst i databasen som en administrator endrer,
får ingen oversettelse før noen legger den inn i tabellen. Et nytt
tjenestenavn vises på norsk i engelsk grensesnitt. For en demo med fire
tjenester er det riktig avveining; i drift ville en engelsk kolonne vært
det rette.

## 3 — Språkvelgeren

| | Før | Nå |
|---|---|---|
| Plassering, telefon | `position: fixed` mot viewporten med gjettet topp (`i18n.css`), og `left: 0` fra `header-nav.css` fra den gangen velgeren sto til venstre. Menyen la seg øverst til venstre på skjermen, over innholdet. | `position: absolute`, rett under knappen (6 px), høyrejustert mot knappens høyre kant, `z-index: 1000` (under dialogene på 10050). Begge de gamle reglene er fjernet. |
| Innhold | 🇳🇴 / 🇬🇧 på knappen og i menyen. Windows viser flaggene som «NO» og «GB». | «Norsk» / «English» som tekst. Valgt språk har farge **og** et hakemerke, så valget ikke bare bæres av farge. |
| Trykkflate | Valgene 42–43 px | Knapp og valg minst 44 px |
| Adminpanelet | Ingen velger | Samme velger i verktøygruppa i seksjonslinja (over 640 px), og som «Norsk \| English» i kontoraden i mobilmenyen. Bytte laster adminsiden på nytt. |

**Sidefunn:** `personvern.html` lastet `demo-ui.css` før `header-nav.css`,
i motsatt rekkefølge av de andre sidene. Merket ble derfor sentrert og
språkvelgeren havnet til venstre på telefon. Rekkefølgen er rettet, og
headeren er lik de andre sidene.

## 4 — Mobilmenyen i adminpanelet

Arket er bygget ovenfra og ned etter bruk:

| Før | Nå |
|---|---|
| «Meny»-hode, så «ADMIN» med strek under, en «…»-varslingsknapp, «Admin-panel» og «Logg ut» som to fulle bredder, **så** rutenettet. Rutenettet startet 311 px ned i arket. | «Meny»-hode (lukkeknapp 44 px), rutenettet rett under (starter 72 px ned), og en kontorad nederst: språk, varsler, «Logg ut». |
| «ADMIN» | Borte. Rollen står i seksjonslinja. |
| «Admin-panel» og sidenes andre topplenker | Ikke i arket; de peker på sider som allerede står i rutenettet. På bred skjerm står de i headeren som før. |
| «Logg ut» | Nederst til høyre som en avsluttende handling, dempet rød ramme. Knappen trykker på sidens egen `#logoutBtn`, så bekreftelsesdialogen og lokal utlogging går samme vei som før. |
| Rader 54 px | 48 px, ikoner og to kolonner beholdt |
| Markert punkt | Stengte tider og loggen over oppslag markerte ingenting, og bunnlinja sa «Westengen Klinikk». Nå markeres forelderen (Innstillinger), og bunnlinja har samme navn som seksjonslinja. |

Målt på kalenderen, 375 × 812: arket er 371 px høyt, mot 579 før. Ingen rulling på 320–414 × 812, begge språk, alle adminsider, og heller ikke på 320 og 375 × 667 på engelsk, som har lengst tekst.

## 5 — Toppen av adminpanelet

To grupper, ikke fire løse elementer:

- **Seksjonen**, venstre: navnet i 16 px halvfet blekk (før 14 px blått, likt lenkene), og demo-merket underordnet som dempet tekst uten ramme og flate. Merket beholder 44 px trefflate, utvidet usynlig. Undersider har forelder foran: «Innstillinger › Stengte tider», «Kunder › Kundekort».
- **Verktøyene**, høyre, i én `role="group"`: rollevelger, språk, «Til nettsiden».

Brekkingen er bestemt, ikke overlatt til `flex-wrap`:

| Bredde | Oppsett |
|---|---|
| Over 640 px, alt får plass | Én rad, begge grupper midtstilt på samme linje |
| Over 640 px, seksjonsnavnet måtte kortes eller verktøyene ikke får plass | To rader: seksjonen øverst med merket til høyre, verktøyene under med «Til nettsiden» til høyre. Måles, ikke gjettet med et tall: engelsk og norsk er ulikt lange, og hver adminside har sin egen innholdsbredde (720 px på kalenderen, 1300 på meldinger). |
| 640 px og under | Alltid to rader. Forelderen skjules (den står i bunnlinja og menyen), språket ligger i menyen, rollevelger og lenke er 44 px høye. Under 400 px sier merket bare «Demo»; hele teksten står i `aria-label` og i dialogen. |

**Seksjonsindikatoren stemte ikke overalt:** `booking-admin.html` het
«Bookinger» i seksjonslinja og «Oversikt» i menyen og i `<title>`. Nå
«Oversikt» begge steder (engelsk «Overview»).

## 6 — Forsiden

| Før | Nå |
|---|---|
| Øyebrynstekst, overskrift og den lange ingressen på mørk flate, **så** de to dørene, som stablet seg under 860 px. På 375 startet dørene etter et helt skjermbilde med tekst. | Øyebrynstekst og overskrift, **så** dørene side om side på alle bredder, **så** ingressen, uendret, i egen seksjon rett under. |

- **Side om side også på 375 og 320.** Prøvd først, som du ba om, og det holdt: 16–22 tegn per linje i listene, alt lesbart. Begge dørknappene står i første skjermbilde på 320, 375 og 414 (812 px høyde), begge språk.
- **Paret:** samme ramme og 1 px skillelinje mellom dem, lik høyde, knappene på samme grunnlinje nederst. Kundeflyten lys som sidene den fører til, adminpanelet mørkt som skallet bak. Det var grepet fra før; det er beholdt.
- **Typografien strammes på telefon**, ikke teksten: 19 px overskrift, 13 px brødtekst, 12,5 px lister, knapper 44 px høye. Under 360 px litt tettere lister og 28 px hovedoverskrift, fordi engelsk er lengre.
- Alt innhold på forsiden står på samme venstrekant som merket i headeren (16 px) på telefon. Før sto headeren på 16 og innholdet på 32.
- **Ingen tekst er skrevet om.** Norsk tekst er sammenlignet mot koden før runden, side for side: bare demomerket (nå to spenn) og språkknappen («Norsk» i stedet for flagg) skiller.
- **Desktop:** som før, bare med ingressen etter dørene. Dørene begynner 437 px ned på 1280.

## 7 — Proben: `scripts/probe-norsk.mjs`

Laster hver side på engelsk i en ekte nettleser (Playwright, 375 px og
1280 px) og melder fra om norsk tekst som står igjen. Den ser alle
tekstnoder, også i lukkede dialoger og menyer, pluss `placeholder`,
`title`, `aria-label`, `alt` og `<title>`. Den går gjennom tilstander som
bare finnes etter en handling, og skriver ut hvilke den faktisk nådde:

| Side | Tilstander |
|---|---|
| Bestilling | trinn 1–5, demoguiden, alle hurtigsvar, to ukjente spørsmål til eskalering |
| Oversikt | alle fem faner, bookingdetaljer, ny booking trinn 1 og 2 |
| Kalender | bookingdetaljer |
| Tjenester, Behandlere | ny og rediger |
| Dokumenter | «Send til kunde» |
| Kunder | kundekortet til første kunde |
| Forsiden | demodialogen, språkmenyen |
| Alle adminsider | demodialogen, mobilmenyen |

Ingen tilstand sender inn noe, og journalen åpnes ikke (hvert oppslag
skrives til loggen over oppslag).

Norsk kjennes igjen på æøå eller et ord fra en liste over norske ord som
ikke også er engelske. Den hopper bevisst over tre ting, og teller dem:

- tekst under `translate="no"` (brukertekst og id-er)
- personnavn, kjent på formen: to ord med stor forbokstav etter hverandre, ingen av dem på ordlista («Thea Molvær»)
- innholdet i `<textarea>`, som er feltverdi, ikke grensesnitt

Den sjekker også at merkenavnet ikke er oversatt.

### Bevist

| Plantet | Resultat |
|---|---|
| `PLANT=1`: «Timen din er bekreftet og lagret» inn i siden etter oversetting | Fanget på begge sidene, exit 1 |
| «Klinikk» tatt ut av katalogen, så ordmerket blir «Clinic» | «MERKENAVN OVERSATT: WestengenClinic», exit 1 |
| Koden før runden | 955 treff |

To feil i proben ble funnet mens den ble skrevet, og rettet før den ble
stolt på: `\b` foran «Ø» (JavaScript-ens `\b` kjenner bare ASCII, så
navn med Ø ble ikke gjenkjent), og en profil som gjenbrukte en gammel
service worker og dermed viste proben filer som ikke fantes på serveren
lenger. Proben starter nå en tom nettleser hver gang, med service
workere blokkert.

**Sidefunn i en eksisterende probe:** `scripts/verify-lekkasje.mjs`
hadde et backspace-tegn (0x08) der det skulle stått `\b`, i mønsteret for
registrerbare domener. Mønsteret krevde et kontrolltegn etter
toppdomenet og kunne aldri treffe; det har vært grønt på feil grunnlag
siden det ble lagt inn. Rettet og bevist mot en plantet adresse. Det ene
treffet det da fant, et sitat i denne rapporten, er maskert. Egen commit.

`scripts/verify-i18n.mjs` behandlet `en-tekst.json` som et tredje språk.
Den kjenner nå katalogene: ingen tomme verdier, og hvert mønster må være
et gyldig regulært uttrykk. Bevist mot en plantet tom verdi og et
uavsluttet mønster.

## 8 — Verifisering

### Sjekkliste

| | Status |
|---|---|
| Engelsk: null norsk tekst i bestillingsflyten, adminpanelet og demoguiden | **Ja.** `probe-norsk`: 21 sider, 0 treff, både 375 og 1280 px. 19 tekster under `translate="no"` og 299 personnavn med æøå hoppet over med vilje, se over. |
| Datoer og ukedager følger valgt språk | **Ja.** «Tuesday 15 September at 12:00», «NOK 1,290» i bestillingsflyten på preview; ukestripa i kalenderen «TU/WE» mot «TI/ON». Norsk er uendret, kontrollert tekst for tekst mot koden før runden. |
| Språkvelgeren under knappen, uten emoji, innenfor skjermen, 320–1440 | **Ja.** Målt på alle åtte kundesider, sju bredder, begge språk: rett under knappen, høyrejustert mot den, innenfor skjermen, øverst (ingenting over den), ingen emoji, valgene 44 px. Samme måling mot koden før runden: 28 feil på to sider. |
| Mobilmenyen: ADMIN borte, Logg ut nederst, alt uten rulling på 375 | **Ja**, alle elleve adminsider, se punkt 4. |
| Toppen av adminpanelet likt på alle sider, forutsigbar brekking | **Ja.** Målt på alle elleve adminsider, sju bredder, begge språk: seksjonen og verktøyene i hver sin gruppe, midtstilt på én linje når det er plass og verktøyene under seksjonen ellers, navnet aldri kuttet, trykkflater 44 px på telefon, bunnlinja og seksjonslinja sier det samme. |
| Forsiden: dørene først, teksten under, lesbart på 375 | **Ja**, se punkt 6. |
| Desktop uendret der det ikke er nevnt | **Ja.** Piksel-diff på 1280 mot koden før runden, ti sider: kundesidene skiller seg bare i headerlinja (språkknappen). `vilkar.html` er 6 px lenger, fordi språkknappen nå er 44 px høy. Adminsidene skiller seg i seksjonslinja, som var oppdraget. |
| Fem offentlige endepunkter gjennom ekte skjemaer, med adminsesjon | **Ja**, se under. |
| Ingen konsollfeil, 320–1440, begge språk | **Ja**, se under. |
| Testrader ryddet og bekreftet borte | **Delvis**, som forrige runde: anmeldelsen står igjen som `rejected`, se under. |

### Endepunktene

Chrome, adminsesjon for `admin@westengenklinikk.example` liggende i
`localStorage`. Testdata: `Testrad Runde`,
`testrad.runde@westengenklinikk.example`, `+47 400 00 099`.

Branchen er ikke merget, så produksjon kjører fortsatt koden fra før
runden. Fire endepunkter er derfor testet på Vercels preview av branchen
(`booking-demo-hwy3sbta7-…vercel.app`, commit `dbefdc9`), som er koden som
skal inn. Kontaktskjemaet kan ikke fullføres der, fordi Turnstile er
bundet til produksjonsdomenet (kjent, se «Turnstile i produksjon»). Det er
testet på live.

| Endepunkt | Hvor | Resultat |
|---|---|---|
| Bestilling, engelsk | preview | Markus → Initial assessment → Tuesday 15 September 12:00 → «Your appointment is confirmed», `WK-46UQ-4921` |
| Bestilling, norsk | preview | Markus → Førstegangsvurdering → fredag 18. september 06:00 → «Timen er bekreftet», `WK-UTZ1-3513` |
| Avbestilling, engelsk | preview | `WK-UTZ1-3513` + e-post → «Confirm cancellation» → «Your appointment is cancelled». Den første bookingen lå under 24 timer fram og kunne ikke avbestilles, derfor to. |
| Venteliste, engelsk | preview | Markus, fra 1. oktober → «You're on the waiting list», `WK-WL-KYG3-N8SX` |
| Anmeldelse, engelsk | preview | `review_token` fra seed-timen `demo-20260911-sofie-52` → «Thank you for your review!» |
| Kontakt | preview | Som ventet: ingen token, knappen låst, «The security check did not go through. Reload the page and try again.», nå på engelsk |
| Kontakt | live | Token utstedt, knappen åpnet, «Takk! Meldingen er sendt.» |

### Konsoll og bredder

Lokal server med filene fra HEAD, Playwright, service workere blokkert:
19 sider × 320, 375, 414, 768, 1024, 1280 og 1440 × norsk og engelsk,
266 sidevisninger. I hver er konsollfeil, sidelengs rulling,
seksjonslinja, mobilmenyen og forsidens dører målt. Sjekkene er bevist
mot koden før runden, der de fanget ADMIN-hodet, «Logg ut» over
rutenettet, rutenettet 311 px ned, trykkflater under 44 px, manglende
markering og feil navn i bunnlinja på stengte tider, og konsollfeilen
under.

Første sveip: **5 feil**, alle på 320 px, alle rettet og sveipet på nytt:

| Feil | Fantes før runden? | Rettet |
|---|---|---|
| Oversikten rullet sidelengs (352 px): en lang e-postadresse dyttet bookingkortets kolonne ut | Ja | `minmax(0, 1fr)` og `overflow-wrap: anywhere` |
| Kundekortet rullet sidelengs (365 px), samme årsak i nøkkel/verdi-rutenettet | Ja | Samme |
| Menyknappen på de to sidene kunne ikke trykkes; innholdet som rant ut, la seg over den | Ja | Forsvant med de to over |
| Forsidens dørknapper under første skjermbilde på engelsk 320 px (845 px) | Nei, min | Strammere lister og overskrift under 360 px |

Etter rettelsene: **0 feil.**

**Konsollfeil fjernet:** alle 21 sider hadde `frame-ancestors 'none'` i
CSP-en i `<meta>`, der nettleseren ignorerer direktivet og logger en feil
på hver side. Det leveres allerede som HTTP-header fra `vercel.json`, så
linja i `<meta>` er fjernet. Sikkerheten er uendret.

Kontaktsidens Turnstile svarer 400 lokalt, som er den kjente
domenebindingen. Sveipet tillater det bare mot `localhost`.

### Testrader

| Tabell | Rad | Status |
|---|---|---|
| `bookings` | `WK-46UQ-4921`, `WK-UTZ1-3513` | Slettet, bekreftet borte |
| `waitlist` | `WK-WL-KYG3-N8SX` | Slettet, bekreftet borte |
| `contact_messages` | Testrad Runde | Slettet, bekreftet borte |
| `reviews` | «Testrad R.», 4 stjerner | **Står igjen**, satt til `rejected`. Admin har ingen delete-policy på anmeldelser (403). Slettes av nullstillingen. |

Kontrollert etterpå: null ikke-seed-rader i `bookings`, `waitlist`,
`contact_messages`, `blocked_slots`, `holidays`, `special_open_days`,
`exercise_documents`, `services` og `staff_members`; én i `reviews`, den
over. Ryddingen gikk mot REST-API-et med demokontoen, ikke gjennom
nettleseren, og ble logget ut med `scope=local`.

Probene logger inn på nytt ved hver kjøring (tom nettleser), så
`auth.sessions` har fått flere admin-sesjoner fra denne maskinen i natt.
De utløper av seg selv.

### Raske gater, sist kjørt

    verify-arvet-tekst   ingen arvet markedsfoeringstekst
    verify-i18n          i18n OK
    verify-inline-js     21 inline-blokker, 0 med feil
    verify-lekkasje      ingen treff
    verify-lenker        30 filer sjekket, alle interne lenker finnes

Service worker-cache bumpet til `v86`.

## 9 — Avvik fra bestillingen

1. **Overskriften står over dørene.** Ingressen er flyttet ned, som bestilt. Øyebrynsteksten og `<h1>` står igjen over dørene, strammere: siden trenger én overskrift før valget, ellers begynner den med to kort uten sammenheng. Dørene er likevel i første skjermbilde på telefon.
2. **Språkvelgeren i adminpanelet ligger i menyen på telefon**, ikke i verktøygruppa. Rollevelger, språk og «Til nettsiden» fikk ikke plass på én rad på 320 px med 44 px trykkflater. På bred skjerm står den i verktøygruppa.
3. **Tekst fra brukere oversettes ikke**: meldinger, bookingnotater, journalnotater, anmeldelser og ventelistenotater. Seed-dataene er norske og vises norsk i engelsk panel, merket `translate="no"`. Å oversette det en kunde har skrevet, ville vært feil i et ekte system. Proben teller dem for seg.
4. **Personnavn med æøå** («Terje Østby») gjenkjennes på formen i proben, ikke ved merking. De vises for mange steder til at hvert er merket.
5. **Databasetekst via tabell i frontend, ikke kolonne.** Et nytt tjenestenavn lagt inn i panelet får ingen engelsk versjon før noen legger den inn i `en-tekst.json`. Se punkt 2.
6. **Demoguidens svar er oversatt ordrett**, også der de ikke stemmer med demoen lenger, se sidefunn.
7. **Kontaktskjemaet er testet på live**, de fire andre på preview. Se Endepunktene.
8. **Terapeutrollen er ikke probet på engelsk.** Rollen ser et utvalg av de samme sidene med de samme tekstene, men proben kjører som administrator.
9. **Proben krever Playwright.** Repoet har ingen `package.json` med vilje (Vercel ville installert den ved hver utrulling), så modulen hentes fra `PLAYWRIGHT_MODULE`. Oppskriften står øverst i fila.

## Sidefunn

**Demoguidens svar stemmer ikke med demoen lenger.** «Innloggingen står
åpent på forsiden» (panelet åpner seg selv nå), «Alle timer er 30
minutter», og prisene kr 4 000 / 2 000 (tjenestene i basen koster
kr 690–1 490 og varer 30–60 minutter). Svarene mangler også æøå
(«arbeidsprove», «pa»). Ikke endret: det var ikke oppdraget.

**`vilkar.html` har de samme gamle prisene.** Oversatt ordrett.

**`personvern.html` lastet CSS i feil rekkefølge**, se punkt 3. Rettet.

**Varslingsknappen i mobilmenyen** viser «…» i en nettleser der service
workere er blokkert, fordi den venter på registreringen. I en vanlig
nettleser viser den bjella. Trykkflata er satt til 44 px.

## Commits

`7c2c310` (verify-lekkasje), `0969136`, `8fedbd0`, `dbefdc9`, og denne
rapporten. Pushet til `runde/2026-09-15`. Ikke merget til `master`.
