-- =============================================================================
-- 08: IMPORT CSV DATA
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Import tree data from CSV files mounted at /data
-- =============================================================================

SET search_path TO trees, shared, public, extensions;

-- =============================================================================
-- IMPORT ECOSENSE DATA
-- =============================================================================
-- The CSV has columns:
-- fid, species, qr_code_id, tree_image, comment, odk_KEY, x_32632, y_32632, 
-- diameter_m, tls_treeheight, plot_id, tree_id, full_id, elevation, sensor_tree

-- Create temporary staging table for ecosense data
CREATE TEMP TABLE ecosense_staging (
    row_num INTEGER,
    species TEXT,
    qr_code_id TEXT,
    tree_image TEXT,
    comment TEXT,
    odk_KEY TEXT,
    x_32632 NUMERIC,
    y_32632 NUMERIC,
    diameter_m NUMERIC,
    tls_treeheight NUMERIC,
    plot_id INTEGER,
    tree_id INTEGER,
    full_id TEXT,
    elevation NUMERIC,
    sensor_tree TEXT
);

-- Load CSV data
COPY ecosense_staging FROM '/data/ecosense_250911.csv' WITH (FORMAT csv, HEADER true);

-- Insert trees from ecosense data (use DISTINCT to handle duplicates)
INSERT INTO trees.Trees (
    LocationID,
    VariantTypeID,
    SpeciesID,
    TreeStatusID,
    TreeID,
    QRCode,
    Height_m,
    Position,
    PositionOriginal,
    FieldNotes,
    CreatedBy
)
SELECT DISTINCT ON (es.full_id)
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'EcoSense Mixed Plot'),
    (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original'),
    COALESCE(
        (SELECT SpeciesID FROM shared.Species WHERE CommonName ILIKE '%' || es.species || '%' LIMIT 1),
        (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'European Beech')
    ),
    (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'healthy'),
    es.full_id,
    es.qr_code_id,
    NULLIF(es.tls_treeheight, 0),
    -- Transform UTM 32N (EPSG:32632) to WGS84 (EPSG:4326)
    ST_Transform(ST_SetSRID(ST_MakePoint(es.x_32632, es.y_32632), 32632), 4326),
    -- Keep original UTM coordinates with elevation
    ST_SetSRID(ST_MakePoint(es.x_32632, es.y_32632, es.elevation), 32632),
    CONCAT_WS('; ', 
        CASE WHEN es.sensor_tree = 'true' THEN 'Sensor tree' END,
        NULLIF(es.comment, '')
    ),
    'csv_import_ecosense'
FROM ecosense_staging es
WHERE es.x_32632 IS NOT NULL AND es.y_32632 IS NOT NULL
ORDER BY es.full_id, es.row_num;

-- Insert stems with DBH for each tree (ecosense data has diameter_m)
INSERT INTO trees.Stems (
    TreeVariantID,
    StemNumber,
    DBH_cm
)
SELECT DISTINCT ON (t.VariantID)
    t.VariantID,
    1,
    es.diameter_m * 100  -- Convert meters to cm
FROM ecosense_staging es
JOIN trees.Trees t ON t.TreeID = es.full_id AND t.CreatedBy = 'csv_import_ecosense'
WHERE es.diameter_m IS NOT NULL AND es.diameter_m > 0;

DROP TABLE ecosense_staging;

DO $$
DECLARE
    tree_count INTEGER;
    stem_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO tree_count FROM trees.Trees WHERE CreatedBy = 'csv_import_ecosense';
    SELECT COUNT(*) INTO stem_count FROM trees.Stems s 
        JOIN trees.Trees t ON s.TreeVariantID = t.VariantID 
        WHERE t.CreatedBy = 'csv_import_ecosense';
    RAISE NOTICE '✅ EcoSense data imported: % trees, % stems', tree_count, stem_count;
END
$$;

-- =============================================================================
-- IMPORT MATHISLE DATA
-- =============================================================================
-- The CSV has columns:
-- row_id, species_short, date_time, qr_code, tree_id_fallback, gps_latitude, 
-- gps_longitude, gps_height, DBH, TreeID, species_label

-- Create temporary staging table for mathisle data (all TEXT to handle NA values)
CREATE TEMP TABLE mathisle_staging (
    row_id TEXT,
    species_short TEXT,
    date_time TEXT,
    qr_code TEXT,
    tree_id_fallback TEXT,
    gps_latitude TEXT,
    gps_longitude TEXT,
    gps_height TEXT,
    dbh TEXT,
    tree_id TEXT,
    species_label TEXT
);

-- Load CSV data
COPY mathisle_staging FROM '/data/mathisle_250904.csv' WITH (FORMAT csv, HEADER true);

-- Insert trees from mathisle data (use DISTINCT to handle duplicates)
INSERT INTO trees.Trees (
    LocationID,
    VariantTypeID,
    SpeciesID,
    TreeStatusID,
    TreeID,
    QRCode,
    Position,
    PositionOriginal,
    FieldNotes,
    CreatedBy
)
SELECT DISTINCT ON (COALESCE(ms.tree_id, ms.row_id))
    (SELECT LocationID FROM shared.Locations WHERE LocationName = 'Mathisleweiher Plot'),
    (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'original'),
    CASE
        WHEN ms.species_short = 'BE' THEN (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'European Beech' LIMIT 1)
        WHEN ms.species_short IN ('NS', 'SP') THEN (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'Norway Spruce' LIMIT 1)
        WHEN ms.species_short IN ('ESF', 'SF') THEN (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'Silver Fir' LIMIT 1)
        WHEN ms.species_short = 'DF' THEN (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'Douglas Fir' LIMIT 1)
        WHEN ms.species_short = 'ELA' THEN (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'Scots Pine' LIMIT 1)  -- European Larch, closest match
        ELSE (SELECT SpeciesID FROM shared.Species WHERE CommonName = 'European Beech' LIMIT 1)  -- Default for WCH, WST, NOM, SY, XBI, other
    END,
    (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'healthy'),
    COALESCE(ms.tree_id, ms.row_id),
    ms.qr_code,
    -- Already in WGS84 (cast TEXT to FLOAT, filtering out NA values)
    ST_SetSRID(ST_MakePoint(ms.gps_longitude::FLOAT, ms.gps_latitude::FLOAT), 4326),
    -- Original with elevation
    ST_SetSRID(ST_MakePoint(ms.gps_longitude::FLOAT, ms.gps_latitude::FLOAT, NULLIF(ms.gps_height, 'NA')::FLOAT), 4326),
    ms.species_label,
    'csv_import_mathisle'
FROM mathisle_staging ms
WHERE ms.gps_latitude IS NOT NULL 
  AND ms.gps_longitude IS NOT NULL
  AND ms.gps_latitude NOT IN ('NA', '0', '')
  AND ms.gps_longitude NOT IN ('NA', '0', '')
ORDER BY COALESCE(ms.tree_id, ms.row_id);

-- Insert stems with DBH for each tree
INSERT INTO trees.Stems (
    TreeVariantID,
    StemNumber,
    DBH_cm
)
SELECT DISTINCT ON (t.VariantID)
    t.VariantID,
    1,
    NULLIF(ms.dbh, 'NA')::FLOAT * 100  -- Convert meters to cm
FROM mathisle_staging ms
JOIN trees.Trees t ON t.TreeID = COALESCE(ms.tree_id, ms.row_id) AND t.CreatedBy = 'csv_import_mathisle'
WHERE ms.dbh IS NOT NULL AND ms.dbh NOT IN ('NA', '0', '');

DROP TABLE mathisle_staging;

DO $$
DECLARE
    tree_count INTEGER;
    stem_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO tree_count FROM trees.Trees WHERE CreatedBy = 'csv_import_mathisle';
    SELECT COUNT(*) INTO stem_count FROM trees.Stems s 
        JOIN trees.Trees t ON s.TreeVariantID = t.VariantID 
        WHERE t.CreatedBy = 'csv_import_mathisle';
    RAISE NOTICE '✅ Mathisle data imported: % trees, % stems', tree_count, stem_count;
END
$$;

-- =============================================================================
-- SUMMARY
-- =============================================================================

DO $$
DECLARE
    total_trees INTEGER;
    total_stems INTEGER;
    total_locations INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_trees FROM trees.Trees;
    SELECT COUNT(*) INTO total_stems FROM trees.Stems;
    SELECT COUNT(*) INTO total_locations FROM shared.Locations;
    
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '  Digital Forest Twin Database - Data Import Complete';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '  Locations: %', total_locations;
    RAISE NOTICE '  Trees:     %', total_trees;
    RAISE NOTICE '  Stems:     %', total_stems;
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '';
END
$$;
