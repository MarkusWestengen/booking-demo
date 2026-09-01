-- ============================================================
-- 0050_k1_journal_select_scope.sql                   2026-06-13
-- ------------------------------------------------------------
-- K1 fra security-review-2026-06-12: journal_entries sin SELECT-
-- policy var `using (true)` — enhver authenticated-konto (også en
-- selvregistrert konto uten rolle hvis public signup står på)
-- kunne lese SAMTLIGE pasientjournaler via direkte PostgREST-kall.
--
-- Ny policy speiler bookings-policyen fra 0018:
--   - admin: leser alt (uendret behov, kalender/kunde-detalj).
--   - therapist: leser KUN journaler for pasienter terapeuten har
--     en behandlingsrelasjon med (minst én booking på egen
--     staff_id som matcher pasientens e-post eller telefon), pluss
--     notater terapeuten selv har skrevet.
--   - Konto uten rolle i app_metadata: 0 rader.
--
-- Tomme identifikatorer matcher ALDRI: admin-opprettede bookinger
-- kan ha email='' / phone='' (0047) — uten <>''-guardene ville to
-- urelaterte pasienter med tom telefon «dele» relasjon.
--
-- MERK: 0051 (K2) revoker i tillegg direkte SELECT-grant og flytter
-- all journal-lesing bak en loggende RPC. Denne policyen beholdes
-- som defense-in-depth: hvis grantet noen gang gjeninnføres ved et
-- uhell (jf. 0037-hendelsen), er tilgangen fortsatt rolle- og
-- relasjonsscopet — ikke åpen.
--
-- Ytelse: exists-subqueryen treffer bookings_email_idx (0027,
-- lower(email)) og er begrenset til terapeut-grenen.
--
-- Idempotent: drop policy if exists + create. Atomisk (begin/commit).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

drop policy if exists "journal: staff can read all" on public.journal_entries;
drop policy if exists "journal: read scoped"        on public.journal_entries;

create policy "journal: read scoped"
  on public.journal_entries for select
  to authenticated
  using (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    or (
      ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'therapist'
      and (
        -- Egne notater (forfatter) — alltid lesbare for forfatteren.
        staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
        -- Behandlingsrelasjon: terapeuten har minst én booking med
        -- denne pasienten (match på e-post ELLER telefon, aldri på
        -- tom streng).
        or exists (
          select 1
            from public.bookings b
           where b.staff_id = ((select auth.jwt()) -> 'app_metadata' ->> 'staff_id')
             and (
                  (journal_entries.patient_email <> ''
                   and lower(b.email) = lower(journal_entries.patient_email))
               or (journal_entries.patient_phone <> ''
                   and b.phone = journal_entries.patient_phone)
             )
        )
      )
    )
  );

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Policyen er byttet ut:
--    select policyname, qual from pg_policies
--     where schemaname='public' and tablename='journal_entries' and cmd='SELECT';
--    -- Forvent: 1 rad, policyname='journal: read scoped',
--    --          qual inneholder 'admin', 'therapist' og en EXISTS mot bookings.
--    --          INGEN 'true'-qual igjen.
--
-- B) Som terapeut-JWT: GET /rest/v1/journal_entries?select=*
--    -- Forvent: kun journaler for pasienter terapeuten har bookinger med.
--    (Etter 0051 gir kallet i stedet 401/permission denied — det er riktig.)
--
-- C) Som konto uten rolle (hvis en testkonto finnes): 0 rader.
-- ============================================================
