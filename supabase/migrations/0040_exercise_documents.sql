-- ============================================================
-- 0040_exercise_documents.sql                        2026-06-03
-- ------------------------------------------------------------
-- Øvelse-/dokumentsystem (DEL 2). Ansatte legger inn øvelser/
-- dokumenter (PDF/video) i 6 kategorier (nakke/skulder/hofte/kne/
-- ankel/fot) og sender dem til kunder som trenger oppfølging.
--
-- To tabeller + privat Storage-bucket + e-posttrigger:
--   - exercise_documents: metadata + storage_path (filen ligger i
--     bucket 'exercise-documents', PRIVAT). Admin laster opp; alle
--     ansatte (admin+therapist) leser.
--   - document_sends: logg over utsendinger. link_url er en SIGNERT
--     URL med 30 dagers gyldighet (generert klient-side med
--     createSignedUrl(path, 2592000)). Alle ansatte sender (INSERT)
--     + leser (SELECT). Trigger e-poster kunden lenken.
--   - Storage: bucket privat → kun signerte 30-dagers-URL-er gir
--     tilgang. storage.objects-policyer KUN for dette bucket-et;
--     admin laster opp/endrer/sletter, alle ansatte leser, anon
--     ingen tilgang.
--
-- Designvalg (avklart med Markus):
--   - Lenke-varighet 30 DAGER (personvern — dokumentene kan være
--     pasient-relaterte; bucket forblir privat, lenken utløper).
--   - GRANTs: revoke all FØRST (0037-lærdom), så minste nødvendige.
--   - RLS bruker 0018-wrap-mønsteret ((select auth.jwt()) -> ...).
--   - E-post: send_document_email() med DO-guard (0011-mønster →
--     bevarer ekte nøkkel ved re-apply), REDACTED_RESEND_KEY-
--     placeholder, html_escape() (0028) på input, exception-when-
--     others så insert committer selv om e-post feiler.
--   - Dokument kan trekkes tilbake: admin UPDATE/DELETE på
--     exercise_documents + remove() av storage-objektet (UI).
--
-- STRUKTUR: Block A (tabeller/RLS/grants/e-post) er atomisk
-- (begin/commit). Block B (bucket + storage.objects-policyer) kjøres
-- UTENFOR transaksjonen — hvis SQL Editor mangler eierskap på
-- storage.objects, feiler bare Block B, og Block A er alt committed.
-- Fallback for Block B: opprett bucket + 4 policyer manuelt i
-- Dashboard → Storage (definisjoner i SCHEMA_DRIFT_TODO §40).
--
-- Idempotent. IKKE applisert av repoet — Markus kjører i Dashboard.
-- ============================================================


-- ============================================================
-- BLOCK A — tabeller + RLS + grants + e-post (atomisk)
-- ============================================================
begin;

-- ----- exercise_documents ------------------------------------
create table if not exists public.exercise_documents (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  category         text not null
    check (category in ('nakke','skulder','hofte','kne','ankel','fot')),
  storage_path     text not null,       -- sti i bucket 'exercise-documents'
  file_name        text,
  mime_type        text,
  uploaded_by      uuid,                 -- auth.uid() til admin som lastet opp
  uploaded_by_name text,
  created_at       timestamptz not null default now()
);

create index if not exists idx_exercise_documents_category
  on public.exercise_documents (category, created_at desc);

-- ----- document_sends (utsendings-logg) ----------------------
create table if not exists public.document_sends (
  id             uuid primary key default gen_random_uuid(),
  document_id    uuid references public.exercise_documents(id) on delete set null,
  document_title text not null,
  customer_email text not null,
  link_url       text not null,         -- signert URL (transient, 30 d)
  sent_by        uuid,
  sent_by_name   text,
  created_at     timestamptz not null default now()
);

create index if not exists idx_document_sends_recent
  on public.document_sends (created_at desc);

-- ----- Grants (revoke all FØRST — 0037-lærdom) ---------------
revoke all on public.exercise_documents from anon, authenticated;
revoke all on public.document_sends     from anon, authenticated;
-- exercise_documents: authenticated trenger alle fire (RLS gater
-- INSERT/UPDATE/DELETE til admin). anon: ingenting.
grant select, insert, update, delete on public.exercise_documents to authenticated;
-- document_sends: alle ansatte sender (INSERT) + leser (SELECT). anon: ingenting.
grant select, insert on public.document_sends to authenticated;

-- ----- RLS: exercise_documents -------------------------------
alter table public.exercise_documents enable row level security;

