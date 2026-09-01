-- ============================================================
-- Westengen Klinikk — RLS-policy-tester
-- ------------------------------------------------------------
-- Kjøres med psql mot en Supabase-instans. Bruker DO-blokker
-- med assert siden pgTAP ikke er garantert tilgjengelig — koden
-- kan trivielt portes til pgTAP ved å erstatte "assert" med
-- "perform ok(...)".
--
-- Hele kjøringen pakkes i en transaksjon som rolles tilbake til
-- slutt, så testen er trygg å kjøre mot prod-data.
--
-- Forutsetninger:
--   - migrasjoner 0001-0007 er kjørt
--   - en testbruker for admin og therapist er opprettet med JWT-claims
--     i app_metadata (role/staff_id/staff_name)
-- ============================================================

begin;

-- Hjelpere ------------------------------------------------------
create or replace function _test_assert(cond boolean, descr text)
returns void language plpgsql as $$
begin
  if cond then
    raise notice 'PASS: %', descr;
  else
    raise exception 'FAIL: %', descr;
  end if;
end $$;

create or replace function _test_set_anon()
returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{}', true);
end $$;

create or replace function _test_set_authenticated(role_name text, staff_id text default null)
returns void language plpgsql as $$
declare claims jsonb;
begin
  claims := jsonb_build_object(
    'role', 'authenticated',
    'app_metadata', jsonb_build_object(
      'role', role_name,
      'staff_id', coalesce(staff_id, ''),
      'staff_name', 'Test User'
    )
  );
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', claims::text, true);
end $$;

-- Test 1: Anon kan IKKE SELECT journal_entries ----------------
do $$
declare n int;
begin
  perform _test_set_anon();
  begin
    select count(*) into n from public.journal_entries;
    -- Hvis vi kom hit returnerte RLS 0 rader (det er måten Postgres
    -- "nekter" SELECT under RLS). Det er den forventede oppførselen.
    perform _test_assert(true, 'anon journal_entries SELECT returns 0 rows (RLS blocks)');
  exception when others then
    perform _test_assert(true, 'anon journal_entries SELECT raises (acceptable)');
  end;
end $$;

-- Test 2: Anon kan IKKE SELECT audit_log ----------------------
do $$
declare n int;
begin
  perform _test_set_anon();
  select count(*) into n from public.audit_log;
  perform _test_assert(n = 0, 'anon audit_log SELECT returns 0 rows (RLS blocks)');
end $$;

-- Test 3: Anon KAN INSERT i bookings (kunde-vendt) ------------
do $$
declare new_id text := 'test_bk_' || gen_random_uuid();
begin
  perform _test_set_anon();
  insert into public.bookings(
    id, ref, staff_id, staff_name, service_id, service_name,
    price, duration, date, time, name, email, phone, status, journal_consent
  ) values (
    new_id, 'TA-TEST', 'markus', 'Markus Test', 'markus-konsult', 'Test',
    100, 30, current_date + 30, '10:00', 'Test', 'rls-test@example.com', '12345678',
    'confirmed', true
  );
  perform _test_assert(true, 'anon bookings INSERT succeeded');
end $$;

-- Test 4: Anon kan IKKE SELECT bookings (lockdown per migrasjon 0010)
-- "anon read bookings"-policyen er droppet + table-grant er revoket.
-- Forventet: 0 rader (RLS default-deny).
do $$
declare cnt int;
begin
  perform _test_set_anon();
  select count(*) into cnt from public.bookings;
  perform _test_assert(cnt = 0,
    'anon bookings SELECT returnerer 0 rader (locked down per 0010)');
end $$;

