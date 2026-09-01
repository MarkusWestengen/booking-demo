-- Legger til description-kolonne på blocked_slots så stengte tider kan
-- merkes (lunsj, ferie, sykmelding, kurs) og rendres som logiske grupper i UI.
-- Eksisterende rader får null-description og fortsetter å fungere som før.

alter table public.blocked_slots
  add column if not exists description text;

create index if not exists blocked_slots_staff_date_idx
  on public.blocked_slots(staff_id, date);
