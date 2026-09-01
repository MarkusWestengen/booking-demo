-- Tillat anonyme brukere å logge KUN login_failed-events.
-- Begrunnelse: Vi må kunne detektere brute-force-forsøk fra ikke-innloggede
-- aktører. Risiko: anon kan spamme audit_log med login_failed-rader.
-- Avbøtning: streng with_check + Supabase sin innebygde rate limiting på
-- anon-anrop er en separat oppgave (TODO i ops-doc).

drop policy if exists "audit: anon can insert login_failed" on public.audit_log;

create policy "audit: anon can insert login_failed"
  on public.audit_log for insert to anon
  with check (
    action = 'login_failed'
    and actor_staff_id = 'unknown'
    and target_type = 'session'
    and metadata ? 'attempted_email'
    and length(coalesce(metadata->>'attempted_email', '')) <= 254
    and length(coalesce(metadata->>'reason', '')) <= 64
  );

-- Dokumenter også action-verdiene som er i bruk for å hjelpe fremtidig
-- audit-logg-viewer (UI-dropdown). Ingen DDL — bare en kommentar.
-- Kjente actions: journal_view, journal_create, booking_status_change,
-- gdpr_export, gdpr_pseudonymize, login_failed, login_success.
