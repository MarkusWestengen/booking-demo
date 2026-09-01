/* ============================================================
   verify-i18n.mjs — sjekker at oversettelsene henger sammen
   ------------------------------------------------------------
   Kjør: node scripts/verify-i18n.mjs

   Fire ting går galt med oversettelsesfiler, og alle fire er
   usynlige helt til noen bytter språk:

     1. En nøkkel finnes i ett språk og ikke i et annet.
     2. Markup bruker en nøkkel som ikke finnes noe sted.
     3. En verdi er tom.
     4. En nøkkel finnes i filene, men ingen bruker den.

   De tre første er feil og gir exit 1. Den fjerde er bare en
   opplysning: mange nøkler slås opp fra JavaScript med variabel
   nøkkel, og de kan ikke ses av et tekstsøk.
   ============================================================ */
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const I18N = join(ROOT, 'i18n');

const langs = readdirSync(I18N)
  .filter((f) => f.endsWith('.json'))
  .map((f) => f.replace('.json', ''))
  .sort();

if (langs.length === 0) {
  console.error('Fant ingen språkfiler i i18n/');
  process.exit(1);
}

const data = {};
for (const l of langs) {
  try {
    data[l] = JSON.parse(readFileSync(join(I18N, `${l}.json`), 'utf8'));
  } catch (e) {
    console.error(`i18n/${l}.json er ikke gyldig JSON: ${e.message}`);
    process.exit(1);
  }
}

const problems = [];

// ----- 1) Samme nøkkelsett i alle språk -----------------------
const base = langs[0];
const baseKeys = new Set(Object.keys(data[base]));
for (const l of langs.slice(1)) {
  const keys = new Set(Object.keys(data[l]));
  for (const k of baseKeys) {
    if (!keys.has(k)) problems.push(`mangler i ${l}.json: ${k}`);
  }
  for (const k of keys) {
    if (!baseKeys.has(k)) problems.push(`mangler i ${base}.json: ${k}`);
  }
}

// ----- 3) Ingen tomme verdier ---------------------------------
for (const l of langs) {
  for (const [k, v] of Object.entries(data[l])) {
    // _meta er et objekt med filinfo, ikke en oversettelse.
    if (k === '_meta') continue;
    if (typeof v !== 'string' || v.trim() === '') {
      problems.push(`tom verdi i ${l}.json: ${k}`);
    }
  }
}

// ----- 2) Alle nøkler markup bruker, finnes -------------------
function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (['node_modules', '.git', '.next'].includes(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.(html|js)$/.test(e.name)) out.push(p);
  }
  return out;
}

const ATTR = /data-i18n(?:-html|-aria-label|-placeholder|-title|-content)?="([^"]+)"/g;
const TCALL = /\bt\(\s*['"]([\w.]+)['"]/g;

const used = new Set();
for (const f of walk(ROOT)) {
  const src = readFileSync(f, 'utf8');
  for (const m of src.matchAll(ATTR)) used.add(m[1]);
  for (const m of src.matchAll(TCALL)) used.add(m[1]);
}

for (const k of used) {
  // Nøkler som ender på punktum er prefikser satt sammen i JS
  // ('behandlere.' + id). Selve oppslaget kan ikke ses av et
  // tekstsøk, så de kan ikke sjekkes her.
  if (k.endsWith('.')) continue;
  // 'key' kommer fra dokumentasjonseksempler i kommentarer.
  if (k === 'key') continue;
  if (!baseKeys.has(k)) problems.push(`brukt i markup, mangler i språkfilene: ${k}`);
}

// ----- 4) Ubrukte nøkler (opplysning, ikke feil) --------------
const unused = [...baseKeys].filter((k) => !used.has(k) && k !== '_meta');

console.log(`språk: ${langs.join(', ')}`);
console.log(`nøkler: ${baseKeys.size}   brukt i markup: ${used.size}`);
if (unused.length) {
  console.log(`ubrukte i tekstsøk: ${unused.length} (mange slås opp dynamisk fra JS)`);
}

if (problems.length) {
  console.error(`\n${problems.length} problemer:`);
  for (const p of problems.slice(0, 40)) console.error(`  ${p}`);
  if (problems.length > 40) console.error(`  ... og ${problems.length - 40} til`);
  process.exit(1);
}

console.log('\ni18n OK');
