/* ============================================================
   Westengen Klinikk — backend-konfigurasjon
   ------------------------------------------------------------
   Demoen har ingen database. shared/demo-backend.js lastes foer
   denne fila og svarer paa alle kall til adressen under, med data
   som ligger i den besoekendes egen nettleser (localStorage).

   demo.invalid er et reservert toppdomene (RFC 2606) og kan aldri
   peke paa en ekte server. Noekkelen er bare en ikke-tom streng,
   fordi sidene sjekker at begge feltene er fylt ut.

   SLIK KOBLER DU EN KOPI TIL EN EKTE DATABASE
   1. Opprett et nytt, tomt Supabase-prosjekt (EU-region).
   2. Kjoer migrasjonene i supabase/migrations/ i nummerrekkefoelge.
      Se DEMO_SETUP.md.
   3. Bytt ut shared/demo-seed.js og shared/demo-backend.js med
      supabase-js fra CDN-en paa sidene som laster dem.
   4. Lim inn prosjektets URL og anon-noekkel under.
   ============================================================ */

window.WestengenKlinikkBackend = {
  supabaseUrl: 'https://demo.invalid',
  supabaseAnonKey: 'demo'
};

// Kanoniske kontaktopplysninger for klinikken.
// ALLE ER PLASSHOLDERE. Nummeret er ikke i bruk, og .example er et
// toppdomene som per RFC 2606 aldri kan registreres — e-posten kan
// altså ikke havne hos en tilfeldig tredjepart.
//
// Sentralisert her fordi flere JS-konsumenter leser samme verdi:
// booking-engine sin feil-fallback, chatbot-prompten og feilmeldingen
// i components.js. Statisk HTML i index/bestilling/kontakt/vilkar har
// fortsatt hardkodede strenger — ved endring, grep etter den gamle.

window.WestengenKlinikkConfig = {
  CLINIC_PHONE: '+47 400 00 000',
  CLINIC_EMAIL: 'post@westengenklinikk.example'
};