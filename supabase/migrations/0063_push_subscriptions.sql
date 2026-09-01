-- ============================================================
-- 0063_push_subscriptions.sql                        2026-06-16 (omdøpt fra 0058 — nummerkollisjon)
-- ------------------------------------------------------------
-- Web Push for ansatte: lagrer hver ansatts push-abonnement
-- (én rad per nettleser/enhet) slik at edge-funksjonen notify-push
-- kan sende ekte push-varsler ved ny booking / ny kontaktmelding,
-- selv når PWA-en er helt lukket.
--
-- Designvalg (avklart med Markus):
--   - Én rad per (ansatt, enhet). endpoint er globalt UNIQUE —
--     samme nettleser gir samme endpoint, så re-abonnering med
--     INSERT ... ON CONFLICT DO NOTHING er trygt og idempotent.
--   - RLS: authenticated kan KUN se/legge til/slette EGNE rader
--     (staff_id = (select auth.uid())). 0018-wrap-mønsteret.
--   - INGEN UPDATE-policy/-grant (frontend bruker insert-or-ignore +
--     delete, aldri update) og INGEN anon-tilgang.
--   - Edge-funksjonen kjører med service_role (BYPASSRLS) og må
--     kunne lese ALLE abonnement + slette døde (404/410). Vi gir
--     service_role select+delete eksplisitt; den røres ikke av
--     revoke-en under (jf. 0037: revoke kun anon/authenticated).
--   - GRANTs: revoke all FØRST (0037-lærdom), så minste nødvendige.
--
-- I tillegg: legg public.bookings og public.contact_messages til
-- realtime-publikasjonen supabase_realtime, slik at åpne admin-faner
-- får in-app INSERT-events (lyd + toast). Idempotent: sjekk
-- pg_publication_tables før `alter publication ... add table`.
-- INSERT-events bærer hele den nye raden uten REPLICA IDENTITY FULL,
-- så vi rører ikke replica identity her. Realtime filtrerer events
-- gjennom abonnentens RLS SELECT-policy — admin/therapist har allerede
-- SELECT på begge tabellene (0010 / 0039), så de mottar eventene.
--
-- PERSONVERN: push-varselet (edge-funksjonen) bruker KUN generisk
-- tekst («Ny booking» / «Ny melding mottatt»). Ingen pasientnavn,
-- helseinfo eller meldingsinnhold forlater DB via varselet.
--
-- Idempotent: create table/policy if (not) exists, DO-guard for
-- publikasjonen. Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase SQL Editor.
-- ============================================================

begin;

-- ----- push_subscriptions-tabell ------------------------------
create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  -- Eieren. Default auth.uid() så frontend slipper å sende den;
  -- RLS-insert-policyen håndhever uansett at den = innlogget bruker.
  staff_id    uuid not null default auth.uid()
                references auth.users(id) on delete cascade,
  -- Push-tjenestens endpoint-URL. Globalt unik → naturlig konflikt-
  -- nøkkel for insert-or-ignore ved re-abonnering.
  endpoint    text not null unique,
  -- Krypteringsnøkler fra PushSubscription.toJSON().keys.
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now()
);

-- Oppslag «mine abonnement» (frontend skru-av-vei) + service_role-feiing.
create index if not exists idx_push_subscriptions_staff
  on public.push_subscriptions (staff_id);

-- ----- Grants + RLS -------------------------------------------
-- 0037-lærdom: fjern evt. for vide default-privileges for anon/
-- authenticated først, så grant kun det RLS-policyene trenger.
-- service_role røres IKKE (den bypasser RLS og må feie døde rader).
revoke all on public.push_subscriptions from anon, authenticated;
grant select, insert, delete on public.push_subscriptions to authenticated;
-- Eksplisitt for edge-funksjonen (service_role): lese alle abonnement
-- + slette de som push-tjenesten avviser med 404/410.
grant select, delete on public.push_subscriptions to service_role;

alter table public.push_subscriptions enable row level security;

drop policy if exists "push_subscriptions select: own" on public.push_subscriptions;
drop policy if exists "push_subscriptions insert: own" on public.push_subscriptions;
drop policy if exists "push_subscriptions delete: own" on public.push_subscriptions;

-- Ansatt ser kun sine egne abonnement.
create policy "push_subscriptions select: own"
  on public.push_subscriptions
  for select
  to authenticated
  using (staff_id = (select auth.uid()));

-- Ansatt kan legge til abonnement for seg selv (staff_id må = innlogget).
create policy "push_subscriptions insert: own"
  on public.push_subscriptions
  for insert
  to authenticated
  with check (staff_id = (select auth.uid()));

-- Ansatt kan slette kun sine egne abonnement (skru-av-vei).
create policy "push_subscriptions delete: own"
  on public.push_subscriptions
  for delete
  to authenticated
  using (staff_id = (select auth.uid()));

-- ----- Realtime-publikasjon (idempotent) ----------------------
-- Legg bookings + contact_messages til supabase_realtime så åpne
-- admin-faner får INSERT-events. På Supabase finnes publikasjonen
-- allerede; på fersk DB skaper vi den tom først.
do $do$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
    raise notice 'opprettet publikasjon supabase_realtime (manglet)';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
    raise notice 'la public.bookings til supabase_realtime';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'contact_messages'
  ) then
    alter publication supabase_realtime add table public.contact_messages;
    raise notice 'la public.contact_messages til supabase_realtime';
  end if;
end
$do$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Tabellen finnes + RLS på:
--    select relrowsecurity from pg_class
--     where oid = 'public.push_subscriptions'::regclass;            -- t
--
-- B) 3 policies (SELECT/INSERT/DELETE), ingen UPDATE:
--    select policyname, cmd from pg_policies
--     where schemaname='public' and tablename='push_subscriptions'
--     order by cmd;
--    -- Forvent: DELETE, INSERT, SELECT (ingen UPDATE)
--
-- C) Grants minimale:
--    select grantee, string_agg(privilege_type, ',' order by privilege_type) privs
--      from information_schema.role_table_grants
--     where table_schema='public' and table_name='push_subscriptions'
--       and grantee in ('anon','authenticated','service_role')
--     group by grantee order by grantee;
--    -- Forvent: authenticated=DELETE,INSERT,SELECT ; service_role=DELETE,SELECT
--    --          (anon: ingen rad)
--
-- D) Realtime dekker begge tabeller:
--    select tablename from pg_publication_tables
--     where pubname='supabase_realtime' and schemaname='public'
--       and tablename in ('bookings','contact_messages')
--     order by tablename;
--    -- Forvent: bookings, contact_messages
-- ============================================================
