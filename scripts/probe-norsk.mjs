// Laster hver side paa engelsk i en ekte nettleser og melder fra om norsk
// tekst som staar igjen.
//
// Kjoer mot en lokal server eller live:
//   node scripts/probe-norsk.mjs                       (http://localhost:8790)
//   BASE=https://booking-demo-rosy.vercel.app node scripts/probe-norsk.mjs
//   node scripts/probe-norsk.mjs kalender.html tjenester.html
//
// Som terapeut (standard er administrator, som auto-innloggingen gir):
//   ROLLE=terapeut node scripts/probe-norsk.mjs
// Proben logger inn med rollens konto foer adminsidene, og sjekker paa
// hver adminside at det er den kontoen sesjonen faktisk tilhoerer.
//
// Beviset for at proben virker:
//   PLANT=1 node scripts/probe-norsk.mjs index.html
// legger en norsk setning inn i hver side etter at den er oversatt. Proben
// skal da feile, og treffet skal staa i lista.
//
// Krever Playwright. Repoet har ingen package.json med vilje (Vercel ville
// da installert den ved hver utrulling), saa modulen hentes fra
// PLAYWRIGHT_MODULE hvis den ikke finnes i vanlig oppslag:
//   PLAYWRIGHT_MODULE=C:/sti/node_modules/playwright/index.mjs
//
// Hva proben ser: alle tekstnoder i <body>, ogsaa skjulte (dialoger og
// menyer som ikke er aapnet), pluss placeholder, title, aria-label, alt,
// knappers value og <title>. Tekst fra brukere (meldinger, notater,
// anmeldelser) og tekniske id-er staar under translate="no", og telles for
// seg, ikke som feil. Personnavn kjennes igjen paa formen, se NAVN.
//
// Norsk kjennes igjen paa to maater: bokstavene æ, ø, å, eller et ord fra
// en liste over norske ord som ikke ogsaa er vanlige engelske ord. «for»,
// «time» og «man» staar derfor ikke paa lista.

const BASE = (process.env.BASE || 'http://localhost:8790').replace(/\/$/, '');
const PLANT = process.env.PLANT === '1';
const ROLLE = process.env.ROLLE || 'admin';
const KONTO = { admin: 'admin@westengenklinikk.example', terapeut: 'terapeut@westengenklinikk.example' }[ROLLE];
if (!KONTO) { console.error('ROLLE maa vaere admin eller terapeut'); process.exit(2); }
const PLANTET = 'Timen din er bekreftet og lagret';

async function lastPlaywright() {
  try { return await import('playwright'); } catch (_) {}
  if (process.env.PLAYWRIGHT_MODULE) {
    const url = new URL('file:///' + process.env.PLAYWRIGHT_MODULE.replace(/\\/g, '/').replace(/^\/+/, ''));
    return await import(url.href);
  }
  console.error('Fant ikke Playwright. Sett PLAYWRIGHT_MODULE, se toppen av fila.');
  process.exit(2);
}

const OFFENTLIGE = ['index.html', 'bestilling.html', 'avbestill.html', 'venteliste.html',
  'kontakt.html', 'anmeldelser.html', 'personvern.html', 'vilkar.html'];
const ADMIN = ['kalender.html', 'booking-admin.html', 'kunder.html', 'kunde-detalj.html',
  'tjenester.html', 'behandlere.html', 'meldinger.html', 'dokumenter.html',
  'stengte-tider.html', 'audit-logg.html', 'innstillinger.html', 'set-password.html', 'ansatt.html'];

