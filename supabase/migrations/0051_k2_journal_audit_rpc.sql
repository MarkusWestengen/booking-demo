-- ============================================================
-- 0051_k2_journal_audit_rpc.sql                      2026-06-13
-- ------------------------------------------------------------
-- K2 fra security-review-2026-06-12: audit-logging av journal-
-- oppslag skjedde KUN i frontend-JS (shared/auth.js auditLog) —
-- en terapeut med sitt eget access_token kunne lese journalen
-- direkte via PostgREST uten at noe `journal_view`-spor oppstod.
-- Postgres kan ikke trigge på SELECT, så logging må gjøres
-- uatskillelig fra lesingen: en SECURITY DEFINER-RPC som skriver
-- audit_log og returnerer radene i SAMME funksjon, kombinert med
-- REVOKE av direkte tabelltilgang for authenticated.
--
-- Denne migrasjonen:
--   (a) get_journal_entries(p_email, p_phone): logger journal_view
--       og returnerer journaler scopet identisk med 0050-policyen
--       (admin: alt; therapist: egne notater + behandlingsrelasjon).
--       Aktør-identitet hentes fra JWT (app_metadata), ALDRI fra
--       klient-oppgitte parametre.
--   (b) create_journal_entry(...): oppretter notat med staff_id/
--       staff_name fra JWT (klienten kan ikke lenger skrive notater
--       i en annens navn) og logger journal_create i samme
--       transaksjon. Returnerer den nye raden (frontend trenger den
--       til UI-cache).
--   (c) revoke all on journal_entries from authenticated — all
--       lesing/skriving går nå via RPC-ene. RLS-policyene (0050/
--       0018) beholdes som defense-in-depth hvis grants gjeninnføres.
--
-- FRONTEND-IMPLIKASJON (samme commit):
--   - kunde-detalj.html + kalender.html: select → rpc('get_journal_entries')
--   - kalender.html saveNote: insert → rpc('create_journal_entry')
--   - klient-side auditLog('journal_view'/'journal_create') fjernes
--     (DB-laget logger nå autoritativt — unngår dobbeltlogging).
--   - shared/gdpr.js leser ikke lenger journal_entries direkte (0053).
--
-- search_path pinnes på begge DEFINER-funksjonene (regel for alle
-- SECURITY DEFINER i dette repoet, jf. 0016/0020).
--
-- Idempotent: create or replace + revoke/grant. Atomisk (begin/commit).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ============================================================
-- (a) Loggende lese-RPC
-- ============================================================
create or replace function public.get_journal_entries(
  p_email text default null,
  p_phone text default null
)
returns setof public.journal_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role       text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_staff_id   text := (auth.jwt() -> 'app_metadata' ->> 'staff_id');
  v_staff_name text := (auth.jwt() -> 'app_metadata' ->> 'staff_name');
  v_email      text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone      text := nullif(btrim(coalesce(p_phone, '')), '');
begin
  -- Kun ansatte med rolle. En selvregistrert konto uten app_metadata
  -- (K7-scenarioet) stoppes her — får aldri logget eller lest noe.
  if v_role is null or v_role not in ('admin', 'therapist') then
    raise exception 'Ingen tilgang til journal' using errcode = '42501';
  end if;

  if v_email is null and v_phone is null then
    return; -- ingenting å slå opp — ikke logg støy
  end if;

  -- Uatskillelig logg: skrives i samme funksjon/transaksjon som
  -- lesingen. Aktør fra JWT — kan ikke forfalskes av klienten.
  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata)
  values (
    coalesce(v_staff_id, case when v_role = 'admin' then 'admin' else 'unknown' end),
    coalesce(v_staff_name, case when v_role = 'admin' then 'Admin' else 'Ukjent' end),
    'journal_view',
    'patient',
    coalesce(v_email, v_phone),
    jsonb_build_object('via', 'rpc')
  );

  -- Samme scoping som 0050-policyen — håndhevet her fordi SECURITY
  -- DEFINER omgår RLS.
  return query
  select j.*
    from public.journal_entries j
   where (
           (v_email is not null and lower(j.patient_email) = v_email)
        or (v_phone is not null and j.patient_phone = v_phone)
         )
     and (
           v_role = 'admin'
        or j.staff_id = v_staff_id
        or exists (
             select 1
               from public.bookings b
              where b.staff_id = v_staff_id
                and (
                     (j.patient_email <> '' and lower(b.email) = lower(j.patient_email))
                  or (j.patient_phone <> '' and b.phone = j.patient_phone)
                )
           )
         )
   order by j.created_at desc;
