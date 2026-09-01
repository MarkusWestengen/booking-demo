-- ============================================================
-- 0039_contact_messages.sql                          2026-06-03
-- ------------------------------------------------------------
-- Meldingssystem: kunder sender en henvendelse fra #kontakt på
-- forsiden. Lagres i public.contact_messages, leses + markeres
-- lest/besvart av ansatte i meldinger.html, og kan eksporteres
-- til CSV (admin). En DB-trigger varsler post@westengenklinikk.example
-- via Resend (pg_net) — men leverer IKKE før Resend-domenet er
-- verifisert (sandbox sender kun til kontoeier). Meldingen lagres
-- uansett om e-posten går ut (exception-when-others i funksjonen).
--
-- Designvalg (avklart med Markus):
--   - anon kan INSERT (status='new' + avgrenset PII + melding
--     1..2000 tegn). Ingen lesing av andres meldinger.
--   - ALLE ansatte (authenticated, admin+therapist) leser + kan
--     UPDATE (markere lest/besvart). Ingen DELETE-policy/-grant.
--   - RLS bruker 0018-wrap-mønsteret ((select auth.jwt()) -> ...).
--   - status CHECK ('new','read','answered').
--   - GRANTs: revoke all FØRST (0037-lærdom — Supabase default-
--     privileges kan gi for vidt), så minste nødvendige.
--   - E-post: send_contact_message_email() med DO-guard (skaper
--     KUN hvis funksjonen ikke finnes → bevarer ekte nøkkel ved
--     re-apply, jf. 0011). REDACTED_RESEND_KEY-placeholder.
--     html_escape() (0028) på all kunde-input. exception-when-
--     others så insert committer selv om e-post feiler.
--
-- Idempotent: create table/index/policy if (not) exists, DO-guard
-- for funksjonen, drop/create trigger. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ----- contact_messages-tabell --------------------------------
create table if not exists public.contact_messages (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  email       text not null,
  message     text not null,
  status      text not null default 'new'
    check (status in ('new','read','answered')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Innboks-indeks: nyeste først, gruppert på status.
create index if not exists idx_contact_messages_inbox
  on public.contact_messages (status, created_at desc);

-- updated_at-trigger (samme mønster som waitlist 0023 / services 0008).
create or replace function public._contact_messages_set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists contact_messages_set_updated_at on public.contact_messages;
create trigger contact_messages_set_updated_at
  before update on public.contact_messages
  for each row execute function public._contact_messages_set_updated_at();

-- ----- Grants + RLS -------------------------------------------
-- 0037-lærdom: fjern evt. for vide default-privileges først, så
-- grant kun det RLS-policyene trenger (begge må tillate).
revoke all on public.contact_messages from anon, authenticated;
grant insert         on public.contact_messages to anon;
grant select, update on public.contact_messages to authenticated;

alter table public.contact_messages enable row level security;

drop policy if exists "anon insert contact_messages"   on public.contact_messages;
drop policy if exists "contact_messages read: staff"   on public.contact_messages;
drop policy if exists "contact_messages update: staff" on public.contact_messages;

-- Anon kan sende en henvendelse. Avgrenset PII + meldingslengde
-- (DB-side maxlength mot misbruk; UI har maxlength i tillegg).
create policy "anon insert contact_messages"
  on public.contact_messages
  for insert
  to anon
  with check (
        status = 'new'
    and length(coalesce(name,    '')) between 1 and 200
    and length(coalesce(email,   '')) between 3 and 320
    and length(coalesce(message, '')) between 1 and 2000
  );

-- Alle ansatte (admin + therapist) leser alle meldinger.
create policy "contact_messages read: staff"
  on public.contact_messages
  for select
  to authenticated
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'));

-- Alle ansatte kan markere lest/besvart (UPDATE).
create policy "contact_messages update: staff"
  on public.contact_messages
  for update
  to authenticated
  using   (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'))
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') in ('admin','therapist'));

-- ----- E-postvarsel (sandbox-klar) ----------------------------
-- pg_net for HTTP-POST til Resend (samme mekanisme som 0011/0026/0028).
create extension if not exists pg_net;

-- DO-guard: skap KUN hvis funksjonen ikke finnes (bevarer prod-
-- versjon med ekte nøkkel ved re-apply, jf. 0011). På fersk DB
-- skapes den med REDACTED_RESEND_KEY — operatør må sette ekte
-- nøkkel + bytte avsender til verifisert domene før den leverer.
do $do$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'send_contact_message_email'
  ) then
    raise notice 'send_contact_message_email finnes ikke — skaper med REDACTED_RESEND_KEY-placeholder. Operatør må sette ekte nøkkel + verifisert avsender før e-post leverer.';
    execute $func_def$
create function public.send_contact_message_email()
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
  notify_to    text := 'post@westengenklinikk.example';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  date_str     text := to_char(new.created_at, 'DD.MM.YYYY HH24:MI');
  notify_html  text;
  -- Pre-escapet kunde-input (jf. 0028 P1-2).
  e_name       text := public.html_escape(new.name);
  e_email      text := public.html_escape(new.email);
  e_message    text := replace(public.html_escape(new.message), chr(10), '<br>');
begin
  notify_html :=
       '<!DOCTYPE html><html lang="no"><body style="margin:0;padding:0;background-color:#FAF7F1;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
    || '<tr><td align="center" style="padding:32px 12px;">'
    || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:600px;background-color:#ffffff;">'
    || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47;padding:40px;">'
    ||   '<div style="font-family:Georgia,serif;font-size:24px;letter-spacing:0.30em;color:#FAF7F1;">MARKUS'&nbsp;ARENA</div>'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.24em;color:#A6C1AC;padding-top:14px;">NY HENVENDELSE</div>'
    || '</td></tr>'
    || '<tr><td style="padding:36px 40px 8px;">'
    ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
    ||     '<tr><td width="92" style="padding:13px 16px 13px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">NAVN</td>'
    ||       '<td style="padding:13px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || e_name || '</td></tr>'
    ||     '<tr><td width="92" style="padding:13px 16px 13px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">E-POST</td>'
    ||       '<td style="padding:13px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;"><a href="mailto:' || e_email || '" style="color:#3E6B47;">' || e_email || '</a></td></tr>'
    ||     '<tr><td width="92" style="padding:13px 16px 13px 0;border-bottom:1px solid #ECE6DA;font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;vertical-align:top;">MOTTATT</td>'
    ||       '<td style="padding:13px 0;border-bottom:1px solid #ECE6DA;font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#15191A;">' || date_str || '</td></tr>'
    ||   '</table>'
    || '</td></tr>'
    || '<tr><td style="padding:22px 40px 40px;">'
    ||   '<div style="font-family:Courier,monospace;font-size:11px;letter-spacing:0.07em;color:#76776F;padding-bottom:10px;">MELDING</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.6;color:#15191A;background-color:#F2EDE3;border:1px solid #E4DAC8;padding:20px;">' || e_message || '</div>'
    || '</td></tr>'
    || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A;padding:26px 40px;">'
    ||   '<div style="font-family:Courier,monospace;font-size:10px;letter-spacing:0.14em;color:#5f6058;">AUTOMATISK VARSEL — WESTENGEN KLINIKK</div>'
    || '</td></tr>'
    || '</table></td></tr></table></body></html>';

  -- Send via Resend gjennom pg_net (asynkront). reply_to = kundens
  -- e-post så ansatte kan svare direkte.
  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'from',     from_email,
      'to',       notify_to,
      'reply_to', new.email,
      'subject',  'Ny henvendelse: ' || e_name,
      'html',     notify_html
    )
  );

  return new;