const NORSKE_ORD = `og ikke eller med av på er som det dette disse deg din ditt dine du vi jeg meg oss
har kan skal må vil ville kunne ingen ingenting alle hvor hva når hvem hvordan hvorfor fra etter før
uten mer mye noe noen bare også nå ny nytt nye ja nei lukk lagre lagret slett slette endre avbryt
tilbake neste forrige uke uker dag dager måned kunde kunder kunden behandler behandlere behandleren
tjeneste tjenester tjenesten melding meldinger meldingen innstillinger stengt stengte tider tid søk
velg legg bestill bestilling bestillinger bestilt avbestill avbestilt avbestilling venteliste
ventelista ventelisten logg innlogget kalender oversikt pris priser varighet minutter telefon navn
beskrivelse aktiv aktive inaktiv skjult synlig rolle terapeut terapeuter samtykke morgen mandag
tirsdag onsdag torsdag fredag lørdag søndag januar februar mars mai juni juli oktober desember kr
ledig ledige opptatt klinikken timen timene hjem meny vis skjul laster sendt svar ulest arkiv
dokument dokumenter notat notater slik der denne hei takk vennligst feil bekreft bekreftet ventende
kommende tidligere totalt antall inntekt år gjennomført fullført utført trinn dato klokken
oppdiktet oppdiktede demoen fiktive velkommen skriv spørsmål hjelp innboks innboksen legg til
ukens dagens neste ingen treff sortering alle behandling behandlinger merknad merknader
e-post epost adresse sted besøk henvendelse registrert opprettet endret slettet åpne åpen stengt
sist blokkering blokkeringer bookinger`;
const ORDSETT = new Set(NORSKE_ORD.split(/\s+/).filter(Boolean));

// Merkenavn og spraakvalget selv. «Norsk» skal staa i spraakmenyen ogsaa
// paa engelsk; det er navnet paa valget, ikke en oversettelse som mangler.
const TILLATT = [/Westengen\s+Klinikk/gi, /\bKlinikk\b/g, /^Norsk$/];

// Personnavn: to eller flere ord med stor forbokstav etter hverandre,
// der ingen av ordene staar paa ordlista («Thea Molvær», «Terje Østby»).
// Kundenavn er brukertekst og skal ikke oversettes, men de vises paa
// for mange steder til at hvert enkelt kan merkes. Et norsk uttrykk med
// to store forbokstaver paa rad er sjeldent i et grensesnitt som ellers
// bruker vanlig setningsstil.
// \b kjenner bare ASCII-bokstaver og feiler foran «Ø», derfor lookaround.
const NAVN = /(?<!\p{L})[A-ZÆØÅ][a-zæøå]+(?:[ -][A-ZÆØÅ][a-zæøå]+)+(?!\p{L})/gu;
let navnHoppet = 0;

function erNorsk(tekst) {
  let s = tekst;
  for (const re of TILLATT) s = s.replace(re, ' ');
  s = s.replace(NAVN, (m) => {
    if (m.split(/[ -]/).some((o) => ORDSETT.has(o.toLowerCase()))) return m;
    if (/[æøåÆØÅ]/.test(m)) navnHoppet++;
    return ' ';
  });
  if (!s.trim()) return null;
  if (/[æøåÆØÅ]/.test(s)) return s.match(/[\p{L}]*[æøåÆØÅ][\p{L}]*/u)[0];
  for (const ord of s.toLowerCase().match(/[\p{L}-]+/gu) || []) {
    if (ORDSETT.has(ord)) return ord;
  }
  return null;
}

