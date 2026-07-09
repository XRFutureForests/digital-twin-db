-- XR Future Forests Lab - UE View Refinements
-- Four changes to the Unreal Engine query views:
--   1. Index sensor.sensor_tree_links(tree_id) to back ue_trees.has_sensors.
--   2. ue_trees: add has_sensors; trim to the ST_TreeCatalogEntry struct
--      (drop parenttreeid, plotid, timedelta_yrs, variant_sortorder, the numeric
--      scenario/varianttype/species IDs, measurementdate, datasourcetype, and the
--      raw PostGIS position — UE uses the flat latitude/longitude).
--   3. ue_sensors: expose the enriched sensor_model (real instrument) and
--      data_owner so UE can display them without a second /sensors call.
--
-- Views are DROP+CREATE'd because CREATE OR REPLACE cannot drop/reorder columns.
-- Nothing depends on ue_trees / ue_sensors.
--
-- Dependencies: 25-forest-state-views.sql, 28-sensor-views.sql, 32-ecosense-sensor-tree-map.sql

-- =============================================================================
-- 1. INDEX FOR has_sensors
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_sensor_tree_links_tree
    ON sensor.sensor_tree_links (tree_id);

-- =============================================================================
-- 2. UE_TREES — lean tree catalogue + has_sensors
-- =============================================================================
DROP VIEW IF EXISTS public.ue_trees;

CREATE VIEW public.ue_trees AS
SELECT
    t.treeid,
    t.treeentityid,
    t.locationid,
    -- Time-step selector: filter by variantid to load one forest state
    t.variantid,
    v.variantname,
    v.simulationyear,
    s.scenarioname,
    vt.varianttypename,
    -- Species (names are the UE asset lookup keys)
    sp.commonname       AS speciesname,
    sp.scientificname,
    -- Measurements for placement / rendering
    t.height_m,
    t.crownwidth_m,
    t.crownbaseheight_m,
    st.dbh_cm,          -- main stem (StemNumber=1)
    t.age_years,
    t.healthscore,
    -- Competition proxy: crown starts above 60% of tree height → high pressure
    COALESCE((t.crownbaseheight_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    -- Sensor cross-reference
    t.aquariusname      AS aquarius_name,
    EXISTS (
        SELECT 1 FROM sensor.sensor_tree_links stl WHERE stl.tree_id = t.treeid
    )                   AS has_sensors,
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude
FROM trees.trees t
LEFT JOIN shared.variants     v   ON t.variantid       = v.variantid
LEFT JOIN shared.scenarios    s   ON v.scenarioid      = s.scenarioid
LEFT JOIN shared.varianttypes vt  ON v.varianttypeid   = vt.varianttypeid
LEFT JOIN shared.species      sp  ON t.speciesid       = sp.speciesid
LEFT JOIN trees.stems         st  ON st.treeid = t.treeid AND st.stemnumber = 1;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import (ST_TreeCatalogEntry). One row '
    'per tree with variant/scenario/species, main-stem DBH, competition flag, '
    'pre-flattened latitude/longitude, and sensor cross-reference '
    '(aquarius_name + has_sensors). Filter by variantid to load one time step. '
    'For a tree''s sensors: GET /ue_sensors?linked_tree_entity_id=eq.<treeentityid>.';

GRANT SELECT ON public.ue_trees TO anon, authenticated;
GRANT ALL    ON public.ue_trees TO service_role;

-- =============================================================================
-- 3. UE_SENSORS — add sensor_model (real instrument) + data_owner
-- =============================================================================
DROP VIEW IF EXISTS public.ue_sensors;

CREATE VIEW public.ue_sensors AS
SELECT
    s.sensorid,
    s.externalid                              AS aquarius_id,
    s.serialnumber                            AS sensor_label,
    s.externalmetadata->>'Parameter'          AS aquarius_parameter,
    -- Sensor classification
    st.sensortypeid,
    st.sensortypename                         AS sensor_type,
    s.unit,
    s.sensormodel                             AS sensor_model,   -- enriched instrument
    s.externalmetadata->>'DataOwner'          AS data_owner,     -- enriched owner
    s.isactive,
    s.installationheight_m,
    s.samplinginterval_seconds,
    s.installationdate,
    -- Location
    l.locationid,
    l.locationname,
    -- Latest reading (LATERAL backed by idx_sensor_readings_sensor_timestamp)
    lr.timestamp                              AS latest_timestamp,
    lr.value                                  AS latest_value,
    lr.quality                                AS latest_quality,
    -- Linked tree (NULL for meteo/soil sensors or unlinked tree sensors)
    t.treeid                                  AS linked_tree_id,
    t.treeentityid                            AS linked_tree_entity_id,
    sp.commonname                             AS linked_tree_species,
    sp.scientificname                         AS linked_tree_scientificname,
    t.height_m                                AS linked_tree_height_m,
    -- Position — flat lat/lon avoids PostGIS parsing in UE Blueprint
    extensions.ST_Y(s.position)              AS latitude,
    extensions.ST_X(s.position)              AS longitude
FROM sensor.sensors s
JOIN  sensor.sensortypes         st  ON s.sensortypeid  = st.sensortypeid
JOIN  shared.locations           l   ON s.locationid    = l.locationid
LEFT JOIN LATERAL (
    SELECT sr.timestamp, sr.value, sr.quality
    FROM   sensor.sensorreadings sr
    WHERE  sr.sensorid = s.sensorid
    ORDER  BY sr.timestamp DESC
    LIMIT  1
) lr ON TRUE
LEFT JOIN sensor.sensor_tree_links stl ON stl.sensor_id = s.sensorid
LEFT JOIN trees.trees              t   ON stl.tree_id   = t.treeid
LEFT JOIN shared.species           sp  ON t.speciesid   = sp.speciesid;

COMMENT ON VIEW public.ue_sensors IS
    'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model '
    '(enriched instrument), data owner, location, latest reading, and linked tree '
    'info (populated after sensor_tree_links is filled). '
    'GET /ue_sensors?linked_tree_entity_id=eq.<treeentityid>';

GRANT SELECT ON public.ue_sensors TO anon, authenticated;
GRANT ALL    ON public.ue_sensors TO service_role;

ALTER VIEW public.ue_sensors SET (security_invoker = on);
