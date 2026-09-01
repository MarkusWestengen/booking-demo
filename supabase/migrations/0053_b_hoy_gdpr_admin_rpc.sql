-- ============================================================
-- 0053_b_hoy_gdpr_admin_rpc.sql                      2026-06-13
-- ------------------------------------------------------------
-- Lukker fire GDPR-funn fra security-review-2026-06-12 i én RPC-pakke:
--   - [A-HØY]  Pseudonymisering/eksport var kun UI-gated
--     (data-admin-only) — en terapeut kunne kalle gdpr.js-funksjonene
--     fra konsollen. Nå: rolle='admin' håndheves i DB.
--   - [B-HØY]  Pseudonymisering var ufullstendig — etterlot ekte
--     PII i waitlist, contact_messages, document_sends, reviews og
--     audit_log.target_id. Nå: alle registre nullstilles i samme kall.
--   - [B-MEDIUM] Flyten var flere uavhengige klient-kall (ikke
--     atomisk). Nå: én funksjon = én transaksjon, alt-eller-ingenting.
--   - [B-LAV]  Usaltet SHA-256 av e-post i audit-metadata (trivielt
--     reverserbar). Nå: hashen er droppet — kun pseudonym_id logges.
--
-- audit_log-noten: tabellen er append-only via API (ingen UPDATE-
-- policy/grants), men SECURITY DEFINER kjører som eier og kan rette
-- target_id ved sletting — det er nettopp slik «append-only for
-- aktører, korrigerbar ved lovpålagt sletting» skal fungere.
-- gdpr_erase oppdaterer KUN target_id (til pseudonymet) — handling,
-- aktør og tidspunkt består, så sporbarheten er intakt.
--
-- Journal-INNHOLD bevares bevisst (helsepersonelloven § 39–40, 10 års
-- oppbevaringsplikt) — kun identifikatorene (patient_email/phone)
-- pseudonymiseres, som før.
--
-- reviews: name pseudonymiseres for anmeldelser koblet til pasientens
-- bookinger. body (fritekst skrevet av kunden selv) beholdes, men
-- flagges i retur-payloaden så operatør kan vurdere manuell sletting
-- hvis teksten identifiserer kunden.
--
-- FRONTEND-IMPLIKASJON (samme commit): shared/gdpr.js skrives om til
-- å kalle disse RPC-ene i stedet for direkte tabell-kall (nødvendig
-- uansett — 0051 fjernet authenticated sin direkte journal-tilgang).
--
-- Idempotent: create or replace + revoke/grant. Atomisk (begin/commit).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- AVHENGER AV: 0039 (contact_messages), 0040 (document_sends).
-- ============================================================

begin;

