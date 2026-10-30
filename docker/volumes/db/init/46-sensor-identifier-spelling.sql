-- Mirrored from supabase/migrations/20260922120000_sensor_identifier_spelling.sql.
-- Fresh builds get the renames here; existing databases get them from the
-- migration. 10-baseline-schema.sql still creates the old spellings, so on a
-- fresh init this renames what the baseline just built -- the documented shape
-- of this history: additive files, the baseline is never edited.
-- Keep the two identical.
-- =============================================================================
-- Two `sensor` identifiers written without word separators
-- =============================================================================
-- XRFF-488. Found by the naming-convention audit (XRFF-484).
--
-- `sensor.sensor_tree_links.sensortreelinkid` was the only single-column primary
-- key among 69 base tables that did not match `<stem>_id`; every other one does.
-- `sensorreadings_sensorid_timestamp_unique` spelled the column `sensorid` where
-- the column is `sensor_id`.
--
-- Neither name was aliased away by `public.sensor_tree_links`, so the raw
-- spelling reached anything reading the view.
--
-- Consumer grep (required by AGENTS.md for any `sensor` migration) found exactly
-- one reader outside this repo's own DDL:
--
--   scripts/import/link_sensors_to_trees.py   RETURNING sensortreelinkid
--
-- and none at all in digital-twin-dashboard, aquarius-connector,
-- open-data-connector or the four Unreal projects. The dashboard joins
-- sensor.sensor_tree_links on sensor_id/tree_id only and never selects the PK.
-- The importer is updated in the same change.
--
-- ALTER TABLE ... RENAME COLUMN carries the primary key, the NOT NULL and the
-- column default with it, so only the sequence has to be renamed separately --
-- and only for tidiness, since the OWNED BY link survives a rename either way.
--
-- Mirror of the migration of the same name.
-- =============================================================================

SET search_path TO sensor, public;


-- 1. sensortreelinkid -> sensor_tree_link_id, and the sequence that feeds it.
ALTER TABLE sensor.sensor_tree_links
    RENAME COLUMN sensortreelinkid TO sensor_tree_link_id;

ALTER SEQUENCE IF EXISTS sensor.sensor_tree_links_sensortreelinkid_seq
    RENAME TO sensor_tree_links_sensor_tree_link_id_seq;


-- 2. The unique index that spelled the column `sensorid`.
ALTER INDEX IF EXISTS sensor.sensorreadings_sensorid_timestamp_unique
    RENAME TO sensorreadings_sensor_id_timestamp_unique;


-- 3. public.sensor_tree_links re-published with the corrected column name.
--    CREATE OR REPLACE VIEW cannot rename an output column, so the view is
--    dropped and recreated -- which drops its grants and comment with it. Both
--    are restored below; the set matches what the view carried before this
--    migration (anon / authenticated / service_role, full DML as for every other
--    public view).
DROP VIEW IF EXISTS public.sensor_tree_links;

CREATE VIEW public.sensor_tree_links WITH (security_invoker = 'on') AS
 SELECT sensor_tree_links.sensor_tree_link_id,
    sensor_tree_links.sensor_id,
    sensor_tree_links.tree_id,
    sensor_tree_links.description,
    sensor_tree_links.start_date,
    sensor_tree_links.end_date,
    sensor_tree_links.created_at
   FROM sensor.sensor_tree_links;

-- Recreating a view resets its owner to whoever runs the migration; every other
-- public view is owned by supabase_admin, so pin it rather than inherit it.
ALTER VIEW public.sensor_tree_links OWNER TO supabase_admin;

COMMENT ON VIEW public.sensor_tree_links IS
    'Public API view for sensor-tree link table';

-- GRANT ALL to the same four roles the baseline grants to. `postgres` is not
-- redundant here: the view is owned by supabase_admin, so postgres holds no
-- implicit privilege on it, and every other public view grants it explicitly.
GRANT ALL ON TABLE public.sensor_tree_links TO postgres, anon, authenticated, service_role;

COMMENT ON COLUMN sensor.sensor_tree_links.sensor_tree_link_id IS
    'Surrogate key. Renamed from sensortreelinkid in XRFF-488 -- it was the only '
    'primary key in the database not spelled <stem>_id.';