// Kjoeres i siden. Samler tekst med en kort sti saa treffet kan finnes igjen.
function samleTekst() {
  const ut = [];
  // TEXTAREA: innholdet er feltets verdi, altså data som redigeres, ikke
  // grensesnitt. En tjenestebeskrivelse som står på norsk i basen skal
  // stå på norsk når den redigeres, også i et engelsk panel.
  const HOPP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'TEXTAREA', 'svg', 'SVG']);
  function sti(el) {
    const deler = [];
    for (let n = el; n && n.nodeType === 1 && deler.length < 4; n = n.parentElement) {
      let d = n.tagName.toLowerCase();
      if (n.id) { d += '#' + n.id; deler.unshift(d); break; }
      if (n.classList.length) d += '.' + [...n.classList].slice(0, 2).join('.');
      deler.unshift(d);
    }
    return deler.join(' > ');
  }
  function brukertekst(el) { return !!(el && el.closest && el.closest('[translate="no"]')); }
  const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
    acceptNode(n) {
      for (let p = n.parentElement; p; p = p.parentElement) if (HOPP.has(p.tagName)) return NodeFilter.FILTER_REJECT;
      return n.nodeValue.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
    }
  });
  for (let n; (n = w.nextNode());) {
    const el = n.parentElement;
    ut.push({ tekst: n.nodeValue.trim().replace(/\s+/g, ' '), sti: sti(el), bruker: brukertekst(el) });
  }
  for (const el of document.body.querySelectorAll('[placeholder],[title],[aria-label],[alt],input[type=button],input[type=submit]')) {
    for (const a of ['placeholder', 'title', 'aria-label', 'alt', 'value']) {
      if (a === 'value' && !/^(button|submit)$/.test(el.type)) continue;
      const v = el.getAttribute(a);
      if (v && v.trim()) ut.push({ tekst: v.trim(), sti: sti(el) + ' @' + a, bruker: brukertekst(el) });
    }
  }
  ut.push({ tekst: document.title, sti: 'title', bruker: false });
  // Merkenavnet skal ikke oversettes. Ordet «Klinikk» står på lista over
  // tillatt tekst, så en oversettelse av det ville ellers gått rett forbi.
  for (const el of document.querySelectorAll('.brand-wordmark > span, .brand')) {
    const tx = el.textContent.replace(/\s+/g, ' ').trim();
    if (/clinic/i.test(tx)) ut.push({ tekst: 'MERKENAVN OVERSATT: ' + tx, sti: sti(el), bruker: false, merke: true });
  }
  return ut;
}

const vent = (p, ms) => p.waitForTimeout(ms);

// Klikker det foerste synlige elementet som passer. Usynlige hoppes over,
// ellers blir en skjult mobilknapp eller en lukket meny staaende i veien.
async function klikk(page, sel, ms = 1500) {
  for (const e of await page.$$(sel)) {
    if (!(await e.isVisible())) continue;
    await e.click().catch(() => {});
    await vent(page, ms);
    return true;
  }
  return false;
}
async function lastPaaNytt(page, side) {
  await page.goto(BASE + '/' + side, { waitUntil: 'load' });
  await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
  await vent(page, 1500);
}

