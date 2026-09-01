-- ============================================================
-- 0015_seed_new_staff.sql                            2026-05-15
-- ------------------------------------------------------------
-- Seeder staff_services for 5 nye terapeuter slik at hver av dem
-- får sin egen RLS-isolerte kalender via auth.jwt -> staff_id.
--
-- Bakgrunn: før denne migrasjonen hadde Westengen Klinikk to staff-grupper
-- i staff_services: 'markus' (Markus Westengen) og 'terapeut' (generisk
-- gruppe alle terapeuter logget seg inn under). Markus har nå bedt
-- om at hver terapeut får egen Auth-konto og styrer egen kalender.
--
-- De 5 nye staff_ids:
--   - sofie      (Sofie Aune)
--   - henrik     (Henrik Dal)
--   - jonas      (Jonas Riis)
--   - amina      (Amina Nour)
--   - petter     (Petter Holm)
--
-- Hver av dem kobles til de samme services som dagens 'terapeut'-
-- gruppe har (ter-konsult + ter-videre fra 0008). Pris-tier:
-- terapeut-priser (2000 kr konsultasjon / 1500 kr videre).
--
-- Hva som IKKE endres:
--   - 'markus' og 'terapeut' beholdes i staff_services for at gamle
--     bookinger og admin-UI fortsatt skal fungere uten endring.
--   - Eksisterende bookings.staff_id='terapeut'-rader røres ikke.
--   - Ingen staff-tabell opprettes (staff_id er fortsatt bare text;
--     se 0008 kommentar om fremtidig refactor).
--
-- Frontend-koblingen: shared/booking-engine.js STAFF-arrayen
-- utvides separat (kode-endring i samme commit som denne migrasjonen)
-- slik at hver av de 5 nye dukker opp som eget bookbart kort.
-- 'terapeut' merkes bookable:false i frontend så den ikke lenger
-- vises som kort i bestilling.html, men beholdes for at admin/
-- kalender-UI skal kunne slå opp staff-objektet for gamle bookinger.
--
-- Idempotent: insert .. on conflict do nothing.
-- ============================================================

-- Seed staff_services-koblinger for de 5 nye terapeutene.
-- Sub-select på services.id matcher på slug slik at vi ikke
-- trenger å vite UUID-verdiene.
--
-- Hver terapeut får ter-konsult (2000 kr) + ter-videre (1500 kr).
-- Hvis noen senere skal ha andre services (f.eks. egen pristier
-- eller spesial-behandlinger), legges det inn via tjenester.html
-- admin-UI eller en ny migrasjon.

insert into public.staff_services (staff_id, service_id)
select 'sofie', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

insert into public.staff_services (staff_id, service_id)
select 'henrik', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

insert into public.staff_services (staff_id, service_id)
select 'jonas', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

insert into public.staff_services (staff_id, service_id)
select 'amina', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

insert into public.staff_services (staff_id, service_id)
select 'petter', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

-- Pasientkoordinatoren tar ogsa imot pasienter, og trenger derfor
-- samme koblinger som resten av poolen.
insert into public.staff_services (staff_id, service_id)
select 'nora', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--
--   select staff_id, count(*) as service_count
--     from public.staff_services
--    group by staff_id
--    order by staff_id;
--
-- Forventet etter denne migrasjonen:
--   amina        | 2
--   markus         | 2   (uendret fra 0008)
--   henrik       | 2
--   jonas        | 2
--   nora         | 2
--   petter       | 2
--   sofie        | 2
--   terapeut     | 2   (uendret fra 0008)
--
-- Totalt 16 rader (8 staff × 2 services).
-- ============================================================