-- ============================================================
-- (a) gdpr_export_patient — GDPR art. 15 (innsyn/dataportabilitet)
-- ============================================================
create or replace function public.gdpr_export_patient(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role       text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_staff_id   text := (auth.jwt() -> 'app_metadata' ->> 'staff_id');
  v_staff_name text := (auth.jwt() -> 'app_metadata' ->> 'staff_name');
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_payload    jsonb;
begin
  if v_role is distinct from 'admin' then
    raise exception 'Kun admin kan eksportere pasientdata' using errcode = '42501';
  end if;
  if v_email = '' then
    raise exception 'Mangler e-post' using errcode = '22023';
  end if;

  select jsonb_build_object(
    'patient_email', v_email,
    'bookings',         coalesce((select jsonb_agg(to_jsonb(t) order by t.date)
                                    from public.bookings t
                                   where lower(t.email) = v_email), '[]'::jsonb),
    'journal_entries',  coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at)
                                    from public.journal_entries t
                                   where lower(t.patient_email) = v_email), '[]'::jsonb),
    'audit_log',        coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at)
                                    from public.audit_log t
                                   where lower(coalesce(t.target_id, '')) = v_email), '[]'::jsonb),
    'waitlist',         coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at)
                                    from public.waitlist t
                                   where lower(t.email) = v_email), '[]'::jsonb),
    'contact_messages', coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at)
                                    from public.contact_messages t
                                   where lower(t.email) = v_email), '[]'::jsonb),
    'document_sends',   coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at)
                                    from public.document_sends t
                                   where lower(t.customer_email) = v_email), '[]'::jsonb),
    'reviews',          coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at)
                                    from public.reviews t
                                   where t.booking_id in (select id from public.bookings
                                                           where lower(email) = v_email)), '[]'::jsonb)
  ) into v_payload;

  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata)
  values (
    coalesce(v_staff_id, 'admin'),
    coalesce(v_staff_name, 'Admin'),
    'gdpr_export',
    'patient',
    v_email,
    jsonb_build_object(
      'bookings_count',         jsonb_array_length(v_payload -> 'bookings'),
      'journal_entries_count',  jsonb_array_length(v_payload -> 'journal_entries'),
      'audit_log_count',        jsonb_array_length(v_payload -> 'audit_log'),
      'waitlist_count',         jsonb_array_length(v_payload -> 'waitlist'),
      'contact_messages_count', jsonb_array_length(v_payload -> 'contact_messages'),
      'document_sends_count',   jsonb_array_length(v_payload -> 'document_sends'),
      'reviews_count',          jsonb_array_length(v_payload -> 'reviews')
    )
  );

  return v_payload;
end;
$$;

comment on function public.gdpr_export_patient(text) is
  'Admin-only GDPR art. 15-eksport på tvers av ALLE registre (bookings, '
  'journal, audit, waitlist, contact, document_sends, reviews). Logger '
  'gdpr_export i samme transaksjon. Migrasjon 0053.';

-- ============================================================
-- (b) gdpr_erase_patient — GDPR art. 17 (pseudonymisering/sletting)
-- ============================================================
create or replace function public.gdpr_erase_patient(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role       text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_staff_id   text := (auth.jwt() -> 'app_metadata' ->> 'staff_id');
  v_staff_name text := (auth.jwt() -> 'app_metadata' ->> 'staff_name');
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_pseudo     text := 'pseudonym_' || gen_random_uuid()::text;
  v_pseudo_em  text;
  n_bookings   int; n_journal int; n_waitlist int; n_contact int;
  n_docsends   int; n_reviews int; n_audit int;
begin
  if v_role is distinct from 'admin' then
    raise exception 'Kun admin kan pseudonymisere pasientdata' using errcode = '42501';
  end if;
  if v_email = '' then
    raise exception 'Mangler e-post' using errcode = '22023';
  end if;

  v_pseudo_em := v_pseudo || '@anon.local';

  -- reviews FØRST (slår opp via bookings-e-posten som straks byttes ut).
  update public.reviews
     set name = 'Pseudonymisert'
   where booking_id in (select id from public.bookings where lower(email) = v_email);
  get diagnostics n_reviews = row_count;

  update public.bookings
     set name = 'Pseudonymisert', email = v_pseudo_em, phone = '000000000', notes = null
   where lower(email) = v_email;
  get diagnostics n_bookings = row_count;

  update public.journal_entries
     set patient_email = v_pseudo_em, patient_phone = '000000000'
   where lower(patient_email) = v_email;
  get diagnostics n_journal = row_count;

  update public.waitlist
     set name = 'Pseudonymisert', email = v_pseudo_em, phone = '000000000', notes = null
   where lower(email) = v_email;
  get diagnostics n_waitlist = row_count;

  update public.contact_messages
     set name = 'Pseudonymisert', email = v_pseudo_em,
         message = '[Slettet etter GDPR art. 17-forespørsel]'
   where lower(email) = v_email;
  get diagnostics n_contact = row_count;

  -- link_url tømmes også: den signerte URL-en er en bearer-lenke og
  -- skal ikke bli liggende knyttet til en slettet person.
  update public.document_sends
     set customer_email = v_pseudo_em, link_url = ''
   where lower(customer_email) = v_email;
  get diagnostics n_docsends = row_count;

  -- audit_log: target_id var rå e-post (B-HØY pkt. 1). Bytt til
  -- pseudonymet — handling/aktør/tid består, identiteten er borte.
  update public.audit_log
     set target_id = v_pseudo
   where lower(coalesce(target_id, '')) = v_email;
  get diagnostics n_audit = row_count;

  if n_bookings + n_journal + n_waitlist + n_contact + n_docsends + n_audit = 0 then
    raise exception 'Fant ingen rader for denne e-posten' using errcode = 'P0002';
  end if;

  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata)
  values (
    coalesce(v_staff_id, 'admin'),
    coalesce(v_staff_name, 'Admin'),
    'gdpr_pseudonymize',
    'patient',
    v_pseudo,
    jsonb_build_object(
      'pseudonym_id', v_pseudo,
      'bookings_updated', n_bookings,
      'journals_updated', n_journal,
      'waitlist_updated', n_waitlist,
      'contact_messages_updated', n_contact,
      'document_sends_updated', n_docsends,
      'reviews_updated', n_reviews,
      'audit_rows_retargeted', n_audit
    )
  );

  return jsonb_build_object(
    'ok', true,
    'pseudonym_id', v_pseudo,
    'bookings_updated', n_bookings,
    'journals_updated', n_journal,
    'waitlist_updated', n_waitlist,
    'contact_messages_updated', n_contact,
    'document_sends_updated', n_docsends,
    'reviews_updated', n_reviews,
    'audit_rows_retargeted', n_audit,
    -- Resterende manuelle steg — vises av frontend/operatør:
    'manual_followup', jsonb_build_array(
      'Sjekk reviews-fritekst manuelt hvis kunden kan identifiseres av egen tekst',
      'Slett kundens e-poster i Resend-loggen (ekstern retensjon)'
    )
  );
