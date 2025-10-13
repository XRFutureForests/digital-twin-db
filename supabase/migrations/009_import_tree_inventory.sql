-- Import Tree Inventory Data from CSV
-- This migration provides a template for importing the tree_inventory_250908.csv file

-- Note: The CSV file has these columns:
-- fid, species, qr_code_id, tree_image, comment, odk_KEY, x_32632, y_32632, diameter_m, tls_treeheight, plot_id, tree_id, full_id, elevation

-- Step 1: Create temporary staging table for CSV import
CREATE TEMP TABLE tree_inventory_staging (
    fid INTEGER,
    species VARCHAR(200),
    qr_code_id TEXT,
    tree_image VARCHAR(500),
    comment TEXT,
    odk_key TEXT,
    x_32632 DOUBLE PRECISION,
    y_32632 DOUBLE PRECISION,
    diameter_m DOUBLE PRECISION,
    tls_treeheight DOUBLE PRECISION,
    plot_id INTEGER,
    tree_id INTEGER,
    full_id VARCHAR(100),
    elevation DOUBLE PRECISION
);

-- Step 2: Import CSV file
-- This step requires running COPY command with appropriate file path
-- Example usage (run this manually or via script):
/*
COPY tree_inventory_staging
FROM '/path/to/data/tree_inventory_250908.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',');
*/

-- Step 3: Create or update species entries
INSERT INTO shared.Species (CommonName, ScientificName, GrowthCharacteristics)
SELECT DISTINCT
    CASE species
        WHEN 'Beech' THEN 'European Beech'
        WHEN 'Oak' THEN 'Pedunculate Oak'
        WHEN 'Spruce' THEN 'Norway Spruce'
        WHEN 'Fir' THEN 'Silver Fir'
        WHEN 'Pine' THEN 'Scots Pine'
        ELSE species
    END AS CommonName,
    CASE species
        WHEN 'Beech' THEN 'Fagus sylvatica'
        WHEN 'Oak' THEN 'Quercus robur'
        WHEN 'Spruce' THEN 'Picea abies'
        WHEN 'Fir' THEN 'Abies alba'
        WHEN 'Pine' THEN 'Pinus sylvestris'
        ELSE 'Unknown species'
    END AS ScientificName,
    '{"source": "tree_inventory_250908.csv"}'::jsonb AS GrowthCharacteristics
FROM tree_inventory_staging
ON CONFLICT (ScientificName) DO NOTHING;

-- Step 4: Create location entries for each plot
INSERT INTO shared.Locations (LocationName, CenterPoint, Description)
SELECT DISTINCT
    'Plot ' || plot_id AS LocationName,
    -- Convert from EPSG:32632 (UTM Zone 32N) to EPSG:4326 (WGS84)
    ST_Transform(
        ST_SetSRID(
            ST_MakePoint(AVG(x_32632), AVG(y_32632)),
            32632
        ),
        4326
    ) AS CenterPoint,
    'Plot imported from tree_inventory_250908.csv with ' || COUNT(*) || ' trees' AS Description
FROM tree_inventory_staging
GROUP BY plot_id
ON CONFLICT DO NOTHING;

-- Step 5: Import trees into trees.Trees table
-- Note: This creates trees with 'manual' variant type since they come from field measurements
INSERT INTO trees.Trees (
    LocationID,
    VariantTypeID,
    SpeciesID,
    TreeStatusID,
    Height_m,
    Position,
    FieldNotes,
    CreatedBy
)
SELECT
    l.LocationID,
    (SELECT VariantTypeID FROM shared.VariantTypes WHERE VariantTypeName = 'manual'),
    s.SpeciesID,
    (SELECT TreeStatusID FROM trees.TreeStatus WHERE TreeStatusName = 'healthy'),
    NULLIF(t.tls_treeheight, 0),  -- Height from TLS
    -- Convert coordinates from EPSG:32632 to EPSG:4326
    ST_Transform(
        ST_SetSRID(ST_MakePoint(t.x_32632, t.y_32632), 32632),
        4326
    ) AS Position,
    CONCAT(
        'Imported from tree_inventory_250908.csv',
        CASE WHEN t.qr_code_id IS NOT NULL THEN ' | QR: ' || t.qr_code_id ELSE '' END,
        CASE WHEN t.comment IS NOT NULL THEN ' | ' || t.comment ELSE '' END,
        ' | Plot: ' || t.plot_id || ', Tree: ' || t.tree_id,
        CASE WHEN t.tree_image IS NOT NULL THEN ' | Image: ' || t.tree_image ELSE '' END
    ) AS FieldNotes,
    'csv_import_250908' AS CreatedBy
