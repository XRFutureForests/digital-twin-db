-- XR Future Forests Lab — UE Sensor Views (XRFF-250)
-- Naming convention: ue_* prefix groups all Unreal Engine query views.
-- Dependencies: 14-sensor-schema.sql, 16-sensor-tree-links-schema.sql, 24-public-api-views.sql

-- =============================================================================
-- PUBLIC VIEW: SENSOR-TREE LINKS
-- =============================================================================

CREATE OR REPLACE VIEW public.sensor_tree_links AS
SELECT * FROM sensor.sensor_tree_links;

COMMENT ON VIEW public.sensor_tree_links IS 'Public API view for sensor-tree link table';

-- =============================================================================
-- UE_SENSORS — sensor catalogue with latest reading + linked tree
-- =============================================================================
-- One row per sensor. Tree-mounted sensors (Stem_Radial_Variation, Sap_Flow)
-- have linked_tree_* populated once sensor_tree_links is filled.
-- Meteo / soil sensors have NULL tree fields.
--
-- Note: sensor→tree mapping requires a manual lookup table (Aquarius label
-- numbering is independent from the DB plot×treenumber scheme). Populate
-- sensor.sensor_tree_links to activate tree fields.
--
-- Example queries:
--   GET /ue_sensors                                         → all sensors
--   GET /ue_sensors?isactive=eq.true                       → active only
--   GET /ue_sensors?sensor_type=eq.Stem_Radial_Variation   → dendrometers
--   GET /ue_sensors?linked_tree_id=eq.42                   → sensors on tree 42

CREATE OR REPLACE VIEW public.ue_sensors AS
SELECT
    s.sensorid,
    s.externalid                              AS aquarius_id,
    s.serialnumber                            AS sensor_label,
    s.externalmetadata->>'Parameter'          AS aquarius_parameter,
    -- Sensor classification
    st.sensortypeid,
    st.sensortypename                         AS sensor_type,
    s.unit,
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
    'Flat sensor catalogue for UE Blueprint. One row per sensor with type, location, '
    'latest reading, and linked tree info (populated after sensor_tree_links is filled). '
    'GET /ue_sensors?sensor_type=eq.Stem_Radial_Variation';

-- =============================================================================
-- UE_SENSORREADINGS — enriched time-series view for UE Blueprint
-- =============================================================================
-- Joins sensor type + unit onto raw readings so UE does not need a separate
-- sensor metadata lookup per reading batch. Keyed by sensorid only — the
-- sensor→tree relationship is looked up once via ue_sensors, not repeated
-- on every reading row.
--
-- Example: GET /ue_sensorreadings?sensorid=eq.7&order=timestamp.desc&limit=96

CREATE OR REPLACE VIEW public.ue_sensorreadings AS
SELECT
    sr.sensorreadingid,
    sr.sensorid,
    st.sensortypename   AS sensor_type,
    s.unit,
    sr.timestamp,
    sr.value,
    sr.quality
FROM sensor.sensorreadings   sr
JOIN  sensor.sensors         s   ON sr.sensorid       = s.sensorid
JOIN  sensor.sensortypes     st  ON s.sensortypeid    = st.sensortypeid;

COMMENT ON VIEW public.ue_sensorreadings IS
    'Enriched sensor time-series for UE Blueprint. Includes sensor type and unit, '
    'keyed by sensorid. Look up the linked tree once via ue_sensors, not per reading. '
    'GET /ue_sensorreadings?sensorid=eq.<id>&order=timestamp.desc&limit=96';

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON public.sensor_tree_links  TO anon, authenticated;
GRANT ALL    ON public.sensor_tree_links  TO service_role;

GRANT SELECT ON public.ue_sensors         TO anon, authenticated;
GRANT ALL    ON public.ue_sensors         TO service_role;

GRANT SELECT ON public.ue_sensorreadings  TO anon, authenticated;
GRANT ALL    ON public.ue_sensorreadings  TO service_role;

-- RLS passthrough (inherits from underlying tables)
ALTER VIEW public.sensor_tree_links SET (security_invoker = on);
ALTER VIEW public.ue_sensors        SET (security_invoker = on);
ALTER VIEW public.ue_sensorreadings SET (security_invoker = on);

-- =============================================================================
-- SENSOR-TREE LINKS INSERT TRIGGER (REST API writability)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sensor_tree_links_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sensor.sensor_tree_links (sensor_id, tree_id, description, start_date, end_date)
    VALUES (NEW.sensor_id, NEW.tree_id, NEW.description, NEW.start_date, NEW.end_date)
    ON CONFLICT (sensor_id, tree_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.sensor_tree_links_insert() IS
    'INSTEAD OF INSERT trigger for public.sensor_tree_links view';

CREATE TRIGGER sensor_tree_links_insert_trigger
INSTEAD OF INSERT ON public.sensor_tree_links
FOR EACH ROW EXECUTE FUNCTION public.sensor_tree_links_insert();

-- =============================================================================
-- NOTES ON PERFORMANCE
-- =============================================================================
-- ue_sensors LATERAL lookup: backed by idx_sensor_readings_sensor_timestamp
--   (sensorid, timestamp DESC) from 14-sensor-schema.sql.
-- ue_sensorreadings: filter always by sensorid; same index covers it.
