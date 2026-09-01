-- ============================================================
-- Westengen Klinikk — Markus «videre behandling» kr 4 000 → kr 3 000
-- Migration 0044
-- ------------------------------------------------------------
-- Markus Westengen skal IKKE lenger ha flat pris. Prisene splittes
-- igjen slik at videre behandling er rimeligere enn førstegangs-
-- konsultasjonen:
--   markus-konsult → 4000  (UENDRET — førstegangskonsultasjon)
--   markus-videre  → 3000  (ned fra 4000, satt av 0030)
-- Dette reverserer effekten av migrasjon 0030 (som satte markus-videre
-- 3000 → 4000 for «flat pris»). Terapeut-prisene (ter-konsult 2000,
-- ter-videre 1500) er IKKE berørt.
--
-- Prisen er DB-autoritativ: bestilling.html leser services.price_nok
-- via staff_services og lagrer den i bookings.price ved INSERT. Når
-- denne migrasjonen er kjørt vises og lagres kr 3 000 for Markus «videre
-- behandling» automatisk. Marketing-copy (i18n ×6, index/bestilling/
-- vilkar, chatbot i components.js) er oppdatert i samme PR.
--
-- ⚠️ MERK om drift: admin kan ha endret prisen via tjenester.html.
-- DIAGNOSE-blokken under skriver ut nåværende pris FØR mutation slik
-- at du ser utgangspunktet. UPDATE-en setter uansett markus-videre =
-- 3000 (idempotent — trygt å kjøre flere ganger).
--
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." + NOTICE-linjene = OK.
-- ============================================================

begin;

-- ----- DIAGNOSE (read-only, FØR mutation) ---------------------
-- Skriver ut nåværende Markus-priser som NOTICE. Ingen endring her.
do $$
declare
  r record;
begin
  raise notice 'Markus-priser FØR 0044:';
  for r in
    select slug, name, price_nok
      from public.services
     where slug in ('markus-konsult', 'markus-videre')
     order by slug
  loop
    raise notice '  % (%) = kr %', r.slug, r.name, r.price_nok;
  end loop;
end $$;

-- ----- MUTATION -----------------------------------------------
-- Sett videre behandling med Markus ned til kr 3 000.
-- Bruker slug (stabil nøkkel) — ikke uuid eller navn.
update public.services
   set price_nok = 3000
 where slug = 'markus-videre'
   and price_nok <> 3000;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--   select slug, name, price_nok, is_active
--     from public.services
--    where slug like 'tom-%'
--    order by sort_order;
-- Forvent: markus-konsult = 4000 OG markus-videre = 3000.
--
-- Ende-til-ende (anbefalt): åpne bestilling.html, velg Markus →
-- "Konsultasjon" skal vise kr 4 000 og "Videre behandling" kr 3 000,
-- og en testbooking på videre behandling skal lagre bookings.price = 3000.
-- ============================================================
