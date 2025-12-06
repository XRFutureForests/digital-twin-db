-- Public API Views Migration
-- This migration creates views in the public schema that expose tables from other schemas
-- This allows PostgREST API to access tables using simple names (e.g., 'trees' instead of 'trees.trees')
-- Dependencies: 11-shared-schema.sql, 12-pointclouds-schema.sql, 13-trees-schema.sql, 14-sensor-schema.sql, 15-environments-schema.sql

-- =============================================================================
-- SHARED SCHEMA VIEWS
-- =============================================================================

-- Species view
CREATE OR REPLACE VIEW public.species AS
SELECT * FROM shared.species;

COMMENT ON VIEW public.species IS 'Public API view for tree species reference table';

-- Locations view
CREATE OR REPLACE VIEW public.locations AS
SELECT * FROM shared.locations;

COMMENT ON VIEW public.locations IS 'Public API view for locations reference table';

-- =============================================================================
-- TREES SCHEMA VIEWS
-- =============================================================================

-- Trees view
CREATE OR REPLACE VIEW public.trees AS
SELECT * FROM trees.trees;

COMMENT ON VIEW public.trees IS 'Public API view for trees table';

-- Stems view
CREATE OR REPLACE VIEW public.stems AS
SELECT * FROM trees.stems;

COMMENT ON VIEW public.stems IS 'Public API view for tree stems table';

-- =============================================================================
-- SENSOR SCHEMA VIEWS
-- =============================================================================

-- Sensors view
CREATE OR REPLACE VIEW public.sensors AS
SELECT * FROM sensor.sensors;

COMMENT ON VIEW public.sensors IS 'Public API view for sensors table';

-- SensorReadings view
CREATE OR REPLACE VIEW public.sensorreadings AS
SELECT * FROM sensor.sensorreadings;

COMMENT ON VIEW public.sensorreadings IS 'Public API view for sensor readings table';

-- SensorTypes view
CREATE OR REPLACE VIEW public.sensortypes AS
SELECT * FROM sensor.sensortypes;

COMMENT ON VIEW public.sensortypes IS 'Public API view for sensor types reference table';

-- =============================================================================
-- POINTCLOUDS SCHEMA VIEWS
-- =============================================================================

-- PointClouds view
CREATE OR REPLACE VIEW public.pointclouds AS
SELECT * FROM pointclouds.pointclouds;

COMMENT ON VIEW public.pointclouds IS 'Public API view for point clouds table';

-- =============================================================================
-- ENVIRONMENTS SCHEMA VIEWS
-- =============================================================================

-- Environments view
CREATE OR REPLACE VIEW public.environments AS
SELECT * FROM environments.environments;

COMMENT ON VIEW public.environments IS 'Public API view for environments table';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

-- Grant SELECT to anon and authenticated users on all public views
GRANT SELECT ON public.species TO anon, authenticated;
GRANT SELECT ON public.locations TO anon, authenticated;
GRANT SELECT ON public.trees TO anon, authenticated;
GRANT SELECT ON public.stems TO anon, authenticated;
GRANT SELECT ON public.sensors TO anon, authenticated;
GRANT SELECT ON public.sensorreadings TO anon, authenticated;
GRANT SELECT ON public.sensortypes TO anon, authenticated;
GRANT SELECT ON public.pointclouds TO anon, authenticated;
GRANT SELECT ON public.environments TO anon, authenticated;

-- Grant INSERT/UPDATE/DELETE to authenticated users on data tables
GRANT INSERT, UPDATE, DELETE ON public.trees TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.stems TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.sensors TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.sensorreadings TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.pointclouds TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.environments TO authenticated;

-- Grant INSERT/UPDATE/DELETE to service_role on all tables (for admin operations)
GRANT ALL ON public.species TO service_role;
GRANT ALL ON public.locations TO service_role;
GRANT ALL ON public.trees TO service_role;
GRANT ALL ON public.stems TO service_role;
GRANT ALL ON public.sensors TO service_role;
GRANT ALL ON public.sensorreadings TO service_role;
GRANT ALL ON public.sensortypes TO service_role;
GRANT ALL ON public.pointclouds TO service_role;
GRANT ALL ON public.environments TO service_role;

-- =============================================================================
-- INSTEAD OF TRIGGERS FOR INSERTABLE/UPDATABLE VIEWS
-- =============================================================================

-- Trees INSERT trigger
CREATE OR REPLACE FUNCTION public.trees_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.trees SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trees_insert_trigger
INSTEAD OF INSERT ON public.trees
FOR EACH ROW EXECUTE FUNCTION public.trees_insert();

-- Trees UPDATE trigger
CREATE OR REPLACE FUNCTION public.trees_update()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE trees.trees SET
        variantid = NEW.variantid,
        parentvariantid = NEW.parentvariantid,
        pointcloudvariantid = NEW.pointcloudvariantid,
        locationid = NEW.locationid,
        speciesid = NEW.speciesid,
        name = NEW.name,
        plantingdate = NEW.plantingdate,
        status = NEW.status,
        position = NEW.position,
        positionoriginal = NEW.positionoriginal,
        height_m = NEW.height_m,
        canopywidth_m = NEW.canopywidth_m,
        crownboundary = NEW.crownboundary,
        notes = NEW.notes,
        createdby = NEW.createdby,
        createdat = NEW.createdat,
        updatedat = NEW.updatedat
    WHERE variantid = OLD.variantid;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trees_update_trigger
