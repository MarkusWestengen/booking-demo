-- ============================================================
-- Westengen Klinikk — Omtrentlig kø-posisjon på venteliste
-- Migration 0035
-- ------------------------------------------------------------
-- N3 (2026-06-01): kunden vil se «omtrent nr. X på listen» etter
-- påmelding. Ventelista er IKKE en ren FIFO-kø (tildeling avhenger av
-- ønsket tid/behandler og gjøres manuelt av admin), så posisjonen er
-- BEVISST omtrentlig — beregnet innen samme behandler-segment.
--
-- Hvorfor RPC: anon-RLS (0023) lar IKKE en innsender lese andres
-- waitlist-rader, så posisjon kan ikke telles klientside. Denne
-- SECURITY DEFINER-funksjonen kjører med eier-rettigheter, men
-- returnerer KUN ett heltall — aldri andres data.
--
-- Posisjon = antall ventende rader (status='waiting') i samme
-- staff_id-segment ('erik' vs NULL=terapeut) med created_at <= egen
-- (dvs. 1-basert, inkluderer raden selv). NULL hvis ref ikke finnes
-- eller ikke lenger venter.
--
-- Idempotent (create or replace). Avhenger av waitlist (0023, applisert).
-- Apply: lim inn i Supabase Dashboard → SQL Editor → kjør.
-- "Success. No rows returned." = OK.
-- ============================================================

begin;

create or replace function public.get_waitlist_position(p_ref text)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_staff   text;
  v_created timestamptz;
  v_pos     int;
begin
  -- Finn raden det spørres om. Returner NULL hvis den ikke finnes
  -- eller ikke lenger står som ventende (da gir posisjon ikke mening).
  select staff_id, created_at
    into v_staff, v_created
  from public.waitlist
  where ref = p_ref and status = 'waiting'
  limit 1;

  if not found then
    return null;
  end if;

  -- Tell ventende foran/på samme plass i samme behandler-segment.
  -- `is not distinct from` håndterer NULL-segmentet (terapeut-køen).
  select count(*)::int
    into v_pos
  from public.waitlist
  where status = 'waiting'
    and staff_id is not distinct from v_staff
    and created_at <= v_created;

  return v_pos;
end;
$$;

-- Kun ett heltall returneres — trygt å eksponere for anon.
revoke all on function public.get_waitlist_position(text) from public;
grant execute on function public.get_waitlist_position(text) to anon, authenticated;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--   select public.get_waitlist_position('TA-WL-XXXX-XXXX');
--   → heltall (1 = fremst i sitt segment), eller NULL hvis ukjent ref.
--
-- Som anon (anon-nøkkel) via RPC:
--   rpc('get_waitlist_position', { p_ref: '...' })  → kun tallet.
--   Ingen tilgang til andre kolonner/rader bekreftes ved at direkte
--   SELECT mot waitlist fortsatt blokkeres av RLS for anon.
-- ============================================================
