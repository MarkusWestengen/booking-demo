-- ============================================================
-- 0077 — flytt den nattlige nullstillingen ut av åpningstiden
-- ------------------------------------------------------------
-- Jobben sto på `15 4 * * *`. Cron i pg_cron er UTC, så det er
--
--   06:15 norsk tid om sommeren (CEST)
--   05:15 norsk tid om vinteren (CET)
--
-- Markus åpner 06:00. Nullstillingen kjørte altså et kvarter etter at
-- klinikken åpnet i sommerhalvåret: en booking en besøkende la 06:00–06:15
-- ble slettet minutter senere. Og selve tidspunktet flyttet seg en time
-- ved sommertidsskiftet, fordi UTC står stille mens Norge ikke gjør det.
--
-- `0 1 * * *` gir 02:00 om sommeren og 03:00 om vinteren. Begge ligger
-- godt utenfor åpningstiden uansett hvilken vei skiftet går, og jobben
-- treffer aldri en åpen klinikk.
--
-- Kun `schedule` endres. cron.alter_job lar de andre feltene stå:
-- command, database, username, nodename, nodeport og active er urørt.
-- ============================================================

begin;

do $do$
declare
  v_jobid    bigint;
  v_command  text;
  v_active   boolean;
begin
  select jobid, command, active
    into v_jobid, v_command, v_active
    from cron.job
   where jobname = 'demo-nightly-reset';

  if v_jobid is null then
    raise exception '0077: fant ingen cron-jobb «demo-nightly-reset»';
  end if;

  perform cron.alter_job(job_id => v_jobid, schedule => '0 1 * * *');

  -- Sikkerhetsnett: bekreft at kun tidsplanen flyttet seg.
  if not exists (
    select 1 from cron.job
     where jobid = v_jobid
       and jobname = 'demo-nightly-reset'
       and schedule = '0 1 * * *'
       and command = v_command
       and active = v_active
  ) then
    raise exception '0077: noe annet enn schedule ble endret på jobb %', v_jobid;
  end if;

  raise notice '0077: demo-nightly-reset flyttet fra 15 4 * * * til 0 1 * * * (jobid %)', v_jobid;
end
$do$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
--   select jobname, schedule, command, active from cron.job
--    where jobname = 'demo-nightly-reset';
--   -- Forvent: 0 1 * * *, « select public.demo_reset(); », true.
--
--   select to_char(timezone('Europe/Oslo', timestamptz '2026-09-03 01:00+00'), 'HH24:MI') as sommer,
--          to_char(timezone('Europe/Oslo', timestamptz '2026-11-03 01:00+00'), 'HH24:MI') as vinter;
--   -- Forvent: 03:00 og 02:00.
-- ============================================================
