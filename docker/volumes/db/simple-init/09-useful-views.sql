-- =============================================================================
-- 09: USEFUL VIEWS
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Convenience views for common queries
-- =============================================================================

SET search_path TO trees, shared, sensor, environments, public, extensions;

-- =============================================================================
-- TREES VIEWS
-- =============================================================================

-- View: Trees with species and stem info
CREATE OR REPLACE VIEW trees.v_trees_full AS
SELECT
    t.VariantID,
    t.TreeID,
    t.QRCode,
    sp.CommonName AS species_common,
    sp.ScientificName AS species_scientific,
    ts.TreeStatusName AS status,
    t.Height_m,
    s.DBH_cm,
    t.Position,
    ST_X(t.Position) AS longitude,
    ST_Y(t.Position) AS latitude,
    l.LocationName,
    t.FieldNotes,
    t.CreatedBy,
    t.CreatedAt
FROM trees.Trees t
LEFT JOIN shared.Species sp ON t.SpeciesID = sp.SpeciesID
LEFT JOIN trees.TreeStatus ts ON t.TreeStatusID = ts.TreeStatusID
LEFT JOIN shared.Locations l ON t.LocationID = l.LocationID
LEFT JOIN trees.Stems s ON t.VariantID = s.TreeVariantID AND s.StemNumber = 1;

COMMENT ON VIEW trees.v_trees_full IS 'Complete tree information with species, location, and main stem DBH';

-- View: Tree count by species and location
CREATE OR REPLACE VIEW trees.v_tree_summary AS
SELECT
    l.LocationName,
    sp.CommonName AS species,
    COUNT(*) AS tree_count,
    ROUND(AVG(t.Height_m)::numeric, 2) AS avg_height_m,
    ROUND(AVG(s.DBH_cm)::numeric, 2) AS avg_dbh_cm,
    ROUND(MIN(t.Height_m)::numeric, 2) AS min_height_m,
    ROUND(MAX(t.Height_m)::numeric, 2) AS max_height_m
FROM trees.Trees t
LEFT JOIN shared.Species sp ON t.SpeciesID = sp.SpeciesID
LEFT JOIN shared.Locations l ON t.LocationID = l.LocationID
LEFT JOIN trees.Stems s ON t.VariantID = s.TreeVariantID AND s.StemNumber = 1
GROUP BY l.LocationName, sp.CommonName
ORDER BY l.LocationName, tree_count DESC;

COMMENT ON VIEW trees.v_tree_summary IS 'Tree statistics aggregated by location and species';

-- =============================================================================
-- LOCATION VIEWS
-- =============================================================================

-- View: Location overview with tree counts
CREATE OR REPLACE VIEW shared.v_locations_overview AS
SELECT
    l.LocationID,
    l.LocationName,
    l.Description,
    l.Elevation_m,
    st.SoilTypeName,
    cz.ClimateZoneName,
    COUNT(DISTINCT t.VariantID) AS tree_count,
    COUNT(DISTINCT sen.SensorID) AS sensor_count,
    ST_AsGeoJSON(l.CenterPoint)::jsonb AS center_geojson
FROM shared.Locations l
LEFT JOIN shared.SoilTypes st ON l.SoilTypeID = st.SoilTypeID
LEFT JOIN shared.ClimateZones cz ON l.ClimateZoneID = cz.ClimateZoneID
LEFT JOIN trees.Trees t ON l.LocationID = t.LocationID
LEFT JOIN sensor.Sensors sen ON l.LocationID = sen.LocationID
GROUP BY l.LocationID, l.LocationName, l.Description, l.Elevation_m, 
         st.SoilTypeName, cz.ClimateZoneName, l.CenterPoint;

COMMENT ON VIEW shared.v_locations_overview IS 'Location summary with tree and sensor counts';

-- =============================================================================
-- SENSOR VIEWS
-- =============================================================================

-- View: Active sensors with latest readings
CREATE OR REPLACE VIEW sensor.v_active_sensors AS
SELECT
    s.SensorID,
    st.SensorTypeName,
    s.SensorModel,
    s.Unit,
    l.LocationName,
    s.IsActive,
    (
        SELECT sr.Value 
        FROM sensor.SensorReadings sr 
        WHERE sr.SensorID = s.SensorID 
        ORDER BY sr.Timestamp DESC 
        LIMIT 1
    ) AS last_value,
    (
        SELECT sr.Timestamp 
        FROM sensor.SensorReadings sr 
        WHERE sr.SensorID = s.SensorID 
        ORDER BY sr.Timestamp DESC 
        LIMIT 1
    ) AS last_reading_time
FROM sensor.Sensors s
JOIN sensor.SensorTypes st ON s.SensorTypeID = st.SensorTypeID
JOIN shared.Locations l ON s.LocationID = l.LocationID
WHERE s.IsActive = TRUE;

COMMENT ON VIEW sensor.v_active_sensors IS 'Active sensors with their most recent reading';

-- =============================================================================
-- EXPORT VIEWS (for data extraction)
-- =============================================================================

-- View: Export trees as GeoJSON-ready
CREATE OR REPLACE VIEW trees.v_trees_geojson AS
SELECT
    t.VariantID AS id,
    t.TreeID,
    sp.CommonName AS species,
    t.Height_m,
    s.DBH_cm,
    ts.TreeStatusName AS status,
    l.LocationName AS location,
    ST_AsGeoJSON(t.Position)::jsonb AS geometry
FROM trees.Trees t
LEFT JOIN shared.Species sp ON t.SpeciesID = sp.SpeciesID
LEFT JOIN trees.TreeStatus ts ON t.TreeStatusID = ts.TreeStatusID
LEFT JOIN shared.Locations l ON t.LocationID = l.LocationID
LEFT JOIN trees.Stems s ON t.VariantID = s.TreeVariantID AND s.StemNumber = 1;

COMMENT ON VIEW trees.v_trees_geojson IS 'Trees formatted for GeoJSON export';

DO $$
BEGIN
    RAISE NOTICE '✅ Convenience views created';
END
$$;
