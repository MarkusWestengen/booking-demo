-- ============================================================
-- Westengen Klinikk — Erik: flat pris kr 4 000
-- Migration 0030
-- ------------------------------------------------------------
-- Erik Westengen skal koste kr 4 000 UANSETT om timen er en
-- førstegangskonsultasjon eller videre behandling. Seed (0008) ga:
--   erik-konsult → 4000  (allerede riktig)
--   erik-videre  → 3000  (skal opp til 4000)
-- Terapeut-prisene (ter-konsult 2000, ter-videre 1500) er IKKE berørt.
--
-- Prisen er DB-autoritativ: bestilling.html leser services.price_nok
-- via staff_services og lagrer den i bookings.price ved INSERT. Når
-- denne migrasjonen er kjørt vises og lagres kr 4 000 for begge Erik-
-- tjenestene automatisk — ingen frontend-deploy nødvendig for tallet
-- (marketing-copy er separat oppdatert i samme PR).
--
-- ⚠️ MERK om drift: admin kan ha endret prisen via tjenester.html
-- siden 0008-seed. DIAGNOSE-blokken under skriver ut nåværende
-- pris FØR mutation slik at du ser utgangspunktet. UPDATE-en setter
-- uansett erik-videre = 4000 (idempotent — trygt å kjøre flere ganger).
--
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." + NOTICE-linjene = OK.
-- ============================================================

begin;

-- ----- DIAGNOSE (read-only, FØR mutation) ---------------------
-- Skriver ut nåværende Erik-priser som NOTICE. Ingen endring her.
do $$
declare
  r record;
begin
  raise notice 'Erik-priser FØR 0030:';
  for r in
    select slug, name, price_nok
      from public.services
     where slug in ('erik-konsult', 'erik-videre')
     order by slug
  loop
    raise notice '  % (%) = kr %', r.slug, r.name, r.price_nok;
  end loop;
end $$;

-- ----- MUTATION -----------------------------------------------
-- Sett videre behandling med Erik til samme pris som konsultasjon.
-- Bruker slug (stabil nøkkel) — ikke uuid eller navn.
update public.services
   set price_nok = 4000
 where slug = 'erik-videre'
   and price_nok <> 4000;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--   select slug, name, price_nok, is_active
--     from public.services
--    where slug like 'tom-%'
--    order by sort_order;
-- Forvent: erik-konsult = 4000 OG erik-videre = 4000.
--
-- Ende-til-ende (anbefalt): åpne bestilling.html, velg Erik →
-- både "Konsultasjon" og "Videre behandling" skal vise kr 4 000,
-- og en testbooking skal lagre bookings.price = 4000.
-- ============================================================