drop policy if exists "exdocs insert: admin" on public.exercise_documents;
drop policy if exists "exdocs read: staff"   on public.exercise_documents;
drop policy if exists "exdocs update: admin" on public.exercise_documents;
drop policy if exists "exdocs delete: admin" on public.exercise_documents;

-- Kun admin kan legge inn nye dokumenter.
create policy "exdocs insert: admin"
  on public.exercise_documents for insert to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

-- Alle ansatte (admin + therapist) leser dokumentlista.
create policy "exdocs read: staff"
  on public.exercise_documents for select to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'));

-- Kun admin kan endre/trekke tilbake dokumenter.
create policy "exdocs update: admin"
  on public.exercise_documents for update to authenticated
  using   (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create policy "exdocs delete: admin"
  on public.exercise_documents for delete to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

-- ----- RLS: document_sends -----------------------------------
alter table public.document_sends enable row level security;

drop policy if exists "docsends insert: staff" on public.document_sends;
drop policy if exists "docsends read: staff"   on public.document_sends;

-- Alle ansatte kan sende et dokument (logge en utsending).
create policy "docsends insert: staff"
  on public.document_sends for insert to authenticated
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'));

-- Alle ansatte ser utsendings-loggen.
create policy "docsends read: staff"
  on public.document_sends for select to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'));

-- ----- E-postvarsel til kunde (sandbox-klar) -----------------
create extension if not exists pg_net;

-- DO-guard: skap KUN hvis funksjonen ikke finnes (bevarer prod-
-- versjon med ekte nøkkel ved re-apply, jf. 0011/0039).
do $do$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'send_document_email'
  ) then
    raise notice 'send_document_email finnes ikke — skaper med REDACTED_RESEND_KEY-placeholder. Operatør må sette ekte nøkkel + verifisert avsender før e-post leverer.';
    execute $func_def$
create function public.send_document_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $body$
declare
  -- ⚠️ HARDKODET API-NØKKEL — placeholder kun for ferske deploys.
  -- DO-guarden hopper over CREATE på eksisterende prod-DB, så den
  -- ekte nøkkelen bevares. Aldri lim inn ekte nøkkel her (git).
  resend_key   text := 'REDACTED_RESEND_KEY';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  notify_to    text := new.customer_email;
  e_title      text := public.html_escape(new.document_title);
  e_link       text := public.html_escape(new.link_url);
  e_sender     text := public.html_escape(coalesce(new.sent_by_name, 'Westengen Klinikk'));
  notify_html  text;
begin
  notify_html :=
       '<!DOCTYPE html><html lang="no"><body style="margin:0;padding:0;background-color:#FAF7F1;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
    || '<tr><td align="center" style="padding:32px 12px;">'
    || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background-color:#ffffff;">'
    || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;padding:40px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:24px;letter-spacing:0.30em;color:#FAF7F1;">MARKUS'&nbsp;ARENA</div>'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.24em;color:#A6C1AC;padding-top:14px;">ØVELSER &amp; OPPFØLGING</div>'
    || '</td></tr>'
    || '<tr><td style="padding:40px 40px 8px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:21px;color:#15191A;">Du har fått tilsendt et dokument.</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#5c5d55;padding-top:12px;">'
    ||     e_sender || ' ved Westengen Klinikk har delt «' || e_title || '» med deg. Klikk knappen under for å laste det ned.</div>'
    || '</td></tr>'
    || '<tr><td align="center" style="padding:14px 40px 8px;">'
    ||   '<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:8px auto 0;">'
    ||     '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;border-radius:4px;">'
    ||       '<a href="' || e_link || '" style="display:inline-block;padding:15px 42px;font-family:Helvetica,Arial,sans-serif;font-size:15px;font-weight:bold;letter-spacing:0.05em;color:#FAF7F1;text-decoration:none;">LAST NED DOKUMENT</a>'
    ||     '</td></tr>'
    ||   '</table>'
    || '</td></tr>'
    || '<tr><td style="padding:18px 40px 40px;">'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;color:#8a8b82;word-break:break-all;">' || e_link || '</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8a8b82;padding-top:14px;">Lenken er gyldig i 30 dager. Trenger du den på nytt etterpå, ta kontakt med klinikken.</div>'
    || '</td></tr>'
    || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A;padding:30px 40px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:15px;letter-spacing:0.20em;color:#FAF7F1;">WESTENGEN KLINIKK</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:12px;line-height:1.7;color:#8f9089;padding-top:9px;">Bregneveien 12, 0283 Oslo<br>+47 400 00 000</div>'
    || '</td></tr>'
    || '</table></td></tr></table></body></html>';

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'from',    from_email,
      'to',      notify_to,
      'subject', 'Dokument fra Westengen Klinikk: ' || e_title,
      'html',    notify_html
    )
  );

  return new;