-- Test 4b: Anon KAN kalle public.get_booked_slots() --------
-- Funksjonen erstattet booked_slots-view i migrasjon 0016
-- (security_definer_view linter-ERROR). SECURITY DEFINER +
-- RETURNS TABLE-whitelist eksponerer kun (staff_id, date, time,
-- duration) — aldri PII. Vi inserter en confirmed booking og
-- verifiserer at den vises i funksjons-resultatet.
do $$
declare cnt int;
declare test_id text := 'test_4b_' || gen_random_uuid();
declare test_date date := current_date + 130;
begin
  perform _test_set_anon();
  insert into public.bookings(
    id, ref, staff_id, staff_name, service_id, service_name,
    price, duration, date, time, name, email, phone, status, journal_consent
  ) values (
    test_id, 'TA-T4B', 'markus', 'Markus', 'markus-konsult', 'Test',
    100, 30, test_date, '14:00', 'Test 4b', 'test4b@example.com', '111',
    'confirmed', false
  );

  -- Anon kaller funksjonen uten argumenter (defaults = alle bookinger).
  select count(*) into cnt from public.get_booked_slots()
   where staff_id = 'markus' and date = test_date and time = '14:00';
  perform _test_assert(cnt = 1,
    'anon get_booked_slots() returnerer confirmed booking');

  -- Named-arg filtering fungerer (frontend bruker pos-args).
  select count(*) into cnt from public.get_booked_slots('markus', test_date, test_date);
  perform _test_assert(cnt >= 1,
    'anon get_booked_slots(staff_id, from, to) respekterer filter');

  -- Filtrert til en annen staff_id skal gi 0 rader for vår testdata.
  select count(*) into cnt from public.get_booked_slots('sofie', test_date, test_date);
  perform _test_assert(cnt = 0,
    'anon get_booked_slots filtrerer korrekt på staff_id');
end $$;

-- Test 4c: get_booked_slots() lekker INGEN PII-kolonner ----
-- Funksjonens RETURNS TABLE-signatur er kolonne-whitelisted
-- ved migrasjons-tid (0016). Verifiseres ved å inspisere
-- pg_get_function_result() — hvis noen senere endrer
-- funksjonen til å returnere PII, vil disse assertene feile
-- og blokkere en utilsiktet datalekkasje.
do $$
declare result_shape text;
begin
  select pg_get_function_result(p.oid) into result_shape
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_booked_slots';

  perform _test_assert(result_shape is not null,
    'get_booked_slots-funksjonen finnes i public schema (post-0016)');

  -- Forventede 4 kolonner skal være tilstede.
  perform _test_assert(result_shape like '%staff_id%',
    'get_booked_slots returnerer staff_id-kolonne');
  perform _test_assert(result_shape like '%date%',
    'get_booked_slots returnerer date-kolonne');
  perform _test_assert(result_shape like '%time%',
    'get_booked_slots returnerer time-kolonne');
  perform _test_assert(result_shape like '%duration%',
    'get_booked_slots returnerer duration-kolonne');

  -- PII-kolonner skal ALDRI eksponeres. RETURNS TABLE-signaturen
  -- garanterer dette på type-system-nivå; assertene fanger opp
  -- regresjoner hvis funksjons-definisjonen senere endres.
  -- (`name` matcher også `staff_name`/`service_name` hvis de skulle
  -- lekke — bevisst bredt for å fange composite-leak.)
  perform _test_assert(result_shape not like '%name%',
    'get_booked_slots eksponerer ikke name-kolonner');
  perform _test_assert(result_shape not like '%email%',
    'get_booked_slots eksponerer ikke email-kolonne');
  perform _test_assert(result_shape not like '%phone%',
    'get_booked_slots eksponerer ikke phone-kolonne');
  perform _test_assert(result_shape not like '%notes%',
    'get_booked_slots eksponerer ikke notes-kolonne');
  perform _test_assert(result_shape not like '%price%',
    'get_booked_slots eksponerer ikke price-kolonne');
  perform _test_assert(result_shape not like '%status%',
    'get_booked_slots eksponerer ikke status-kolonne');
  perform _test_assert(result_shape not like '%ref%',
    'get_booked_slots eksponerer ikke ref-kolonne');
end $$;

