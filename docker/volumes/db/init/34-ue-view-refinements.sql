-- XR Future Forests Lab - UE View Refinements
-- Four changes to the Unreal Engine query views:
--   1. Index sensor.sensor_tree_links(tree_id) to back ue_trees.has_sensors.
--   2. ue_trees: add has_sensors; trim to the ST_TreeCatalogEntry struct
--      (drop parent_tree_id, plot_id, time_delta_yrs, variant_sortorder, the numeric
--      scenario/varianttype/species IDs, measurement_date, datasourcetype, and the
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
    t.tree_id,
    t.tree_entity_id,
    t.location_id,
    -- Time-step selector: filter by variant_id to load one forest state
    t.variant_id,
    v.variant_name,
    v.simulation_year,
    s.scenario_name,
    vt.variant_type_name,
    -- Species (names are the UE asset lookup keys)
    sp.common_name       AS species_name,
    sp.scientific_name,
    -- Measurements for placement / rendering
    t.height_m,
    t.crown_width_m,
    t.crown_base_height_m,
    st.dbh_cm,          -- main stem (stem_number=1)
    t.age_years,
    t.health_score,
    -- Competition proxy: crown starts above 60% of tree height → high pressure
    COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0)) > 0.6, false) AS competition,
    -- Sensor cross-reference
    t.aquarius_name      AS aquarius_name,
    EXISTS (
        SELECT 1 FROM sensor.sensor_tree_links stl WHERE stl.tree_id = t.tree_id
    )                   AS has_sensors,
    -- Flat lat/lon for UE JSON parsing (no PostGIS parsing needed in Blueprint)
    ST_Y(t.position)    AS latitude,
    ST_X(t.position)    AS longitude
FROM trees.trees t
LEFT JOIN shared.variants     v   ON t.variant_id       = v.variant_id
LEFT JOIN shared.scenarios    s   ON v.scenario_id      = s.scenario_id
LEFT JOIN shared.varianttypes vt  ON v.variant_type_id   = vt.variant_type_id
LEFT JOIN shared.species      sp  ON t.species_id       = sp.species_id
LEFT JOIN trees.stems         st  ON st.tree_id = t.tree_id AND st.stem_number = 1;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import (ST_TreeCatalogEntry). One row '
    'per tree with variant/scenario/species, main-stem DBH, competition flag, '
    'pre-flattened latitude/longitude, and sensor cross-reference '
    '(aquarius_name + has_sensors). Filter by variant_id to load one time step. '
    'For a tree''s sensors: GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>.';

GRANT SELECT ON public.ue_trees TO anon, authenticated;
GRANT ALL    ON public.ue_trees TO service_role;

-- =============================================================================
-- 3. UE_SENSORS — add sensor_model (real instrument) + data_owner
-- =============================================================================
DROP VIEW IF EXISTS public.ue_sensors;

CREATE VIEW public.ue_sensors AS
SELECT
    s.sensor_id,
    s.external_id                              AS aquarius_id,
    s.serial_number                            AS sensor_label,
    s.external_metadata->>'Parameter'          AS aquarius_parameter,
    -- Sensor classification
    st.sensor_type_id,
    st.sensor_type_name                         AS sensor_type,
    s.unit,
    s.sensor_model                             AS sensor_model,   -- enriched instrument
    s.external_metadata->>'DataOwner'          AS data_owner,     -- enriched owner
    s.is_active,
    s.installation_height_m,
    s.sampling_interval_seconds,
    s.installation_date,
    -- Location
    l.location_id,
    l.location_name,
    -- Latest reading (LATERAL backed by idx_sensor_readings_sensor_timestamp)
    lr.timestamp                              AS latest_timestamp,
    lr.value                                  AS latest_value,
    lr.quality                                AS latest_quality,
    -- Linked tree (NULL for meteo/soil sensors or unlinked tree sensors)
    t.tree_id                                  AS linked_tree_id,
    t.tree_entity_id                            AS linked_tree_entity_id,
    sp.common_name                             AS linked_tree_species,
    sp.scientific_name                         AS linked_tree_scientificname,
    t.height_m                                AS linked_tree_height_m,
    -- Position — flat lat/lon avoids PostGIS parsing in UE Blueprint
    extensions.ST_Y(s.position)              AS latitude,
    extensions.ST_X(s.position)              AS longitude
FROM sensor.sensors s
JOIN  sensor.sensortypes         st  ON s.sensor_type_id  = st.sensor_type_id
JOIN  shared.locations           l   ON s.location_id    = l.location_id
LEFT JOIN LATERAL (
    SELECT sr.timestamp, sr.value, sr.quality
    FROM   sensor.sensorreadings sr
    WHERE  sr.sensor_id = s.sensor_id
    ORDER  BY sr.timestamp DESC
    LIMIT  1
) lr ON TRUE
LEFT JOIN sensor.sensor_tree_links stl ON stl.sensor_id = s.sensor_id
LEFT JOIN trees.trees              t   ON stl.tree_id   = t.tree_id
LEFT JOIN shared.species           sp  ON t.species_id   = sp.species_id;

COMMENT ON VIEW public.ue_sensors IS
    'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model '
    '(enriched instrument), data owner, location, latest reading, and linked tree '
    'info (populated after sensor_tree_links is filled). '
    'GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>';

GRANT SELECT ON public.ue_sensors TO anon, authenticated;
GRANT ALL    ON public.ue_sensors TO service_role;

ALTER VIEW public.ue_sensors SET (security_invoker = on);