end;
$$;

comment on function public.gdpr_erase_patient(text) is
  'Admin-only, atomisk GDPR art. 17-pseudonymisering på tvers av bookings, '
  'journal_entries, waitlist, contact_messages, document_sends, reviews og '
  'audit_log.target_id. Journal-INNHOLD bevares (hpl. § 39, 10 år). '
  'Migrasjon 0053.';

-- ============================================================
-- (c) Grants — kallbar kun for authenticated (admin-sjekk i funksjonen)
-- ============================================================
revoke execute on function public.gdpr_export_patient(text) from public, anon;
revoke execute on function public.gdpr_erase_patient(text)  from public, anon;
grant  execute on function public.gdpr_export_patient(text) to authenticated;
grant  execute on function public.gdpr_erase_patient(text)  to authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Terapeut-JWT: POST /rest/v1/rpc/gdpr_export_patient {"p_email":"x@y.example"}
--    -- Forvent: 403 'Kun admin kan eksportere pasientdata'.
--
-- B) Admin-JWT: samme kall → jsonb med alle 7 registre + ny
--    gdpr_export-rad i audit_log.
--
-- C) Pseudonymiser en TESTKUNDE (admin-JWT):
--    POST /rest/v1/rpc/gdpr_erase_patient {"p_email":"test@example.com"}
--    Deretter residual-sjekk (V12 fra revisjonen):
--    select 'bookings' t, count(*) from bookings where lower(email)='test@example.com'
--    union all select 'waitlist', count(*) from waitlist where lower(email)='test@example.com'
--    union all select 'contact', count(*) from contact_messages where lower(email)='test@example.com'
--    union all select 'docsends', count(*) from document_sends where lower(customer_email)='test@example.com'
--    union all select 'audit', count(*) from audit_log where lower(coalesce(target_id,''))='test@example.com';
--    -- Forvent: 0 på alle.
-- ============================================================