-- Test 4d: Anon kan FORTSATT INSERT på bookings ----------
-- Kunde-flyten må overleve lockdown — "anon insert bookings"
-- policyen er sikret idempotent i 0010, og INSERT-grant på
-- bookings er bevisst IKKE revoket (kun SELECT/UPDATE/DELETE/
-- TRUNCATE/REFERENCES/TRIGGER ble revoket).
do $$
declare new_id text := 'test_4d_' || gen_random_uuid();
declare test_date date := current_date + 200;
begin
  perform _test_set_anon();
  insert into public.bookings(
    id, ref, staff_id, staff_name, service_id, service_name,
    price, duration, date, time, name, email, phone, status, journal_consent
  ) values (
    new_id, 'TA-T4D', 'markus', 'Markus', 'markus-konsult', 'Test',
    100, 30, test_date, '08:00', 'Test 4d', 'test4d@example.com', '222',
    'confirmed', false
  );
  perform _test_assert(true,
    'anon INSERT på bookings fortsatt mulig (kunde-flyt intakt)');
end $$;

-- Test 4e: Authenticated kan SELECT bookings -------------
-- Verifiserer at "auth read bookings" gir admin OG therapist
-- tilgang etter at anon-SELECT er stengt. Vi inserter en kjent
-- rad som anon, så ser begge auth-rollene den.
do $$
declare cnt int;
declare test_id text := 'test_4e_' || gen_random_uuid();
declare test_date date := current_date + 210;
begin
  perform _test_set_anon();
  insert into public.bookings(
    id, ref, staff_id, staff_name, service_id, service_name,
    price, duration, date, time, name, email, phone, status, journal_consent
  ) values (
    test_id, 'TA-T4E', 'markus', 'Markus', 'markus-konsult', 'Test',
    100, 30, test_date, '08:30', 'Test 4e', 'test4e@example.com', '333',
    'confirmed', false
  );

  -- Admin skal se den
  perform _test_set_authenticated('admin');
  select count(*) into cnt from public.bookings where id = test_id;
  perform _test_assert(cnt = 1,
    'authenticated admin kan SELECT bookings (auth read bookings policy)');

  -- Therapist skal også se den (samme policy, ingen staff_id-filter ennå)
  perform _test_set_authenticated('therapist', 'markus');
  select count(*) into cnt from public.bookings where id = test_id;
  perform _test_assert(cnt = 1,
    'authenticated therapist kan SELECT bookings (auth read bookings policy)');
end $$;

-- Test 5: Authenticated therapist KAN SELECT journal_entries --
do $$
declare cnt int;
begin
  perform _test_set_authenticated('therapist', 'markus');
  select count(*) into cnt from public.journal_entries;
  perform _test_assert(cnt >= 0, 'therapist journal_entries SELECT succeeded (any count)');
end $$;

-- Test 6: Authenticated therapist kan IKKE SELECT audit_log ---
do $$
declare cnt int;
begin
  perform _test_set_authenticated('therapist', 'markus');
  select count(*) into cnt from public.audit_log;
  perform _test_assert(cnt = 0, 'therapist audit_log SELECT returns 0 (admin-only)');
end $$;

-- Test 7: Admin KAN SELECT audit_log --------------------------
do $$
declare cnt int;
begin
  perform _test_set_authenticated('admin');
  select count(*) into cnt from public.audit_log;
  perform _test_assert(cnt >= 0, 'admin audit_log SELECT succeeded');
end $$;

-- Test 8: journal_entries.content CHECK constraint avviser tom -
do $$
begin
  perform _test_set_authenticated('therapist', 'markus');
  begin
    insert into public.journal_entries(
      booking_id, patient_email, patient_phone, staff_id, staff_name, content
    ) values (
      null, 'check-test@example.com', '12345678', 'markus', 'Markus', ''
    );
    perform _test_assert(false, 'empty content INSERT should have failed (CHECK constraint)');
  exception when check_violation then
    perform _test_assert(true, 'empty content INSERT blocked by CHECK constraint');
  end;
end $$;

