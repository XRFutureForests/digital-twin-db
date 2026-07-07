-- XR Future Forests Lab - Role Tiers (Administrator / Curator / Contributor / Consumer)
-- Adds claim-based write tiers on top of the existing anon/authenticated/service_role
-- split. No new Postgres roles, no custom access token hook.
--
-- Consumer  = anon, unchanged (read-only, no account).
-- The three authenticated tiers are a single app_metadata.role claim, checked via
-- the helper functions below. Only an admin can set this claim on another user
-- (Supabase Auth Admin API / direct SQL as service_role):
--
--   UPDATE auth.users
--   SET raw_app_meta_data = raw_app_meta_data || '{"role": "curator"}'::jsonb
--   WHERE email = 'someone@example.com';
--
-- Valid values: 'admin', 'curator', 'contributor'. No claim = plain authenticated,
-- which still has full CRUD on the untiered metadata tables (see below) but no
-- write access to field-data tables.
--
-- This migration only re-tiers the field-data tables (Trees, Stems, PointClouds,
-- Environments, Images, SensorReadings, PhenologyObservations, Deadwood,
-- GroundVegetation). Reference/lookup/metadata tables (Species, Scenarios,
-- Locations, Sensors, ManagementEvents, DisturbanceEvents, Campaigns, Processes,
-- ...) are left exactly as defined in 20-rls-policies.sql — full CRUD for any
-- authenticated user. Low-risk, low-volume, not worth tiering.

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.is_admin()
RETURNS BOOLEAN AS $$
    SELECT COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION shared.is_curator()
RETURNS BOOLEAN AS $$
    SELECT COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'curator'), false);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION shared.is_contributor()
RETURNS BOOLEAN AS $$
    SELECT COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') IN ('admin', 'curator', 'contributor'), false);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION shared.is_admin IS 'RDA tier: Administrator - full user/role management, implies Curator rights';
COMMENT ON FUNCTION shared.is_curator IS 'RDA tier: Curator - can alter/delete field-data records';
COMMENT ON FUNCTION shared.is_contributor IS 'RDA tier: Contributor - can insert new field-data records, no alter/delete';

GRANT EXECUTE ON FUNCTION shared.is_admin() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.is_curator() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION shared.is_contributor() TO anon, authenticated, service_role;

-- =============================================================================
-- POINTCLOUDS.POINTCLOUDS
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can create point clouds" ON pointclouds.PointClouds;
DROP POLICY IF EXISTS "Users can update their own point clouds" ON pointclouds.PointClouds;

CREATE POLICY "Contributors can create point clouds"
    ON pointclouds.PointClouds FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update point clouds"
    ON pointclouds.PointClouds FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete point clouds"
    ON pointclouds.PointClouds FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- TREES.TREES
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can create trees" ON trees.Trees;
DROP POLICY IF EXISTS "Users can update their own trees or unowned trees" ON trees.Trees;

CREATE POLICY "Contributors can create trees"
    ON trees.Trees FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update trees"
    ON trees.Trees FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete trees"
    ON trees.Trees FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- TREES.STEMS
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can create stems" ON trees.Stems;
DROP POLICY IF EXISTS "Authenticated users can update stems" ON trees.Stems;

CREATE POLICY "Contributors can create stems"
    ON trees.Stems FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update stems"
    ON trees.Stems FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete stems"
    ON trees.Stems FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- ENVIRONMENTS.ENVIRONMENTS
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can create environments" ON environments.Environments;
DROP POLICY IF EXISTS "Users can update their own environments" ON environments.Environments;

CREATE POLICY "Contributors can create environments"
    ON environments.Environments FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update environments"
    ON environments.Environments FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete environments"
    ON environments.Environments FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- IMAGERY.IMAGES
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can create images" ON imagery.Images;
DROP POLICY IF EXISTS "Users can update their own images" ON imagery.Images;

CREATE POLICY "Contributors can create images"
    ON imagery.Images FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update images"
    ON imagery.Images FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete images"
    ON imagery.Images FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- SENSOR.SENSORREADINGS
-- =============================================================================
-- No authenticated UPDATE/DELETE existed before this migration either (only
-- service_role could correct/remove a reading) - left that way. Telemetry is
-- treated as append-only; only the INSERT tier changes.

DROP POLICY IF EXISTS "Authenticated users can insert sensor readings" ON sensor.SensorReadings;

CREATE POLICY "Contributors can insert sensor readings"
    ON sensor.SensorReadings FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

-- =============================================================================
-- TREES.PHENOLOGYOBSERVATIONS
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can manage phenology observations" ON trees.PhenologyObservations;

CREATE POLICY "Contributors can create phenology observations"
    ON trees.PhenologyObservations FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update phenology observations"
    ON trees.PhenologyObservations FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete phenology observations"
    ON trees.PhenologyObservations FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- TREES.DEADWOOD
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can manage deadwood records" ON trees.Deadwood;

CREATE POLICY "Contributors can create deadwood records"
    ON trees.Deadwood FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update deadwood records"
    ON trees.Deadwood FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete deadwood records"
    ON trees.Deadwood FOR DELETE
    TO authenticated
    USING (shared.is_curator());

-- =============================================================================
-- TREES.GROUNDVEGETATION
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can manage ground vegetation" ON trees.GroundVegetation;

CREATE POLICY "Contributors can create ground vegetation records"
    ON trees.GroundVegetation FOR INSERT
    TO authenticated
    WITH CHECK (shared.is_contributor());

CREATE POLICY "Curators can update ground vegetation records"
    ON trees.GroundVegetation FOR UPDATE
    TO authenticated
    USING (shared.is_curator())
    WITH CHECK (shared.is_curator());

CREATE POLICY "Curators can delete ground vegetation records"
    ON trees.GroundVegetation FOR DELETE
    TO authenticated
    USING (shared.is_curator());
