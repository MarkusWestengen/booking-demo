-- ============================================================
-- 0046_contact_messages_admin_delete.sql             2026-06-11
-- ------------------------------------------------------------
-- «Slett»-knapp på meldinger.html: KUN admin skal kunne slette
-- kontaktmeldinger. 0039 ga bevisst ingen DELETE — denne åpner
-- den minimalt:
--   - grant DELETE til authenticated (ytre skall; RLS gjør den
--     reelle gatingen — samme mønster som bookings-delete)
--   - RLS-policy: DELETE kun når app_metadata.role = 'admin'
--     (0018-wrap-mønsteret). Therapist får INGEN delete.
--   - anon er uendret (kun INSERT fra 0039).
--
-- Hard delete er avklart med Markus: kontaktmeldinger er ikke
-- journal-/regnskapsdata, ingen FK peker på contact_messages,
-- og CSV-eksport (admin) finnes for arkivering før sletting.
-- Frontend audit-logger sletting best-effort (audit_log-tabellen
-- berøres ikke av denne migrasjonen).
--
-- Idempotent: revoke-all-først + re-grant (0037-mønsteret),
-- drop policy if exists før create. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- Uavhengig av 0042/0043/0045 — kan kjøres når som helst etter 0039.
-- ============================================================

begin;

-- ----- Grants: revoke-all-først, så minste nødvendige ---------
-- (identisk med 0039 + DELETE for authenticated)
revoke all on public.contact_messages from anon, authenticated;
grant insert                 on public.contact_messages to anon;
grant select, update, delete on public.contact_messages to authenticated;

-- RLS skal allerede være på (0039) — re-assert er en no-op.
alter table public.contact_messages enable row level security;

-- ----- DELETE-policy: kun admin -------------------------------
drop policy if exists "contact_messages delete: admin" on public.contact_messages;

create policy "contact_messages delete: admin"
  on public.contact_messages
  for delete
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) 4 policies på contact_messages (3 fra 0039 + delete):
--    select policyname, cmd from pg_policies
--     where schemaname='public' and tablename='contact_messages'
--     order by policyname;
--    -- Forvent: anon insert contact_messages (INSERT),
--    --          contact_messages delete: admin (DELETE),
--    --          contact_messages read: staff (SELECT),
--    --          contact_messages update: staff (UPDATE)
--
-- B) Grants:
--    select grantee, string_agg(privilege_type, ',' order by privilege_type) as privs
--      from information_schema.role_table_grants
--     where table_schema='public' and table_name='contact_messages'
--       and grantee in ('anon','authenticated')
--     group by grantee order by grantee;
--    -- Forvent: anon=INSERT ; authenticated=DELETE,SELECT,UPDATE
--
-- C) Ende-til-ende:
--    - Som ADMIN i meldinger.html: «Slett» på en testmelding →
--      bekreftelsesdialog → raden forsvinner uten reload.
--    - Som THERAPIST: ingen Slett-knapp rendres; en håndlaget
--      DELETE via REST treffer RLS og sletter 0 rader.
-- ============================================================
