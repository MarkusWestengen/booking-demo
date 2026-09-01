-- ============================================================
-- 0064_reminder_email_vault.sql                       2026-06-24
-- ------------------------------------------------------------
-- Migrerer e-post-PÅMINNELSEN (24t) fra app.*-settings til Supabase
-- Vault — samme omlegging som SMS fikk i 0061/0062 (commit 7cd1673).
--
-- BAKGRUNN / HVORFOR:
--   process_pending_reminders() (0014) leser webhook-URL + secret via
--   current_setting('app.edge_function_url') / app.webhook_secret. Supabase
--   tillater IKKE `alter database ... set app.*` / `alter role ... set app.*`
--   i SQL Editor (permission denied, 42501), så disse parameterne kan ikke
--   settes der → funksjonen bail-er stille (no-op) og INGEN 24t-påminnelser
--   sendes i prod. SMS-sporet løste nøyaktig dette ved å hente URL + secret
--   fra vault.decrypted_secrets — det støttede mønsteret. Denne migrasjonen
--   speiler det for e-post-påminnelsen. ALL ANNEN LOGIKK ER UENDRET:
--   reminder-vinduet (22–26t), WHEN/where-filteret (status='confirmed' og
--   reminder_sent_at is null), event-payloaden ('event'='reminder', booking),
--   og umiddelbar reminder_sent_at-setting. Cron-jobben
--   «westengen-klinikk-24h-reminders» (0014) kaller fortsatt samme funksjon — den
--   re-schedules IKKE her (CREATE OR REPLACE bytter kun funksjonskroppen).
--
-- ⚠️ MERK — notify_booking_change() (0007) er BEVISST IKKE inkludert:
--   0011 (linje 102–103) DROPPET både funksjonen og trg_notify_booking_change
--   permanent (den var funksjonelt død — app.edge_function_url NOT SET, Q9).
--   Bekreftelse-/avbestilling-e-post går i dag via den hardkodede DB-funksjonen
--   send_booking_email() + trg_booking_email. Å gjenskape notify_booking_change
--   med trigger ville lagt til en ANDRE bekreftelse-e-post-sti → kunden får
--   DOBBEL bekreftelse-e-post per booking. Derfor rør vi den ikke. (Hvis man
--   senere VIL flytte booking-e-posten til Edge Function-mønsteret, må man
--   samtidig fjerne send_booking_email-stien — egen, eksplisitt beslutning.)
--
-- ⚠️ APPLY-GUIDE (Dashboard, i denne rekkefølgen FØR migrasjonen kjøres):
--   1. Aktiver Supabase Vault hvis det ikke alt er på
--      (Project Settings → Vault). Vanligvis aktivt som standard.
--   2. Opprett/forvent to Vault-secrets
--      (Project Settings → Vault → New secret, eller via SQL:
--       select vault.create_secret('<verdi>', '<navn>')):
--        a) navn = edge_function_url
--           verdi = https://<project-ref>.supabase.co/functions/v1/send-booking-email
--        b) navn = webhook_secret   (DELES med send-sms / 0061-0062)
--           verdi = samme tilfeldige streng som Edge Function-env
--                   WEBHOOK_SECRET. Opprett KUN hvis den ikke alt finnes.
--   3. Edge Function send-booking-email må være deployd (env RESEND_API_KEY +
--      WEBHOOK_SECRET) og håndtere event='reminder' (den gjør det allerede).
--   4. Kjør denne migrasjonen.
--
-- INGEN secret-verdi ligger i denne fila — kun Vault-NAVN (REDACTED by design).
-- Lim ALDRI inn en ekte nøkkel her; den havner i git-historikken.
--
-- Idempotent: create or replace + atomisk transaksjon. search_path pinnes
-- (repo-regel for SECURITY DEFINER, jf. 0011/0014/0061).
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

-- Diagnostisk pre-sjekk (varsler, stopper ikke).
do $$
declare
  v_url text;
