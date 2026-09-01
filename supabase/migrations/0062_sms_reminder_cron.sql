-- ============================================================
-- 0062_sms_reminder_cron.sql                          2026-06-23
-- ------------------------------------------------------------
-- 24-timers SMS-påminnelse — kolonne + helper-funksjon + cron.
-- Speiler e-post-påminnelsen (0013 + 0014) nøyaktig: samme vindu-
-- logikk, samme demping (status='confirmed' + flagg-kolonne som
-- hindrer dobbeltsending), samme Edge Function-invokasjon (pg_net
-- + X-Webhook-Secret).
--
-- E-POST i dag (0014): process_pending_reminders() plukker
--   confirmed-bookinger 22–26t frem, kaller send-booking-email, og
--   setter reminder_sent_at = now(). pg_cron 'westengen-klinikk-24h-reminders'
--   hver time (minutt :05).
--
-- SMS her: process_pending_sms_reminders() plukker confirmed-bookinger
--   23–25t frem MED telefon og reminder_sms_sent_at IS NULL, kaller
--   send-sms, og setter reminder_sms_sent_at = now(). Egen pg_cron-jobb.
--
-- ⚠️ APPLY-GUIDE (Dashboard, i denne rekkefølgen FØR migrasjonen kjøres):
--   1. Vault-secrets må finnes (Project Settings → Vault → New secret, eller
--      select vault.create_secret('<verdi>', '<navn>')):
--        a) navn = sms_function_url
--           verdi = https://<project-ref>.supabase.co/functions/v1/send-sms
--        b) navn = webhook_secret   (DELES med send-booking-email + 0061)
--           verdi = samme tilfeldige streng som Edge Function-env WEBHOOK_SECRET.
--      Er de alt opprettet for 0061, gjenbrukes de her — IKKE opprett på nytt.
--   2. Edge Function send-sms deployd med env-secrets WEBHOOK_SECRET,
--      SVEVE_USER, SVEVE_API_KEY (jf. 0061).
--   3. pg_cron enablet (Database → Extensions). Krever Pro-plan; på Free
--      brukes Supabase Cron i stedet (se nederst).
--   4. Kjør denne migrasjonen.
--
-- HVORFOR VAULT (ikke app.*): `alter database ... set app.*` er blokkert i
-- SQL Editor (permission denied, 42501), så current_setting('app.*') duger
-- ikke. URL + secret hentes fra vault.decrypted_secrets — samme mønster som
-- 0061. INGEN secret-verdi i denne fila, kun Vault-NAVN (REDACTED by design).
-- Samme app.*-designfeil finnes i e-post-påminnelsen 0014 — egen runde.
--
-- Idempotent: add column if not exists, create index if not exists,
-- create or replace, DO-blokk som unscheduler før schedule.
-- search_path pinnes. IKKE applisert av repoet — Markus kjører manuelt.
-- ============================================================

-- Diagnostisk pre-sjekk.
do $$
declare
  v_url text;
begin
  if to_regclass('public.bookings') is null then
    raise notice '0062: public.bookings finnes ikke — kjør grunnmigrasjonene først.';
  end if;
  if to_regclass('vault.decrypted_secrets') is null then
    raise notice '0062: Supabase Vault (vault.decrypted_secrets) er ikke tilgjengelig — aktiver Vault og opprett secrets (se apply-guide).';
  else
    select decrypted_secret into v_url
      from vault.decrypted_secrets where name = 'sms_function_url';
    if coalesce(v_url, '') = '' then
      raise notice '0062: Vault-secret «sms_function_url» mangler — funksjonen blir no-op til den opprettes.';
    end if;
  end if;
end $$;

-- ============================================================
-- (a) reminder_sms_sent_at-kolonne på bookings
-- ------------------------------------------------------------
-- NULL = SMS-påminnelse ikke sendt ennå. Settes av funksjonen under.
-- Speiler reminder_sent_at (0013) men er SEPARAT, så e-post- og SMS-
-- påminnelser spores uavhengig.
-- ============================================================
alter table public.bookings
  add column if not exists reminder_sms_sent_at timestamptz;

-- Partial index for effektiv cron-spørring (kun kandidat-rader).
create index if not exists bookings_pending_sms_reminder_idx
  on public.bookings(date, time)
  where status = 'confirmed' and reminder_sms_sent_at is null;

