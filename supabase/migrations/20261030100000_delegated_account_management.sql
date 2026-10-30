-- =============================================================================
-- Delegated account management, and no-role accounts become read-only
-- =============================================================================
-- Until now every account on either stack was made by the lab administrator
-- with scripts/server/create-user.sh, which needs the service_role key and a
-- shell on the host. With other teams asking for access that does not scale,
-- and it cannot be handed to a team lead without handing over the whole
-- database.
--
-- Decided 2026-10-30 (owner):
--   * curators (team leads) create accounts and grant or revoke `contributor`;
--     only admins grant `curator` or `admin`;
--   * accounts are made by a curator, not by self-signup -- GOTRUE_DISABLE_SIGNUP
--     goes to true in docker/.env;
--   * roles stay global (no per-team ownership of rows yet).
--
-- Why SQL and not the GoTrue admin endpoint: that endpoint wants the
-- service_role key, so it needs a server-side caller holding it, and Edge
-- Functions were removed from this design (XRFF-351). A SECURITY DEFINER
-- function is that caller, with the role check inside it. The rows it writes
-- are the same shape GoTrue's admin endpoint writes for create-user.sh
-- (compared column by column on dev): confirmed email, the token columns '' not
-- NULL -- GoTrue fails sign-in with "converting NULL to string" otherwise -- and
-- one `email` identity.
--
-- Why a generated password and not an invite: mail from dt.unr does not leave
-- the host (outbound 25/465/587 to the university relays is closed, measured
-- 2026-10-30), so an invite or reset link has nowhere to go. The curator hands
-- the one-time password over; the account is flagged must_change_password and
-- the portal asks the holder to change it (PUT /auth/v1/user with their own
-- token). Once SMTP is opened this can move to invite links.
--
-- Every create / role change / reset is written to shared.account_events, so
-- what curators do stays visible to admins without asking.
--
-- Second part: 18 write policies on metadata tables were `TO authenticated
-- USING (true)`, so ANY signed-in account -- including one with no role --
-- could write species, sensors, plots, scenarios, campaigns, processes, events
-- and locations. Harmless while only the administrator made accounts; not once
-- team leads do. They now require shared.is_contributor() (admin, curator or
-- contributor), commands unchanged. Only the jobs page signs in with a user
-- token today; every connector uses service_role, which these policies do not
-- touch.
--
-- Mirrored to init 68-delegated-account-management.sql.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The record of who did what to which account
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS shared.account_events (
    account_event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at      timestamptz NOT NULL DEFAULT now(),
    actor_id         uuid,
    actor_email      text,
    target_email     text NOT NULL,
    action           text NOT NULL CHECK (action IN ('create', 'set_role', 'reset_password')),
    old_role         text,
    new_role         text
);

COMMENT ON TABLE shared.account_events IS
    'Account creations, role changes and password resets made through public.create_account / set_account_role / reset_account_password. Written only by those functions; curators and admins can read it.';

ALTER TABLE shared.account_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Curators can read account events" ON shared.account_events;
CREATE POLICY "Curators can read account events" ON shared.account_events
    FOR SELECT TO authenticated USING (shared.is_curator());

REVOKE ALL ON shared.account_events FROM anon, authenticated;
GRANT SELECT ON shared.account_events TO authenticated;
GRANT ALL ON shared.account_events TO service_role;

-- -----------------------------------------------------------------------------
-- 2. Which role tiers the caller may hand out or take away
-- -----------------------------------------------------------------------------
-- NULL stands for "no role" (read-only). An admin manages every tier; a curator
-- manages only accounts that are, and stay, below curator.

