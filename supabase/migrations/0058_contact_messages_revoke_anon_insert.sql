-- ============================================================
-- 0058_contact_messages_revoke_anon_insert.sql        2026-06-20
-- ------------------------------------------------------------
-- Turnstile-pilot for kontaktskjemaet: kontaktmeldinger sendes nå
-- via Edge Function «submit-contact» (Cloudflare Turnstile-verify
-- + IP-rate-limit + insert via service_role). Denne migrasjonen
-- stenger den DIREKTE anon-veien inn, slik at den verifiserte
-- funksjonen blir eneste innslippspunkt.
--
--   - revoke INSERT på contact_messages fra anon.
--   - authenticated-grants (select/update/delete fra 0039/0046) +
--     service_role er URØRT (service_role bypasser RLS og beholder
--     sine default-grants → funksjonen kan fortsatt insert-e).
--
-- BEVISST BEHOLDT som dødt/backstop-forsvar (skadefritt):
--   - RLS-policyen «anon insert contact_messages» (0039/0052): blir
--     uvirksom uten INSERT-grant, men gjenåpner validering hvis grant
--     noen gang re-introduseres.
--   - Triggeren trg_anon_quota_contact (0052): fyrer ikke for
--     service_role, så rate-limit håndteres nå i Edge Function-en.
--     Den står igjen som backstop dersom anon-veien gjenåpnes.
-- All input-validering for den nye veien bor i submit-contact.
--
-- PROD-REKKEFØLGE (kritisk — unngå nedetid):
--   1. Deploy submit-contact + push frontend (peker mot funksjonen).
--   2. Verifiser HELE kjeden i prod MENS anon-insert fortsatt virker.
--   3. FØRST DA: apply DENNE migrasjonen (revoke).
--   Kjøres for tidlig = kontaktskjemaet på gammel frontend brekker.
--
-- Idempotent: revoke er en no-op om grant alt er borte.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

revoke insert on public.contact_messages from anon;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) anon skal IKKE lenger ha INSERT; authenticated uendret:
--    select grantee, string_agg(privilege_type, ',' order by privilege_type) as privs
--      from information_schema.role_table_grants
--     where table_schema='public' and table_name='contact_messages'
--       and grantee in ('anon','authenticated')
--     group by grantee order by grantee;
--    -- Forvent: anon = (ingen rad) ; authenticated = DELETE,SELECT,UPDATE
--
-- B) Ende-til-ende (etter funksjon + frontend er live):
--    - kontakt.html → fyll ut + løs Turnstile → melding lander i
--      meldinger.html + e-post + push (uendret).
--    - Håndlaget direkte REST INSERT mot /rest/v1/contact_messages
--      med anon-nøkkel → 401/permission denied (veien er stengt).
-- ============================================================
