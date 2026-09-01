-- ============================================================
-- Westengen Klinikk — Pasient-journal (journal_entries)
-- Migration 0001
-- ------------------------------------------------------------
-- Journal-notater knyttet til en pasient (via email + phone),
-- skrevet av en innlogget terapeut. Notater er IKKE knyttet
-- 1:1 til en booking — én pasient kan ha flere notater over tid.
--
-- Auth-modell (bekreftet ved å lese booking-admin.html):
--   • Supabase Auth med email/passord
--   • Rolle og staff_id ligger i auth.users.app_metadata
--     ({ role: 'admin'|'therapist', staff_id, staff_name })
--   • Anonyme (anon) skal ALDRI lese eller skrive journal.
-- ============================================================

create table if not exists public.journal_entries (
  id            uuid primary key default gen_random_uuid(),
  booking_id    text references public.bookings(id) on delete set null,
  patient_email text not null,
  patient_phone text not null,
  staff_id      text not null,
  staff_name    text not null,
  content       text not null check (length(trim(content)) > 0),
  created_at    timestamptz not null default now()
);

-- Pasient-oppslag matcher case-insensitivt på e-post (Supabase Auth
-- lagrer e-post lowercased — frontend lowercaser før query). Telefon
-- matches eksakt (frontend stripper whitespace før query).
create index if not exists journal_entries_patient_email_idx
  on public.journal_entries (lower(patient_email));
create index if not exists journal_entries_patient_phone_idx
  on public.journal_entries (patient_phone);
create index if not exists journal_entries_booking_id_idx
  on public.journal_entries (booking_id);
create index if not exists journal_entries_created_at_idx
  on public.journal_entries (created_at desc);

-- ============================================================
-- Row-Level Security
-- ------------------------------------------------------------
-- Standardatferd når RLS er på og ingen policy matcher = NEKT.
-- Vi gir EKSPLISITT bare authenticated-rollen tilgang.
-- Anon-rollen blokkeres dermed implisitt.
-- ============================================================
alter table public.journal_entries enable row level security;

-- Hvis migrasjonen kjøres flere ganger lokalt — fjern eksisterende.
drop policy if exists "journal: staff can read all"        on public.journal_entries;
drop policy if exists "journal: staff can insert"          on public.journal_entries;
drop policy if exists "journal: staff can update own"      on public.journal_entries;
drop policy if exists "journal: admin can delete"          on public.journal_entries;

-- Alle innloggede ansatte (admin + terapeuter) kan lese alt.
-- Journal følger pasienten på tvers av terapeuter — kollegaer ser
-- hverandres notater.
create policy "journal: staff can read all"
  on public.journal_entries for select
  to authenticated
  using (true);

-- Alle innloggede kan opprette notater. INSERT sjekker at staff_id
-- i raden matcher staff_id i JWT-en (eller at brukeren er admin og
-- skriver på vegne av en terapeut).
create policy "journal: staff can insert"
  on public.journal_entries for insert
  to authenticated
  with check (
    staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- Kun forfatter (eller admin) kan endre. Brukes for fremtidig
-- "rediger notat"-funksjon — i v1 lar UI-en det ikke skje, men
-- policy må uansett være riktig.
create policy "journal: staff can update own"
  on public.journal_entries for update
  to authenticated
  using (
    staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  )
  with check (
    staff_id = (auth.jwt() -> 'app_metadata' ->> 'staff_id')
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  );

-- Sletting er admin-only (medisinske notater bør være append-only
-- av juridiske grunner; admin har nødåpning).
create policy "journal: admin can delete"
  on public.journal_entries for delete
  to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

-- ============================================================
-- Sanity check (kjør manuelt etter migrasjon):
--   select * from pg_policies where tablename = 'journal_entries';
-- Skal vise 4 policyer, alle scoped til 'authenticated'.
-- ============================================================