INSTEAD OF UPDATE ON public.trees
FOR EACH ROW EXECUTE FUNCTION public.trees_update();

-- Trees DELETE trigger
CREATE OR REPLACE FUNCTION public.trees_delete()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM trees.trees WHERE variantid = OLD.variantid;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trees_delete_trigger
INSTEAD OF DELETE ON public.trees
FOR EACH ROW EXECUTE FUNCTION public.trees_delete();

-- Sensors INSERT trigger
CREATE OR REPLACE FUNCTION public.sensors_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sensor.sensors SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensors_insert_trigger
INSTEAD OF INSERT ON public.sensors
FOR EACH ROW EXECUTE FUNCTION public.sensors_insert();

-- Sensors UPDATE trigger
CREATE OR REPLACE FUNCTION public.sensors_update()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE sensor.sensors SET
        sensorid = NEW.sensorid,
        sensortypeid = NEW.sensortypeid,
        externalsensorid = NEW.externalsensorid,
        treeid = NEW.treeid,
        serialnumber = NEW.serialnumber,
        installationdate = NEW.installationdate,
        lastmaintenancedate = NEW.lastmaintenancedate,
        status = NEW.status,
        position = NEW.position,
        positionoriginal = NEW.positionoriginal,
        notes = NEW.notes,
        createdby = NEW.createdby,
        createdat = NEW.createdat,
        updatedat = NEW.updatedat
    WHERE sensorid = OLD.sensorid;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensors_update_trigger
INSTEAD OF UPDATE ON public.sensors
FOR EACH ROW EXECUTE FUNCTION public.sensors_update();

-- Sensors DELETE trigger
CREATE OR REPLACE FUNCTION public.sensors_delete()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM sensor.sensors WHERE sensorid = OLD.sensorid;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensors_delete_trigger
INSTEAD OF DELETE ON public.sensors
FOR EACH ROW EXECUTE FUNCTION public.sensors_delete();

-- SensorReadings INSERT trigger
CREATE OR REPLACE FUNCTION public.sensorreadings_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sensor.sensorreadings SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensorreadings_insert_trigger
INSTEAD OF INSERT ON public.sensorreadings
FOR EACH ROW EXECUTE FUNCTION public.sensorreadings_insert();

-- PointClouds INSERT trigger
CREATE OR REPLACE FUNCTION public.pointclouds_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pointclouds.pointclouds SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pointclouds_insert_trigger
INSTEAD OF INSERT ON public.pointclouds
FOR EACH ROW EXECUTE FUNCTION public.pointclouds_insert();

-- Environments INSERT trigger
CREATE OR REPLACE FUNCTION public.environments_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO environments.environments SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER environments_insert_trigger
INSTEAD OF INSERT ON public.environments
FOR EACH ROW EXECUTE FUNCTION public.environments_insert();

-- Stems INSERT trigger
CREATE OR REPLACE FUNCTION public.stems_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.stems SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stems_insert_trigger
INSTEAD OF INSERT ON public.stems
FOR EACH ROW EXECUTE FUNCTION public.stems_insert();

COMMENT ON FUNCTION public.trees_insert() IS 'INSTEAD OF INSERT trigger function for public.trees view';
COMMENT ON FUNCTION public.trees_update() IS 'INSTEAD OF UPDATE trigger function for public.trees view';
COMMENT ON FUNCTION public.trees_delete() IS 'INSTEAD OF DELETE trigger function for public.trees view';
COMMENT ON FUNCTION public.sensors_insert() IS 'INSTEAD OF INSERT trigger function for public.sensors view';
COMMENT ON FUNCTION public.sensorreadings_insert() IS 'INSTEAD OF INSERT trigger function for public.sensorreadings view';
COMMENT ON FUNCTION public.pointclouds_insert() IS 'INSTEAD OF INSERT trigger function for public.pointclouds view';
COMMENT ON FUNCTION public.environments_insert() IS 'INSTEAD OF INSERT trigger function for public.environments view';
COMMENT ON FUNCTION public.stems_insert() IS 'INSTEAD OF INSERT trigger function for public.stems view';

-- Enable RLS on views (inherits from underlying tables)
ALTER VIEW public.trees SET (security_invoker = on);
ALTER VIEW public.sensors SET (security_invoker = on);
ALTER VIEW public.sensorreadings SET (security_invoker = on);
ALTER VIEW public.pointclouds SET (security_invoker = on);
ALTER VIEW public.environments SET (security_invoker = on);
ALTER VIEW public.stems SET (security_invoker = on);
ALTER VIEW public.species SET (security_invoker = on);
ALTER VIEW public.locations SET (security_invoker = on);
ALTER VIEW public.sensortypes SET (security_invoker = on);

-- Grant USAGE on sequences to allow auto-incrementing IDs
GRANT USAGE ON SEQUENCE trees.trees_variantid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE sensor.sensors_sensorid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE sensor.sensorreadings_readingid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.stems_stemid_seq TO authenticated, service_role;
