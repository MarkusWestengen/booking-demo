-- ============================================================
-- 0047_admin_booking_optional_contact.sql            2026-06-13
-- ------------------------------------------------------------
-- Admin-tilpasset «+ Ny booking»: ansatte som registrerer en
-- booking for noen som ringer trenger kun navn + behandler + tid.
-- E-post og telefon blir VALGFRIE i admin-flyten (lagres som ''
-- når de mangler — kolonnene forblir NOT NULL, ingen null-migrering).
--
-- To DB-endringer kreves:
--
-- 1) PHONE-CHECK: 0019 sin bookings_phone_min_digits krever ≥8
--    sifre på ALLE rader — den ville avvist admin-bookinger uten
--    telefon. Erstattes med: tom streng ELLER ≥8 sifre. Den
--    OFFENTLIGE flyten er uendret strengt gated: anon-INSERT-
--    policyen (0027) krever fortsatt length(phone) BETWEEN 3 AND 30
--    og frontend krever ≥8 sifre — kunder kan altså IKKE sende tom
--    telefon; kun authenticated (ansatte) kan.
--
-- 2) BEKREFTELSES-TRIGGER: trg_booking_email (0011) fyrer på hver
--    INSERT og ville forsøkt å sende e-post til ''. Re-skapes med
--    WHEN-guard så den hopper over rader uten e-post. Selve
--    funksjonen send_booking_email røres IKKE (den bærer prod-
--    nøkkelen og er beskyttet av DO-guard-mønsteret) — triggere
--    inneholder ingen hemmeligheter og kan trygt drop/create (jf.
--    0011 som gjør det samme).
--
-- Påminnelses-cron håndteres i frontend: admin-flyten setter
-- reminder_sent_at = now() når e-post mangler, så
-- process_pending_reminders() (0014) aldri plukker raden.
-- Kunderegisteret (kunder.html) grupperer på e-post og hopper
-- allerede over rader med tom e-post — ingen endring nødvendig.
--
-- Idempotent: DO-blokk-guards på constraint (drop hvis gammelt
-- uttrykk, skip hvis nytt finnes), drop trigger if exists.
-- Atomisk via begin/commit.
-- IKKE applisert av repoet — Markus kjører i Supabase Dashboard.
-- Avhenger av 0011 (trigger) + 0019 (constraint); ellers uavhengig.
-- ============================================================

begin;

-- ----- 1) Phone-CHECK: tillat tom streng (kun relevant for
--          authenticated — anon-policyen krever fortsatt utfylt) ---
do $$
declare
  has_old boolean;
begin
  -- Finnes 0019-constrainten (uansett uttrykk), dropp og re-skap
  -- med det nye uttrykket. Re-apply av 0047 er no-op-sikker fordi
  -- det nye uttrykket inneholder teksten 'phone = ''''' — sjekk den.
  select exists (
    select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
     where t.relname = 'bookings'
       and c.conname = 'bookings_phone_min_digits'
       and pg_get_constraintdef(c.oid) not like '%phone = %'
  ) into has_old;

  if has_old then
    alter table public.bookings drop constraint bookings_phone_min_digits;
    raise notice '0047: droppet gammel bookings_phone_min_digits (krevde 8 sifre på alle rader).';
  end if;

  if not exists (
    select 1
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
     where t.relname = 'bookings'
       and c.conname = 'bookings_phone_min_digits'
  ) then
    execute $ddl$
      alter table public.bookings
        add constraint bookings_phone_min_digits
        check (phone = '' or length(regexp_replace(phone, '[^0-9]', '', 'g')) >= 8)
        not valid
    $ddl$;
    raise notice '0047: ny bookings_phone_min_digits lagt til (tom ELLER >=8 sifre).';
  else
    raise notice '0047: bookings_phone_min_digits har allerede nytt uttrykk — hopper over.';
  end if;
end $$;

-- Alle eksisterende rader passerte den STRENGERE 0019-varianten,
-- så validate er garantert trygg.
alter table public.bookings
  validate constraint bookings_phone_min_digits;

-- ----- 2) Bekreftelses-trigger: hopp over rader uten e-post ------
-- Triggeren inneholder ingen secret — trygt å re-skape (0011-mønster).
drop trigger if exists trg_booking_email on public.bookings;
create trigger trg_booking_email
  after insert on public.bookings
  for each row
  when (coalesce(new.email, '') <> '')
  execute function public.send_booking_email();

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Constraint har nytt uttrykk (tom ELLER >=8 sifre):
--    select pg_get_constraintdef(c.oid)
--      from pg_constraint c
--      join pg_class t on t.oid = c.conrelid
--     where t.relname = 'bookings'
--       and c.conname = 'bookings_phone_min_digits';
--    -- Forvent: ... (phone = ''::text) OR (length(...) >= 8) ...
--
-- B) Trigger har WHEN-guard:
--    select pg_get_triggerdef(oid) from pg_trigger
--     where tgname = 'trg_booking_email';
--    -- Forvent: ... WHEN ((COALESCE(new.email, ''::text) <> ''::text)) ...
--
-- C) Anon kan fortsatt IKKE sende tom telefon (RLS-policy 0027):
--    select with_check from pg_policies
--     where tablename='bookings' and policyname like '%anon%insert%';
--    -- Forvent: ... length(coalesce(phone, '')) >= 3 ... (uendret)
--
-- D) Ende-til-ende: admin oppretter booking med kun navn+behandler+tid
--    → lagres (201), vises i Bestillinger + kalender, ingen e-post
--    forsøkes sendt, dukker IKKE opp i kunder.html (grupperes på e-post).
-- ============================================================