exception when others then
  -- E-post er sekundært: la utsendings-loggen lagres selv om varselet
  -- feiler (forventet i sandbox før domeneverifisering).
  raise notice 'send_document_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$body$;
$func_def$;
  else
    raise notice 'send_document_email finnes allerede — bevarer prod-versjon (antatt ekte nøkkel).';
  end if;
end
$do$;

drop trigger if exists trg_document_email on public.document_sends;
create trigger trg_document_email
  after insert on public.document_sends
  for each row
  execute function public.send_document_email();

commit;


-- ============================================================
-- BLOCK B — Supabase Storage (bucket + storage.objects-policyer)
-- KJØRES UTENFOR transaksjonen over. Hvis SQL Editor mangler
-- eierskap på storage.objects og CREATE POLICY feiler, er Block A
-- allerede committet — gjør da Block B manuelt i Dashboard →
-- Storage (se SCHEMA_DRIFT_TODO §40 for nøyaktige definisjoner).
-- ============================================================

-- Privat bucket (public=false → kun signerte URL-er gir tilgang).
insert into storage.buckets (id, name, public)
values ('exercise-documents', 'exercise-documents', false)
on conflict (id) do nothing;

-- RLS-policyer på storage.objects, AVGRENSET til dette bucket-et.
-- anon nevnes ikke → har ingen tilgang til objektene.
drop policy if exists "exdocs storage read: staff"   on storage.objects;
drop policy if exists "exdocs storage upload: admin" on storage.objects;
drop policy if exists "exdocs storage update: admin" on storage.objects;
drop policy if exists "exdocs storage delete: admin" on storage.objects;

-- Alle ansatte leser (trengs for å liste + lage signerte URL-er).
create policy "exdocs storage read: staff"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist')
  );

-- Kun admin laster opp.
create policy "exdocs storage upload: admin"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

-- Kun admin endrer (bytter ut fil).
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

-- Kun admin sletter (trekker tilbake).
create policy "exdocs storage delete: admin"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'exercise-documents'
    and ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
  );

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Tabeller + RLS-policyer:
--    select tablename, policyname, cmd from pg_policies
--     where schemaname='public'
--       and tablename in ('exercise_documents','document_sends')
--     order by tablename, policyname;
--    -- Forvent exercise_documents: insert(admin), read(staff),
--    --   update(admin), delete(admin)
--    --        document_sends: insert(staff), read(staff)
--
-- B) Grants minimale (IKKE for vide — jf. 0037):
--    select table_name, grantee,
--           string_agg(privilege_type, ',' order by privilege_type) as privs
--      from information_schema.role_table_grants
--     where table_schema='public'
--       and table_name in ('exercise_documents','document_sends')
--       and grantee in ('anon','authenticated')
--     group by table_name, grantee order by table_name, grantee;
--    -- Forvent: exercise_documents/authenticated = DELETE,INSERT,SELECT,UPDATE
--    --          document_sends/authenticated      = INSERT,SELECT
--    --          anon: INGEN rader for noen av tabellene
--
-- C) Bucket finnes + er PRIVAT:
--    select id, public from storage.buckets where id='exercise-documents';
--    -- Forvent: 1 rad, public = false
--
-- D) Storage-policyer for bucket-et:
--    select policyname, cmd from pg_policies
--     where schemaname='storage' and tablename='objects'
--       and policyname like 'exdocs storage%' order by policyname;
--    -- Forvent 4: read(SELECT/staff), upload(INSERT/admin),
--    --            update(UPDATE/admin), delete(DELETE/admin)
--    -- (Hvis 0 rader: Block B feilet — sett dem manuelt i Dashboard.)
--
-- E) E-postfunksjon finnes + escaping (+ må reapply ekte nøkkel):
--    select case when prosrc ~ 'resend_key\s+text\s*:=\s*''re_'
--                then 'EKTE NØKKEL OK' else 'MÅ REAPPLY (placeholder)' end as nokkel,
--           prosrc ~ 'html_escape' as has_escape
--      from pg_proc where proname='send_document_email';
-- ============================================================