// Tilstander som bare finnes etter en handling. Hver funksjon faar siden og
// en callback som samler inn en gang til. Ingen av dem sender inn noe:
// proben skal ikke etterlate rader i databasen. Journalen aapnes heller
// ikke, fordi hvert oppslag skrives til loggen over oppslag.
const SCENARIER = {
  'avbestill.html': async (page, samle) => {
    if (await klikk(page, 'form button[type=submit]')) await samle('tomt skjema sendt');
  },
  'venteliste.html': async (page, samle) => {
    if (await klikk(page, 'form button[type=submit]')) await samle('tomt skjema sendt');
  },
  'index.html': async (page, samle) => {
    // Demomerket er skjult under 420 px; dialogen aapnes da fra koden.
    if (!(await klikk(page, '.wk-demo-badge', 600))) {
      await page.evaluate(() => window.WestengenKlinikkDemo && window.WestengenKlinikkDemo.open());
      await vent(page, 600);
    }
    await samle('demodialog');
    await page.keyboard.press('Escape');
    if (await klikk(page, '.lang-btn', 400)) await samle('spraakmeny');
  },
  'bestilling.html': async (page, samle) => {
    const trykk = async (sel) => { const e = await page.$(sel); if (!e) return false; await e.click(); await vent(page, 1800); return true; };
    await trykk('.tabf-staff-card'); await samle('trinn 2');
    await trykk('.tabf-service-card'); await samle('trinn 3');
    await trykk('.tabf-cal-cell.open'); await samle('trinn 4');
    await trykk('.tabf-time-slot:not(.unavailable)'); await samle('trinn 5');
    // Demoguiden: aapne, og trykk hvert hurtigsvar.
    await page.goto(BASE + '/bestilling.html', { waitUntil: 'networkidle' }); await vent(page, 1200);
    if (await trykk('[data-chat-toggle]')) {
      await samle('demoguide');
      const antall = (await page.$$('[data-quick] button')).length;
      for (let i = 0; i < antall - 1; i++) {
        const knapper = await page.$$('[data-quick] button');
        if (!knapper[i]) break;
        await knapper[i].click(); await vent(page, 1400);
      }
      await page.fill('[data-chat-input]', 'xyzzy'); await page.press('[data-chat-input]', 'Enter'); await vent(page, 1400);
      await page.fill('[data-chat-input]', 'xyzzy'); await page.press('[data-chat-input]', 'Enter'); await vent(page, 1400);
      await samle('demoguide etter svar');
    }
  },
};
const ADMIN_SCENARIER = {
  'kalender.html': async (page, samle) => {
    if (await klikk(page, '.b-card')) await samle('bookingdetaljer');
  },
  'booking-admin.html': async (page, samle, side) => {
    for (const tab of ['availability', 'waitlist', 'reviews', 'settings', 'bookings']) {
      if (await klikk(page, `.tab[data-tab="${tab}"]`)) await samle('fane ' + tab);
    }
    if (await klikk(page, '[data-detail]')) await samle('bookingdetaljer');
    await lastPaaNytt(page, side);
    if (await klikk(page, '#newBookingBtn', 2000)) {
      await samle('ny booking');
      if (await klikk(page, '.nb-item-service', 1500)) await samle('ny booking, trinn 2');
    }
  },
  'tjenester.html': async (page, samle, side) => {
    if (await klikk(page, '#addBtn')) await samle('ny tjeneste');
    await lastPaaNytt(page, side);
    if (await klikk(page, '[data-act="edit"]')) await samle('rediger tjeneste');
  },
  'behandlere.html': async (page, samle, side) => {
    if (await klikk(page, '#newBtn')) await samle('ny behandler');
    await lastPaaNytt(page, side);
    if (await klikk(page, '.edit-btn')) await samle('rediger behandler');
  },
  'dokumenter.html': async (page, samle) => {
    if (await klikk(page, '.send-btn')) await samle('send til kunde');
  },
  'kunder.html': async (page, samle) => {
    const kort = await page.$('.cust-card[data-url]');
    if (kort) {
      await page.goto(new URL(await kort.getAttribute('data-url'), BASE + '/').href, { waitUntil: 'load' });
      await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
      await vent(page, 2500);
      await samle('kundekort');
    }
  },
};
for (const side of ADMIN) {
  SCENARIER[side] = async (page, samle) => {
    if (ADMIN_SCENARIER[side]) {
      await ADMIN_SCENARIER[side](page, samle, side);
      await lastPaaNytt(page, side);
    }
    if (await klikk(page, '.wk-demo-badge', 600)) { await samle('demodialog'); await page.keyboard.press('Escape'); }
    if (await klikk(page, '.bn-menu-btn', 600)) await samle('mobilmeny');
  };
}

const { chromium } = await lastPlaywright();
const sider = process.argv.slice(2).length ? process.argv.slice(2) : [...OFFENTLIGE, ...ADMIN];
const bredde = +(process.env.W || 375);
// Ny, tom nettleserprofil hver gang. En gammel profil kan ha en service
// worker som serverer adminsidene fra cache, og da ser proben filer som
// ikke lenger finnes paa serveren.
const nettleser = await chromium.launch();
const ctx = await nettleser.newContext({
  viewport: { width: bredde, height: 812 }, isMobile: bredde < 800, hasTouch: bredde < 800,
  serviceWorkers: 'block',
});
await ctx.addInitScript(() => {
  try {
    localStorage.setItem('westengen-klinikk-lang', 'en');
    localStorage.setItem('tas-cookie-consent', JSON.stringify({ value: 'essential', ts: Date.now() }));
  } catch (_) {}
});

if (sider.some((s) => ADMIN.includes(s))) {
  const p = await ctx.newPage();
  await p.goto(`${BASE}/ansatt.html?auto=${ROLLE === 'terapeut' ? 'therapist' : 'admin'}&next=kalender.html`);
  await p.waitForURL('**/kalender.html', { timeout: 30000 }).catch(() => {});
  await p.close();
}

