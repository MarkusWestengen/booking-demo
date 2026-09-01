-- ============================================================
-- 0028_email_html_escape.sql                         2026-05-21
-- ------------------------------------------------------------
-- P1-2 fra audit-2026-05-21: send_booking_email bygde HTML ved
-- uskapet konkatenering av kunde-input (new.name, new.email osv.).
-- En ondsinnet booking kunne sprøyte HTML/lenker inn i varsel-
-- eposten. Denne migrasjonen:
--   (a) legger til en html_escape()-hjelpefunksjon, og
--   (b) re-skaper send_booking_email der ALL kunde-input går
--       gjennom html_escape() før den limes inn i templaten.
--
-- Templaten er ellers identisk med 0026 (brand-tema). date_str,
-- time_str og cancel_url er trygge (Postgres-formatert / intern URL).
--
-- ⚠️ KRITISK — MANUELL NØKKEL-REAPPLY: `create or replace function`
--   overskriver prod-funksjonen inkl. den ekte Resend-nøkkelen.
--   Etter apply MÅ Markus erstatte `REDACTED_RESEND_KEY` manuelt
--   (Dashboard → Database → Functions → send_booking_email).
--   Samme rutine som etter 0025/0026.
--
-- ⚠️ base_url beholdes som `http://localhost:5500` (uendret fra
--   0026). Triggeren trg_booking_email røres ikke (OID bevares).
--
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- ============================================================

begin;

