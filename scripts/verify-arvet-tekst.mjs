// Leter etter tekst demoen arvet fra klinikken den ble laget ut av:
// paastander om metode, opplaering, erfaring og resultater, omtale av
// idrett og medier, og kundesitater. Navnebyttet fanget navnene, ikke
// spraaket; denne sjekken fanger spraaket.
//
// Ordlista er bygget av det som faktisk sto i repoet foer oppryddingen
// 2026-09-12 (docs/QA-lansering.md). Den er ikke generisk.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname, sep } from 'node:path';

const HOPP_OVER = new Set(['.git', 'node_modules', '_arkiv', 'dist', '.vercel']);
const TEKST = new Set(['.html', '.js', '.mjs', '.css', '.json', '.md', '.sql', '.ts', '.txt']);

// Rapporten siterer det som ble fjernet, og denne fila inneholder
// moenstrene. Begge ville alltid treffe seg selv.
const UNNTAK = [
  'verify-arvet-tekst.mjs',
  ['docs', 'QA-lansering.md'].join(sep),
];

const MOENSTRE = [
  /oppl(æ|ae)rt (direkte|av Markus)/i,
  /samme (metodikk|filosofi|grundighet|metode)/i,
  /Markus'? (metode|metoder|teknikker|filosofi)/i,
  /\b\d+ ?års? erfaring/i,
  /erfarne terapeuter/i,
  /tilknyttet klinikken i minst/i,
  /dyktige terapeuter/i,
  /eliteidrett|verdensrekord|mesterskap|Tour de France|landslag|olymp/i,
  /\bNRK\b/,
  /kundehistorie|det kundene sier|what our clients say|patient stories/i,
  /varig(e)? resultat|lasting results|kroppen tilbake|your body back/i,
  /raffinert gjennom/i,
  /grundig kartlegging/i,
  /daglig leder|markedssjef|leder for produktutvikling|trainee-koordinator/i,
  /finne årsaken, ikke bare/i,
];

const funn = [];
function gaa(dir) {
  for (const navn of readdirSync(dir)) {
    if (HOPP_OVER.has(navn)) continue;
    const sti = join(dir, navn);
    if (statSync(sti).isDirectory()) { gaa(sti); continue; }
    if (!TEKST.has(extname(sti))) continue;
    if (UNNTAK.some((u) => sti === u || sti.endsWith(sep + u) || navn === u)) continue;
    readFileSync(sti, 'utf8').split('\n').forEach((linje, i) => {
      // Samme grep som verify-lekkasje: escapene i JSON og SQL
      // («\n14 års erfaring») blir mellomrom, og alle treff telles.
      const l = linje.replace(/\\[nrt"']/g, '  ');
      for (const re of MOENSTRE) {
        for (const m of l.matchAll(new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g'))) {
          funn.push(`${sti}:${i + 1}  ${m[0]}`);
        }
      }
    });
  }
}
// Uten argument: repoet. Med en katalog: den, f.eks. en eksport av databasen.
gaa(process.argv[2] || '.');

if (funn.length) {
  console.log(`${funn.length} treff:`);
  for (const f of funn) console.log('  ' + f);
  process.exit(1);
}
console.log('ingen arvet markedsfoeringstekst');
