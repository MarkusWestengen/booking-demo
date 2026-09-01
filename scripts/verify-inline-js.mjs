// Sjekker at hvert inline <script> i HTML-filene parser.
//
// HTML-kommentarer fjernes foerst: flere av sidene har kommentarer som
// omtaler script-tagger, og de ble ellers plukket opp som kode.
import { readFileSync, readdirSync } from 'node:fs';

const filer = readdirSync('.').filter(f => f.endsWith('.html'));
let feil = 0, blokker = 0;

for (const f of filer) {
  const uten = readFileSync(f, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
  const treff = [...uten.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/g)];
  for (const [i, m] of treff.entries()) {
    const kode = m[1];
    if (!kode.trim()) continue;
    blokker++;
    try {
      new Function(kode);
    } catch (e) {
      feil++;
      console.log(`${f}: script ${i}: ${e.message}`);
    }
  }
}

console.log(`${blokker} inline-blokker, ${feil} med feil`);
process.exit(feil ? 1 : 0);
