-- ============================================================
-- 0052_k3_k4_anon_rate_limit.sql                     2026-06-13
-- ------------------------------------------------------------
-- K3 + K4 (+ G-HØY contact-flom, G-MEDIUM waitlist-flom) fra
-- security-review-2026-06-12: anon kan POST-e ubegrenset mange
-- rader direkte mot PostgREST:
--   - K4: ~500 bookings-INSERTs fyller hele kalenderen (DoS).
--   - K3: når kunde-bekreftelse (0048) en gang appliseres, blir
--     hver INSERT også en e-post fra klinikkens domene til en
--     vilkårlig adresse (backscatter/amplifisering). 0048 skal
--     IKKE appliseres før denne kvoten + Turnstile er på plass.
--   - G: contact_messages-INSERT fyrer e-post til klinikken i dag
--     → innboks-/Resend-kvote-storm. waitlist fyller admin-UI.
--
-- Tiltak (DB-laget, kan ikke omgås av rått REST-kall):
--   (a) Kvote-tabell + BEFORE INSERT-trigger som teller anon-
--       inserts per kilde-IP (PostgREST eksponerer x-forwarded-for
--       via request.headers) og globalt per tabell, innenfor et
--       glidende vindu. Overskridelse → exception → 0 rader, 0
--       e-poster. Gjelder KUN anon — admin/terapeut-flyter urørt.
--   (b) Strammere WITH CHECK på "anon insert bookings": dato må
--       være i dag..+365, klokkeslett innenfor 06–22, og staff_id
--       må (om satt) finnes blant aktive behandlere. Stopper
--       fortid-/nonsens-rader som aldri kan være legitime.
--
-- Kvotene er rause for en klinikk (ingen legitim kunde sender 5
-- bookinger på en time fra samme IP), men gjør masse-spam dyrt:
-- kalender-fylling går fra «sekunder, gratis» til «dager, og
-- admin rekker å se det».
--
-- Dette er interimsvernet anbefalt i revisjonen. Full løsning er
-- Cloudflare Turnstile + create_booking_verified-RPC (eget spor,
-- se operator-checklist-2026-06-13.md).
--
-- Idempotent: create table/index if not exists, create or replace,
-- drop/create trigger + policy. Atomisk (begin/commit).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ============================================================
-- (a1) Kvote-logg. Kun DEFINER-funksjonen skriver/leser — ingen
--      grants, RLS på uten policyer = deny-all for anon/authenticated.
-- ============================================================
create table if not exists public.anon_insert_events (
  id         bigint generated always as identity primary key,
  bucket     text not null,                -- 'bookings' | 'contact' | 'waitlist'
  ip         text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_anon_insert_events_window
  on public.anon_insert_events (bucket, created_at desc);
create index if not exists idx_anon_insert_events_ip
  on public.anon_insert_events (bucket, ip, created_at desc);

revoke all on public.anon_insert_events from anon, authenticated, public;
alter table public.anon_insert_events enable row level security;

-- ============================================================
-- (a2) Trigger-funksjon. Args: bucket, per-IP-grense, global
--      grense, vindu i minutter. SECURITY DEFINER fordi anon ikke
--      har (og ikke skal ha) tilgang til kvote-tabellen.
-- ============================================================
create or replace function public.enforce_anon_insert_quota()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bucket   text     := tg_argv[0];
  v_ip_limit int      := tg_argv[1]::int;
  v_glob_lim int      := tg_argv[2]::int;
  v_window   interval := make_interval(mins => tg_argv[3]::int);
  v_ip       text;
  v_ip_count int;
  v_glob     int;
begin
  -- Kvoten gjelder KUN anon-rollen. Ansatte (authenticated) og
  -- SQL Editor/migrasjoner (ingen request-JWT) passerer fritt.
  if coalesce(auth.jwt() ->> 'role', '') <> 'anon' then
    return new;
  end if;

  -- Kilde-IP fra PostgREST sine request-headers. Mangler den
  -- (eller parsing feiler) deles én felles 'unknown'-kvote —
  -- fail-closed-ish: misbruk uten IP-header får ikke fri bane.
  begin
    v_ip := btrim(split_part(coalesce(
              current_setting('request.headers', true)::json ->> 'x-forwarded-for',
            ''), ',', 1));
  exception when others then
    v_ip := '';
  end;
  if v_ip is null or v_ip = '' then v_ip := 'unknown'; end if;

  -- Husholdning: kast hendelser eldre enn 24t (tabellen forblir bitteliten).
  delete from public.anon_insert_events where created_at < now() - interval '24 hours';

  select count(*) into v_ip_count
    from public.anon_insert_events
   where bucket = v_bucket and ip = v_ip and created_at > now() - v_window;

  select count(*) into v_glob
    from public.anon_insert_events
   where bucket = v_bucket and created_at > now() - v_window;

  if v_ip_count >= v_ip_limit or v_glob >= v_glob_lim then
    raise exception 'For mange forespørsler — vent litt og prøv igjen, eller ring klinikken på +47 400 00 000.'
      using errcode = '53400'; -- configuration_limit_exceeded
  end if;

  insert into public.anon_insert_events (bucket, ip) values (v_bucket, v_ip);
  return new;
end;
$$;

comment on function public.enforce_anon_insert_quota() is
  'BEFORE INSERT-kvote for anon-flater (K3/K4/G fra revisjon 2026-06-12). '
  'Args: bucket, per-IP-grense, global grense, vindu (minutter). Teller i '
  'public.anon_insert_events. Gjelder kun JWT-rolle anon. Migrasjon 0052.';

revoke execute on function public.enforce_anon_insert_quota()
  from anon, authenticated, public;

-- ----- Triggere per anon-flate --------------------------------
-- bookings: maks 5/time per IP, 20/time globalt.
drop trigger if exists trg_anon_quota_bookings on public.bookings;
create trigger trg_anon_quota_bookings
  before insert on public.bookings
  for each row
  execute function public.enforce_anon_insert_quota('bookings', '5', '20', '60');

-- contact_messages: maks 3/time per IP, 15/time globalt.
drop trigger if exists trg_anon_quota_contact on public.contact_messages;
create trigger trg_anon_quota_contact
  before insert on public.contact_messages
  for each row
  execute function public.enforce_anon_insert_quota('contact', '3', '15', '60');

-- waitlist: maks 3/time per IP, 15/time globalt.
drop trigger if exists trg_anon_quota_waitlist on public.waitlist;
create trigger trg_anon_quota_waitlist
  before insert on public.waitlist
  for each row
  execute function public.enforce_anon_insert_quota('waitlist', '3', '15', '60');

-- ============================================================
-- (b) Strammere WITH CHECK på anon booking-INSERT
-- ------------------------------------------------------------
-- Viderefører ALLE krav fra 0027 (+ 0020 sin nullable staff_id),
-- og legger til:
--   - date i [i dag, +365] (ingen fortids-/evighetsrader)
--   - time innenfor 06:00–22:00 (utenfor kan aldri være en reell slot)
--   - staff_id, om satt, må være en aktiv behandler (anon sin RLS
--     på staff_members viser kun aktive — exists-en evalueres som
--     anon). NULL = ufordelt pool-booking, fortsatt lov (0020).
-- ============================================================
drop policy if exists "anon insert bookings" on public.bookings;
create policy "anon insert bookings" on public.bookings
  for insert to anon
  with check (
    status = 'confirmed'
    and length(coalesce(name, '')) between 1 and 200
    and length(coalesce(email, '')) between 3 and 254
    and length(coalesce(phone, '')) between 3 and 30
    and service_id is not null
    and date is not null
    and "time" is not null
    -- System-felter må ikke settes av anon (0027)
    and reminder_sent_at is null
    and (notes is null or length(notes) <= 2000)
    and journal_consent is not null
    -- Nytt i 0052 (K3/K4):
    and date >= current_date
    and date <= current_date + 365
    and "time" >= time '06:00'
    and "time" <= time '22:00'
    and (
      staff_id is null
      or exists (select 1 from public.staff_members sm where sm.staff_id = bookings.staff_id)
    )
  );

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Triggere finnes:
--    select tgname, tgrelid::regclass from pg_trigger
--     where tgname like 'trg_anon_quota_%' order by tgname;
--    -- Forvent 3 rader (bookings, contact_messages, waitlist).
--
-- B) Policy har de nye leddene:
--    select with_check from pg_policies
--     where tablename='bookings' and policyname='anon insert bookings';
--    -- Forvent: inneholder current_date, '06:00', staff_members.
--
-- C) Kvote-smoke (med anon-nøkkel via REST — IKKE SQL Editor):
--    POST /rest/v1/contact_messages 4 ganger på rad fra samme IP
--    -- Forvent: 3 × 201, deretter 4xx med 'For mange forespørsler'.
--    Rydd test-radene etterpå.
--
-- D) Fortidsbooking avvises (anon REST):
--    POST /rest/v1/bookings med date=i går → 403 (RLS with check).
--
-- E) Ansatt-flyt upåvirket: opprett booking i booking-admin → OK
--    (authenticated treffer aldri kvoten).
-- ============================================================