const funn = [];
const tilstander = {};
let brukerTreff = 0;
for (const side of sider) {
  const page = await ctx.newPage();
  const sett = new Set();
  const samle = async (tilstand) => {
    (tilstander[side] ||= []).push(tilstand);
    if (PLANT) {
      await page.evaluate((t) => {
        const d = document.createElement('div'); d.hidden = true; d.textContent = t; document.body.appendChild(d);
      }, PLANTET);
    }
    for (const r of await page.evaluate(samleTekst)) {
      const ord = r.merke ? 'merkenavn' : erNorsk(r.tekst);
      if (!ord) continue;
      const nokkel = r.sti + '|' + r.tekst;
      if (sett.has(nokkel)) continue;
      sett.add(nokkel);
      if (r.bruker) { brukerTreff++; continue; }
      funn.push({ side, tilstand, ord, tekst: r.tekst.slice(0, 120), sti: r.sti });
    }
  };
  try {
    await page.goto(BASE + '/' + side, { waitUntil: 'load', timeout: 45000 });
    // Kontaktsiden holder en forbindelse aapen for Turnstile, saa
    // «networkidle» kommer aldri der. Da holder det at siden er lastet.
    await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
  } catch (e) {
    funn.push({ side, tilstand: 'lasting', ord: '-', tekst: 'kunne ikke laste: ' + e.message.split('\n')[0], sti: '-' });
    await page.close();
    continue;
  }
  await vent(page, +(process.env.WAIT || 2500));
  if (ADMIN.includes(side) && side !== 'set-password.html' && side !== 'ansatt.html') {
    const epost = await page.evaluate(() => {
      for (const k of Object.keys(localStorage)) if (/^sb-.*-auth-token$/.test(k)) {
        try { return JSON.parse(localStorage.getItem(k)).user.email; } catch (_) {}
      }
      return null;
    });
    if (epost !== KONTO) funn.push({ side, tilstand: 'rolle', ord: '-', tekst: `innlogget som ${epost}, ikke ${KONTO}`, sti: '-' });
    const her = page.url().split('/').pop().split('?')[0];
    if (her !== side) (tilstander[side] ||= []).push('omdirigert til ' + her);
  }
  const lang = await page.evaluate(() => document.documentElement.lang);
  if (lang !== 'en') funn.push({ side, tilstand: 'lasting', ord: '-', tekst: `<html lang="${lang}">, ikke en`, sti: 'html' });
  await samle('lastet');
  if (SCENARIER[side]) await SCENARIER[side](page, samle);
  await page.close();
}
await ctx.close();
await nettleser.close();

// Hvilke tilstander proben faktisk kom til. Et scenario som ikke fant
// knappen sin, står ikke her, og da er siden bare sjekket delvis.
console.log('Tilstander sjekket:');
for (const [side, t] of Object.entries(tilstander)) console.log(`  ${side}: ${t.join(', ')}`);

const perSide = {};
for (const f of funn) (perSide[f.side] ||= []).push(f);
for (const [side, liste] of Object.entries(perSide)) {
  console.log(`\n${side}: ${liste.length}`);
  for (const f of liste) console.log(`  [${f.tilstand}] «${f.ord}»  ${f.tekst}\n      ${f.sti}`);
}
console.log(`\n${sider.length} sider som ${ROLLE}, ${funn.length} treff paa norsk tekst` +
  (brukerTreff ? `, ${brukerTreff} under translate="no" (ikke feil)` : '') +
  (navnHoppet ? `, ${navnHoppet} personnavn med æøå hoppet over` : '') + (PLANT ? '  [PLANT]' : ''));
if (PLANT) {
  const fanget = funn.filter((f) => f.tekst === PLANTET).length;
  console.log(fanget ? `plantet streng fanget paa ${fanget} tilstand(er)` : 'PLANTET STRENG IKKE FANGET');
}
process.exit(funn.length ? 1 : 0);
