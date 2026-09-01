-- ============================================================
-- 0071 — Behandlingskatalogen merkes som en del av demoen
-- ------------------------------------------------------------
-- Funnet i sluttkontrollen før lansering:
--
--   select count(*) from services where is_demo_seed;        -- 0 av 4
--   select count(*) from staff_services where is_demo_seed;  -- 0 av 36
--
-- Migrasjon 0066 merket alt som lå der da den kjørte. Migrasjon 0068
-- byttet ut hele behandlingskatalogen etterpå, og demo_guard() tvinger
-- is_demo_seed til false på INSERT. De nye radene kom derfor inn
-- umerket, og ingen senere migrasjon rettet det opp.
--
-- To ting fulgte av det:
--
--   1. En besøkende kunne endre og slette klinikkens behandlinger for
--      alle andre. Sperren var aldri på.
--   2. Verre: demo_reset() sletter «det de besøkende har laget» med
--      «delete from services where not is_demo_seed». Med null merkede
--      rader ville den nattlige jobben tømt hele katalogen, og demoen
--      hadde våknet uten en eneste behandling å bestille.
--
-- Denne filen gjør to ting: merker katalogen slik den skulle vært
-- merket, og setter et sikkerhetsnett i nullstillingen slik at samme
-- feil aldri kan tømme en katalog igjen.
--
-- Idempotent. Avhenger av 0066 (kolonnen og vaktposten).
-- ============================================================

begin;


-- ============================================================
-- (a) Merk katalogen
-- ------------------------------------------------------------
-- Triggeren må av først. demo_guard() tvinger is_demo_seed til false
-- på UPDATE, så en oppdatering med triggeren på ville ikke ha satt
-- noe som helst. Samme rekkefølge som i 0066.
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array['services', 'staff_services', 'staff_members'] loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;

    execute format('drop trigger if exists demo_guard_trg on public.%I', t);

    execute format(
      'update public.%I set is_demo_seed = true where is_demo_seed = false', t);

    execute format(
      'create trigger demo_guard_trg before insert or update or delete '
      'on public.%I for each row execute function public.demo_guard()', t);
  end loop;
end $$;


-- ============================================================
-- (b) Sikkerhetsnett i nullstillingen
-- ------------------------------------------------------------
-- Katalogtabellene er de eneste der en tom tabell ødelegger demoen:
-- uten behandlinger finnes det ingenting å bestille, og uten
-- behandlere finnes det ingen å bestille hos. De andre tabellene
-- fylles opp igjen av demo_seed() rett etterpå.
--
-- Derfor: en katalogtabell tømmes bare hvis det finnes minst én
-- merket rad å beholde. Er det ingen, står radene igjen. Det verste
-- som da skjer er at en besøkendes egen behandling overlever natta,
-- i stedet for at demoen mister katalogen sin.
-- ============================================================
create or replace function public.demo_reset()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t text;
begin
  -- Besøkendes rader, barn først.
  delete from public.journal_entries    where not is_demo_seed;
  delete from public.exercise_documents where not is_demo_seed;
  delete from public.bookings           where not is_demo_seed;
  delete from public.waitlist           where not is_demo_seed;
  delete from public.reviews            where not is_demo_seed;
  delete from public.contact_messages   where not is_demo_seed;
  delete from public.blocked_slots      where not is_demo_seed;
  delete from public.holidays           where not is_demo_seed;
  delete from public.special_open_days  where not is_demo_seed;

  -- Katalogendringer en besøkende har rukket å legge til. Barn før
  -- foreldre, og bare når det finnes en merket rad igjen å beholde.
  foreach t in array array['staff_services', 'services', 'staff_members'] loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;

    execute format(
      'delete from public.%I where not is_demo_seed '
      'and exists (select 1 from public.%I where is_demo_seed)', t, t);
  end loop;

  -- Driftslogger. Ingen av dem har seed-rader, og en audit-logg som
  -- vokser i det uendelige er ikke til nytte for noen i en demo.
  foreach t in array array[
    'audit_log', 'journal_audit', 'anon_insert_events',
    'document_sends', 'push_subscriptions'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('delete from public.%I', t);
    end if;
  end loop;

  -- Og opp igjen, med dagens dato som utgangspunkt.
  perform public.demo_seed();
end $$;

comment on function public.demo_reset() is
  'Sletter besøkendes rader og driftslogger, og kaller demo_seed() på '
  'nytt. Katalogtabellene tømmes bare når det finnes minst én merket '
  'rad igjen, så en manglende merking ikke kan etterlate demoen uten '
  'behandlinger. Kjøres nattlig av pg_cron-jobben «demo-nightly-reset». '
  'Migrasjon 0067, sikkerhetsnett i 0071.';

revoke all on function public.demo_reset() from public, anon, authenticated;
grant execute on function public.demo_reset() to service_role;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Katalogen er merket:
--      select 'services' as tabell, count(*) filter (where is_demo_seed) as merket,
--             count(*) as sum from public.services
--      union all
--      select 'staff_services', count(*) filter (where is_demo_seed), count(*)
--        from public.staff_services
--      union all
--      select 'staff_members', count(*) filter (where is_demo_seed), count(*)
--        from public.staff_members;
--    -- Forvent: merket = sum for alle tre.
--
-- B) Sperren biter på katalogen — kjør som authenticated, ikke som
--    postgres i SQL-editoren:
--      update public.services set name = 'Test' where slug = 'oppfolging';
--    -- Forvent: ERROR ... demo_readonly
--
-- C) Nullstillingen beholder katalogen:
--      select count(*) from public.services;   -- noter tallet
--      select public.demo_reset();
--      select count(*) from public.services;   -- samme tall
-- ============================================================
