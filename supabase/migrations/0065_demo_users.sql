-- ============================================================
-- 0065_demo_users.sql                                2026-09-01
-- ------------------------------------------------------------
-- To innloggede brukere for demoen: én admin og én terapeut.
--
-- HVORFOR DENNE FINNES
-- Halve systemet ligger bak innlogging — kalender, kunderegister,
-- journal, meldinger, tjenester, behandlere, audit-logg. Ingen
-- migrasjon har hittil opprettet en bruker, fordi kontoene i
-- produksjon ble laget for hånd i Supabase-dashbordet. En besøkende
-- i demoen har ikke det dashbordet, og kom derfor aldri lenger enn
-- til forsiden. Brukerne må ligge i migrasjonene.
--
-- Innloggingen er publisert åpent på forsiden og i demo-dialogen i
-- headeren. Det er meningen. Sikkerheten i demoen ligger ikke i at
-- passordet er hemmelig, men i at seed-dataene er skrivebeskyttet
-- (migrasjon 0066) og at alt nullstilles hvert døgn.
--
-- TO ROLLER, IKKE ÉN
-- Rolleskillet er en av tingene som er verdt å vise fram: admin ser
-- alle behandlere, alle kunder og audit-loggen; terapeuten ser sin
-- egen kalender og sine egne pasienter. Med bare én konto hadde det
-- vært usynlig.
--
-- HVORDAN
-- Supabase Auth lagrer brukere i auth.users og innloggingsmetoden i
-- auth.identities. Rollen leses av RLS-policyene gjennom
--   auth.jwt() -> 'app_metadata' ->> 'role'
-- og frontend leser staff_id og staff_name fra samme sted
-- (shared/auth.js, ansatt.html). Derfor må app_metadata settes her,
-- ikke i user_metadata — user_metadata kan brukeren endre selv.
--
-- Passordene hashes med bcrypt via pgcrypto. E-postene er bekreftet
-- direkte (email_confirmed_at), så ingen bekreftelses-e-post sendes;
-- domenet .example kan uansett ikke ta imot post.
--
-- Idempotent: faste UUID-er + «where not exists», så re-apply
-- verken dupliserer eller nullstiller et passord noen har byttet.
-- Atomisk via begin/commit.
--
-- ADVARSEL VED KOPIERING TIL ET EKTE OPPSETT
-- Ikke kjør denne filen mot en produksjonsdatabase. Den oppretter
-- kontoer med kjente passord. En ekte installasjon lager brukere
-- via Supabase Dashboard → Authentication → Users, eller via
-- Admin API med genererte passord.
-- ============================================================

begin;

-- pgcrypto gir crypt() og gen_salt(). Supabase legger den i
-- schemaet «extensions»; vi kvalifiserer kallene eksplisitt så
-- filen ikke er avhengig av search_path i den kjørende sesjonen.
create extension if not exists pgcrypto with schema extensions;

do $$
declare
  -- Faste UUID-er. Nøkkelen til at re-apply er en no-op, og til at
  -- 0066 kan peke på nøyaktig disse to kontoene.
  admin_id    uuid := '00000000-0000-4000-a000-000000000a01';
  terapeut_id uuid := '00000000-0000-4000-a000-000000000a02';

  admin_email    text := 'admin@westengenklinikk.example';
  terapeut_email text := 'terapeut@westengenklinikk.example';

  -- Publisert på forsiden. Se kommentaren øverst.
  admin_pw    text := 'demo-admin-2026';
  terapeut_pw text := 'demo-terapeut-2026';
begin

  -- ----- Admin ------------------------------------------------
  -- staff_id peker på grunnleggeren, som i demoen både behandler
  -- og administrerer. Det speiler hvordan en klinikk faktisk
  -- ser ut: eieren står i kalenderen og har alle rettigheter.
  if not exists (select 1 from auth.users where email = admin_email) then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000',
      admin_id,
      'authenticated',
      'authenticated',
      admin_email,
      extensions.crypt(admin_pw, extensions.gen_salt('bf')),
      now(),
      jsonb_build_object(
        'provider',   'email',
        'providers',  jsonb_build_array('email'),
        'role',       'admin',
        'staff_id',   'markus',
        'staff_name', 'Markus Westengen',
        'demo',       true
      ),
      jsonb_build_object('full_name', 'Markus Westengen'),
      now(), now(),
      '', '', '', ''
    );

    -- auth.identities er det GoTrue slår opp i ved e-post-innlogging.
    -- provider_id må være brukerens id som tekst for email-provideren.
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(),
      admin_id,
      admin_id::text,
      jsonb_build_object('sub', admin_id::text, 'email', admin_email, 'email_verified', true),
      'email',
      now(), now(), now()
    );
  end if;

  -- ----- Terapeut ---------------------------------------------
  -- Egen staff_id gir egen kalender og egen pasientliste. Det er
  -- denne kontoen som viser hva en ansatt IKKE får se.
  if not exists (select 1 from auth.users where email = terapeut_email) then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000',
      terapeut_id,
      'authenticated',
      'authenticated',
      terapeut_email,
      extensions.crypt(terapeut_pw, extensions.gen_salt('bf')),
      now(),
      jsonb_build_object(
        'provider',   'email',
        'providers',  jsonb_build_array('email'),
        'role',       'therapist',
        'staff_id',   'sofie',
        'staff_name', 'Sofie Aune',
        'demo',       true
      ),
      jsonb_build_object('full_name', 'Sofie Aune'),
      now(), now(),
      '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(),
      terapeut_id,
      terapeut_id::text,
      jsonb_build_object('sub', terapeut_id::text, 'email', terapeut_email, 'email_verified', true),
      'email',
      now(), now(), now()
    );
  end if;

end $$;

commit;

-- ============================================================
-- Verifikasjon (kjør manuelt etter apply):
--
-- A) Begge kontoene finnes, med rolle og staff_id på plass:
--    select email,
--           raw_app_meta_data ->> 'role'       as role,
--           raw_app_meta_data ->> 'staff_id'   as staff_id,
--           email_confirmed_at is not null     as bekreftet
--      from auth.users
--     where email like '%@westengenklinikk.example'
--     order by email;
--    -- Forvent 2 rader: admin/admin/markus/t og terapeut/therapist/sofie/t
--
-- B) Identiteten henger sammen (uten den feiler innlogging med
--    «Invalid login credentials» selv om brukeren finnes):
--    select u.email, i.provider
--      from auth.users u join auth.identities i on i.user_id = u.id
--     where u.email like '%@westengenklinikk.example';
--    -- Forvent 2 rader, provider = 'email'
--
-- C) Ende-til-ende: åpne ansatt.html, logg inn med
--    admin@westengenklinikk.example / demo-admin-2026.
--    Du skal lande i kalenderen med admin-merket i headeren.
--    Logg deretter inn som terapeuten og se at audit-logg og
--    behandlere er borte fra menyen.
-- ============================================================
