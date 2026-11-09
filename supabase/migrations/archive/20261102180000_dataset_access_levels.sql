-- =============================================================================
-- Dataset ownership, licence and access levels; teams; a read-only dashboard role
-- =============================================================================
-- XRFF-625. Until now every row was readable by everyone, which was fine while
-- all data was the lab's own. Other groups now bring data, and the portal
-- offers any table as CSV from anywhere, so the owner of a dataset decides
-- where it is visible (owner, 2026-11-02).
--
-- A dataset is a campaign (shared.campaigns): trees, sensors, point clouds and
-- images point at one through campaign_id. A campaign gains an owner team, a
-- licence (required), an access level, an optional embargo date, a citation
-- and a DOI.
--
--   public      everyone
--   campus      requests from the university network (132.230.0.0/16, which
--               includes the university VPN) and any signed-in account
--   registered  any signed-in account
--   team        members of the owning team
--
-- Curators and admins see everything; members of the owning team see their
-- team's campaigns at any level and during an embargo; during an embargo
-- nobody else sees them. Rows without a campaign -- all data loaded so far --
-- stay public, so nothing changes for existing data.
--
-- How the network is known: only the dashboard's nginx sees the client
-- address. It maps the university's range to a header, X-DT-Network: campus
-- or internet, and always overwrites whatever value a client sent. PostgREST
-- passes request headers to SQL, where shared.request_network() reads it.
-- Direct database connections carry no header and count as internet. The
-- header can only be trusted while Kong and the database are reachable from
-- the host alone, which the deployment guarantees (docs/deployment-guide.md).
--
-- How rows are hidden: RESTRICTIVE select policies, added on top of the
-- existing permissive ones.
--   * trees, sensors, point clouds, images: the campaign must be readable.
--   * their child tables (stems, phenology, roots, crown profiles, QSMs and
--     their cylinders and graph edges, growth simulations, sensor readings,
--     sensor-tree links, deadwood): the parent row must not be hidden. While
--     no campaign is restricted, a one-off check short-circuits this, so the
--     current all-public data pays nothing for it.
-- Writes: a contributor may only put rows into a campaign without an owner
-- team or one of their own teams; only curators and team members may create
-- or change a team-owned campaign.
--
-- Three views ignored row-level security because they ran with their owner's
-- rights: ue_trees, growth_simulations, simulation_runs. They now run with the
-- caller's (security_invoker), like the other data views.
--
-- growth_simulations and sensor_tree_links had row-level security off. It is
-- on now, with a policy that lets everyone read and the new restrictive one.
-- Their writers (silva-connector, link_sensors_to_trees.py) connect as a role
-- that bypasses row-level security and are unaffected.
--
-- The dashboard read the base tables as `postgres`, which bypasses row-level
-- security. The new role dashboard_reader inherits exactly what an anonymous
-- API caller may read, so the dashboard shows public data only. It is created
-- without login here; each host gives it a password (RUNBOOK §9) and the
-- dashboard's .env switches to it.
--
-- Mirrored to init 79-dataset-access-levels.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Teams
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS shared.teams (
    team_id      serial PRIMARY KEY,
    team_name    varchar(200) NOT NULL UNIQUE,
    description  text,
    created_at   timestamptz DEFAULT now(),
    updated_at   timestamptz DEFAULT now(),
    created_by   varchar(200),
    updated_by   varchar(200)
);

COMMENT ON TABLE shared.teams IS
    'A group that owns datasets (campaigns). Members see their team''s campaigns at every access level and during an embargo; team curators manage the membership.';

CREATE TABLE IF NOT EXISTS shared.team_members (
    team_id          integer NOT NULL REFERENCES shared.teams (team_id) ON DELETE CASCADE,
    user_id          uuid    NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    is_team_curator  boolean NOT NULL DEFAULT false,
    created_at       timestamptz DEFAULT now(),
    created_by       varchar(200),
    PRIMARY KEY (team_id, user_id)
);

