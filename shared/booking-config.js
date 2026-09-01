/* ============================================================
   Westengen Klinikk — backend-konfigurasjon
   ------------------------------------------------------------
   Demoen peker på sitt eget, tomme Supabase-prosjekt. Den skal
   ALDRI peke på en produksjonsdatabase: innloggingen til
   adminpanelet er publisert åpent på forsiden.

   Anon-nøkkelen er ment å være offentlig og beskyttes av RLS.
   Service role-nøkkelen skal aldri inn i frontend.

   SLIK KOBLER DU EN NY KOPI TIL SIN EGEN DATABASE
   1. Opprett et nytt, tomt Supabase-prosjekt (EU-region).
   2. Kjør migrasjonene i supabase/migrations/ i nummerrekkefølge.
      Se DEMO_SETUP.md.
   3. Project Settings → API → kopier «Project URL» og «anon public».
   4. Lim dem inn under.
   ============================================================ */

window.WestengenKlinikkBackend = {
  supabaseUrl: 'https://pfyidlnztpwjnpxpoheu.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBmeWlkbG56dHB3am5weHBvaGV1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyMjE0MTQsImV4cCI6MjEwMzc5NzQxNH0.quP4tfd9eiHvF11mJqn78HdGECgbOektXeQ-O9uoj6c'
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