CREATE OR REPLACE FUNCTION shared.may_manage_role(p_role text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
    SELECT CASE
        WHEN shared.is_admin()   THEN p_role IS NULL OR p_role IN ('contributor', 'curator', 'admin')
        WHEN shared.is_curator() THEN p_role IS NULL OR p_role = 'contributor'
        ELSE false
    END;
$$;

COMMENT ON FUNCTION shared.may_manage_role(text) IS
    'True when the caller may grant, revoke or reset an account at this role tier (NULL = no role). Admins: every tier. Curators: no role and contributor only.';

REVOKE ALL ON FUNCTION shared.may_manage_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION shared.may_manage_role(text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. The four calls the portal makes
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.new_account_password() RETURNS text
    LANGUAGE sql VOLATILE
    SET search_path TO ''
    AS $$
    -- 15 random bytes -> 20 URL-safe characters, no padding, no look-alike
    -- trouble from '+' and '/' when it is read out over the phone.
    SELECT translate(encode(extensions.gen_random_bytes(15), 'base64'), '+/', '-_');
$$;

REVOKE ALL ON FUNCTION shared.new_account_password() FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE FUNCTION public.list_accounts()
    RETURNS TABLE (
        email                text,
        role                 text,
        created_at           timestamptz,
        last_sign_in_at      timestamptz,
        must_change_password boolean,
        manageable           boolean
    )
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can list accounts'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    RETURN QUERY
    SELECT u.email::text,
           u.raw_app_meta_data ->> 'role',
           u.created_at,
           u.last_sign_in_at,
           COALESCE((u.raw_user_meta_data ->> 'must_change_password')::boolean, false),
           shared.may_manage_role(u.raw_app_meta_data ->> 'role') AND u.id <> auth.uid()
      FROM auth.users u
     WHERE u.deleted_at IS NULL
       AND NOT u.is_anonymous
     ORDER BY u.email;
END;
$$;

COMMENT ON FUNCTION public.list_accounts() IS
    'Every account with its role tier and last sign-in; `manageable` says whether the caller may change it. Curators and admins only.';


CREATE OR REPLACE FUNCTION public.create_account(p_email text, p_role text DEFAULT NULL)
    RETURNS TABLE (email text, role text, password text)
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_email    text := lower(btrim(p_email));
    v_role     text := NULLIF(btrim(p_role), '');
    v_id       uuid := gen_random_uuid();
    v_password text;
    v_now      timestamptz := now();
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can create accounts'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    IF v_email IS NULL OR v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION 'Not an email address: %', COALESCE(p_email, '(empty)')
            USING ERRCODE = '22023';
    END IF;

    IF v_role IS NOT NULL AND v_role NOT IN ('contributor', 'curator', 'admin') THEN
        RAISE EXCEPTION 'Unknown role: %', v_role
            USING ERRCODE = '22023',
                  HINT = 'Use contributor, curator or admin -- or leave it empty for a read-only account.';
    END IF;

    IF NOT shared.may_manage_role(v_role) THEN
        RAISE EXCEPTION 'You cannot create a % account', v_role
            USING ERRCODE = '42501',
                  HINT = 'Curators create read-only and contributor accounts; only admins grant curator or admin.';
    END IF;

    IF EXISTS (SELECT 1 FROM auth.users u WHERE lower(u.email) = v_email AND u.deleted_at IS NULL) THEN
        RAISE EXCEPTION 'An account for % already exists', v_email
            USING ERRCODE = '23505',
                  HINT = 'Change its role or reset its password instead.';
    END IF;

    v_password := shared.new_account_password();

    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
        v_email, extensions.crypt(v_password, extensions.gen_salt('bf')),
        v_now,
        jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'))
            || CASE WHEN v_role IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('role', v_role) END,
        jsonb_build_object('must_change_password', true),
        v_now, v_now,
        '', '', '', ''
    );

    INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    VALUES (
        v_id::text, v_id,
        jsonb_build_object('sub', v_id::text, 'email', v_email,
                           'email_verified', false, 'phone_verified', false),
        'email', v_now, v_now
    );

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, new_role)
    VALUES (auth.uid(), auth.jwt() ->> 'email', v_email, 'create', v_role);

    RETURN QUERY SELECT v_email, v_role, v_password;
END;
$$;

COMMENT ON FUNCTION public.create_account(text, text) IS
    'Create a confirmed email/password account and return its one-time password. Curators: read-only (NULL) or contributor; admins: any tier. Logged to shared.account_events.';


