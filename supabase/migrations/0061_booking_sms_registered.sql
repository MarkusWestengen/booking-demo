-- ============================================================
-- 0061_booking_sms_registered.sql                     2026-06-23
-- ------------------------------------------------------------
-- «Time registrert»-SMS til kunden ved ny booking. Speiler
-- e-post-mekanismen (0011/0047) så tett som mulig:
--
--   E-POST i dag:
--     • send_booking_email() SECURITY DEFINER-trigger-funksjon
--       kaller net.http_post (pg_net).
--     • trigger trg_booking_email AFTER INSERT WHEN
--       (coalesce(new.email,'') <> '')  ← DEMPINGEN: e-post sendes
--       kun når kontaktfeltet (e-post) er utfylt. Det finnes INGEN
--       egen «bulk-import»-flagg-kolonne i bookings-skjemaet; WHEN-
--       guarden PÅ kontaktfeltet ER dempingen (en bulk-import uten
--       kontakt → ingen utsendelse).
--
--   SMS her (speilet):
--     • send_booking_sms() SECURITY DEFINER kaller net.http_post mot
--       send-sms Edge Function (samme X-Webhook-Secret-mønster som
--       e-post-PÅMINNELSEN i 0014).
--     • trigger trg_booking_sms AFTER INSERT WHEN
--       (coalesce(new.phone,'') <> '')  ← SAMME demping, men på
--       telefon-feltet. Dekker BÅDE portal-bestilling og manuelt
--       registrerte timer (begge lager en rad i bookings).
--
-- ⚠️ APPLY-GUIDE (Dashboard, i denne rekkefølgen FØR migrasjonen kjøres):
--   1. Aktiver Supabase Vault hvis det ikke alt er på
--      (Project Settings → Vault). Vanligvis aktivt som standard.
--   2. Opprett to Vault-secrets (Project Settings → Vault → New secret),
--      eller via SQL: select vault.create_secret('<verdi>', '<navn>');
--        a) navn = sms_function_url
--           verdi = https://<project-ref>.supabase.co/functions/v1/send-sms
--        b) navn = webhook_secret   (DELES med send-booking-email)
--           verdi = samme tilfeldige streng som Edge Function-env
--                   WEBHOOK_SECRET. Opprett KUN hvis den ikke alt finnes.
--   3. Deploy Edge Function send-sms med env-secrets WEBHOOK_SECRET,
--      SVEVE_USER, SVEVE_API_KEY.
--   4. Kjør denne migrasjonen.
--
-- HVORFOR VAULT (ikke app.*): Supabase tillater ikke
-- `alter database ... set app.*` / `alter role ... set app.*` i SQL Editor
-- (permission denied, 42501), så current_setting('app.*') duger ikke. URL +
-- secret hentes derfor fra vault.decrypted_secrets — det støttede mønsteret
-- (jf. docs/handoff/2026-05-25-pre-demo-polish.md). Samme designfeil finnes
-- i den eldre e-post-påminnelsen process_pending_reminders (0014) — egen runde.
--
-- INGEN secret-verdi ligger i denne fila — kun Vault-NAVN (REDACTED by design).
-- Lim ALDRI inn en ekte nøkkel her; den havner i git-historikken.
--
-- Idempotent: create or replace + drop trigger if exists. Atomisk.
-- search_path pinnes (repo-regel for SECURITY DEFINER, jf. 0011/0014).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

-- Diagnostisk pre-sjekk (varsler, stopper ikke).
do $$
declare
  v_url text;
begin
  if to_regclass('public.bookings') is null then
    raise notice '0061: public.bookings finnes ikke — kjør grunnmigrasjonene først.';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice '0061: Supabase Vault (vault.decrypted_secrets) er ikke tilgjengelig — aktiver Vault og opprett secrets (se apply-guide).';
  else
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'sms_function_url';
    if coalesce(v_url, '') = '' then
      raise notice '0061: Vault-secret «sms_function_url» mangler — triggeren blir no-op til den opprettes.';
    end if;
  end if;
end $$;

begin;

create or replace function public.send_booking_sms()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  sms_url        text;
  webhook_secret text;
  date_str       text := to_char(new.date, 'FMDD.MM.YYYY');
  time_str       text := to_char(new.time, 'HH24:MI');
  msg            text;
begin
  -- Hent funksjons-URL + webhook-secret fra Supabase Vault. app.*-settings
  -- kan ikke settes i SQL Editor (42501), så current_setting('app.*') duger
  -- ikke. vault.* er fullkvalifisert siden search_path er pinnet til public.
  select decrypted_secret into sms_url
    from vault.decrypted_secrets where name = 'sms_function_url';
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'webhook_secret';

  -- Bail stille hvis SMS-konfig mangler — vi vil ALDRI brekke booking-
  -- flyten fordi SMS-oppsett ikke er på plass (samme prinsipp som 0007).
  if sms_url is null or sms_url = '' then
    return new;
  end if;

  msg := 'Timen din hos Westengen Klinikk er registrert ' || date_str || ' kl. ' || time_str
      || '. Ved spørsmål eller behov for endring, kontakt klinikken. '
      || 'Avbestilling mindre enn 24 timer før timen belastes i sin helhet.';

  -- Samme invokasjonsmønster som e-post-påminnelsen (0014): pg_net mot
  -- Edge Function med X-Webhook-Secret. send-sms tar { to, message }.
  perform net.http_post(
    url := sms_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Webhook-Secret', coalesce(webhook_secret, '')
    ),
    body := jsonb_build_object(
      'to', new.phone,
      'message', msg
    )
  );

  return new;
end;
$$;

comment on function public.send_booking_sms() is
  'Sender «time registrert»-SMS til kunden via send-sms Edge Function. '
  'Speiler send_booking_email (0011/0047). Lagt til i migrasjon 0061.';

-- Trigger: AFTER INSERT, kun når telefon er utfylt (samme demping som
-- e-post-triggeren bruker på e-post). Inneholder ingen secret — trygt å
-- droppe/gjenskape.
drop trigger if exists trg_booking_sms on public.bookings;
create trigger trg_booking_sms
  after insert on public.bookings
  for each row
  when (coalesce(new.phone, '') <> '')
  execute function public.send_booking_sms();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Trigger har WHEN-guard på telefon:
--    select pg_get_triggerdef(oid) from pg_trigger
--     where tgname = 'trg_booking_sms';
--    -- Forvent: ... WHEN ((COALESCE(new.phone, ''::text) <> ''::text)) ...
--
-- B) Ende-til-ende (krever send-sms deployd + Vault-secrets sms_function_url
--    + webhook_secret opprettet):
--    insert booking med telefon → SMS forsøkes sendt;
--    insert booking UTEN telefon (admin-flyt) → ingen SMS (WHEN-guard).
--
-- C) net.http_post-kall logges i pg_net:
--    select id, status_code, error_msg
--      from net._http_response order by id desc limit 5;
-- ============================================================
