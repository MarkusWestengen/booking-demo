-- ============================================================
-- 0075 — det gamle prosjektnavnet i to e-postfunksjoner til
-- ------------------------------------------------------------
-- Punkt 4 i sluttkontrollen av 0074 var å bekrefte at ingen ANDRE
-- funksjoner i public har det gamle navnet. Bekreftelsen slo feil:
--
--   send_contact_message_email    «ERIKS&nbsp;ARENA» i e-posthodet
--   send_document_email           «ERIKS&nbsp;ARENA» i e-posthodet
--
-- Samme defekt som i send_booking_email, samme flate: tekst som går
-- ut til folk. send_document_email sender til new.customer_email,
-- altså til kunden selv.
--
-- Ingen av de to bygger lenker, så ingen av dem har base_url.
-- Treffet på «westengenklinikk.example» i send_contact_message_email
-- er notify_to = 'post@westengenklinikk.example', den oppdiktede
-- klinikkens egen adresse. Den er riktig og røres ikke.
--
-- Samme metode som 0074: definisjonen leses ut av katalogen, endres
-- i minnet, og kjøres tilbake. Ingen funksjonskropp er skrevet for
-- hånd, og ingenting annet i kroppene er rørt.
--
-- Kopi av begge før endringen ligger nederst i
-- docs/db-funksjoner-før-0074.sql.
--
-- Idempotent.
-- ============================================================

begin;

do $do$
declare
  def   text;
  ny    text;
  n     int := 0;
  GAMMELT_NAVN constant text := 'ERIKS&nbsp;ARENA';
  NYTT_NAVN    constant text := 'WESTENGEN&nbsp;KLINIKK';
begin
  for def in
    select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('send_contact_message_email', 'send_document_email')
     order by p.proname
  loop
    ny := replace(def, GAMMELT_NAVN, NYTT_NAVN);
    if ny <> def then
      execute ny;
      n := n + 1;
    end if;
  end loop;

  raise notice '0075: % funksjon(er) endret', n;

  -- Vaktsjekken må holde seg til de to funksjonene. Første forsøk
  -- spurte hele public, og pg_get_functiondef() feiler på aggregater
  -- (SQLSTATE 42809, «array_agg is an aggregate function»).
  -- prokind = 'f' holder også aggregater og prosedyrer utenfor.
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n2 on n2.oid = p.pronamespace
     where n2.nspname = 'public'
       and p.prokind = 'f'
       and p.proname in ('send_contact_message_email', 'send_document_email')
       and position(GAMMELT_NAVN in pg_get_functiondef(p.oid)) > 0
  ) then
    raise exception '0075: det gamle navnet står igjen i minst én funksjon';
  end if;
end
$do$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Ingen funksjon i public har det gamle navnet:
--      select proname from pg_proc p
--        join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public' and p.prokind = 'f'
--         and prosrc ilike '%eriks%';
--    -- Forvent: null rader.
--
-- B) Eier, security og search_path er uendret på begge:
--      select proname, prosecdef, pg_get_userbyid(proowner) as eier, proconfig
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and proname in ('send_contact_message_email', 'send_document_email');
-- ============================================================