COMMENT ON TABLE shared.team_members IS
    'Who belongs to which team. Written through public.add_team_member / remove_team_member: curators and admins for any team, team curators for their own team (members only).';

CREATE INDEX IF NOT EXISTS idx_team_members_user ON shared.team_members (user_id);

-- Helpers are SECURITY DEFINER so policies can use them without recursing
-- into team_members' own policies.
CREATE OR REPLACE FUNCTION shared.my_team_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
    SELECT tm.team_id FROM shared.team_members tm WHERE tm.user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION shared.my_curated_team_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
    SELECT tm.team_id FROM shared.team_members tm WHERE tm.user_id = auth.uid() AND tm.is_team_curator;
$$;

GRANT SELECT ON shared.teams TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON shared.teams TO authenticated;
GRANT SELECT ON shared.team_members TO authenticated;
GRANT ALL ON shared.teams, shared.team_members TO service_role;
GRANT USAGE ON SEQUENCE shared.teams_team_id_seq TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.my_team_ids(), shared.my_curated_team_ids() TO anon, authenticated, service_role;

ALTER TABLE shared.teams        ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.team_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Teams are viewable by everyone" ON shared.teams;
CREATE POLICY "Teams are viewable by everyone" ON shared.teams FOR SELECT USING (true);
DROP POLICY IF EXISTS "Curators manage teams" ON shared.teams;
CREATE POLICY "Curators manage teams" ON shared.teams FOR ALL TO authenticated
    USING (shared.is_curator()) WITH CHECK (shared.is_curator());
DROP POLICY IF EXISTS "Service role can manage all teams" ON shared.teams;
CREATE POLICY "Service role can manage all teams" ON shared.teams TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Members see their teams, curators see all" ON shared.team_members;
CREATE POLICY "Members see their teams, curators see all" ON shared.team_members FOR SELECT TO authenticated
    USING (shared.is_curator() OR team_id IN (SELECT shared.my_team_ids()));
DROP POLICY IF EXISTS "Service role can manage all team members" ON shared.team_members;
CREATE POLICY "Service role can manage all team members" ON shared.team_members TO service_role USING (true) WITH CHECK (true);

DROP TRIGGER IF EXISTS trigger_teams_created_by ON shared.teams;
CREATE TRIGGER trigger_teams_created_by BEFORE INSERT ON shared.teams
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();
DROP TRIGGER IF EXISTS trigger_teams_updated_by ON shared.teams;
CREATE TRIGGER trigger_teams_updated_by BEFORE UPDATE ON shared.teams
    FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();

CREATE OR REPLACE VIEW public.teams WITH (security_invoker = on) AS
SELECT team_id, team_name, description, created_at, updated_at, created_by, updated_by
  FROM shared.teams;

COMMENT ON VIEW public.teams IS 'Teams that own datasets. Readable by everyone; curators create and change them.';

GRANT SELECT ON public.teams TO anon, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.teams TO authenticated, service_role;

-- Team changes join the account events log.
ALTER TABLE shared.account_events ADD COLUMN IF NOT EXISTS team_id integer;
ALTER TABLE shared.account_events DROP CONSTRAINT IF EXISTS account_events_action_check;
ALTER TABLE shared.account_events ADD CONSTRAINT account_events_action_check
    CHECK (action IN ('create', 'set_role', 'reset_password', 'team_add', 'team_remove'));

