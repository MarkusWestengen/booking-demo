-- Database webhook som kaller Edge Function ved INSERT eller UPDATE av status
-- på bookings-tabellen. Bruker pg_net-extension for HTTP-kall.
--
-- Forutsetninger som må settes manuelt i Supabase Dashboard FØR denne kjøres:
--   - app.edge_function_url   = full URL til deployd send-booking-email
--   - app.webhook_secret      = randomly generated secret (samme som settes
--                                 som Edge Function secret WEBHOOK_SECRET)
-- Disse settes via Database → Settings → Custom Postgres Parameters
-- (eller psql: ALTER DATABASE postgres SET app.edge_function_url = '...';).

create extension if not exists pg_net;

create or replace function notify_booking_change()
returns trigger
language plpgsql
security definer
as $$
declare
  webhook_url text := current_setting('app.edge_function_url', true);
  webhook_secret text := current_setting('app.webhook_secret', true);
  payload jsonb;
  event_type text;
begin
  -- Hvis kontekst-variablene ikke er satt, hopp ut stille — vi vil ikke
  -- breke booking-flyten bare fordi e-post-konfig mangler.
  if webhook_url is null or webhook_url = '' then
    return new;
  end if;

  if TG_OP = 'INSERT' then
    event_type := 'confirmation';
  elsif TG_OP = 'UPDATE' and OLD.status is distinct from NEW.status and NEW.status = 'cancelled' then
    event_type := 'cancellation';
  else
    return new;
  end if;

  payload := jsonb_build_object(
    'event', event_type,
    'booking', row_to_json(NEW)
  );

  perform net.http_post(
    url := webhook_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Webhook-Secret', coalesce(webhook_secret, '')
    ),
    body := payload
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_booking_change on public.bookings;
create trigger trg_notify_booking_change
  after insert or update on public.bookings
  for each row
  execute function notify_booking_change();
