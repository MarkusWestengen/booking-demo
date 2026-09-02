-- ============================================================
-- 0076 — rester etter navnebytte, og vakten som manglet
-- ------------------------------------------------------------
-- Sveipen av databasen (docs/QA-lansering.md) fant fire ting.
-- Alle fire rettes her.
--
--   1. staff_members.bio hadde «Erik» i 8 av 9 rader. anon har SELECT
--      på kolonnen, og policyen slipper gjennom alt med aktiv = true,
--      så navnet på et tidligere kundeprosjekt sto lesbart for
--      publikum på behandlerlista.
--
--   2. Kolonnekommentaren på staff_members.color sa «Erik streng».
--      Det skal være «Tom streng». Et søk-og-erstatt uten ordgrense
--      har truffet det norske ordet «tom». Den kommentaren er
--      grunnen til at vi vet hvordan navnebyttene ble gjort.
--
--   3. notify_to i send_booking_email var en ekte privat
--      e-postadresse. Byttes til post@westengenklinikk.example, som
--      er den de tre andre e-postfunksjonene allerede bruker.
--
--   4. process_pending_review_emails har en vakt som hindrer
--      HTTP-kall så lenge resend_key er plassholderen. De tre andre
--      manglet den og sendte kallet uansett: 13 × 401 fra Resend
--      2026-09-02 mellom 10:45 og 10:54 UTC. Vakten speiles inn.
--
-- ------------------------------------------------------------
-- METODE
-- ------------------------------------------------------------
-- Ingen funksjonskropp er skrevet for hånd. Definisjonen leses ut av
-- katalogen med pg_get_functiondef(), endres i minnet, og kjøres
-- tilbake. Repoet er eldre enn produksjon — se 0074 — så filene i
-- supabase/migrations er ikke fasit for disse kroppene.
--
-- Den private e-postadressen står ikke i denne fila. Den matches med
-- et mønster mot det som faktisk ligger i katalogen, ikke mot en
-- hardkodet verdi. Repoet er offentlig.
--
-- Vakten er lest ut av process_pending_review_emails og speilet, ikke
-- funnet på. Eneste tilpasning er funksjonsnavnet i meldingen og
-- «return new» i stedet for «return», fordi de tre er
-- trigger-funksjoner. Kommentarlinja om cron-tikk er utelatt: den
-- gjelder bare den køstyrte funksjonen.
--
-- Kopi av alle fire kropper før endringen:
-- docs/db-funksjoner-før-0076.sql
--
-- Ytre blokker bruker $do$, vaktteksten $g$. Kroppene bruker kun
-- $function$, så ingen tagg kan kollidere.
--
-- Idempotent: kjøres den om igjen finner replace() ingenting å bytte,
-- og vakten settes ikke inn to ganger.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1) Biografiene
-- ------------------------------------------------------------
-- Erstatningen går mot det som faktisk står i radene. Genitiven må
-- tas først: bytter vi «Erik» før «Eriks», blir «Eriks» til
-- «Markuss». Norsk genitiv av et navn som ender på s er apostrof
-- alene — «Markus' metoder», ikke «Markus's».
do $do$
declare
  n int;
begin
  update public.staff_members
     set bio = replace(replace(bio, 'Eriks', 'Markus'''), 'Erik', 'Markus')
   where bio like '%Erik%';
  get diagnostics n = row_count;

  raise notice '0076: % biografi(er) oppdatert', n;

  if exists (
    select 1 from public.staff_members
     where coalesce(bio, '')  like '%Erik%'
        or coalesce(name, '') like '%Erik%'
        or coalesce(role, '') like '%Erik%'
  ) then
    raise exception '0076: «Erik» står igjen i staff_members';
  end if;

  if exists (
    select 1 from public.services
     where coalesce(name, '')        like '%Erik%'
        or coalesce(description, '') like '%Erik%'
        or coalesce(slug, '')        like '%Erik%'
  ) then
    raise exception '0076: «Erik» står i services — ikke forventet, se etter';
  end if;
end
$do$;

-- ------------------------------------------------------------
-- 2) Kolonnekommentaren
-- ------------------------------------------------------------
-- Leses ut av katalogen og endres kirurgisk, samme disiplin som
-- kroppene. Resten av kommentaren skal stå urørt.
do $do$
declare
  gammel text;