CREATE OR REPLACE FUNCTION public.add_team_member(
    p_team_id         integer,
    p_email           text,
    p_is_team_curator boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_user  uuid;
    v_actor text := (SELECT u.email FROM auth.users u WHERE u.id = auth.uid());
BEGIN
    IF NOT (shared.is_curator()
            OR (p_team_id IN (SELECT shared.my_curated_team_ids()) AND NOT p_is_team_curator)) THEN
        RAISE EXCEPTION 'Only curators, or curators of this team adding a plain member, may add team members'
            USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.teams t WHERE t.team_id = p_team_id) THEN
        RAISE EXCEPTION 'No team %', p_team_id USING ERRCODE = 'P0002';
    END IF;
    SELECT u.id INTO v_user FROM auth.users u WHERE lower(u.email) = lower(trim(p_email));
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'No account with e-mail %', p_email USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO shared.team_members (team_id, user_id, is_team_curator, created_by)
    VALUES (p_team_id, v_user, p_is_team_curator, v_actor)
    ON CONFLICT (team_id, user_id) DO UPDATE SET is_team_curator = EXCLUDED.is_team_curator;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, new_role, team_id)
    VALUES (auth.uid(), v_actor, lower(trim(p_email)), 'team_add',
            CASE WHEN p_is_team_curator THEN 'team_curator' ELSE 'team_member' END, p_team_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_team_member(p_team_id integer, p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_user       uuid;
    v_is_curator boolean;
    v_actor      text := (SELECT u.email FROM auth.users u WHERE u.id = auth.uid());
BEGIN
    SELECT u.id INTO v_user FROM auth.users u WHERE lower(u.email) = lower(trim(p_email));
    SELECT tm.is_team_curator INTO v_is_curator
      FROM shared.team_members tm WHERE tm.team_id = p_team_id AND tm.user_id = v_user;
    IF NOT FOUND THEN
        RAISE EXCEPTION '% is not a member of team %', p_email, p_team_id USING ERRCODE = 'P0002';
    END IF;
    IF NOT (shared.is_curator()
            OR (p_team_id IN (SELECT shared.my_curated_team_ids()) AND NOT v_is_curator)) THEN
        RAISE EXCEPTION 'Only curators, or curators of this team removing a plain member, may remove team members'
            USING ERRCODE = '42501';
    END IF;

    DELETE FROM shared.team_members tm WHERE tm.team_id = p_team_id AND tm.user_id = v_user;

    INSERT INTO shared.account_events (actor_id, actor_email, target_email, action, old_role, team_id)
    VALUES (auth.uid(), v_actor, lower(trim(p_email)), 'team_remove',
            CASE WHEN v_is_curator THEN 'team_curator' ELSE 'team_member' END, p_team_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_team_members(p_team_id integer)
RETURNS TABLE (email text, is_team_curator boolean, added_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF NOT (shared.is_curator() OR p_team_id IN (SELECT shared.my_team_ids())) THEN
        RAISE EXCEPTION 'Only curators and members of the team may list its members' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT u.email::text, tm.is_team_curator, tm.created_at
      FROM shared.team_members tm
      JOIN auth.users u ON u.id = tm.user_id
     WHERE tm.team_id = p_team_id
     ORDER BY tm.is_team_curator DESC, u.email;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.add_team_member(integer, text, boolean), public.remove_team_member(integer, text),
                           public.list_team_members(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_team_member(integer, text, boolean), public.remove_team_member(integer, text),
                          public.list_team_members(integer) TO authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 2. Campaign ownership, licence and access level
-- -----------------------------------------------------------------------------

ALTER TABLE shared.campaigns
    ADD COLUMN IF NOT EXISTS owner_team_id integer REFERENCES shared.teams (team_id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS licence       varchar(100),
    ADD COLUMN IF NOT EXISTS access_level  varchar(20) NOT NULL DEFAULT 'public',
    ADD COLUMN IF NOT EXISTS embargo_until date,
    ADD COLUMN IF NOT EXISTS citation      text,
    ADD COLUMN IF NOT EXISTS doi           varchar(255);

-- No campaign exists yet on any host (checked 2026-11-02), so the licence can
-- be required outright.
ALTER TABLE shared.campaigns ALTER COLUMN licence SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'campaigns_access_level_check') THEN
        ALTER TABLE shared.campaigns ADD CONSTRAINT campaigns_access_level_check
            CHECK (access_level IN ('public', 'campus', 'registered', 'team'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'campaigns_team_level_needs_owner_check') THEN
        ALTER TABLE shared.campaigns ADD CONSTRAINT campaigns_team_level_needs_owner_check
            CHECK (access_level <> 'team' OR owner_team_id IS NOT NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'campaigns_licence_not_blank_check') THEN
        ALTER TABLE shared.campaigns ADD CONSTRAINT campaigns_licence_not_blank_check
            CHECK (btrim(licence) <> '');
    END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_campaigns_owner_team ON shared.campaigns (owner_team_id);

COMMENT ON COLUMN shared.campaigns.owner_team_id IS 'Team that owns the dataset. Its members see the campaign at every access level and during an embargo. Required for access_level team.';
COMMENT ON COLUMN shared.campaigns.licence IS 'Licence of the dataset, preferably an SPDX identifier (CC-BY-4.0, CC0-1.0, ...) or "all rights reserved". Required.';
COMMENT ON COLUMN shared.campaigns.access_level IS 'Who may read the campaign''s rows: public (everyone), campus (university network incl. VPN, and any signed-in account), registered (any signed-in account), team (members of owner_team_id). Curators and admins see all.';
COMMENT ON COLUMN shared.campaigns.embargo_until IS 'Until this date only the owning team, curators and admins see the campaign''s rows, whatever the access level. NULL = no embargo.';
COMMENT ON COLUMN shared.campaigns.citation IS 'How to cite the dataset.';
COMMENT ON COLUMN shared.campaigns.doi IS 'DOI of the dataset, if published (e.g. 10.5281/zenodo.123).';

-- The view and its INSTEAD OF triggers name their columns, so they gain the
-- new ones (appended; existing columns keep their order).
CREATE OR REPLACE VIEW public.campaigns WITH (security_invoker = on) AS
SELECT campaign_id, campaign_name, campaign_type, location_id, start_date, end_date, description,
       methodology, equipment, personnel, created_at, updated_at, created_by, updated_by,
       owner_team_id, licence, access_level, embargo_until, citation, doi
  FROM shared.campaigns;

ALTER VIEW public.campaigns ALTER COLUMN access_level SET DEFAULT 'public';

CREATE OR REPLACE FUNCTION public.campaigns_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO shared.campaigns (
        campaign_name, campaign_type, location_id, start_date, end_date,
        description, methodology, equipment, personnel,
        created_by, updated_by,
        owner_team_id, licence, access_level, embargo_until, citation, doi
    ) VALUES (
        NEW.campaign_name, NEW.campaign_type, NEW.location_id, NEW.start_date, NEW.end_date,
        NEW.description, NEW.methodology, NEW.equipment, NEW.personnel,
        NEW.created_by, NEW.updated_by,
        NEW.owner_team_id, NEW.licence, coalesce(NEW.access_level, 'public'), NEW.embargo_until,
        NEW.citation, NEW.doi
    ) RETURNING campaign_id INTO NEW.campaign_id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.campaigns_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE shared.campaigns SET
        campaign_name = NEW.campaign_name,
        campaign_type = NEW.campaign_type,
        location_id = NEW.location_id,
        start_date = NEW.start_date,
        end_date = NEW.end_date,
        description = NEW.description,
        methodology = NEW.methodology,
        equipment = NEW.equipment,
        personnel = NEW.personnel,
        owner_team_id = NEW.owner_team_id,
        licence = NEW.licence,
        access_level = NEW.access_level,
        embargo_until = NEW.embargo_until,
        citation = NEW.citation,
        doi = NEW.doi,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE campaign_id = OLD.campaign_id;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN NEW;
END;
$$;


-- -----------------------------------------------------------------------------
-- 3. Who may read and write which campaign
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION shared.request_network()
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO ''
AS $$
    SELECT CASE
        WHEN (nullif(current_setting('request.headers', true), '')::json ->> 'x-dt-network') = 'campus'
        THEN 'campus' ELSE 'internet'
    END;
$$;

COMMENT ON FUNCTION shared.request_network() IS
    'campus when the request came through the dashboard''s nginx from the university network (header X-DT-Network, set by nginx and never taken from the client), internet otherwise, including direct database connections.';

CREATE OR REPLACE FUNCTION shared.readable_campaign_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
    SELECT c.campaign_id
      FROM shared.campaigns c
     WHERE shared.is_curator()
        OR c.owner_team_id IN (SELECT shared.my_team_ids())
        OR ((c.embargo_until IS NULL OR c.embargo_until <= current_date)
            AND (c.access_level = 'public'
                 OR (c.access_level = 'campus'
                     AND (shared.request_network() = 'campus' OR auth.uid() IS NOT NULL))
                 OR (c.access_level = 'registered' AND auth.uid() IS NOT NULL)));
$$;

COMMENT ON FUNCTION shared.readable_campaign_ids() IS
    'Campaigns the caller may read: all for curators and admins; their teams'' campaigns for team members; otherwise, outside an embargo, public ones, campus ones from the university network or with an account, registered ones with an account.';

CREATE OR REPLACE FUNCTION shared.writable_campaign_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
    SELECT c.campaign_id
      FROM shared.campaigns c
     WHERE shared.is_curator()
        OR c.owner_team_id IS NULL
        OR c.owner_team_id IN (SELECT shared.my_team_ids());
$$;

COMMENT ON FUNCTION shared.writable_campaign_ids() IS
    'Campaigns the caller may add rows to or change rows of (row-level policies still decide the role): those without an owner team, their own teams'', all for curators and admins.';

CREATE OR REPLACE FUNCTION shared.has_restricted_campaigns()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
    SELECT EXISTS (SELECT 1 FROM shared.campaigns c
                    WHERE c.access_level <> 'public' OR c.embargo_until > current_date);
$$;

COMMENT ON FUNCTION shared.has_restricted_campaigns() IS
    'True when any campaign is not public or is under embargo. Child-table policies use it to skip their parent check while everything is public.';

GRANT EXECUTE ON FUNCTION shared.request_network(), shared.readable_campaign_ids(),
                          shared.writable_campaign_ids(), shared.has_restricted_campaigns()
    TO anon, authenticated, service_role;

-- Who am I to the twin: what the database knows about the caller.
CREATE OR REPLACE FUNCTION public.my_access()
RETURNS TABLE (network text, signed_in boolean, app_role text, team_ids integer[])
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $$
-- plpgsql, not sql: auth.jwt() does not exist yet when a fresh database runs
-- its init files, and a sql function body is checked at creation.
BEGIN
    RETURN QUERY
    SELECT shared.request_network(),
           auth.uid() IS NOT NULL,
           auth.jwt() -> 'app_metadata' ->> 'role',
           ARRAY(SELECT shared.my_team_ids());
END;
$$;

COMMENT ON FUNCTION public.my_access() IS
    'What the database knows about the caller: network (campus or internet), signed in or not, app role, team ids. POST /rest/v1/rpc/my_access.';

GRANT EXECUTE ON FUNCTION public.my_access() TO anon, authenticated, service_role;

-- Campaign writes: a team-owned campaign belongs to its team.
DROP POLICY IF EXISTS "Team campaigns: create for own team" ON shared.campaigns;
CREATE POLICY "Team campaigns: create for own team" ON shared.campaigns AS RESTRICTIVE FOR INSERT
    WITH CHECK (owner_team_id IS NULL OR shared.is_curator() OR owner_team_id IN (SELECT shared.my_team_ids()));
DROP POLICY IF EXISTS "Team campaigns: change own team's" ON shared.campaigns;
CREATE POLICY "Team campaigns: change own team's" ON shared.campaigns AS RESTRICTIVE FOR UPDATE
    USING      (owner_team_id IS NULL OR shared.is_curator() OR owner_team_id IN (SELECT shared.my_team_ids()))
    WITH CHECK (owner_team_id IS NULL OR shared.is_curator() OR owner_team_id IN (SELECT shared.my_team_ids()));
DROP POLICY IF EXISTS "Team campaigns: delete own team's" ON shared.campaigns;
CREATE POLICY "Team campaigns: delete own team's" ON shared.campaigns AS RESTRICTIVE FOR DELETE
    USING (owner_team_id IS NULL OR shared.is_curator() OR owner_team_id IN (SELECT shared.my_team_ids()));


-- -----------------------------------------------------------------------------
-- 4. Restrictive policies on campaign data
-- -----------------------------------------------------------------------------

-- Tables that point at a campaign directly.
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['trees.trees', 'sensor.sensors', 'point_clouds.point_clouds', 'imagery.images']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Dataset access level" ON %s', t);
        EXECUTE format('CREATE POLICY "Dataset access level" ON %s AS RESTRICTIVE FOR SELECT '
                       'USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.readable_campaign_ids()))', t);
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: insert" ON %s', t);
        EXECUTE format('CREATE POLICY "Dataset owner: insert" ON %s AS RESTRICTIVE FOR INSERT '
                       'WITH CHECK (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))', t);
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: update" ON %s', t);
        EXECUTE format('CREATE POLICY "Dataset owner: update" ON %s AS RESTRICTIVE FOR UPDATE '
                       'USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids())) '
                       'WITH CHECK (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))', t);
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: delete" ON %s', t);
        EXECUTE format('CREATE POLICY "Dataset owner: delete" ON %s AS RESTRICTIVE FOR DELETE '
                       'USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))', t);
    END LOOP;
END;
$$;

-- Child tables: visible only with their parent row. The parent check runs only
-- once some campaign is restricted.
ALTER TABLE trees.growth_simulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor.sensor_tree_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Growth simulations are viewable by everyone" ON trees.growth_simulations;
CREATE POLICY "Growth simulations are viewable by everyone" ON trees.growth_simulations FOR SELECT USING (true);
DROP POLICY IF EXISTS "Service role can manage all growth simulations" ON trees.growth_simulations;
CREATE POLICY "Service role can manage all growth simulations" ON trees.growth_simulations
    TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Sensor tree links are viewable by everyone" ON sensor.sensor_tree_links;
CREATE POLICY "Sensor tree links are viewable by everyone" ON sensor.sensor_tree_links FOR SELECT USING (true);
DROP POLICY IF EXISTS "Service role can manage all sensor tree links" ON sensor.sensor_tree_links;
CREATE POLICY "Service role can manage all sensor tree links" ON sensor.sensor_tree_links
    TO service_role USING (true) WITH CHECK (true);

-- The parent check asks "is the parent among the hidden rows?": that set is
-- small (rows of campaigns the caller may not read) where the visible set is
-- the whole table. Each helper uses the same readable_campaign_ids(), so a
-- child is hidden exactly when its parent is.
CREATE OR REPLACE FUNCTION shared.hidden_tree_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $f$
    SELECT t.tree_id FROM trees.trees t
     WHERE t.campaign_id IS NOT NULL
       AND t.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$f$;

CREATE OR REPLACE FUNCTION shared.hidden_sensor_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $f$
    SELECT s.sensor_id FROM sensor.sensors s
     WHERE s.campaign_id IS NOT NULL
       AND s.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$f$;

CREATE OR REPLACE FUNCTION shared.hidden_point_cloud_ids()
RETURNS SETOF integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $f$
    SELECT pc.point_cloud_id FROM point_clouds.point_clouds pc
     WHERE pc.campaign_id IS NOT NULL
       AND pc.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$f$;

CREATE OR REPLACE FUNCTION shared.hidden_qsm_ids()
RETURNS SETOF bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $f$
    SELECT q.qsm_id FROM trees.qsms q
     WHERE q.tree_id IN (SELECT shared.hidden_tree_ids())
        OR q.point_cloud_id IN (SELECT shared.hidden_point_cloud_ids());
$f$;

GRANT EXECUTE ON FUNCTION shared.hidden_tree_ids(), shared.hidden_sensor_ids(),
                          shared.hidden_point_cloud_ids(), shared.hidden_qsm_ids()
    TO anon, authenticated, service_role;

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('trees.stems',                 'tree_id NOT IN (SELECT shared.hidden_tree_ids())'),
        ('trees.phenology_observations','tree_id NOT IN (SELECT shared.hidden_tree_ids())'),
        ('trees.roots',                 'tree_id NOT IN (SELECT shared.hidden_tree_ids())'),
        ('trees.crown_foliage_profiles','tree_id NOT IN (SELECT shared.hidden_tree_ids())'),
        ('trees.qsms',                  '(tree_id IS NULL OR tree_id NOT IN (SELECT shared.hidden_tree_ids())) '
                                        'AND (point_cloud_id IS NULL OR point_cloud_id NOT IN '
                                        '(SELECT shared.hidden_point_cloud_ids()))'),
        ('trees.qsm_cylinders',         'qsm_id NOT IN (SELECT shared.hidden_qsm_ids())'),
        ('trees.tree_graph_edges',      'qsm_id NOT IN (SELECT shared.hidden_qsm_ids())'),
        ('trees.growth_simulations',    'base_tree_id IS NULL OR base_tree_id NOT IN (SELECT shared.hidden_tree_ids())'),
        ('sensor.sensor_readings',      'sensor_id NOT IN (SELECT shared.hidden_sensor_ids())'),
        ('sensor.sensor_tree_links',    'sensor_id NOT IN (SELECT shared.hidden_sensor_ids()) '
                                        'AND tree_id NOT IN (SELECT shared.hidden_tree_ids())'),
        ('forest_floor.deadwood',       'tree_id IS NULL OR tree_id NOT IN (SELECT shared.hidden_tree_ids())')
    ) AS v(tbl, parent_check)
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Dataset access level" ON %s', r.tbl);
        EXECUTE format('CREATE POLICY "Dataset access level" ON %s AS RESTRICTIVE FOR SELECT '
                       'USING ((SELECT NOT shared.has_restricted_campaigns()) OR (%s))', r.tbl, r.parent_check);
    END LOOP;
END;
$$;


-- -----------------------------------------------------------------------------
-- 5. The three data views that ignored row-level security
-- -----------------------------------------------------------------------------

-- With the caller's rights, the caller needs read access to the base tables.
-- trees.growth_simulations was the only one anon and authenticated could not
-- read directly; writes stay with silva-connector.
GRANT SELECT ON trees.growth_simulations TO anon, authenticated;

ALTER VIEW public.ue_trees           SET (security_invoker = on);
ALTER VIEW public.growth_simulations SET (security_invoker = on);
ALTER VIEW public.simulation_runs    SET (security_invoker = on);


-- -----------------------------------------------------------------------------
-- 6. Read-only role for the dashboard
-- -----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dashboard_reader') THEN
        CREATE ROLE dashboard_reader NOLOGIN NOINHERIT;
    END IF;
END;
$$;

-- Exactly what an anonymous API caller may read, no more. INHERIT is set on
-- the role so anon's grants and policies apply; anon's 3 s statement timeout
-- is a per-role setting and does not carry over.
ALTER ROLE dashboard_reader INHERIT;
GRANT anon TO dashboard_reader;
ALTER ROLE dashboard_reader SET statement_timeout = '30s';
ALTER ROLE dashboard_reader SET search_path = shared, trees, sensor, environments, extensions, public;

COMMENT ON ROLE dashboard_reader IS
    'Read-only role for digital-twin-dashboard: a member of anon, so it reads what an anonymous API caller may read and row-level security applies. No login here; each host sets a password (RUNBOOK §9).';

NOTIFY pgrst, 'reload schema';
