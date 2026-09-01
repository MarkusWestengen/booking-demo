-- ============================================================
-- 0056_d_med_review_email_escape.sql                 2026-06-13
-- ------------------------------------------------------------
-- D-MEDIUM fra security-review-2026-06-12: 0043 sin
-- process_pending_review_emails bygde «Hei <navn>,»-linjen RÅTT
-- (coalesce(b.name,'')) — i strid med escape-disiplinen fra 0028/
-- 0039/0040. En booking med name =
--   <a href="https://phish.evil">Bekreft kontoen</a>
-- ville 1–72 t senere blitt til en merkevarestøttet phishing-e-post.
--
-- Denne migrasjonen ERSTATTER 0043 i sin helhet (0043 er IKKE
-- applisert i prod): identisk innhold, men kundenavnet går gjennom
-- public.html_escape() (0028). Selvstendig og idempotent — operatør
-- applikerer 0042 og deretter DENNE (hopp over 0043). Er 0043
-- likevel applisert først, er denne en trygg overskriving (create
-- or replace; nøkkel-placeholder + DO-guard bevarer sandbox-
-- semantikken til ekte nøkkel limes inn manuelt).
--
-- Alt annet er ordrett fra 0043 — se den for full design-
-- begrunnelse (1t–72t-vindu, sandbox-guard, cron :15).
-- ============================================================

begin;

-- ----- (a) Sporings-kolonne (uendret fra 0043) -----
alter table public.bookings
  add column if not exists review_email_sent_at timestamptz;

create index if not exists idx_bookings_review_email_pending
  on public.bookings (review_email_sent_at)
  where review_email_sent_at is null;

-- ----- (b) Helper-funksjon — nå med html_escape på kundenavn -----
create or replace function public.process_pending_review_emails()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  b           record;
  -- ⚠️ HARDKODET API-NØKKEL — placeholder. På prod erstattes denne
  -- manuelt av operatøren etter apply. Lim ALDRI inn ekte nøkkel her —
  -- den havner i git-historikken.
  resend_key  text := 'REDACTED_RESEND_KEY';
  from_email  text := 'Westengen Klinikk <onboarding@resend.dev>';
  base_url    text := 'https://demo.westengenklinikk.example';
  review_url  text;
  date_str    text;
  e_name      text;
  sent        int  := 0;
  email_html  text;
begin
  -- DO-GUARD (sandbox): så lenge nøkkelen er placeholder gjør vi INGENTING
  -- — ingen HTTP-kall og ingen rader markeres. Når ekte nøkkel limes inn
  -- plukkes de siste 72t opp ved neste cron-tikk.
  if resend_key = 'REDACTED_RESEND_KEY' then
    raise warning 'process_pending_review_emails: Resend-nøkkel er placeholder — hopper over (sandbox-modus).';
    return;
  end if;

  for b in
    select *
      from public.bookings
     where review_email_sent_at is null
       and status in ('confirmed', 'completed')
       and email is not null and email <> ''
       and ((date + time + (coalesce(duration, 30) || ' minutes')::interval)
              at time zone 'Europe/Oslo')
             between (now() - interval '72 hours')
                 and (now() - interval '1 hour')
       and not exists (select 1 from public.reviews r where r.booking_id = b.id)
  loop
    review_url := base_url || '/anmeldelser.html?token=' || b.review_token::text;
    date_str   := to_char(b.date, 'DD.MM.YYYY');
    -- D-MEDIUM-fiksen: kunde-styrt navn escapes (0028-disiplin).
    e_name     := public.html_escape(coalesce(b.name, ''));

    email_html :=
         '<!DOCTYPE html><html><body style="font-family: -apple-system, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f5f5f0;">'
      || '<div style="background: #ffffff; padding: 32px; border-radius: 8px;">'
      || '<h2 style="color: #1a1a1a; margin: 0 0 16px 0;">Hvordan var timen hos Westengen Klinikk?</h2>'
      || '<p style="margin: 0 0 8px 0; color: #555; font-size: 15px;">Hei ' || e_name || ',</p>'
      || '<p style="margin: 0 0 24px 0; color: #555; font-size: 15px;">Takk for at du var hos oss '
         || date_str || '. Vi setter stor pris på om du deler et par ord om opplevelsen — '
         || 'det hjelper andre å finne riktig behandling.</p>'
      || '<div style="margin: 28px 0; padding: 24px; background: #eef3ee; border-left: 4px solid #3E6B47; border-radius: 4px;">'
      || '<p style="margin: 0 0 18px 0; color: #2A4A31; font-size: 14px;">Klikk knappen for å legge igjen anmeldelsen din:</p>'
      || '<table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">'
      || '<tr><td align="center" style="background: #3E6B47; border-radius: 6px;">'
      || '<a href="' || review_url || '" '
      || 'style="display: inline-block; padding: 14px 32px; color: #ffffff; text-decoration: none; '
      || 'font-weight: 600; font-size: 16px; font-family: -apple-system, Arial, sans-serif;">'
      || 'SKRIV EN ANMELDELSE</a>'
      || '</td></tr></table>'
      || '<p style="margin: 16px 0 0 0; font-size: 12px; color: #888; word-break: break-all;">'
      || 'Eller kopier denne lenken: ' || review_url || '</p>'
      || '</div>'
      || '<p style="margin-top: 28px; font-size: 12px; color: #999;">Westengen Klinikk · Bregneveien 12, 0283 Oslo</p>'
      || '</div></body></html>';

    perform net.http_post(
      url     := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || resend_key,
        'Content-Type',  'application/json'
      ),
      body    := jsonb_build_object(
        'from',    from_email,
        'to',      b.email,
        'subject', 'Hvordan var timen hos Westengen Klinikk?',
        'html',    email_html
      )
    );

    -- Marker umiddelbart (hindrer dobbeltsending; jf. 0014-avveiingen).
    update public.bookings set review_email_sent_at = now() where id = b.id;
    sent := sent + 1;
  end loop;

  if sent > 0 then
    raise notice 'process_pending_review_emails: sendte % anmeldelse-e-poster', sent;
  end if;

exception when others then
  raise warning 'process_pending_review_emails feilet: % %', sqlstate, sqlerrm;
end;
$$;

-- ----- (c) Cron-schedule (uendret fra 0043; guard hvis pg_cron mangler) -----
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice '0056: pg_cron ikke installert — schedule jobben via Dashboard → Integrations → Cron i stedet (''15 * * * *'', select public.process_pending_review_emails();).';
    return;
  end if;

  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'westengen-klinikk-review-emails';

  perform cron.schedule(
    'westengen-klinikk-review-emails',
    '15 * * * *',
    $cron$ select public.process_pending_review_emails(); $cron$
  );
end $$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Funksjonen escaper navnet:
--    select prosrc ~ 'html_escape' as has_escape
--      from pg_proc where proname='process_pending_review_emails';
--    -- Forvent: true.
--
-- B) Resten: identisk med 0043 sin verifikasjonsblokk (kolonne,
--    cron-job, sandbox-no-op, nøkkel-reapply, smoke-test).
-- ============================================================
