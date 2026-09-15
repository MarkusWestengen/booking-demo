// Sammenligner prisene og varighetene i teksten med databasen.
//
// Demoguiden (shared/components.js), vilkaarene (vilkar.html) og
// rammene paa bestillingssiden skriver prisene ut som tekst. Databasen
// er autoritativ, saa teksten sklir naar noen endrer en pris i panelet.
// Denne proben leser tjenestene som anon (samme vei som bestillings-
// siden) og krever at hver aktiv, offentlig tjeneste staar med riktig
// pris og varighet paa norsk og engelsk, og at ingen annen pris staar der.
//
//   node scripts/verify-priser.mjs
import { readFileSync } from 'node:fs';

const les = (f) => readFileSync(f, 'utf8');
const cfg = les('shared/booking-config.js');
const url = cfg.match(/supabaseUrl: '([^']+)'/)[1];
const key = cfg.match(/supabaseAnonKey: '([^']+)'/)[1];

let tjenester;
try {
  const r = await fetch(url + '/rest/v1/services?select=name,price_nok,duration_min&is_active=eq.true&is_public=eq.true&order=sort_order',
    { headers: { apikey: key, authorization: 'Bearer ' + key } });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  tjenester = await r.json();
} catch (e) {
  console.error('fikk ikke lest tjenestene fra databasen: ' + e.message);
  tjenester = [];
}
// process.exit etter fetch krasjer Node paa Windows (libuv-assert, exit 127),
// saa utgangskoden settes i stedet.
if (!tjenester.length) { console.error('databasen ga null tjenester'); process.exitCode = 2; }

const kat = JSON.parse(les('i18n/en-tekst.json'));
const en = JSON.parse(les('i18n/en.json'));
const no = JSON.parse(les('i18n/no.json'));
const nb = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');   // 1 290
const gb = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');   // 1,290
const feil = [];
if (!tjenester.length) feil.push('ingen tjenester aa sammenligne med');

// Demoguidens prissvar, slik det staar i koden og i katalogen.
const js = les('shared/components.js');
const svarNo = (js.match(/'(Prisene ligger i databasen[^']*)'/) || [])[1] || '';
const svarEn = kat[svarNo] || '';
if (!svarNo) feil.push('demoguiden: fant ikke prissvaret i shared/components.js');
if (svarNo && !svarEn) feil.push('demoguiden: prissvaret mangler i i18n/en-tekst.json');

// Vilkaarene: <li><strong>Navn:</strong> kr N (M min)</li>
const vilkar = les('vilkar.html');
const liste = (vilkar.match(/<ul data-priser>([\s\S]*?)<\/ul>/) || [])[1] || '';
if (!liste) feil.push('vilkar.html: fant ikke <ul data-priser>');
const rader = [...liste.matchAll(/<li><strong>([^<]+):<\/strong>\s*([^<]+)<\/li>/g)].map((m) => [m[1].trim(), m[2].trim()]);

for (const t of tjenester) {
  const navnEn = kat[t.name];
  if (!navnEn) feil.push(`${t.name}: mangler engelsk navn i i18n/en-tekst.json`);
  const gNo = `${t.name} kr ${nb(t.price_nok)} (${t.duration_min} minutter)`;
  const gEn = `${navnEn} NOK ${gb(t.price_nok)} (${t.duration_min} minutes)`;
  if (!svarNo.includes(gNo)) feil.push(`demoguiden, norsk: forventet «${gNo}»`);
  if (!svarEn.includes(gEn)) feil.push(`demoguiden, engelsk: forventet «${gEn}»`);

  const rad = rader.find(([n]) => n === t.name);
  const vNo = `kr ${nb(t.price_nok)} (${t.duration_min} min)`;
  const vEn = `NOK ${gb(t.price_nok)} (${t.duration_min} min)`;
  if (!rad) feil.push(`vilkar.html: ${t.name} mangler i prislista`);
  else if (rad[1] !== vNo) feil.push(`vilkar.html, norsk: ${t.name} staar som «${rad[1]}», databasen sier «${vNo}»`);
  if (kat[vNo] !== vEn) feil.push(`vilkar.html, engelsk: «${vNo}» skal vaere «${vEn}» i katalogen, er «${kat[vNo]}»`);
  if (kat[t.name + ':'] !== navnEn + ':') feil.push(`vilkar.html, engelsk: «${t.name}:» mangler i katalogen`);
}

// Ingen pris eller tjeneste i teksten som databasen ikke kjenner.
const priserNo = new Set(tjenester.map((t) => nb(t.price_nok)));
const priserEn = new Set(tjenester.map((t) => gb(t.price_nok)));
for (const [hvor, tekst, re, kjente] of [
  ['demoguiden, norsk', svarNo, /kr ([\d ]+\d)/g, priserNo],
  ['demoguiden, engelsk', svarEn, /NOK ([\d,]+\d)/g, priserEn],
  ['vilkar.html, norsk', vilkar, /kr ([\d ]+\d)/g, priserNo],
]) {
  for (const m of tekst.matchAll(re)) if (!kjente.has(m[1])) feil.push(`${hvor}: «${m[0]}» finnes ikke i databasen`);
}
for (const [n] of rader) if (!tjenester.some((t) => t.name === n)) feil.push(`vilkar.html: «${n}» er ikke en aktiv tjeneste i databasen`);
for (const m of svarNo.matchAll(/\((\d+) minutter\)/g)) if (!tjenester.some((t) => String(t.duration_min) === m[1])) feil.push(`demoguiden: varighet ${m[1]} minutter finnes ikke i databasen`);

// Rammene paa bestillingssiden: varighetene som «30 eller 60 minutter».
const varigheter = [...new Set(tjenester.map((t) => t.duration_min))].sort((a, b) => a - b);
for (const [hvor, tekst] of [['spec.duration_val, norsk', no['spec.duration_val']], ['spec.duration_val, engelsk', en['spec.duration_val']]]) {
  const tall = [...(tekst || '').matchAll(/\d+/g)].map((m) => +m[0]);
  if (tall.join() !== varigheter.join()) feil.push(`${hvor}: «${tekst}», databasen har ${varigheter.join(' og ')} minutter`);
}

if (feil.length) {
  console.log(`${feil.length} avvik mot databasen:`);
  for (const f of feil) console.log('  ' + f);
  if (!process.exitCode) process.exitCode = 1;
} else console.log(`priser OK: ${tjenester.length} tjenester, demoguiden, vilkaarene og rammene stemmer med databasen`);
