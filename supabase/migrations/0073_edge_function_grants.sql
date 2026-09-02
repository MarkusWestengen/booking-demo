-- ============================================================
-- 0073 — Edge-funksjonene får lese og skrive det de trenger
-- ------------------------------------------------------------
-- Funnet da funksjonene ble deployet for første gang og
-- kontaktskjemaet ble testet mot live: `submit-contact` svarte
-- 500 «server_error», og feilen lå i rate-limit-oppslaget.
--
-- Årsaken er den samme som i 0069: Supabase sine «default
-- privileges» er ikke i effekt i dette prosjektet (notert i 0036).
-- Hver rolle må derfor få grants eksplisitt, også `service_role`.
--
-- `anon_insert_events` (0052) gjør i tillegg
-- `revoke all ... from anon, authenticated, public` og slår på RLS
-- uten policyer. Det er riktig: bare den SECURITY DEFINER-triggeren
-- skal røre den fra databasesiden. Men Edge-funksjonen når den fra
-- utsiden, som service_role, og hadde ingen vei inn.
--
-- service_role går utenom RLS, så policyer trengs ikke. Det som
-- manglet var tabellrettighetene under.
--
-- Nøyaktig det funksjonene gjør, ikke mer:
--   submit-contact   anon_insert_events: select (telling), insert
--                    contact_messages:   insert
--   notify-push      push_subscriptions: select, delete
--
-- Idempotent.
-- ============================================================

begin;

-- ----- submit-contact -----
grant select, insert on public.anon_insert_events to service_role;
grant usage, select on all sequences in schema public to service_role;
grant insert on public.contact_messages to service_role;

-- ----- notify-push -----
do $$
begin
  if to_regclass('public.push_subscriptions') is not null then
    execute 'grant select, delete on public.push_subscriptions to service_role';
  end if;
end $$;

-- ----- send-booking-email og send-sms -----
-- Disse kalles av databasen via pg_net og leser ingenting selv.
-- Ingen grants nødvendig.

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) service_role har rettighetene:
--      select table_name, privilege_type
--        from information_schema.role_table_grants
--       where grantee = 'service_role'
--         and table_schema = 'public'
--         and table_name in ('anon_insert_events', 'contact_messages',
--                            'push_subscriptions')
--       order by table_name, privilege_type;
--
-- B) Kontaktskjemaet ende til ende på den publiserte siden:
--    send inn skjemaet, og se meldingen dukke opp i meldinger.html.
--
-- C) Ingen andre roller fikk noe:
--      select grantee, privilege_type
--        from information_schema.role_table_grants
--       where table_schema = 'public'
--         and table_name = 'anon_insert_events';
--    -- Forvent: bare service_role (og eier).
-- ============================================================