CREATE OR REPLACE FUNCTION public.set_account_role(p_email text, p_role text DEFAULT NULL)
    RETURNS TABLE (email text, role text)
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_email text := lower(btrim(p_email));
    v_role  text := NULLIF(btrim(p_role), '');
    v_id    uuid;
    v_old   text;
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can change roles'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    IF v_role IS NOT NULL AND v_role NOT IN ('contributor', 'curator', 'admin') THEN
        RAISE EXCEPTION 'Unknown role: %', v_role
            USING ERRCODE = '22023',
                  HINT = 'Use contributor, curator or admin -- or leave it empty for read-only.';
    END IF;

    SELECT u.id, u.raw_app_meta_data ->> 'role' INTO v_id, v_old
      FROM auth.users u
     WHERE lower(u.email) = v_email AND u.deleted_at IS NULL;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'No account for %', COALESCE(p_email, '(empty)')
            USING ERRCODE = 'P0002';
    END IF;

    -- Nobody changes their own tier: a curator cannot promote themselves, and
    -- an admin cannot lock the lab out by demoting the last admin by accident.
    IF v_id = auth.uid() THEN
        RAISE EXCEPTION 'You cannot change your own role'
            USING ERRCODE = '42501',
                  HINT = 'Ask another admin.';
    END IF;

    IF NOT (shared.may_manage_role(v_old) AND shared.may_manage_role(v_role)) THEN
        RAISE EXCEPTION 'You cannot change a % account to %',
                COALESCE(v_old, 'read-only'), COALESCE(v_role, 'read-only')
            USING ERRCODE = '42501',
                  HINT = 'Curators manage read-only and contributor accounts; only admins grant or revoke curator and admin.';
    END IF;

    UPDATE auth.users u
       SET raw_app_meta_data = CASE WHEN v_role IS NULL
                                    THEN COALESCE(u.raw_app_meta_data, '{}'::jsonb) - 'role'
                                    ELSE COALESCE(u.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', v_role)
                               END,
           updated_at = now()
     WHERE u.id = v_id;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, old_role, new_role)
    VALUES (auth.uid(), auth.jwt() ->> 'email', v_email, 'set_role', v_old, v_role);

    RETURN QUERY SELECT v_email, v_role;
END;
$$;

COMMENT ON FUNCTION public.set_account_role(text, text) IS
    'Set or clear (NULL = read-only) an account''s role tier. Takes effect at its next sign-in or token refresh (at most JWT_EXPIRY later). Curators: between read-only and contributor; admins: any tier; never your own. Logged to shared.account_events.';


CREATE OR REPLACE FUNCTION public.reset_account_password(p_email text)
    RETURNS TABLE (email text, password text)
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    v_email    text := lower(btrim(p_email));
    v_id       uuid;
    v_role     text;
    v_password text;
BEGIN
    IF NOT shared.is_curator() THEN
        RAISE EXCEPTION 'Only curators and admins can reset passwords'
            USING ERRCODE = '42501',
                  HINT = 'Ask a curator of your team, or the lab administrator.';
    END IF;

    SELECT u.id, u.raw_app_meta_data ->> 'role' INTO v_id, v_role
      FROM auth.users u
     WHERE lower(u.email) = v_email AND u.deleted_at IS NULL;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'No account for %', COALESCE(p_email, '(empty)')
            USING ERRCODE = 'P0002';
    END IF;

    IF v_id = auth.uid() THEN
        RAISE EXCEPTION 'Change your own password on the account page instead'
            USING ERRCODE = '42501';
    END IF;

    IF NOT shared.may_manage_role(v_role) THEN
        RAISE EXCEPTION 'You cannot reset the password of a % account', v_role
            USING ERRCODE = '42501',
                  HINT = 'Ask an admin.';
    END IF;

    v_password := shared.new_account_password();

    UPDATE auth.users u
       SET encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
           raw_user_meta_data = COALESCE(u.raw_user_meta_data, '{}'::jsonb)
                                || jsonb_build_object('must_change_password', true),
           updated_at = now()
     WHERE u.id = v_id;

    -- A reset is usually "lost it" or "someone else had it": end every session,
    -- so an old refresh token cannot outlive the password it came with.
    DELETE FROM auth.sessions s WHERE s.user_id = v_id;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, old_role, new_role)
    VALUES (auth.uid(), auth.jwt() ->> 'email', v_email, 'reset_password', v_role, v_role);

    RETURN QUERY SELECT v_email, v_password;
