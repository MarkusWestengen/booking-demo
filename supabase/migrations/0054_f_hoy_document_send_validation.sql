-- ============================================================
-- 0054_f_hoy_document_send_validation.sql            2026-06-13
-- ------------------------------------------------------------
-- F-HØY + F-MEDIUM fra security-review-2026-06-12: e-posttriggeren
-- på document_sends var en phishing-/spam-relay for enhver ansatt-
-- konto. INSERT-policyen sjekket kun rolle — verken customer_email
-- eller link_url ble validert, og sent_by/sent_by_name/document_title
-- var klientstyrte. En kompromittert terapeut-sesjon kunne POST-e
-- {customer_email: <offer>, document_title: 'Bekreft kontoen',
--  link_url: 'https://evil/phish'} i løkke og sende proff-utseende
-- phishing fra klinikkens domene, signert med en kollegas navn.
--
-- Fiks: en BEFORE INSERT-valideringstrigger på document_sends.
-- Bevisst IKKE en endring av send_document_email() — den bærer den
-- ekte Resend-nøkkelen i prod (DO-guard-mønsteret fra 0040), og en
-- create or replace ville overskrevet nøkkelen. Valideringen skjer
-- FØR raden finnes → AFTER-triggeren (e-posten) fyrer aldri for en
-- avvist rad.
--
-- Triggeren håndhever:
--   (1) document_id må peke på et faktisk dokument i
--       exercise_documents (ingen frittstående «lenke-sendinger»).
--   (2) link_url MÅ være en signert URL til prosjektets egen
--       exercise-documents-bucket — ingen eksterne URL-er i
--       «LAST NED»-knappen, noensinne.
--   (3) customer_email: enkel strukturell sjekk + lengdetak.
--   (4) document_title overskrives med tittelen fra
--       exercise_documents (autoritativ — klienten bestemmer ikke
--       hva e-posten påstår at den deler).
--   (5) sent_by/sent_by_name overskrives fra JWT (auth.uid() +
--       app_metadata) — utsendings-loggen kan ikke forfalskes og
--       e-posten kan ikke signeres med en annens navn.
--   (6) Rate-limit: maks 20 utsendinger per ansatt per time.
--
-- Frontend (dokumenter.html) sender allerede document_id, ekte
-- signert URL og egen identitet → ingen frontend-endring nødvendig.
--
-- search_path pinnes (SECURITY DEFINER-regel, jf. 0016/0020).
-- Idempotent: create or replace + drop/create trigger. Atomisk.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- AVHENGER AV: 0040 (tabeller + e-posttrigger).
-- ============================================================

begin;

create or replace function public.validate_document_send()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_doc        public.exercise_documents%rowtype;
  v_role       text := (auth.jwt() -> 'app_metadata' ->> 'role');
  v_staff_name text := (auth.jwt() -> 'app_metadata' ->> 'staff_name');
  v_recent     int;
  -- Prosjektets egen Storage-signering — eneste lovlige lenkemål.
  -- Prosjekt-ref-en var tidligere hardkodet her. Det bandt migrasjonen
  -- til én bestemt database og gjorde at enhver ny installasjon (som
  -- demoen) avviste alle dokumentlenker. Mønsteret er derfor gjort
  -- prosjekt-uavhengig: vi krever fortsatt HTTPS mot et supabase.co-
  -- prosjekt og nøyaktig vår egen private bucket, men ikke lenger en
  -- bestemt ref. `like` med underscore-wildcard er unngått ved å bruke
  -- et regulært uttrykk, siden `_` matcher ett tegn i like-mønstre.
  c_pattern    constant text :=
    '^https://[a-z0-9-]+\.supabase\.co/storage/v1/object/sign/exercise-documents/';
begin
  -- (1) Må referere et reelt dokument.
  if new.document_id is null then
    raise exception 'document_id mangler' using errcode = '23514';
  end if;
  select * into v_doc from public.exercise_documents where id = new.document_id;
  if not found then
    raise exception 'Ukjent dokument' using errcode = '23514';
  end if;

  -- (2) Lenken må gå til vår egen private bucket.
  if new.link_url is null or new.link_url !~ c_pattern then
    raise exception 'Ugyldig dokumentlenke' using errcode = '23514';
  end if;

  -- (3) Strukturell e-postsjekk + lengdetak.
  if new.customer_email is null
     or length(new.customer_email) > 320
     or new.customer_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Ugyldig e-postadresse' using errcode = '23514';
  end if;

  -- (4) Autoritativ tittel fra dokument-registeret.
  new.document_title := v_doc.title;

  -- (5) Autoritativ avsender-identitet fra JWT.
  new.sent_by := auth.uid();
  new.sent_by_name := coalesce(
    v_staff_name,
    case when v_role = 'admin' then 'Westengen Klinikk (admin)' else 'Westengen Klinikk' end
  );

  -- (6) Rate-limit per ansatt: 20/time.
  select count(*) into v_recent
    from public.document_sends
   where sent_by = new.sent_by
     and created_at > now() - interval '1 hour';
  if v_recent >= 20 then
    raise exception 'For mange utsendinger siste time — prøv igjen senere.'
      using errcode = '53400';
  end if;

  return new;
end;
$$;

comment on function public.validate_document_send() is
  'BEFORE INSERT på document_sends: krever reelt dokument, lenke til egen '
  'signert Storage-URL, gyldig e-post; overskriver tittel + avsender fra '
  'autoritative kilder (JWT/exercise_documents); 20/time per ansatt. '
  'Stopper phishing-relay-vektoren (F-HØY, revisjon 2026-06-12). Migrasjon 0054.';

revoke execute on function public.validate_document_send()
  from anon, authenticated, public;

drop trigger if exists trg_validate_document_send on public.document_sends;
create trigger trg_validate_document_send
  before insert on public.document_sends
  for each row
  execute function public.validate_document_send();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Trigger finnes og fyrer FØR e-posttriggeren:
--    select tgname from pg_trigger
--     where tgrelid = 'public.document_sends'::regclass
--     order by tgname;
--    -- Forvent: trg_document_email (AFTER) + trg_validate_document_send (BEFORE).
--
-- B) Phishing-payload avvises (ansatt-JWT via REST):
--    POST /rest/v1/document_sends
--      {"document_id": "<ekte uuid>", "document_title": "Bekreft kontoen",
--       "customer_email": "offer@example.com", "link_url": "https://evil.example/phish"}
--    -- Forvent: 4xx 'Ugyldig dokumentlenke'. INGEN e-post sendt.
--
-- C) Legitim sending fra dokumenter.html virker uendret, og raden
--    får sent_by = auth.uid() + sent_by_name fra JWT uansett hva
--    klienten sendte:
--    select document_title, sent_by, sent_by_name from document_sends
--     order by created_at desc limit 1;
-- ============================================================
