/* ============================================================
   Westengen Klinikk — backend-konfigurasjon
   ------------------------------------------------------------
   ⚠  NØKLENE ER TOMME MED VILJE.

   Her lå tidligere URL og anon-nøkkel til den ekte klinikkens
   Supabase-prosjekt. De er fjernet. Demoen skal ALDRI peke på den
   databasen: innloggingen til adminpanelet er publisert åpent på
   forsiden, og med produksjonsnøkkelen her ville hvem som helst
   fått lese ekte pasientdata.

   SLIK KOBLER DU DEMOEN TIL SIN EGEN DATABASE
   1. Opprett et nytt, tomt Supabase-prosjekt (EU-region).
   2. Kjør migrasjonene i supabase/migrations/ i nummerrekkefølge,
      fra 0000 til 0067. Se DEMO_SETUP.md.
   3. Project Settings → API → kopier «Project URL» og «anon public».
   4. Lim dem inn under.

   MENS DE ER TOMME
   Bestillingsflyten faller tilbake til localStorage, så den kan
   klikkes gjennom, men bare i din egen nettleser. Adminpanelet
   trenger en ekte database og vil be deg logge inn uten å komme
   videre. Det er forventet oppførsel, ikke en feil.
   ============================================================ */
window.WestengenKlinikkBackend = {
  supabaseUrl: '',
  supabaseAnonKey: ''
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
