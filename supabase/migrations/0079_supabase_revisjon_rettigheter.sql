-- 0079 · Supabase-revisjon 2026-10-13: rettigheter, search_path, RLS-initplan, FK-indeks.
--
-- 1) Interne SECURITY DEFINER-funksjoner kan ikke lenger kalles via /rest/v1/rpc.
--    Triggerfunksjoner trenger ikke EXECUTE når triggeren fyrer (sjekkes bare ved
--    CREATE TRIGGER), og pg_cron kjører som postgres. service_role beholder EXECUTE.
--    Ingen av disse kalles med .rpc( fra frontend eller edge functions.
-- 2) gdpr_*/get_journal_entries/create_journal_entry kalles fra frontend
--    (shared/gdpr.js, kalender.html, kunde-detalj.html) og har allerede intern
--    rollesjekk (admin, evt. admin/therapist). De beholder EXECUTE for authenticated,
--    men anon/public strammes eksplisitt.
-- 3) demo_guard får search_path = '' (kroppen refererer ingen tabeller).
-- 4) RLS-policyer på reviews og journal_audit: auth.jwt() -> (select auth.jwt()).
-- 5) Indeks på document_sends.document_id (FK uten indeks).

-- 1) Kun triggere / cron / service_role
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.send_booking_sms()',
    'public.send_booking_email()',
    'public.send_document_email()',
    'public.send_contact_message_email()',
    'public.process_pending_reminders()',
    'public.process_pending_review_emails()',
    'public.process_pending_sms_reminders()',
    'public.log_journal_change()',
    'public.enforce_anon_insert_quota()',
    'public.enforce_unassigned_capacity()',
    'public.validate_document_send()',
    'public.demo_reset()',
    'public.demo_seed()',
    'public.rls_auto_enable()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- 2) Klientkalte, rollesjekkede funksjoner: kun innloggede (sjekk inni funksjonen)
revoke execute on function public.gdpr_erase_patient(text)  from public, anon;
revoke execute on function public.gdpr_export_patient(text) from public, anon;
revoke execute on function public.get_journal_entries(text, text) from public, anon;
revoke execute on function public.create_journal_entry(text, text, text, text) from public, anon;

-- 3) search_path
alter function public.demo_guard() set search_path = '';

-- 4) RLS-initplan
alter policy "reviews: admin select all" on public.reviews
  using ((((select auth.jwt()) -> 'app_metadata') ->> 'role') = 'admin');

alter policy "reviews: admin update" on public.reviews
  using      ((((select auth.jwt()) -> 'app_metadata') ->> 'role') = 'admin')
  with check ((((select auth.jwt()) -> 'app_metadata') ->> 'role') = 'admin');

alter policy "journal_audit: admin can read" on public.journal_audit
  using ((((select auth.jwt()) -> 'app_metadata') ->> 'role') = 'admin');

-- 5) FK-indeks
create index if not exists document_sends_document_id_idx
  on public.document_sends (document_id);