begin
  if to_regclass('public.bookings') is null then
    raise notice '0064: public.bookings finnes ikke — kjør grunnmigrasjonene først.';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice '0064: Supabase Vault (vault.decrypted_secrets) er ikke tilgjengelig — aktiver Vault og opprett secrets (se apply-guide).';
  else
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'edge_function_url';
    if coalesce(v_url, '') = '' then
      raise notice '0064: Vault-secret «edge_function_url» mangler — påminnelsen blir no-op til den opprettes.';
    end if;
  end if;
end $$;

begin;

-- ============================================================
-- process_pending_reminders — Vault-basert (erstatter app.*-varianten
-- fra 0014). Kalt av cron-jobben «westengen-klinikk-24h-reminders» hver time,
-- og kan kjøres manuelt for test: select public.process_pending_reminders();
-- ============================================================
create or replace function public.process_pending_reminders()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  b record;
  webhook_url    text;
  webhook_secret text;
  reminders_sent int := 0;
begin
  -- Hent funksjons-URL + webhook-secret fra Supabase Vault. app.*-settings
  -- kan ikke settes i SQL Editor (42501), så current_setting('app.*') duger
  -- ikke. vault.* er fullkvalifisert siden search_path er pinnet til public.
  select decrypted_secret into webhook_url
    from vault.decrypted_secrets where name = 'edge_function_url';
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'webhook_secret';

  -- Bail tidlig hvis konfig mangler. Cron fyrer fortsatt hver time men blir
  -- no-op til Vault-secret er satt — ingen feilmelding spammer logs.
  if webhook_url is null or webhook_url = '' then
    raise warning 'process_pending_reminders: Vault-secret edge_function_url not set — skipping';
    return;
  end if;

  for b in
    select *
      from public.bookings
     where status = 'confirmed'
       and reminder_sent_at is null
       and ((date + time) at time zone 'Europe/Oslo')
             between (now() + interval '22 hours')
                 and (now() + interval '26 hours')
  loop
    -- Kall Edge Function med X-Webhook-Secret + event='reminder'.
    -- Samme webhook-mønster som SMS-påminnelsen (0062).
    perform net.http_post(
      url := webhook_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'X-Webhook-Secret', coalesce(webhook_secret, '')
      ),
      body := jsonb_build_object(
        'event', 'reminder',
        'booking', row_to_json(b)
      )
    );

    -- Marker som påminnet umiddelbart. Hvis send_email feiler i Edge
    -- Function: loggføres der, kunde mister reminder-en, ingen retry.
    -- Dette er bevisst — alternativet er race conditions med duplikate
    -- sendinger.
    update public.bookings
       set reminder_sent_at = now()
     where id = b.id;

    reminders_sent := reminders_sent + 1;
  end loop;

  if reminders_sent > 0 then
    raise notice 'process_pending_reminders: sent % reminders', reminders_sent;
  end if;
end;
$$;

comment on function public.process_pending_reminders() is
  '24t e-post-påminnelse. Henter edge_function_url + webhook_secret fra '
  'Supabase Vault (migrasjon 0064 — erstattet app.*-varianten fra 0014).';

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Funksjonen bruker ikke lenger app.* (forvent 0 treff):
--    select position('current_setting' in prosrc)
--      from pg_proc where proname = 'process_pending_reminders';
--    -- Forvent: 0
--
-- B) Cron-jobben kaller fortsatt samme funksjon (uendret av 0064):
--    select jobid, schedule, command, jobname, active
--      from cron.job where jobname = 'westengen-klinikk-24h-reminders';
--
-- C) Ende-til-ende (krever send-booking-email deployd + Vault-secrets
--    edge_function_url + webhook_secret opprettet):
--    -- Insert en confirmed booking 22–26t frem i tid, så:
--    select public.process_pending_reminders();
--    -- Verifiser reminder_sent_at ble satt + e-post mottatt.
--
-- D) net.http_post-kall logges i pg_net:
--    select id, status_code, error_msg
--      from net._http_response order by id desc limit 5;
-- ============================================================
