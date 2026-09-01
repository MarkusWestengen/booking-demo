-- ============================================================
-- 0022_cancel_booking_rpc.sql                        2026-05-20
-- ------------------------------------------------------------
-- Kunde-avbestilling: en SECURITY DEFINER-RPC som lar en kunde
-- avbestille sin egen time fra avbestill.html — uten innlogging,
-- og uten at anon får UPDATE-tilgang på bookings-tabellen.
--
-- Kunden oppgir referansekode (TA-XXXX-XXXX) + e-post. RPC-en
-- verifiserer paret, sjekker status + 24-timers-frist, og setter
-- status = 'cancelled'.
--
-- Sikkerhet:
--   - SECURITY DEFINER: kjører som eier, så UPDATE går forbi RLS
--     (anon har ingen UPDATE-policy på bookings etter 0010).
--     Selve RPC-en ER tilgangskontrollen: (ref + e-post)-paret.
--   - not_found returneres UNIFORMT enten ref ikke finnes ELLER
--     e-post ikke matcher — så responsen ikke kan brukes som
--     oracle for å finne gyldige referansekoder.
--   - search_path pinnet (linter function_search_path_mutable).
--   - REVOKE fra PUBLIC; kun anon + authenticated får EXECUTE.
--
-- 24-timers-frist: bookingens (date + time) tolkes som Europe/Oslo
-- lokaltid (klinikken ligger i Oslo) og må være > now() + 24t.
--
-- Idempotent: CREATE OR REPLACE. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

create or replace function public.cancel_booking_by_ref(
  p_ref   text,
  p_email text
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  b public.bookings%rowtype;
begin
  -- Slå opp på ref + e-post (case-insensitiv e-post).
  select * into b
    from public.bookings
   where ref = p_ref
     and lower(email) = lower(coalesce(p_email, ''))
   limit 1;

  -- Uniform not_found: skiller ikke "ref finnes ikke" fra "ref
  -- finnes, men feil e-post" — unngår oracle-angrep mot ref-koder.
  if not found then
    return json_build_object('ok', false, 'reason', 'not_found');
  end if;

  if b.status = 'cancelled' then
    return json_build_object('ok', false, 'reason', 'already_cancelled');
  end if;

  if b.status = 'completed' then
    return json_build_object('ok', false, 'reason', 'already_completed');
  end if;

  -- 24-timers-frist. (date + time) tolkes som Oslo-lokaltid.
  if ((b.date + b.time) at time zone 'Europe/Oslo') < (now() + interval '24 hours') then
    return json_build_object('ok', false, 'reason', 'too_late');
  end if;

  update public.bookings
     set status = 'cancelled'
   where id = b.id;

  return json_build_object(
    'ok',         true,
    'ref',        b.ref,
    'date',       b.date,
    'time',       to_char(b.time, 'HH24:MI'),
    'staff_name', b.staff_name
  );
end;
$$;

comment on function public.cancel_booking_by_ref(text, text) is
  'Kunde-avbestilling via avbestill.html. Verifiserer (ref, e-post), '
  'sjekker status + 24-timers-frist (Europe/Oslo), setter '
  'status=cancelled. not_found returneres uniformt (ingen oracle). '
  'Lagt til i migrasjon 0022.';

-- Kun anon + authenticated kan kalle RPC-en; ikke PUBLIC.
revoke execute on function public.cancel_booking_by_ref(text, text) from public;
grant  execute on function public.cancel_booking_by_ref(text, text) to anon, authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Funksjonen er kallbar av anon:
--    select has_function_privilege(
--      'anon', 'public.cancel_booking_by_ref(text,text)', 'execute');
--    -- Forvent: t
--
-- B) Uniform not_found (ingen oracle):
--    select public.cancel_booking_by_ref('TA-FINNES-IKKE', 'x@y.example');
--    -- Forvent: {"ok":false,"reason":"not_found"}
--
-- C) Smoke-test med en ekte framtidig test-booking:
--    select public.cancel_booking_by_ref('TA-XXXX-XXXX', 'kunde@eksempel.example');
--    -- Forvent: {"ok":true,"ref":...,"date":...,"time":...,"staff_name":...}
--    -- Verifiser så: select status from public.bookings where ref='TA-XXXX-XXXX';
--    --   → 'cancelled'
-- ============================================================
