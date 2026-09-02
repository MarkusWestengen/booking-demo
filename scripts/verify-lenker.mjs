// Sjekker at hver interne lenke og hver lokal ressurs finnes.
//
// Tar href/src i HTML, url() i CSS, og de stiene JS-en slaar opp med
// vanlige strenger. Eksterne adresser og mailto/tel hoppes over.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, extname, dirname, normalize } from 'node:path';

const filer = [];
function gaa(dir) {
  for (const n of readdirSync(dir)) {
    if (['.git', 'node_modules', '_arkiv', '.vercel', 'supabase'].includes(n)) continue;
    const s = join(dir, n);
    if (statSync(s).isDirectory()) gaa(s);
    else if (['.html', '.css'].includes(extname(s))) filer.push(s);
  }
}
gaa('.');

const EKSTERN = /^(https?:|mailto:|tel:|data:|#|javascript:|blob:)/i;
const problemer = [];

for (const f of filer) {
  const tekst = readFileSync(f, 'utf8');
  const mål = new Set();

  if (extname(f) === '.html') {
    for (const m of tekst.matchAll(/(?:href|src)\s*=\s*"([^"]+)"/g)) mål.add(m[1]);
    for (const m of tekst.matchAll(/(?:href|src)\s*=\s*'([^']+)'/g)) mål.add(m[1]);
  }
  for (const m of tekst.matchAll(/url\(\s*['"]?([^'")]+)['"]?\s*\)/g)) mål.add(m[1]);

  for (const raw of mål) {
    const u = raw.trim();
    if (!u || EKSTERN.test(u)) continue;
    const sti = u.split('#')[0].split('?')[0];
    if (!sti) continue;
    const abs = sti.startsWith('/')
      ? normalize('.' + sti)
      : normalize(join(dirname(f), sti));
    if (!existsSync(abs)) problemer.push(`${f}  ->  ${u}`);
  }
}

if (problemer.length) {
  console.log(`${problemer.length} lenker peker paa noe som ikke finnes:`);
  for (const p of problemer) console.log('  ' + p);
  process.exit(1);
}
console.log(`${filer.length} filer sjekket, alle interne lenker finnes`);
