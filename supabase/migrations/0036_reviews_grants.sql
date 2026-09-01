-- ============================================================
-- Westengen Klinikk — Manglende tabell-GRANTs på reviews (bugfix)
-- Migration 0036
-- ------------------------------------------------------------
-- ROTÅRSAK: 0034 opprettet `public.reviews` + RLS-policyer, men
-- glemte tabell-GRANTs. I dette prosjektet kreves EKSPLISITTE grants
-- (jf. 0023 som gjør `grant insert on public.waitlist to anon`) —
-- standard «default privileges»-auto-grant er ikke i effekt her.
--
-- Uten grant blokkeres operasjonen av manglende tabell-privilegier
-- FØR RLS-policyen i det hele tatt evalueres. Symptom: anmeldelses-
-- innsending feilet med «Noe gikk galt», forsidens visning av
-- godkjente anmeldelser fikk 0 rader, og admin-moderering kunne ikke
-- lese/oppdatere.
--
-- RLS-policyene fra 0034 er korrekte og uendret — de gater fortsatt
-- hva hver rolle faktisk får se/gjøre. Disse grantene gir bare
-- rollene tabell-tilgang som RLS så begrenser.
--
-- Idempotent (GRANT er trygt å re-kjøre). Avhenger av 0034 (reviews).
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- Anon: sende inn anmeldelse + lese godkjente (RLS begrenser til
-- status='pending' ved insert og status='approved' ved select).
grant insert, select on public.reviews to anon;

-- Authenticated: admin-moderering (RLS begrenser til role='admin').
-- En terapeut har grant, men RLS gir 0 rader — trygt.
grant select, update on public.reviews to authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- 1) Som anon (anon-nøkkel): INSERT skal nå lykkes:
--      insert into public.reviews (name, rating, body)
--        values ('Test', 5, 'Fungerer nå');  → ok (status=pending).
--
-- 2) Som anon: SELECT returnerer kun godkjente (RLS):
--      select count(*) from public.reviews;  → kun approved.
--
-- 3) Som admin (innlogget): ser pending + kan UPDATE status.
--
-- Privilegie-sjekk:
--   select has_table_privilege('anon', 'public.reviews', 'INSERT');  -- t
--   select has_table_privilege('anon', 'public.reviews', 'SELECT');  -- t
-- ============================================================
