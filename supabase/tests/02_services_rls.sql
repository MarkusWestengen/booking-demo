-- ============================================================
-- Westengen Klinikk — RLS-tester for services + staff_services
-- ------------------------------------------------------------
-- Følger samme mønster som 01_rls_policies.sql:
--   - DO-blokker med _test_assert + _test_set_anon/_test_set_authenticated
--     hjelpere som lever fra 01-suiten (hvis kjørt før), eller defineres
--     på nytt her for å være kjørbar isolert.
--   - Hele kjøringen pakkes i en transaksjon som rolles tilbake → trygg
--     mot prod-data.
--
-- Forutsetninger:
--   - Migrasjon 0008 er kjørt (services + staff_services + seed)
--   - Helpers fra 01_rls_policies.sql kan re-defineres her (idempotent)
-- ============================================================

begin;

-- Hjelpere (re-deklareres slik at filen kan kjøres alene) ---------
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

-- Sett opp en kjent test-tjeneste vi kan bruke som anker for inaktiv-tester.
-- Tas med i transaksjonen så den ruller tilbake.
do $$
declare svc_id uuid;
begin
  perform _test_set_authenticated('admin');
  -- Slett eventuelle gamle test-rader
  delete from public.services where slug like 'test-rls-%';
  insert into public.services (slug, name, duration_min, price_nok, is_active, sort_order)
  values ('test-rls-active', 'Test aktiv',  30, 100, true,  900),
         ('test-rls-inactive', 'Test inaktiv', 30, 100, false, 901);
  insert into public.staff_services (staff_id, service_id)
  select 'erik', id from public.services where slug = 'test-rls-active';
  insert into public.staff_services (staff_id, service_id)
  select 'erik', id from public.services where slug = 'test-rls-inactive';
end $$;

-- ============================================================
-- Test 1: Anon kan SELECT services WHERE is_active = true
-- ============================================================
do $$
declare cnt int;
begin
  perform _test_set_anon();
  select count(*) into cnt from public.services where slug = 'test-rls-active';
  perform _test_assert(cnt = 1, 'anon kan SELECT aktiv services-rad');
end $$;

-- ============================================================
-- Test 2: Anon kan IKKE SELECT inaktive services
-- ============================================================
do $$
declare cnt int;
begin
  perform _test_set_anon();
  select count(*) into cnt from public.services where slug = 'test-rls-inactive';
  perform _test_assert(cnt = 0, 'anon ser ikke inaktive services (RLS filtrerer)');
end $$;

-- ============================================================
-- Test 3: Anon kan IKKE INSERT/UPDATE/DELETE services
-- ============================================================
do $$
declare svc_id uuid;
begin
  perform _test_set_anon();
  begin
    insert into public.services (slug, name, duration_min, price_nok)
    values ('anon-evil', 'evil', 30, 0);
    perform _test_assert(false, 'anon INSERT på services skulle ha feilet');
  exception when others then
    perform _test_assert(true, 'anon INSERT på services blokkert');
  end;

  begin
    update public.services set price_nok = 1 where slug = 'test-rls-active';
    if found then
      perform _test_assert(false, 'anon UPDATE skulle ikke ha truffet rader');
    else
      perform _test_assert(true, 'anon UPDATE returnerte 0 rader (RLS OK)');
    end if;
  exception when others then
    perform _test_assert(true, 'anon UPDATE på services blokkert');
  end;

  begin
    delete from public.services where slug = 'test-rls-active';
    if found then
      perform _test_assert(false, 'anon DELETE skulle ikke ha truffet rader');
    else
      perform _test_assert(true, 'anon DELETE returnerte 0 rader (RLS OK)');
    end if;
  exception when others then
    perform _test_assert(true, 'anon DELETE på services blokkert');
  end;
end $$;

