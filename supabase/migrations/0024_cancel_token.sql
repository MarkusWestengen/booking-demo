-- ============================================================
-- 0024_cancel_token.sql                              2026-05-20
-- ------------------------------------------------------------
-- Token-basert avbestillings-lenke (Fase 1).
--
-- Erik + Henrik ba om en "avbestillings-knapp" i bekreftelsen —
-- særlig for eldre kunder som synes ref + e-post-skjema er
-- tungvint. Denne migrasjonen legger til en unik, crypto-secure
-- token per booking + to RPC-er:
--   - lookup_booking_by_token : hent booking-info FØR avbestilling
--     (avbestill.html viser detaljer + bekreftelses-knapp)
--   - cancel_booking_by_token : avbestill med kun token
--
-- Token er et TILLEGG. cancel_booking_by_ref (0022) og hele
-- ref + e-post-flyten består uendret.
--
-- Fase 2 (senere, ikke her): samme lenke automatisk inn i
-- kunde-bekreftelses-e-posten når Resend-domenet er verifisert.
--
-- Idempotent: add column if not exists, create index if not
-- exists, create or replace function. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- Legg til kolonne med crypto-secure default
alter table public.bookings
  add column if not exists cancel_token uuid default gen_random_uuid();

-- Backfill: gi eksisterende rader en token
update public.bookings
   set cancel_token = gen_random_uuid()
 where cancel_token is null;

-- Gjør kolonnen NOT NULL etter backfill
alter table public.bookings
  alter column cancel_token set not null;

-- Indeks for rask token-oppslag (unique = ekstra trygghet mot kollisjon)
create unique index if not exists idx_bookings_cancel_token
  on public.bookings (cancel_token);

-- RPC: avbestill med kun token
create or replace function public.cancel_booking_by_token(p_token uuid)
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
   where cancel_token = p_token
   limit 1;

  if not found then
    return json_build_object('ok', false, 'reason', 'not_found');
  end if;

  if b.status = 'cancelled' then
    return json_build_object('ok', false, 'reason', 'already_cancelled');
  end if;

  if b.status = 'completed' then
    return json_build_object('ok', false, 'reason', 'already_completed');
  end if;

  if ((b.date + b.time) at time zone 'Europe/Oslo') < (now() + interval '24 hours') then
    return json_build_object('ok', false, 'reason', 'too_late');
  end if;

  update public.bookings set status = 'cancelled' where id = b.id;

  return json_build_object(
    'ok', true,
    'ref', b.ref,
    'date', b.date,
    'time', to_char(b.time, 'HH24:MI'),
    'staff_name', b.staff_name,
    'service_name', b.service_name
  );
end;
$$;

-- Verifikasjons-RPC for å hente booking-info FØR avbestilling
-- (slik at avbestill.html kan vise detaljer + bekreftelses-knapp)
create or replace function public.lookup_booking_by_token(p_token uuid)
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
   where cancel_token = p_token
   limit 1;

  if not found then
    return json_build_object('ok', false, 'reason', 'not_found');
  end if;

  return json_build_object(
    'ok', true,
    'ref', b.ref,
    'date', b.date,
    'time', to_char(b.time, 'HH24:MI'),
    'staff_name', b.staff_name,
    'service_name', b.service_name,
    'status', b.status
  );
end;
$$;

revoke execute on function public.cancel_booking_by_token(uuid) from public;
revoke execute on function public.lookup_booking_by_token(uuid) from public;
grant execute on function public.cancel_booking_by_token(uuid) to anon, authenticated;
grant execute on function public.lookup_booking_by_token(uuid) to anon, authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Kolonnen finnes + er NOT NULL:
--    select column_name, is_nullable
--      from information_schema.columns
--     where table_name='bookings' and column_name='cancel_token';
--    -- forvent: 1 rad, is_nullable = 'NO'
--
-- B) Begge RPC-ene finnes:
--    select proname from pg_proc
--     where proname in ('cancel_booking_by_token','lookup_booking_by_token');
--    -- forvent: 2 rader
--
-- C) anon kan kalle begge:
--    select has_function_privilege('anon','public.cancel_booking_by_token(uuid)','execute'),
--           has_function_privilege('anon','public.lookup_booking_by_token(uuid)','execute');
--    -- forvent: t, t
--
-- D) Ukjent token:
--    select public.lookup_booking_by_token(gen_random_uuid());
--    -- {"ok":false,"reason":"not_found"}
-- ============================================================
