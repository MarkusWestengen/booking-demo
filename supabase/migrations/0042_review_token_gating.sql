-- ============================================================
-- 0042_review_token_gating.sql                       2026-06-04
-- ------------------------------------------------------------
-- Anmeldelse-gating: bare kunder som faktisk har hatt en time
-- skal kunne legge igjen en anmeldelse. (Gruppe C, del 1 av 2.)
--
-- Før denne migrasjonen kunne HVEM SOM HELST sende inn en anmeldelse
-- (anon INSERT på reviews, RLS gated kun til status='pending').
-- Nå kreves et unikt, crypto-secure `review_token` per booking, og
-- innsending går KUN gjennom en SECURITY DEFINER-RPC som validerer at:
--   - token matcher en faktisk booking,
--   - timen er IKKE avlyst / no_show,
--   - timen er FAKTISK avsluttet (starttid passert),
--   - bookingen er IKKE allerede anmeldt (én anmeldelse per booking).
--
-- Speiler token-mønsteret fra 0024_cancel_token.sql (cancel_token) og
-- følger 0037-lærdommen: revoke-all/over-grant FØRST, deretter minste
-- nødvendige grants.
--
-- Tidsbasert e-postutsending av selve lenken ligger i 0043 (egen fil).
--
-- Idempotent: add column/constraint/index if not exists,
-- create or replace function, drop policy if exists. Atomisk (begin/commit).
-- ⚠️ IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- AVHENGER AV: 0034 (reviews-tabell) + 0037 (grants). Apply ETTER 0041.
-- ============================================================

begin;

-- ----- (a) review_token på bookings (speiler cancel_token, 0024) -----
alter table public.bookings
  add column if not exists review_token uuid default gen_random_uuid();

-- Backfill eksisterende rader
update public.bookings
   set review_token = gen_random_uuid()
 where review_token is null;

alter table public.bookings
  alter column review_token set not null;

create unique index if not exists idx_bookings_review_token
  on public.bookings (review_token);

-- ----- (b) reviews.booking_id: kobling + «én anmeldelse per booking» -----
-- ⚠️ bookings.id er TEXT i dette prosjektet (ikke uuid) — jf.
-- 0001_journal_entries.sql: `booking_id text references public.bookings(id)`.
-- booking_id MÅ derfor være text for at FK-en kan opprettes.
alter table public.reviews
  add column if not exists booking_id text;

-- FK med ON DELETE SET NULL: sletter man en booking, beholdes anmeldelsen
-- (mister bare koblingen). Idempotent via pg_constraint-sjekk.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'reviews_booking_id_fkey'
  ) then
    alter table public.reviews
      add constraint reviews_booking_id_fkey
      foreign key (booking_id) references public.bookings(id) on delete set null;
  end if;
end $$;

-- Partial unique: maks én anmeldelse per booking. NULL (eldre, pre-gating
-- anmeldelser) er unntatt, så historiske rader ikke kolliderer.
create unique index if not exists idx_reviews_booking_id
  on public.reviews (booking_id) where booking_id is not null;

-- ----- (c) GATING: fjern direkte anon-INSERT -----
-- Uten INSERT-privilegiet kan anon ikke lenger skrive til reviews i det
-- hele tatt — all innsending må gå via submit_review_by_token (DEFINER).
-- SELECT beholdes (forsiden leser godkjente anmeldelser som anon).
revoke insert on public.reviews from anon;

-- Den gamle anon-insert-policyen blir meningsløs uten grantet; fjern den
-- så RLS-bildet er rent. (Lese-/admin-policyene fra 0034 røres IKKE.)
drop policy if exists "reviews: anon insert pending" on public.reviews;

