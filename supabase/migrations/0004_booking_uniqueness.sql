-- Hindre dobbelt-booking av samme slot.
-- Partial unique index: kun aktive bookinger (confirmed eller completed) blokkerer.
-- Cancelled / no_show frigir slot-en for ny booking.
create unique index if not exists bookings_active_slot_unique
  on public.bookings(staff_id, date, time)
  where status in ('confirmed', 'completed');