FROM tree_inventory_staging t
JOIN shared.Locations l ON l.LocationName = 'Plot ' || t.plot_id
LEFT JOIN shared.Species s ON s.ScientificName = CASE t.species
    WHEN 'Beech' THEN 'Fagus sylvatica'
    WHEN 'Oak' THEN 'Quercus robur'
    WHEN 'Spruce' THEN 'Picea abies'
    WHEN 'Fir' THEN 'Abies alba'
    WHEN 'Pine' THEN 'Pinus sylvestris'
    ELSE 'Unknown species'
END;

-- Step 6: Create stem measurements
-- Calculate DBH from diameter_m
INSERT INTO trees.Stems (
    TreeVariantID,
    StemNumber,
    DBH_cm,
    StemHeight_m,
    TaperTypeID,
    StraightnessTypeID
)
SELECT
    tr.VariantID,
    1 AS StemNumber,  -- Assume single stem
    (t.diameter_m * 100) AS DBH_cm,  -- Convert m to cm
    NULLIF(t.tls_treeheight, 0) AS StemHeight_m,
    (SELECT TaperTypeID FROM trees.TaperTypes WHERE TaperTypeName = 'Paraboloid') AS TaperTypeID,
    (SELECT StraightnessTypeID FROM trees.StraightnessTypes WHERE StraightnessName = 'Straight') AS StraightnessTypeID
FROM tree_inventory_staging t
JOIN shared.Locations l ON l.LocationName = 'Plot ' || t.plot_id
JOIN trees.Trees tr ON ST_Equals(
    tr.Position,
    ST_Transform(ST_SetSRID(ST_MakePoint(t.x_32632, t.y_32632), 32632), 4326)
)
WHERE t.diameter_m IS NOT NULL AND t.diameter_m > 0
  AND tr.CreatedBy = 'csv_import_250908';

-- Step 7: Create a view for easy access to imported trees
CREATE OR REPLACE VIEW trees.imported_tree_inventory AS
SELECT
    t.VariantID,
    t.Position,
    ST_X(ST_Transform(t.Position, 32632)) AS x_32632,
    ST_Y(ST_Transform(t.Position, 32632)) AS y_32632,
    s.CommonName AS species,
    s.ScientificName,
    t.Height_m AS tls_treeheight,
    st.DBH_cm / 100.0 AS diameter_m,
    l.LocationName,
    SUBSTRING(t.FieldNotes FROM 'Plot: ([0-9]+)') AS plot_id,
    SUBSTRING(t.FieldNotes FROM 'Tree: ([0-9]+)') AS tree_id,
    SUBSTRING(t.FieldNotes FROM 'QR: ([^|]+)') AS qr_code_id,
    SUBSTRING(t.FieldNotes FROM 'Image: ([^|]+)') AS tree_image,
    t.CreatedAt
FROM trees.Trees t
LEFT JOIN shared.Species s ON t.SpeciesID = s.SpeciesID
LEFT JOIN shared.Locations l ON t.LocationID = l.LocationID
LEFT JOIN trees.Stems st ON t.VariantID = st.TreeVariantID AND st.StemNumber = 1
WHERE t.CreatedBy = 'csv_import_250908';

COMMENT ON VIEW trees.imported_tree_inventory IS 'View of trees imported from tree_inventory_250908.csv with original column names';

-- Step 8: Create summary statistics
CREATE OR REPLACE VIEW trees.inventory_import_summary AS
SELECT
    COUNT(*) AS total_trees,
    COUNT(DISTINCT LocationID) AS total_plots,
    COUNT(DISTINCT SpeciesID) AS unique_species,
    AVG(Height_m) AS avg_height_m,
    MIN(Height_m) AS min_height_m,
    MAX(Height_m) AS max_height_m,
    AVG(st.DBH_cm) AS avg_dbh_cm,
    MIN(st.DBH_cm) AS min_dbh_cm,
    MAX(st.DBH_cm) AS max_dbh_cm
FROM trees.Trees t
LEFT JOIN trees.Stems st ON t.VariantID = st.TreeVariantID
WHERE t.CreatedBy = 'csv_import_250908';

COMMENT ON VIEW trees.inventory_import_summary IS 'Summary statistics of imported tree inventory';

-- Grant permissions
GRANT SELECT ON trees.imported_tree_inventory TO anon, authenticated;
GRANT SELECT ON trees.inventory_import_summary TO anon, authenticated;

-- Instructions for manual import:
COMMENT ON TABLE tree_inventory_staging IS 'Temporary staging table for CSV import.
To import:
1. Place tree_inventory_250908.csv in accessible location
2. Run: COPY tree_inventory_staging FROM ''/path/to/tree_inventory_250908.csv'' WITH (FORMAT csv, HEADER true);
3. The rest of this migration will automatically process the data
4. Verify with: SELECT * FROM trees.inventory_import_summary;';