-- ============================================================
-- P1-2: HTML-escape-hjelpefunksjon for e-post-templates
-- ============================================================
create or replace function public.html_escape(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
  select coalesce(
    replace(
      replace(
        replace(
          replace(
            replace(p_text, '&', '&amp;'),
            '<', '&lt;'),
          '>', '&gt;'),
        '"', '&quot;'),
      '''', '&#39;'),
    ''
  );
$$;

-- ============================================================
-- send_booking_email — brand-tema (0026) med HTML-escape
-- Alle new.<felt> går gjennom html_escape() via e_*-variablene.
-- ============================================================
create or replace function public.send_booking_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $body$
declare
  resend_key   text := 'REDACTED_RESEND_KEY';
  notify_to    text := 'post@westengenklinikk.example';
  from_email   text := 'Westengen Klinikk <onboarding@resend.dev>';
  base_url     text := 'http://localhost:5500';
  cancel_url   text;
  date_str     text := to_char(new.date, 'DD.MM.YYYY');
  time_str     text := to_char(new.time, 'HH24:MI');
  notify_html  text;
  -- Pre-escapet kunde-input (P1-2)
  e_name       text := public.html_escape(new.name);
  e_email      text := public.html_escape(new.email);
  e_phone      text := public.html_escape(new.phone);
  e_service    text := public.html_escape(new.service_name);
  e_staff      text := public.html_escape(new.staff_name);
  e_ref        text := public.html_escape(new.ref);
begin
  cancel_url := base_url || '/avbestill.html?token=' || new.cancel_token::text;

  -- Brand-tema HTML. All CSS inline, table-basert layout, web-safe
  -- fonter, maks 600px, ingen bilder — for e-postklient-kompatibilitet.
  notify_html :=
       '<!DOCTYPE html><html lang="no"><body style="margin:0; padding:0; background-color:#FAF7F1;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAF7F1;">'
    || '<tr><td align="center" style="padding:32px 12px;">'

    -- ===== 600px kort =====
    || '<table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px; max-width:600px; background-color:#ffffff;">'

    -- ----- HEADER (grønt band) -----
    || '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47; padding:46px 40px 40px;">'
    ||   '<div style="font-family:Georgia,serif; font-size:24px; letter-spacing:0.30em; color:#FAF7F1;">ERIKS&nbsp;ARENA</div>'
    ||   '<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:18px auto 16px;">'
    ||     '<tr><td style="width:46px; height:2px; background-color:#B8754A; font-size:0; line-height:0;">&nbsp;</td></tr>'
    ||   '</table>'
    ||   '<div style="font-family:Courier,monospace; font-size:11px; letter-spacing:0.24em; color:#A6C1AC;">NY BESTILLING</div>'
    || '</td></tr>'

    -- ----- BODY: intro + detalj-tabell -----
    || '<tr><td style="padding:40px 40px 6px;">'
    ||   '<div style="font-family:Georgia,serif; font-size:21px; color:#15191A;">'
    ||     e_name || ' har booket en time.</div>'
    || '</td></tr>'
    || '<tr><td style="padding:18px 40px 8px;">'
    ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">E-POST</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || e_email || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TELEFON</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || e_phone || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TJENESTE</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || e_service || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TERAPEUT</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || e_staff || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">DATO</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || date_str || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">TID</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Helvetica,Arial,sans-serif; font-size:15px; color:#15191A; vertical-align:top;">' || time_str || '</td>'
    ||     '</tr>'
    ||     '<tr>'
    ||       '<td width="118" style="padding:13px 16px 13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:11px; letter-spacing:0.07em; color:#76776F; vertical-align:top;">REFERANSE</td>'
    ||       '<td style="padding:13px 0; border-bottom:1px solid #ECE6DA; font-family:Courier,monospace; font-size:14px; color:#15191A; vertical-align:top;">' || e_ref || '</td>'
    ||     '</tr>'
    ||   '</table>'
    || '</td></tr>'

    -- ----- AVBESTILLINGS-SEKSJON (innrammet boks) -----
    || '<tr><td style="padding:26px 40px 40px;">'
    ||   '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F2EDE3; border:1px solid #E4DAC8;">'
    ||     '<tr><td align="center" style="padding:32px 32px 34px;">'
    ||       '<div style="font-family:Georgia,serif; font-size:18px; color:#15191A;">Trenger du å avbestille?</div>'
    ||       '<div style="font-family:Helvetica,Arial,sans-serif; font-size:13px; color:#5c5d55; padding-top:8px;">Klikk knappen under — senest 24 timer før timen.</div>'
    ||       '<table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:22px auto 0;">'
    ||         '<tr><td align="center" bgcolor="#3E6B47" style="background-color:#3E6B47; border-radius:4px;">'
    ||           '<a href="' || cancel_url || '" style="display:inline-block; padding:15px 42px; font-family:Helvetica,Arial,sans-serif; font-size:15px; font-weight:bold; letter-spacing:0.05em; color:#FAF7F1; text-decoration:none;">AVBESTILL TIMEN</a>'
    ||         '</td></tr>'
    ||       '</table>'
    ||       '<div style="font-family:Courier,monospace; font-size:11px; color:#8a8b82; padding-top:20px; word-break:break-all;">' || cancel_url || '</div>'
    ||     '</td></tr>'
    ||   '</table>'
    || '</td></tr>'

    -- ----- FOOTER (mørkt ink-band) -----
    || '<tr><td align="center" bgcolor="#15191A" style="background-color:#15191A; padding:30px 40px;">'
    ||   '<div style="font-family:Georgia,serif; font-size:15px; letter-spacing:0.20em; color:#FAF7F1;">WESTENGEN KLINIKK</div>'
    ||   '<div style="font-family:Helvetica,Arial,sans-serif; font-size:12px; line-height:1.7; color:#8f9089; padding-top:9px;">Storgata 1, 0155 Oslo<br>+47 400 00 000</div>'
    ||   '<div style="font-family:Courier,monospace; font-size:10px; letter-spacing:0.14em; color:#5f6058; padding-top:14px;">AUTOMATISK VARSEL</div>'
    || '</td></tr>'

    || '</table>'
    || '</td></tr></table>'
    || '</body></html>';

  -- Send via Resend gjennom pg_net (asynkront). Samme mekanisme som 0026.
  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || resend_key,
      'Content-Type',  'application/json'
    ),
    body    := jsonb_build_object(
      'from',    from_email,
      'to',      notify_to,
      'subject', 'Ny bestilling: ' || e_name || ' — ' || date_str || ' kl. ' || time_str,
      'html',    notify_html
    )
  );

  return new;

exception when others then
  -- E-post er sekundært: la bookingen committe selv om varselet feiler.
  raise notice 'send_booking_email feilet: % %', sqlstate, sqlerrm;
  return new;
end;
$body$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply + nøkkel-reapply):
--
-- A) html_escape virker:
--    select public.html_escape('<script>"&''');
--    -- &lt;script&gt;&quot;&amp;&#39;
--
-- B) Funksjonen bruker escaping + ekte nøkkel er på plass:
--    select case when prosrc ~ 'resend_key\s+text\s*:=\s*''re_'
--                then 'EKTE NØKKEL OK' else 'MÅ REAPPLY' end as status,
--           prosrc ~ 'html_escape' as has_escape
--      from pg_proc where proname = 'send_booking_email';
--    -- Forvent: EKTE NØKKEL OK + has_escape = true
--
-- C) Smoke-test: opprett en booking med navn = <script>alert(1)</script>
--    → e-posten viser teksten escapet (ikke renderet/kjørt).
-- ============================================================
