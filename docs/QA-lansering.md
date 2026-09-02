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
