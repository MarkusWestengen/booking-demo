-- ============================================================
-- Westengen Klinikk — Stram inn for vide GRANTs på reviews (sikkerhet)
-- Migration 0037
-- ------------------------------------------------------------
-- PROBLEM: prod-verifisering viste at `anon` (og `authenticated`)
-- hadde ALLE tabell-privilegier på public.reviews — DELETE, INSERT,
-- REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE. Til sammenligning
-- har waitlist (0023) korrekt KUN `anon: INSERT`.
--
-- VIKTIG presisering: den committede 0036 grantet SPESIFIKT
-- (`grant insert, select to anon` + `grant select, update to
-- authenticated`) — den brukte IKKE `grant all`. De ekstra
-- privilegiene stammer derfor fra noe annet (sannsynligvis Supabase
-- «default privileges» som grant'er ALL på nye public-tabeller til
-- anon/authenticated, eller en manuelt modifisert apply). Uansett
-- kilde: 0036 fjernet ikke over-grantet.
--
-- FIKS: REVOKE ALL fra anon + authenticated, deretter GRANT kun det
-- RLS-policyene (0034) faktisk trenger — matcher waitlist-mønsteret.
--   - anon:          INSERT (innsending) + SELECT (offentlig lesing)
--                    RLS gater til status='pending' / 'approved'.
--   - authenticated: SELECT + UPDATE (admin-moderering)
--                    RLS gater til role='admin'.
-- postgres/service_role røres IKKE — de skal ha full tilgang.
--
-- Idempotent (REVOKE/GRANT er trygt å re-kjøre). Avhenger av 0034 + 0036.
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

-- Fjern alt fra de to klient-rollene (rydder bort over-grantet).
revoke all on public.reviews from anon, authenticated;

-- Gi tilbake minste nødvendige (RLS begrenser videre).
grant insert, select on public.reviews to anon;
grant select, update on public.reviews to authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply) — samme spørring som
-- avdekket problemet:
--
--   select grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_schema = 'public' and table_name = 'reviews'
--     and grantee in ('anon', 'authenticated')
--   order by grantee, privilege_type;
--
-- Forventet ETTER 0037:
--   anon          | INSERT
--   anon          | SELECT
--   authenticated | SELECT
--   authenticated | UPDATE
--   (ingen DELETE / REFERENCES / TRIGGER / TRUNCATE)
--
-- Funksjonell røyktest (uendret av innstrammingen):
--   - anon kan fortsatt sende inn anmeldelse (status=pending).
--   - anon ser fortsatt kun godkjente.
--   - admin kan fortsatt liste pending + godkjenne/avvise.
-- ============================================================
