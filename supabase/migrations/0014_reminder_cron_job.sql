-- ============================================================
-- 0014_reminder_cron_job.sql                       2026-05-12
-- ------------------------------------------------------------
-- 24-timers booking-påminnelse — cron + helper-funksjon.
-- Adresserer audit-rapport 2026-05-11 punkt 3.
--
-- Avhenger av:
--   - migrasjon 0013 (reminder_sent_at-kolonne + partial index)
--   - pg_cron extension enablet i Dashboard
--   - Postgres-parametere app.edge_function_url + app.webhook_secret satt
--   - Edge Function send-booking-email deployd (eksisterer i repo,
--     har allerede event='reminder'-håndtering)
--
-- ⚠️ MANUELLE FORUTSETNINGER FØR APPLISERING (se også 0013):
--
--   (1) Enable pg_cron:
--       Dashboard → Database → Extensions → pg_cron → Enable.
--       Krever Pro-plan. Hvis Free-plan: hopp over denne migrasjonen
--       og bruk Supabase Cron i stedet (instrukser nederst).
--
--   (2) Postgres-parametere:
--       alter database postgres set app.edge_function_url = '...';
--       alter database postgres set app.webhook_secret    = '...';
--
--   (3) Verifiser med: select current_setting('app.edge_function_url', true);
--
-- Designvalg som er gjort uten å spørre operatør:
--
--   - Cron kjører hver time på minutt :05 (cron-uttrykk '5 * * * *').
--     Forsyver fra top-of-hour for å unngå konflikt med eventuelle
--     andre Supabase-interne jobs.
--
--   - Tidssone: bookings.date og bookings.time lagres som klinikkens
--     wall-clock (Europe/Oslo). Vi bruker `(date + time) at time zone
--     'Europe/Oslo'` for å få korrekt UTC-equivalent å sammenligne mot
--     now() (som er timestamptz).
--
--   - Reminder-vinduet er 22-26 timer fremover (4h-bredde). Det betyr
--     at en cron-tikk garantert treffer en booking minst én gang,
--     selv om cron skulle hoppe over en time eller bli litt forsinket.
--     reminder_sent_at-flagget hindrer dobbeltsendring.
--
--   - reminder_sent_at settes UMIDDELBART etter Edge Function-kallet,
--     før vi vet om Resend faktisk sendte e-posten. Hvis Edge Function
--     feiler internt logges det der; kunde mister i verste fall
--     reminder-en. Akseptabelt — alternativet er duplikate sendinger
--     ved race conditions, som er verre.
-- ============================================================

-- ============================================================
-- (a) Helper-funksjon — process_pending_reminders ----------
-- Idempotent via CREATE OR REPLACE. Kalles av cron hver time.
-- Kan også kalles manuelt for test:
--   select public.process_pending_reminders();
-- ============================================================
create or replace function public.process_pending_reminders()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  b record;
  webhook_url    text := current_setting('app.edge_function_url', true);
  webhook_secret text := current_setting('app.webhook_secret', true);
  reminders_sent int  := 0;
begin
  -- Bail tidlig hvis konfig mangler. Cron fyrer fortsatt hver time
  -- men blir no-op til parametere er satt — ingen feilmelding spammer
  -- logs, kun en advarsel.
  if webhook_url is null or webhook_url = '' then
    raise warning 'process_pending_reminders: app.edge_function_url not set — skipping';
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
    -- Samme webhook-mønster som 0007 var bygget for.
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
    -- Dette er bevisst — alternativet er race conditions med
    -- duplikate sendinger.
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

-- ============================================================
-- (b) Schedule cron-jobben ---------------------------------
-- pg_cron krever unik jobname. Idempotent via DO-blokk som
-- unscheduler eksisterende job med samme navn først.
-- ============================================================
do $$
begin
  -- Drop eksisterende job med samme navn (idempotent re-apply)
  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'westengen-klinikk-24h-reminders';

  -- Schedule på nytt
  perform cron.schedule(
    'westengen-klinikk-24h-reminders',
    '5 * * * *',
    $cron$ select public.process_pending_reminders(); $cron$
  );
end $$;

-- ============================================================
-- (c) Verifikasjon (kjør manuelt etter applisering):
--
--   -- Se at jobben er schedulert
--   select jobid, schedule, command, jobname, active
--     from cron.job
--    where jobname = 'westengen-klinikk-24h-reminders';
--
--   -- Manuell test (krever app-parametere satt og Edge Function deployd):
--   select public.process_pending_reminders();
--
--   -- Sjekk siste kjøringer
--   select start_time, end_time, status, return_message
--     from cron.job_run_details
--    where jobid = (select jobid from cron.job where jobname='westengen-klinikk-24h-reminders')
--    order by start_time desc
--    limit 10;
-- ============================================================

-- ============================================================
-- ALTERNATIV: Supabase Cron (uten pg_cron-extension)
-- ============================================================
-- Hvis du er på Free-plan eller ikke vil enable pg_cron, kan
-- Supabase sin nyere Cron-funksjon brukes i stedet. Helper-
-- funksjonen process_pending_reminders() er kompatibel med begge.
--
-- Setup:
--   1. Apply 0013 + denne migrasjonens (a)-seksjon (helper-funksjonen).
--      Du kan kommentere ut (b)-seksjonen som schedules pg_cron-jobben.
--   2. Dashboard → Integrations → Cron → New cron job
--   3. Schedule: 5 * * * *  (hver time, minutt 5)
--   4. Type: SQL snippet
--   5. SQL: select public.process_pending_reminders();
--   6. Lagre.
--
-- Supabase Cron kjører helper-funksjonen samme måte som pg_cron ville.
-- Du kan se kjøringer i Dashboard → Integrations → Cron → Logs.
-- ============================================================