END;
$$;

COMMENT ON FUNCTION public.reset_account_password(text) IS
    'Give an account a new one-time password and end its sessions. Curators: read-only and contributor accounts; admins: any; never your own. Logged to shared.account_events.';


REVOKE ALL ON FUNCTION public.list_accounts()                FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_account(text, text)     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_account_role(text, text)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reset_account_password(text)   FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_accounts()              TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_account(text, text)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_account_role(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_account_password(text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. No role = read-only: the 18 open metadata write policies need contributor
-- -----------------------------------------------------------------------------
-- Generated from pg_policies on dev (roles = {authenticated}, qual or
-- with_check = true, cmd <> SELECT). Same command, same table, renamed so the
-- name says who it is for.

DO $$
DECLARE
    p record;
BEGIN
    FOR p IN
        SELECT * FROM (VALUES
            ('pointclouds', 'scanners',                        'Authenticated users can manage scanners',                'Contributors can manage scanners'),
            ('sensor',      'sensors',                         'Authenticated users can manage sensors',                 'Contributors can manage sensors'),
            ('shared',      'campaigns',                       'Authenticated users can manage campaigns',               'Contributors can manage campaigns'),
            ('shared',      'disturbance_events',              'Authenticated users can manage disturbance events',      'Contributors can manage disturbance events'),
            ('shared',      'disturbance_events_trees',        'Authenticated users can manage disturbance tree links',  'Contributors can manage disturbance tree links'),
            ('shared',      'locations',                       'Authenticated users can insert locations',               'Contributors can insert locations'),
            ('shared',      'locations',                       'Authenticated users can update locations',               'Contributors can update locations'),
            ('shared',      'management_events',               'Authenticated users can manage management events',       'Contributors can manage management events'),
            ('shared',      'plots',                           'Authenticated users can manage plots',                   'Contributors can manage plots'),
            ('shared',      'process_metrics',                 'Authenticated users can manage process metrics',         'Contributors can manage process metrics'),
            ('shared',      'process_parameters',              'Authenticated users can manage process parameters',      'Contributors can manage process parameters'),
            ('shared',      'process_parameters_environments', 'Authenticated users can manage process parameter links', 'Contributors can manage process parameter links'),
            ('shared',      'process_parameters_point_clouds', 'Authenticated users can manage process parameter links', 'Contributors can manage process parameter links'),
            ('shared',      'process_parameters_stems',        'Authenticated users can manage process parameter links', 'Contributors can manage process parameter links'),
            ('shared',      'process_parameters_trees',        'Authenticated users can manage process parameter links', 'Contributors can manage process parameter links'),
            ('shared',      'processes',                       'Authenticated users can manage processes',               'Contributors can manage processes'),
            ('shared',      'scenarios',                       'Authenticated users can manage scenarios',               'Contributors can manage scenarios'),
            ('shared',      'species',                         'Authenticated users can manage species',                 'Contributors can manage species')
        ) AS v(sch, tbl, old_name, new_name)
    LOOP
        -- Already applied (renamed) on a re-run: nothing to do.
        CONTINUE WHEN NOT EXISTS (
            SELECT 1 FROM pg_policies
             WHERE schemaname = p.sch AND tablename = p.tbl AND policyname = p.old_name);

        -- An INSERT policy has no USING clause; everything else gets both.
        IF (SELECT cmd FROM pg_policies
             WHERE schemaname = p.sch AND tablename = p.tbl AND policyname = p.old_name) = 'INSERT' THEN
            EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (shared.is_contributor())',
                           p.old_name, p.sch, p.tbl);
        ELSE
            EXECUTE format('ALTER POLICY %I ON %I.%I USING (shared.is_contributor()) WITH CHECK (shared.is_contributor())',
                           p.old_name, p.sch, p.tbl);
        END IF;
        EXECUTE format('ALTER POLICY %I ON %I.%I RENAME TO %I', p.old_name, p.sch, p.tbl, p.new_name);
    END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