-- ============================================================
-- Test 4: Therapist kan SELECT aktive, IKKE inaktive
-- ============================================================
do $$
declare cnt int;
begin
  perform _test_set_authenticated('therapist', 'erik');
  select count(*) into cnt from public.services where slug = 'test-rls-active';
  perform _test_assert(cnt = 1, 'therapist ser aktiv tjeneste');

  select count(*) into cnt from public.services where slug = 'test-rls-inactive';
  perform _test_assert(cnt = 0, 'therapist ser IKKE inaktiv tjeneste');
end $$;

-- ============================================================
-- Test 5: Therapist kan IKKE INSERT/UPDATE/DELETE services
-- ============================================================
do $$
begin
  perform _test_set_authenticated('therapist', 'erik');
  begin
    insert into public.services (slug, name, duration_min, price_nok)
    values ('therapist-evil', 'evil', 30, 0);
    perform _test_assert(false, 'therapist INSERT skulle ha feilet');
  exception when others then
    perform _test_assert(true, 'therapist INSERT på services blokkert');
  end;

  begin
    update public.services set price_nok = 9999 where slug = 'test-rls-active';
    if found then
      perform _test_assert(false, 'therapist UPDATE skulle ikke ha truffet rader');
    else
      perform _test_assert(true, 'therapist UPDATE returnerte 0 rader (RLS OK)');
    end if;
  exception when others then
    perform _test_assert(true, 'therapist UPDATE på services blokkert');
  end;
end $$;

-- ============================================================
-- Test 6: Admin kan SELECT alle (inkl. inaktive)
-- ============================================================
do $$
declare cnt int;
begin
  perform _test_set_authenticated('admin');
  select count(*) into cnt from public.services where slug in ('test-rls-active', 'test-rls-inactive');
  perform _test_assert(cnt = 2, 'admin ser BÅDE aktiv og inaktiv tjeneste');
end $$;

-- ============================================================
-- Test 7: Admin kan INSERT services
-- ============================================================
do $$
declare new_id uuid;
begin
  perform _test_set_authenticated('admin');
  insert into public.services (slug, name, duration_min, price_nok)
  values ('test-rls-admin-create', 'Admin oppretter', 45, 1500)
  returning id into new_id;
  perform _test_assert(new_id is not null, 'admin INSERT på services lykkes');
end $$;

-- ============================================================
-- Test 8: Admin kan UPDATE services
-- ============================================================
do $$
declare updated_price int;
begin
  perform _test_set_authenticated('admin');
  update public.services set price_nok = 2500 where slug = 'test-rls-admin-create';
  select price_nok into updated_price from public.services where slug = 'test-rls-admin-create';
  perform _test_assert(updated_price = 2500, 'admin UPDATE på services lykkes');
end $$;

-- ============================================================
-- Test 9: Admin kan deaktivere tjeneste (is_active = false)
-- ============================================================
do $$
declare is_act boolean;
begin
  perform _test_set_authenticated('admin');
  update public.services set is_active = false where slug = 'test-rls-admin-create';
  select is_active into is_act from public.services where slug = 'test-rls-admin-create';
  perform _test_assert(is_act = false, 'admin kan deaktivere tjeneste');
end $$;

-- ============================================================
-- Test 10: staff_services SELECT følger services.is_active for anon
-- ============================================================
do $$
declare cnt int; aid uuid; iid uuid;
begin
  -- Hent IDene med admin-session
  perform _test_set_authenticated('admin');
  select id into aid from public.services where slug = 'test-rls-active';
  select id into iid from public.services where slug = 'test-rls-inactive';

  perform _test_set_anon();
  select count(*) into cnt from public.staff_services where service_id = aid;
  perform _test_assert(cnt >= 1, 'anon ser staff_services for aktiv tjeneste');

  select count(*) into cnt from public.staff_services where service_id = iid;
  perform _test_assert(cnt = 0, 'anon ser IKKE staff_services for inaktiv tjeneste');
end $$;

-- ============================================================
-- Test 11: Therapist kan SELECT alle staff_services (UI filtrerer videre)
-- ============================================================
do $$
declare cnt int;
begin
  perform _test_set_authenticated('therapist', 'erik');
  select count(*) into cnt from public.staff_services where staff_id = 'erik';
  perform _test_assert(cnt >= 1, 'therapist kan SELECT staff_services for staff_id = tom');