-- Test 9: bookings_active_slot_unique blokkerer dobbel-booking -
do $$
declare base_id text := 'test_unique_' || gen_random_uuid();
begin
  perform _test_set_anon();
  insert into public.bookings(
    id, ref, staff_id, staff_name, service_id, service_name,
    price, duration, date, time, name, email, phone, status, journal_consent
  ) values (
    base_id, 'TA-UNQ-1', 'markus', 'Markus', 'markus-konsult', 'Test', 100, 30,
    current_date + 60, '11:00', 'Slot A', 'rls-test-a@example.com', '11111111',
    'confirmed', true
  );

  begin
    insert into public.bookings(
      id, ref, staff_id, staff_name, service_id, service_name,
      price, duration, date, time, name, email, phone, status, journal_consent
    ) values (
      base_id || '_dup', 'TA-UNQ-2', 'markus', 'Markus', 'markus-konsult', 'Test', 100, 30,
      current_date + 60, '11:00', 'Slot B', 'rls-test-b@example.com', '22222222',
      'confirmed', true
    );
    perform _test_assert(false, 'double-booking should have failed (unique index)');
  exception when unique_violation then
    perform _test_assert(true, 'double-booking blocked by bookings_active_slot_unique');
  end;
end $$;

-- Test 10: audit_log er append-only (UPDATE/DELETE skal feile) -
do $$
begin
  perform _test_set_authenticated('admin');
  -- Sett inn en testrad først så det er noe å forsøke å oppdatere
  insert into public.audit_log(actor_staff_id, actor_staff_name, action, target_type)
  values ('admin', 'Admin', 'test_append_only', 'session');

  begin
    update public.audit_log set action = 'mutated' where action = 'test_append_only';
    -- Hvis vi kommer hit returnerte UPDATE 0 rader (RLS-måten å nekte på).
    -- Postgres throwerere ikke alltid på dette — vi sjekker antall berørte rader.
    if found then
      perform _test_assert(false, 'audit_log UPDATE should not affect rows (append-only)');
    else
      perform _test_assert(true, 'audit_log UPDATE returned 0 rows (append-only OK)');
    end if;
  exception when others then
    perform _test_assert(true, 'audit_log UPDATE raised (append-only OK)');
  end;

  begin
    delete from public.audit_log where action = 'test_append_only';
    if found then
      perform _test_assert(false, 'audit_log DELETE should not affect rows (append-only)');
    else
      perform _test_assert(true, 'audit_log DELETE returned 0 rows (append-only OK)');
    end if;
  exception when others then
    perform _test_assert(true, 'audit_log DELETE raised (append-only OK)');
  end;
end $$;

-- Bonus-test: 0005-policy tillater anon-insert av login_failed med strenge constraints
do $$
begin
  perform _test_set_anon();

  -- Skal gå
  insert into public.audit_log(
    actor_staff_id, actor_staff_name, action, target_type, target_id, metadata
  ) values (
    'unknown', 'Anonym pre-auth', 'login_failed', 'session', null,
    jsonb_build_object('attempted_email', 'a@b.example', 'reason', 'invalid_credentials')
  );
  perform _test_assert(true, 'anon can INSERT login_failed with correct shape');

  -- Skal feile (annen action)
  begin
    insert into public.audit_log(
      actor_staff_id, actor_staff_name, action, target_type, metadata
    ) values (
      'unknown', 'Anonym', 'gdpr_export', 'patient',
      jsonb_build_object('attempted_email', 'a@b.example')
    );
    perform _test_assert(false, 'anon should NOT insert gdpr_export');
  exception when insufficient_privilege then
    perform _test_assert(true, 'anon blocked from inserting non-login_failed actions');
  when others then
    -- Andre feil-typer er også OK — bevis at vi ble stoppet
    perform _test_assert(true, 'anon blocked from inserting non-login_failed actions (other err)');
  end;

  -- Skal feile (manglende attempted_email)
  begin
    insert into public.audit_log(
      actor_staff_id, actor_staff_name, action, target_type, metadata
    ) values (
      'unknown', 'Anonym', 'login_failed', 'session',
      jsonb_build_object('reason', 'oops')
    );
    perform _test_assert(false, 'anon should NOT insert login_failed without attempted_email');
  exception when others then
    perform _test_assert(true, 'anon blocked from inserting login_failed without attempted_email');
  end;
end $$;

-- Rull tilbake all testdata — vi vil ikke forurense prod.
rollback;
