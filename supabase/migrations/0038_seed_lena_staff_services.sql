-- ============================================================
-- 0038_seed_lena_staff_services.sql                2026-06-02
-- ------------------------------------------------------------
-- NB (avklaring 2026-06-02): Denne migrasjonen treffer M:N-tabellen
-- public.staff_services (opprettet i 0008) — IKKE en `staff`-tabell.
-- Det finnes INGEN staff-tabell i Westengen Klinikk: terapeut-katalogen bor
-- i koden (STAFF + THERAPIST_POOL i shared/booking-engine.js), og
-- staff_id er bare en text-nøkkel. Migrasjonen oppretter ingen tabell;
-- den seeder kun rader i den eksisterende staff_services.
-- (Omdøpt fra 0038_seed_lena_staff.sql for å unngå forveksling med
--  en staff-tabell — innholdet er uendret.)
--
-- Hva den gjør: kobler terapeuten 'lena' til de to terapeut-
-- tjenestene (ter-konsult + ter-videre) via slug — nøyaktig samme
-- mønster som de 5 fra 0015 (sofie, henrik, jonas, amina, petter).
--
-- Trenger Lena denne raden? Nyansert:
--   - For å TILDELES TIMER (admin-tildeling i booking-admin.html):
--     NEI. Den flyten bruker kun THERAPIST_POOL + STAFF fra koden.
--     Kode-endringen (samme commit-spor) gjør ham allerede tildelbar.
--   - For å være KOBLET TIL ter-tjenestene på lik linje med de andre:
--     JA. tjenester.html-admin leser staff_services og viser hvilke
--     utførere som er avkrysset per tjeneste. De 5 andre har disse
--     radene (0015); uten dem ville Lena vært den eneste terapeuten
--     uten ter-service-kobling. Denne migrasjonen lukker det gapet.
--
-- Hva som IKKE endres:
--   - Ingen RLS-/sikkerhetsendringer.
--   - 'markus', 'terapeut' og de 5 eksisterende terapeutene røres ikke.
--   - Ingen staff-tabell opprettes (staff_id er fortsatt text; se 0008).
--
-- Idempotent: insert .. on conflict do nothing. Trygt å re-kjøre.
-- Forutsetning: services-radene ter-konsult/ter-videre fra 0008 (i prod).
-- ============================================================

insert into public.staff_services (staff_id, service_id)
select 'lena', id from public.services
 where slug in ('ter-konsult', 'ter-videre')
on conflict do nothing;

-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--
--   select staff_id, count(*) as service_count
--     from public.staff_services
--    where staff_id = 'lena'
--    group by staff_id;
--
-- Forventet etter denne migrasjonen:
--   lena | 2
--
-- (Totalt i staff_services blir da 18 rader: 9 staff × 2 services,
--  opp fra 16 etter 0015.)
-- ============================================================