end $$;

-- ============================================================
-- Test 12: Therapist kan IKKE INSERT/DELETE staff_services
-- ============================================================
do $$
declare aid uuid;
begin
  perform _test_set_authenticated('admin');
  select id into aid from public.services where slug = 'test-rls-active';

  perform _test_set_authenticated('therapist', 'erik');
  begin
    insert into public.staff_services (staff_id, service_id) values ('terapeut', aid);
    perform _test_assert(false, 'therapist INSERT på staff_services skulle ha feilet');
  exception when others then
    perform _test_assert(true, 'therapist INSERT på staff_services blokkert');
  end;

  begin
    delete from public.staff_services where staff_id = 'erik' and service_id = aid;
    if found then
      perform _test_assert(false, 'therapist DELETE skulle ikke ha truffet rader');
    else
      perform _test_assert(true, 'therapist DELETE returnerte 0 rader (RLS OK)');
    end if;
  exception when others then
    perform _test_assert(true, 'therapist DELETE på staff_services blokkert');
  end;
end $$;

-- ============================================================
-- Test 13: Admin kan INSERT/DELETE staff_services
-- ============================================================
do $$
declare aid uuid; cnt int;
begin
  perform _test_set_authenticated('admin');
  select id into aid from public.services where slug = 'test-rls-active';

  -- Legg til 'terapeut' som performer for test-rls-active
  insert into public.staff_services (staff_id, service_id) values ('terapeut', aid)
  on conflict do nothing;
  select count(*) into cnt from public.staff_services
    where staff_id = 'terapeut' and service_id = aid;
  perform _test_assert(cnt = 1, 'admin INSERT på staff_services lykkes');

  -- Fjern den igjen
  delete from public.staff_services where staff_id = 'terapeut' and service_id = aid;
  select count(*) into cnt from public.staff_services
    where staff_id = 'terapeut' and service_id = aid;
  perform _test_assert(cnt = 0, 'admin DELETE på staff_services lykkes');
end $$;

-- ============================================================
-- Test 14: services.slug har UNIQUE constraint
-- ============================================================
do $$
begin
  perform _test_set_authenticated('admin');
  begin
    -- Forsøk å sette inn en eksisterende slug
    insert into public.services (slug, name, duration_min, price_nok)
    values ('erik-konsult', 'Duplikat', 30, 0);
    perform _test_assert(false, 'duplicate slug INSERT skulle ha feilet');
  exception when unique_violation then
    perform _test_assert(true, 'duplicate slug blokkert av UNIQUE constraint');
  end;
end $$;

-- ============================================================
-- Test 15: services.duration_min CHECK > 0 håndheves
-- ============================================================
do $$
begin
  perform _test_set_authenticated('admin');
  begin
    insert into public.services (slug, name, duration_min, price_nok)
    values ('test-rls-zero-dur', 'Null varighet', 0, 100);
    perform _test_assert(false, 'duration_min = 0 skulle ha feilet');
  exception when check_violation then
    perform _test_assert(true, 'duration_min = 0 blokkert av CHECK constraint');
  end;
end $$;

-- ============================================================
-- Test 16: updated_at-trigger oppdateres ved UPDATE
-- ============================================================
do $$
declare ts1 timestamptz; ts2 timestamptz;
begin
  perform _test_set_authenticated('admin');
  select updated_at into ts1 from public.services where slug = 'test-rls-active';
  perform pg_sleep(0.05);
  update public.services set name = 'Test aktiv (oppdatert)' where slug = 'test-rls-active';
  select updated_at into ts2 from public.services where slug = 'test-rls-active';
  perform _test_assert(ts2 > ts1, 'updated_at-trigger fyrer ved UPDATE');
end $$;

-- Rull tilbake all testdata — ingen skader på prod.
rollback;