exception when others then
  -- E-post er sekundært: la meldingen lagres selv om varselet feiler
  -- (forventet i sandbox før domeneverifisering).
  raise notice 'send_contact_message_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$body$;
$func_def$;
  else
    raise notice 'send_contact_message_email finnes allerede — bevarer prod-versjon (antatt ekte nøkkel).';
  end if;
end
$do$;

-- Trigger: AFTER INSERT på hver melding. Inneholder ingen secret —
-- trygt å droppe/gjenskape; refererer kun funksjonen bevart over.
drop trigger if exists trg_contact_message_email on public.contact_messages;
create trigger trg_contact_message_email
  after insert on public.contact_messages
  for each row
  execute function public.send_contact_message_email();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Tabellen finnes:
--    select tablename from pg_tables
--     where schemaname='public' and tablename='contact_messages';   -- 1 rad
--
-- B) RLS på + 3 policies:
--    select policyname, cmd from pg_policies
--     where schemaname='public' and tablename='contact_messages'
--     order by policyname;
--    -- Forvent: anon insert contact_messages (INSERT),
--    --          contact_messages read: staff (SELECT),
--    --          contact_messages update: staff (UPDATE)
--
-- C) Grants er minimale (IKKE for vide — jf. 0037):
--    select grantee, string_agg(privilege_type, ',' order by privilege_type) as privs
--      from information_schema.role_table_grants
--     where table_schema='public' and table_name='contact_messages'
--       and grantee in ('anon','authenticated')
--     group by grantee order by grantee;
--    -- Forvent: anon=INSERT ; authenticated=SELECT,UPDATE
--    --          (INGEN DELETE/TRUNCATE/REFERENCES/TRIGGER/INSERT for authenticated)
--
-- D) E-postfunksjon finnes + bruker escaping (+ må reapply ekte nøkkel):
--    select case when prosrc ~ 'resend_key\s+text\s*:=\s*''re_'
--                then 'EKTE NØKKEL OK' else 'MÅ REAPPLY (placeholder)' end as nokkel,
--           prosrc ~ 'html_escape' as has_escape
--      from pg_proc where proname = 'send_contact_message_email';
--    -- Forvent: MÅ REAPPLY (placeholder) på fersk apply, has_escape = true
--
-- E) anon kan IKKE lese (via anon REST-klient):
--    -- GET /rest/v1/contact_messages  → [] (RLS blokkerer) / aldri andres rader
-- ============================================================