-- ----- (d) RPC: send inn anmeldelse med gyldig token -----
create or replace function public.submit_review_by_token(
  p_token  uuid,
  p_name   text,
  p_rating int,
  p_body   text
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  b public.bookings%rowtype;
begin
  -- Input-validering (samme regler som frontend, men håndhevet i DB).
  if p_rating is null or p_rating < 1 or p_rating > 5 then
    return json_build_object('ok', false, 'reason', 'bad_rating');
  end if;
  if p_body is null or length(btrim(p_body)) = 0 then
    return json_build_object('ok', false, 'reason', 'no_body');
  end if;

  select * into b
    from public.bookings
   where review_token = p_token
   limit 1;

  if not found then
    return json_build_object('ok', false, 'reason', 'not_found');
  end if;

  if b.status in ('cancelled', 'no_show') then
    return json_build_object('ok', false, 'reason', 'not_eligible');
  end if;

  -- Timen må faktisk ha startet (vi tillater anmeldelse fra starttidspunktet
  -- og utover; e-posten sendes uansett først ~1t etter, jf. 0043).
  if ((b.date + b.time) at time zone 'Europe/Oslo') > now() then
    return json_build_object('ok', false, 'reason', 'too_early');
  end if;

  if exists (select 1 from public.reviews where booking_id = b.id) then
    return json_build_object('ok', false, 'reason', 'already_reviewed');
  end if;

  insert into public.reviews (name, rating, body, booking_id, status)
  values (nullif(btrim(p_name), ''), p_rating, btrim(p_body), b.id, 'pending');

  return json_build_object('ok', true);

exception
  -- Race: to samtidige innsendinger for samme booking → unik-indeksen
  -- fanger den andre. Returner pent i stedet for en rå feil.
  when unique_violation then
    return json_build_object('ok', false, 'reason', 'already_reviewed');
end;
$$;

-- ----- (e) RPC: valider token FØR skjemaet vises (frontend-bruk) -----
create or replace function public.lookup_review_by_token(p_token uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  b public.bookings%rowtype;
begin
  select * into b
    from public.bookings
   where review_token = p_token
   limit 1;

  if not found then
    return json_build_object('ok', false, 'reason', 'not_found');
  end if;
  if b.status in ('cancelled', 'no_show') then
    return json_build_object('ok', false, 'reason', 'not_eligible');
  end if;
  if ((b.date + b.time) at time zone 'Europe/Oslo') > now() then
    return json_build_object('ok', false, 'reason', 'too_early');
  end if;
  if exists (select 1 from public.reviews where booking_id = b.id) then
    return json_build_object('ok', false, 'reason', 'already_reviewed');
  end if;

  -- Kun ufarlig kontekst returneres (ingen e-post/telefon).
  return json_build_object(
    'ok', true,
    'staff_name', b.staff_name,
    'service_name', b.service_name,
    'date', b.date
  );
end;
$$;

-- ----- (f) Grants: revoke fra public, grant KUN anon (minste nødvendige) -----
revoke execute on function public.submit_review_by_token(uuid, text, int, text) from public;
revoke execute on function public.lookup_review_by_token(uuid) from public;
grant  execute on function public.submit_review_by_token(uuid, text, int, text) to anon;
grant  execute on function public.lookup_review_by_token(uuid) to anon;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) review_token finnes + NOT NULL:
--    select is_nullable from information_schema.columns
--     where table_name='bookings' and column_name='review_token';
--    -- forvent: 'NO'
--
-- B) anon kan IKKE lenger INSERT direkte på reviews:
--    select privilege_type from information_schema.role_table_grants
--     where table_schema='public' and table_name='reviews' and grantee='anon';
--    -- forvent: KUN SELECT (ingen INSERT)
--
-- C) Begge RPC-ene finnes + anon kan kalle dem:
--    select has_function_privilege('anon','public.submit_review_by_token(uuid,text,int,text)','execute'),
--           has_function_privilege('anon','public.lookup_review_by_token(uuid)','execute');
--    -- forvent: t, t
--
-- D) Ukjent token:
--    select public.lookup_review_by_token(gen_random_uuid());
--    -- {"ok":false,"reason":"not_found"}
--
-- E) Ekte token (hent en avsluttet booking):
--    select public.lookup_review_by_token(review_token)
--      from public.bookings
--     where ((date + time) at time zone 'Europe/Oslo') < now()
--       and status in ('confirmed','completed') limit 1;
--    -- {"ok":true,"staff_name":...}  (eller already_reviewed hvis alt anmeldt)
--
-- F) Innsending via RPC (anon-nøkkel) med samme token → {"ok":true};
--    ny innsending med samme token → {"ok":false,"reason":"already_reviewed"}.
-- ============================================================
