-- ============================================================
-- 0074 — base_url og gammelt prosjektnavn i e-postfunksjonene
-- ------------------------------------------------------------
-- To ting rettes, begge i tekst som går ut til kunder:
--
--   1. base_url pekte på https://demo.westengenklinikk.example.
--      Samme døde plassholderdomene som sto i CORS-allowlisten og
--      gjorde at kontaktskjemaet aldri kunne virke. Hver
--      avbestillingslenke i hver bekreftelse, og hver lenke i hver
--      anmeldelses-e-post, pekte ingen steder.
--
--   2. send_booking_email hadde «ERIKS&nbsp;ARENA» i e-posthodet.
--      Det er navnet på et tidligere kundeprosjekt, og skal ikke stå
--      i e-post fra en offentlig arbeidsprøve. Migrasjon 0072 fjernet
--      de arkiverte tjenestene med samme navn; dette var siste stedet
--      det overlevde.
--
-- ------------------------------------------------------------
-- HVORFOR DENNE FILA IKKE INNEHOLDER FUNKSJONSKROPPENE
-- ------------------------------------------------------------
-- Migrasjonene 0026, 0028, 0039, 0040 og 0048 står som applisert,
-- men kan ikke ha kjørt slik de står i git: linja
--
--     ||   '<div style="...">MARKUS'&nbsp;ARENA</div>'
--
-- har en uescapet apostrof, og `supabase db push` avviser nøyaktig
-- de bytene med SQLSTATE 42601. Repoet er derfor ikke en tro kopi av
-- databasen for disse funksjonene.
--
-- Det ble bekreftet ved uttak: git sier «MARKUS'&nbsp;ARENA»,
-- produksjon sier «ERIKS&nbsp;ARENA». Kroppen som kjører er eldre enn
-- den i git, fra før navnebyttet Erik til Markus.
--
-- Derfor skrives ingen CREATE OR REPLACE FUNCTION her. Definisjonen
-- leses ut av katalogen, endres i minnet, og kjøres tilbake. Da er
-- det som kjører fasit, og alt annet i kroppene står urørt: tekst,
-- farger, logikk, og verdier operatøren har satt for hånd.
--
-- En kopi av kroppene før endringen ligger i
-- docs/db-funksjoner-før-0074.sql.
--
-- ------------------------------------------------------------
-- URØRT MED VILJE
-- ------------------------------------------------------------
--   resend_key  står fortsatt som 'REDACTED_RESEND_KEY'. En ekte
--               nøkkel skal ikke i git, og settes i SQL-editoren.
--   notify_to   i send_booking_email er en ekte privat e-postadresse.
--               Den er operatørens eget valg og røres ikke her.
--
-- ------------------------------------------------------------
-- Ytre blokk bruker taggen $do$. Kroppene bruker kun $function$ og
-- inneholder verken $do$ eller bart $$, så det kan ikke kollidere.
--
-- Idempotent: kjøres den om igjen, finner replace() ingenting å bytte,
-- og tellerne under er null. Da hopper den over uten å feile.
-- ============================================================

begin;

do $do$
declare
  def        text;
  ny         text;
  n_url      int := 0;
  n_navn     int := 0;
  n_rort     int := 0;
  GAMMEL_URL constant text := 'https://demo.westengenklinikk.example';
  NY_URL     constant text := 'https://booking-demo-rosy.vercel.app';
  GAMMELT_NAVN constant text := 'ERIKS&nbsp;ARENA';
  NYTT_NAVN    constant text := 'WESTENGEN&nbsp;KLINIKK';
begin
  for def in
    select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('send_booking_email', 'process_pending_review_emails')
     order by p.proname
  loop
    ny := def;

    if position(GAMMEL_URL in ny) > 0 then
      n_url := n_url + 1;
      ny := replace(ny, GAMMEL_URL, NY_URL);
    end if;

    if position(GAMMELT_NAVN in ny) > 0 then
      n_navn := n_navn + 1;
      ny := replace(ny, GAMMELT_NAVN, NYTT_NAVN);
    end if;

    if ny <> def then
      execute ny;
      n_rort := n_rort + 1;
    end if;
  end loop;

  raise notice '0074: % funksjon(er) endret, % med gammel base_url, % med gammelt navn',
    n_rort, n_url, n_navn;

  -- Sikkerhetsnett mot en stille no-op: har noen av strengene
  -- overlevd, har erstatningen ikke truffet, og da skal migrasjonen
  -- si fra i stedet for å se ut som den lyktes.
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('send_booking_email', 'process_pending_review_emails')
       and (position(GAMMEL_URL   in pg_get_functiondef(p.oid)) > 0
         or position(GAMMELT_NAVN in pg_get_functiondef(p.oid)) > 0)
  ) then
    raise exception '0074: en av strengene står igjen etter erstatning';
  end if;
end
$do$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Ingen av funksjonene har de gamle strengene:
--      select proname,
--             position('demo.westengenklinikk.example' in prosrc) > 0 as har_dodt_domene,
--             position('ERIKS'                         in prosrc) > 0 as har_gammelt_navn
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and proname in ('send_booking_email', 'process_pending_review_emails');
--    -- Forvent: false, false for begge.
--
-- B) Eier, security og search_path er uendret:
--      select proname, prosecdef, pg_get_userbyid(proowner) as eier, proconfig
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and proname in ('send_booking_email', 'process_pending_review_emails');
--    -- Forvent: postgres, true, {search_path=public, extensions}.
--
-- C) Ingen andre funksjoner i public har spor av noe av det:
--      select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and (prosrc ilike '%westengenklinikk.example%' or prosrc ilike '%eriks%');
--    -- Forvent: null rader.
-- ============================================================
