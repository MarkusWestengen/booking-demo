// Leter etter spor av virkelige mennesker, steder og systemer i alt
// som foelger med repoet.
//
// Ordlista er ikke generisk. Den er bygget av det som faktisk har
// ligget her tidligere: klinikkens gamle navn, ekte e-postdomener,
// LAN-adresser, og vokabular fra oppdraget demoen kom ut av.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

const HOPP_OVER = new Set(['.git', 'node_modules', '_arkiv', 'dist', '.vercel']);
// Denne fila inneholder moenstrene og ville alltid treffe seg selv.
const EGEN_FIL = 'verify-lekkasje.mjs';

// onboarding@resend.dev er Resend sin egen offentlige testavsender.
// Den staar i e-postmalene med vilje, og er ikke en lekkasje.
const GODKJENT = [/onboarding@resend\.dev/];
const TEKST = new Set(['.html', '.js', '.mjs', '.css', '.json', '.md', '.sql', '.ts', '.txt', '.yml', '.yaml', '.svg']);

const MOENSTRE = [
  // Ekte e-post: alt som ikke er .example eller et aapenbart eksempel.
  [/[\w.+-]+@(?!(?:[\w-]+\.)*example\b)(?!example\.(?:com|org|net))[\w-]+\.[a-z]{2,}/gi, 'e-postadresse'],
  // Registrerbare domener som ligner klinikkens.
  // Bare ekte toppdomener. «WestengenKlinikk.openBooking» i JS er
  // ikke et domene.
  [/westengenklinikk\.(?:no|com|net|org|dev|io|app|se|dk)/gi, 'registrerbart domene'],
  [/tomsarena|toms-arena|toms\.arena/gi, 'gammelt prosjektnavn'],
  // Norske telefonnumre som ikke er plassholderen 400 00 000.
  [/\+47[ ]?(?!400[ ]?00[ ]?000)\d{2}[ ]?\d{2}[ ]?\d{2}[ ]?\d{2}/g, 'telefonnummer'],
  // Adresser paa LAN.
  [/\b(?:192\.168|10\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b/g, 'LAN-adresse'],
  // Hemmeligheter.
  [/service_role["' ]*[:=]["' ]*eyJ/g, 'service role key'],
  [/sk_live_|sk_test_|SUPABASE_SERVICE_ROLE_KEY\s*=\s*ey/g, 'hemmelig noekkel'],
];

const funn = [];
function gaa(dir) {
  for (const navn of readdirSync(dir)) {
    if (HOPP_OVER.has(navn)) continue;
    const sti = join(dir, navn);
    const st = statSync(sti);
    if (st.isDirectory()) { gaa(sti); continue; }
    if (!TEKST.has(extname(sti))) continue;
    if (navn === EGEN_FIL) continue;
    const linjer = readFileSync(sti, 'utf8').split('\n');
    linjer.forEach((l, i) => {
      for (const [re, navn2] of MOENSTRE) {
        re.lastIndex = 0;
        const m = re.exec(l);
        if (!m) continue;
        if (GODKJENT.some((g) => g.test(m[0]))) continue;
        funn.push(`${sti}:${i + 1}  [${navn2}]  ${m[0]}`);
      }
    });
  }
}
gaa('.');

if (funn.length) {
  console.log(`${funn.length} treff:`);
  for (const f of funn) console.log('  ' + f);
  process.exit(1);
}
console.log('ingen treff');