end;
$$;

comment on function public.get_journal_entries(text, text) is
  'Eneste lesevei til journal_entries for frontend. Skriver journal_view '
  'til audit_log i samme transaksjon som lesingen (K2, helsepersonelloven '
  '§25 — logg som ikke kan omgås av den som logges). Scoping speiler '
  '0050-policyen. Lagt til i migrasjon 0051.';

-- ============================================================
-- (b) Loggende skrive-RPC
-- ============================================================
create or replace function public.create_journal_entry(
  p_booking_id    text,
  p_patient_email text,
  p_patient_phone text,
  p_content       text
)
returns public.journal_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role       text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_staff_id   text := (auth.jwt() -> 'app_metadata' ->> 'staff_id');
  v_staff_name text := (auth.jwt() -> 'app_metadata' ->> 'staff_name');
  v_row        public.journal_entries;
begin
  if v_role is null or v_role not in ('admin', 'therapist') then
    raise exception 'Ingen tilgang til journal' using errcode = '42501';
  end if;

  if p_content is null or length(btrim(p_content)) = 0 then
    raise exception 'Notatet kan ikke være tomt' using errcode = '23514';
  end if;

  -- Identitet fra JWT — samme fallback som frontend brukte, men nå
  -- server-autoritativt (klienten kan ikke skrive i en annens navn).
  insert into public.journal_entries
    (booking_id, patient_email, patient_phone, staff_id, staff_name, content)
  values (
    p_booking_id,
    lower(btrim(coalesce(p_patient_email, ''))),
    btrim(coalesce(p_patient_phone, '')),
    coalesce(v_staff_id, case when v_role = 'admin' then 'admin' else 'unknown' end),
    coalesce(v_staff_name, case when v_role = 'admin' then 'Admin' else 'Ukjent' end),
    btrim(p_content)
  )
  returning * into v_row;

  insert into public.audit_log
    (actor_staff_id, actor_staff_name, action, target_type, target_id, metadata)
  values (
    coalesce(v_staff_id, case when v_role = 'admin' then 'admin' else 'unknown' end),
    coalesce(v_staff_name, case when v_role = 'admin' then 'Admin' else 'Ukjent' end),
    'journal_create',
    'journal_entry',
    v_row.id::text,
    jsonb_build_object('booking_id', p_booking_id)
  );

  return v_row;
end;
$$;

comment on function public.create_journal_entry(text, text, text, text) is
  'Eneste skrivevei til journal_entries for frontend. staff_id/staff_name '
  'settes fra JWT (server-autoritativt) og journal_create logges i samme '
  'transaksjon. Lagt til i migrasjon 0051.';

-- ============================================================
-- (c) Grants: tabellen lukkes, RPC-ene åpnes
-- ============================================================
-- All frontend-tilgang går nå via RPC-ene. RLS-policyene beholdes
-- (defense-in-depth), men uten grants er direkte REST-kall mot
-- tabellen umulig for både anon (0027) og authenticated.
revoke all on public.journal_entries from anon, authenticated;

revoke execute on function public.get_journal_entries(text, text) from public, anon;
revoke execute on function public.create_journal_entry(text, text, text, text) from public, anon;
grant  execute on function public.get_journal_entries(text, text) to authenticated;
grant  execute on function public.create_journal_entry(text, text, text, text) to authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Direkte tabelltilgang er stengt:
--    select has_table_privilege('authenticated','public.journal_entries','select') as can_select,
--           has_table_privilege('authenticated','public.journal_entries','insert') as can_insert;
--    -- Forvent: f, f
--
-- B) RPC-ene er kallbare KUN for authenticated:
--    select has_function_privilege('authenticated','public.get_journal_entries(text,text)','execute') as auth_read,
--           has_function_privilege('anon','public.get_journal_entries(text,text)','execute')          as anon_read;
--    -- Forvent: t, f
--
-- C) Lesing logger (kjør med en ansatt-JWT via REST, IKKE SQL Editor):
--    POST /rest/v1/rpc/get_journal_entries {"p_email":"test@example.com"}
--    select action, target_id, created_at from audit_log
--     where action='journal_view' order by created_at desc limit 3;
--    -- Forvent: ny rad per kall.
--
-- D) Direkte GET /rest/v1/journal_entries?select=* med ansatt-JWT
--    -- Forvent: 403/permission denied (grant er borte).
-- ============================================================