begin;

-- ============================================================
-- (b) Helper-funksjon — process_pending_sms_reminders
-- ============================================================
create or replace function public.process_pending_sms_reminders()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  b record;
  sms_url        text;
  webhook_secret text;
  time_str       text;
  msg            text;
  reminders_sent int := 0;
begin
  -- Hent funksjons-URL + webhook-secret fra Supabase Vault. app.*-settings
  -- kan ikke settes i SQL Editor (42501), så current_setting('app.*') duger
  -- ikke. vault.* er fullkvalifisert siden search_path er pinnet til public.
  select decrypted_secret into sms_url
    from vault.decrypted_secrets where name = 'sms_function_url';
  select decrypted_secret into webhook_secret
    from vault.decrypted_secrets where name = 'webhook_secret';

  -- Bail tidlig hvis konfig mangler — no-op, ingen feil-spam.
  if sms_url is null or sms_url = '' then
    raise warning 'process_pending_sms_reminders: Vault-secret sms_function_url mangler — hopper over';
    return;
  end if;

  for b in
    select *
      from public.bookings
     where status = 'confirmed'
       and reminder_sms_sent_at is null
       and coalesce(phone, '') <> ''               -- samme demping som SMS-triggeren
       and ((date + time) at time zone 'Europe/Oslo')
             between (now() + interval '23 hours')
                 and (now() + interval '25 hours')
  loop
    time_str := to_char(b.time, 'HH24:MI');
    msg := 'Påminnelse fra Westengen Klinikk. Du har time i morgen kl. ' || time_str
        || ' hos ' || coalesce(b.staff_name, 'oss')
        || '. Husk at avbestilling mindre enn 24 timer før timen belastes i sin helhet.';

    -- Samme invokasjonsmønster som e-post-påminnelsen (0014).
    perform net.http_post(
      url := sms_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'X-Webhook-Secret', coalesce(webhook_secret, '')
      ),
      body := jsonb_build_object(
        'to', b.phone,
        'message', msg
      )
    );

    -- Marker som sendt umiddelbart (hindrer dobbeltsending ved race/
    -- overlappende cron-tikk). Samme avveining som 0014.
    update public.bookings
       set reminder_sms_sent_at = now()
     where id = b.id;

    reminders_sent := reminders_sent + 1;
  end loop;

  if reminders_sent > 0 then
    raise notice 'process_pending_sms_reminders: sent % SMS-reminders', reminders_sent;
  end if;
end;
$$;

comment on function public.process_pending_sms_reminders() is
  '24t SMS-påminnelse. Speiler process_pending_reminders (0014) men bruker '
  'reminder_sms_sent_at + send-sms Edge Function. Lagt til i migrasjon 0062.';

-- ============================================================
-- (c) Schedule cron-jobben (egen jobb, separat fra e-post)
-- ============================================================
do $$
begin
  -- Idempotent: dropp eksisterende jobb med samme navn først.
  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'westengen-klinikk-24h-sms-reminders';

  -- Minutt :07 for å forskyve fra e-post-jobben (:05) og top-of-hour.
  perform cron.schedule(
    'westengen-klinikk-24h-sms-reminders',
    '7 * * * *',
    $cron$ select public.process_pending_sms_reminders(); $cron$
  );
end $$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
--   -- Kolonne finnes:
--   select column_name from information_schema.columns
--    where table_name='bookings' and column_name='reminder_sms_sent_at';
--
--   -- Cron-jobben er schedulert:
--   select jobid, schedule, jobname, active
--     from cron.job where jobname = 'westengen-klinikk-24h-sms-reminders';
--
--   -- Manuell test (krever send-sms deployd + Vault-secrets sms_function_url
--   -- + webhook_secret opprettet):
--   select public.process_pending_sms_reminders();
--
--   -- Siste kjøringer:
--   select start_time, status, return_message
--     from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname='westengen-klinikk-24h-sms-reminders')
--    order by start_time desc limit 10;
-- ============================================================
--
-- ALTERNATIV (Free-plan, uten pg_cron): apply (a)+(b), kommenter ut
-- (c), og opprett en Supabase Cron-jobb i Dashboard:
--   Schedule: 7 * * * *   Type: SQL snippet
--   SQL: select public.process_pending_sms_reminders();
-- ============================================================
