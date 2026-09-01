-- ============================================================
-- 0072 — Den gamle behandlingskatalogen ryddes bort
-- ------------------------------------------------------------
-- Migrasjon 0068 byttet katalogen og deaktiverte den gamle i stedet
-- for å slette den, fordi bookinger lagrer service_id og fortsatt
-- skulle kunne vises. Det var riktig da. Nå er det ikke det lenger:
--
--   select service_id, count(*) from public.bookings group by 1;
--   -- ingen peker på de gamle radene
--
-- demo_seed() bygger alle bookingene på nytt fra den nye katalogen
-- hver natt, så koblingen kan ikke oppstå igjen heller.
--
-- Det som blir igjen er fire arkiverte rader som bare admin ser, med
-- navn fra en tidligere versjon av demoen: «Konsultasjon (Erik)» og
-- «Videre behandling (Erik)». Navnet Erik finnes ikke andre steder i
-- prosjektet lenger. Sammen med dem ligger 18 koblingsrader i
-- staff_services som ikke peker på noe man kan bestille.
--
-- Sidenotat til den som leser 0068: UPDATE-en der traff på
-- 'markus-konsult' og 'markus-videre', men radene het 'erik-konsult'
-- og 'erik-videre'. De to ble deaktivert av noe annet. Filen er
-- allerede kjørt og røres ikke; det står her fordi det forklarer
-- hvorfor opprydningen ikke skjedde av seg selv.
--
-- Sletter ingenting hvis en booking fortsatt peker hit.
-- Idempotent.
-- ============================================================

begin;

do $$
declare
  gamle_slugs text[] := array['erik-konsult', 'erik-videre',
                              'ter-konsult', 'ter-videre'];
  gamle_ider  uuid[];
  brukt       int;
  n_kobling   int;
  n_tjeneste  int;
begin
  select array_agg(id) into gamle_ider
    from public.services
   where slug = any(gamle_slugs);

  if gamle_ider is null then
    raise notice '0072: ingen gamle katalograder igjen, ingenting aa gjoere.';
    return;
  end if;

  -- bookings.service_id er tekst og har holdt baade slug og uuid
  -- gjennom demoens levetid. Vi sjekker begge formene.
  select count(*) into brukt
    from public.bookings b
   where b.service_id = any(gamle_slugs)
      or b.service_id = any(select unnest(gamle_ider)::text);

  if brukt > 0 then
    raise notice '0072: % booking(er) peker fortsatt paa den gamle katalogen. Beholder radene.', brukt;
    return;
  end if;

  delete from public.staff_services where service_id = any(gamle_ider);
  get diagnostics n_kobling = row_count;

  delete from public.services where id = any(gamle_ider);
  get diagnostics n_tjeneste = row_count;

  raise notice '0072: slettet % tjeneste(r) og % kobling(er).', n_tjeneste, n_kobling;
end $$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Bare de fire behandlingene som tilbys:
--      select slug, name, is_active, is_demo_seed
--        from public.services order by sort_order;
--    -- Forvent: fire rader, alle is_active = true, alle merket.
--
-- B) Ingen koblinger uten behandling:
--      select count(*) from public.staff_services ss
--       where not exists (select 1 from public.services s where s.id = ss.service_id);
--    -- Forvent: 0
--
-- C) Ingen spor av det gamle navnet:
--      select count(*) from public.services where name ilike '%erik%';
--    -- Forvent: 0
-- ============================================================
