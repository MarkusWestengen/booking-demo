-- ============================================================
-- 0055_k5_storage_hardening.sql                      2026-06-13
-- ------------------------------------------------------------
-- K5 (betinget kritisk) + F-MEDIUM fra security-review-2026-06-12:
-- det kunne ikke bevises fra kode at exercise-documents-bucketen er
-- privat og at storage-policyene fra 0040 Block B faktisk ble
-- opprettet (Block B kjørte utenfor transaksjon og kan ha feilet på
-- eierskap; bucketen kan ha blitt opprettet manuelt med Public=PÅ).
-- I tillegg manglet bucketen file_size_limit/allowed_mime_types —
-- vilkårlig innhold/størrelse kunne lastes opp.
--
-- Denne migrasjonen RE-ASSERTER ønsket tilstand idempotent:
--   (a) Bucket: tvinges privat + 50 MB-tak + mime-whitelist
--       (PDF/video/bilde — matcher dokumenter.html sin accept).
--   (b) De 4 storage.objects-policyene fra 0040 Block B gjenskapes
--       (drop if exists + create). Avgrenset til bucket_id =
--       'exercise-documents'; anon nevnes ikke → null tilgang.
--
-- ⚠️ Som i 0040: storage.objects-policyer kan feile på eierskap i
-- enkelte SQL-Editor-kontekster. Kjør (a) og (b) hver for seg hvis
-- nødvendig; feiler (b), opprett policyene manuelt i Dashboard →
-- Storage → Policies (definisjonene under er fasit). Selv om (b)
-- feiler er (a) det viktigste: public=false gjør at ingen objekter
-- kan leses uten signert URL.
--
-- K5 er IKKE lukket før verifiserings-SQL-en (V5/V6) + anon-curl er
-- kjørt mot prod — se operator-checklist-2026-06-13.md.
--
-- Idempotent. IKKE applisert av repoet — Markus kjører i Dashboard.
-- ============================================================

-- ============================================================
-- (a) Bucket: privat + størrelse/type-tak (upsert)
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'exercise-documents', 'exercise-documents', false,
  52428800, -- 50 MB
  array['application/pdf',
        'video/mp4', 'video/quicktime', 'video/webm',
        'image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update
  set public            = false,
      file_size_limit   = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ============================================================
-- (b) Re-assert de 4 policyene fra 0040 Block B
-- ============================================================
drop policy if exists "exdocs storage read: staff"   on storage.objects;
drop policy if exists "exdocs storage upload: admin" on storage.objects;
drop policy if exists "exdocs storage update: admin" on storage.objects;
drop policy if exists "exdocs storage delete: admin" on storage.objects;

create policy "exdocs storage read: staff"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist')
  );

create policy "exdocs storage upload: admin"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "exdocs storage update: admin"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  )
  with check (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

create policy "exdocs storage delete: admin"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply — dette ER K5-beviset):
--
-- V5) Bucket privat + tak satt:
--     select id, public, file_size_limit, allowed_mime_types
--       from storage.buckets where id='exercise-documents';
--     -- Forvent: public=false, 52428800, 7 mime-typer.
--
-- V6) Nøyaktig 4 policyer for bucketen:
--     select policyname, cmd from pg_policies
--      where schemaname='storage' and tablename='objects'
--        and policyname like 'exdocs storage%' order by policyname;
--     -- Forvent 4: delete/insert/select/update, alle med bucket_id-sjekk.
--
-- Live (anon skal IKKE nå objekter — forvent 400/404):
--     curl "https://<din-project-ref>.supabase.co/storage/v1/object/public/exercise-documents/<path>"
--     curl -X POST "https://<din-project-ref>.supabase.co/storage/v1/object/list/exercise-documents" -H "apikey: <ANON>"
-- ============================================================