begin
  select col_description(a.attrelid, a.attnum)
    into gammel
    from pg_attribute a
   where a.attrelid = 'public.staff_members'::regclass
     and a.attname  = 'color';

  if gammel is null then
    raise exception '0076: fant ingen kommentar på staff_members.color';
  end if;

  if position('Erik streng' in gammel) > 0 then
    execute format('comment on column public.staff_members.color is %L',
                   replace(gammel, 'Erik streng', 'Tom streng'));
    raise notice '0076: kolonnekommentaren rettet';
  else
    raise notice '0076: kolonnekommentaren var allerede rettet';
  end if;
end
$do$;

-- ------------------------------------------------------------
-- 3) og 4) notify_to og vakten
-- ------------------------------------------------------------
do $do$
declare
  def      text;
  ny       text;
  vakt     text;
  i        int;
  n_epost  int := 0;
  n_vakt   int := 0;
  fn       text;
begin
  foreach fn in array array[
    'send_booking_email', 'send_contact_message_email', 'send_document_email'
  ] loop

    select pg_get_functiondef(p.oid)
      into def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = fn and p.prokind = 'f';

    if def is null then
      raise exception '0076: fant ikke public.%()', fn;
    end if;

    ny := def;

    -- 3) notify_to. Mønsteret matcher verdien som ligger der, så
    -- adressen aldri trenger å stå i denne fila.
    ny := regexp_replace(
            ny,
            'notify_to(\s+)text := ''[^'']*@gmail\.com'';',
            'notify_to\1text := ''post@westengenklinikk.example'';');
    if ny <> def then
      n_epost := n_epost + 1;
    end if;

    -- 4) Vakten, spleiset inn rett etter funksjonens egen «begin».
    -- Hver av de tre har nøyaktig én begin på toppnivå; exception-
    -- blokken hører til samme blokk og har ingen egen.
    if position('if resend_key = ''REDACTED_RESEND_KEY'' then' in ny) = 0 then
      vakt := format($g$  -- DO-GUARD (sandbox): så lenge nøkkelen er placeholder gjør vi
  -- INGENTING — ingen HTTP-kall. Speilet fra
  -- process_pending_review_emails i 0076.
  if resend_key = 'REDACTED_RESEND_KEY' then
    raise warning '%s: Resend-nøkkel er placeholder — hopper over (sandbox-modus).';
    return new;
  end if;

$g$, fn);

      i := position(E'\nbegin\n' in ny);
      if i = 0 then
        raise exception '0076: fant ingen «begin» på egen linje i %()', fn;
      end if;

      ny := left(ny, i + 6) || vakt || substr(ny, i + 7);
      n_vakt := n_vakt + 1;
    end if;

    if ny <> def then
      execute ny;
    end if;
  end loop;

  raise notice '0076: % notify_to byttet, % vakt(er) satt inn', n_epost, n_vakt;
end
$do$;

-- ------------------------------------------------------------
-- Sikkerhetsnett
-- ------------------------------------------------------------
do $do$
declare
  mangler text;
begin
  select string_agg(p.proname, ', ' order by p.proname)
    into mangler
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f'
     and p.proname in ('send_booking_email', 'send_contact_message_email',
                       'send_document_email', 'process_pending_review_emails')
     and position('if resend_key = ''REDACTED_RESEND_KEY'' then' in p.prosrc) = 0;

  if mangler is not null then
    raise exception '0076: vakten mangler fortsatt i: %', mangler;
  end if;

  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'
       and p.prosrc ~ '@gmail\.com'
  ) then
    raise exception '0076: en gmail-adresse står igjen i en funksjon i public';
  end if;
end
$do$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Biografiene:
--      select staff_id, bio from public.staff_members order by sortering;
--    -- Forvent: ingen «Erik», «Markus' metoder» med apostrof.
--
-- B) Kolonnekommentaren:
--      select col_description('public.staff_members'::regclass, attnum)
--        from pg_attribute
--       where attrelid = 'public.staff_members'::regclass and attname = 'color';
--    -- Forvent: «Tom streng = bruk frontend-fallback».
--
-- C) Vakt og adresse i alle fire:
--      select proname,
--             position('if resend_key = ''REDACTED_RESEND_KEY'' then' in prosrc) > 0 as har_vakt,
--             prosrc ~ '@gmail\.com' as har_gmail
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and proname in ('send_booking_email', 'send_contact_message_email',
--                         'send_document_email', 'process_pending_review_emails');
--    -- Forvent: true, false for alle fire.
--
-- D) Eier, security og search_path uendret:
--      select proname, prosecdef, pg_get_userbyid(proowner), proconfig
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and proname in ('send_booking_email', 'send_contact_message_email',
--                         'send_document_email');
--    -- Forvent: postgres, true, {search_path=public, extensions}.
-- ============================================================
