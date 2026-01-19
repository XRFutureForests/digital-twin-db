-- XR Future Forests Lab - Trees Schema Migration
-- This migration creates the trees schema for tree measurement and simulation data with multi-stem support

-- Create trees schema
CREATE SCHEMA IF NOT EXISTS trees;

-- Set search path
SET search_path TO trees, shared, pointclouds, public;

-- =============================================================================
-- REFERENCE TABLES FOR TREE CHARACTERISTICS
-- =============================================================================

CREATE TABLE trees.TreeStatus (
    TreeStatusID SERIAL PRIMARY KEY,
    TreeStatusName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_tree_status_name CHECK (TreeStatusName IN ('healthy', 'stressed', 'declining', 'dead', 'harvested', 'missing'))
);

COMMENT ON TABLE trees.TreeStatus IS 'Tree health and status classification';

-- NOTE: TreeStatus data is loaded from data/lookups/tree_status.csv

CREATE TABLE trees.TaperTypes (
    TaperTypeID SERIAL PRIMARY KEY,
    TaperTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    TypicalTaperRatioMin NUMERIC(4, 3) CHECK (TypicalTaperRatioMin >= 0 AND TypicalTaperRatioMin <= 1),
    TypicalTaperRatioMax NUMERIC(4, 3) CHECK (TypicalTaperRatioMax >= 0 AND TypicalTaperRatioMax <= 1),
    CONSTRAINT chk_taper_ratio_order CHECK (TypicalTaperRatioMin <= TypicalTaperRatioMax)
);

COMMENT ON TABLE trees.TaperTypes IS 'Stem taper form classifications';
COMMENT ON COLUMN trees.TaperTypes.TypicalTaperRatioMin IS 'Minimum typical taper ratio (diameter at top / diameter at bottom)';

-- NOTE: TaperTypes data is loaded from data/lookups/taper_types.csv

CREATE TABLE trees.StraightnessTypes (
    StraightnessTypeID SERIAL PRIMARY KEY,
    StraightnessName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    DeviationAngleMin NUMERIC(5, 2) CHECK (DeviationAngleMin >= 0 AND DeviationAngleMin <= 90),
    DeviationAngleMax NUMERIC(5, 2) CHECK (DeviationAngleMax >= 0 AND DeviationAngleMax <= 90),
    CONSTRAINT chk_deviation_order CHECK (DeviationAngleMin <= DeviationAngleMax)
);

COMMENT ON TABLE trees.StraightnessTypes IS 'Stem straightness classifications';

-- NOTE: StraightnessTypes data is loaded from data/lookups/straightness_types.csv

CREATE TABLE trees.BranchingPatterns (
    BranchingPatternID SERIAL PRIMARY KEY,
    BranchingPatternName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.BranchingPatterns IS 'Branch arrangement patterns on stems';

-- NOTE: BranchingPatterns data is loaded from data/lookups/branching_patterns.csv

CREATE TABLE trees.BarkCharacteristics (
    BarkCharacteristicID SERIAL PRIMARY KEY,
    BarkCharacteristicName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    TypicalSpecies TEXT
);

COMMENT ON TABLE trees.BarkCharacteristics IS 'Bark texture and appearance classifications';

-- NOTE: BarkCharacteristics data is loaded from data/lookups/bark_characteristics.csv

-- Create indexes on reference tables
CREATE INDEX idx_tree_status_name ON trees.TreeStatus(TreeStatusName);
CREATE INDEX idx_taper_types_name ON trees.TaperTypes(TaperTypeName);
CREATE INDEX idx_straightness_types_name ON trees.StraightnessTypes(StraightnessName);
CREATE INDEX idx_branching_patterns_name ON trees.BranchingPatterns(BranchingPatternName);
CREATE INDEX idx_bark_characteristics_name ON trees.BarkCharacteristics(BarkCharacteristicName);

-- =============================================================================
-- TREES TABLE (VARIANT-BASED WITH MULTI-STEM SUPPORT)
-- =============================================================================

CREATE TABLE trees.Trees (
    VariantID SERIAL PRIMARY KEY,
    ParentVariantID INTEGER REFERENCES trees.Trees(VariantID) ON DELETE SET NULL,
    PointCloudVariantID INTEGER REFERENCES pointclouds.PointClouds(VariantID) ON DELETE SET NULL,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    ScenarioID INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    VariantTypeID INTEGER NOT NULL REFERENCES shared.VariantTypes(VariantTypeID),
    ProcessID INTEGER REFERENCES shared.Processes(ProcessID) ON DELETE SET NULL,
    SpeciesID INTEGER REFERENCES shared.Species(SpeciesID) ON DELETE SET NULL,
    TreeStatusID INTEGER REFERENCES trees.TreeStatus(TreeStatusID),
    BranchingPatternID INTEGER REFERENCES trees.BranchingPatterns(BranchingPatternID),
    BarkCharacteristicID INTEGER REFERENCES trees.BarkCharacteristics(BarkCharacteristicID),
    Height_m NUMERIC(6, 2) CHECK (Height_m > 0 AND Height_m <= 200),
    CrownWidth_m NUMERIC(6, 2) CHECK (CrownWidth_m >= 0 AND CrownWidth_m <= 100),
    CrownBaseHeight_m NUMERIC(6, 2) CHECK (CrownBaseHeight_m >= 0),
    CrownBoundary extensions.GEOMETRY(Polygon, 4326),
    Volume_m3 NUMERIC(10, 3) CHECK (Volume_m3 >= 0),
    Position extensions.GEOMETRY(Point, 4326) NOT NULL,
    PositionOriginal extensions.GEOMETRY,
    LeanAngle_deg NUMERIC(5, 2) CHECK (LeanAngle_deg >= 0 AND LeanAngle_deg <= 90),
    LeanDirection_azimuth INTEGER CHECK (LeanDirection_azimuth >= 0 AND LeanDirection_azimuth < 360),
    TimeDelta_yrs NUMERIC(8, 2),
    Age_years INTEGER CHECK (Age_years >= 0 AND Age_years <= 5000),
    HealthScore NUMERIC(3, 2) CHECK (HealthScore >= 0 AND HealthScore <= 1),
    Biomass_kg NUMERIC(12, 2) CHECK (Biomass_kg >= 0),
    CarbonContent_kg NUMERIC(12, 2) CHECK (CarbonContent_kg >= 0),
    FieldNotes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_crown_base_height CHECK (CrownBaseHeight_m IS NULL OR CrownBaseHeight_m <= Height_m)
);

COMMENT ON TABLE trees.Trees IS 'Tree measurement and simulation variants with spatial positions';
COMMENT ON COLUMN trees.Trees.VariantID IS 'Unique identifier for this tree variant';
COMMENT ON COLUMN trees.Trees.ParentVariantID IS 'Parent variant for tracking growth or modifications';
COMMENT ON COLUMN trees.Trees.PointCloudVariantID IS 'Source point cloud variant if tree was detected from LiDAR';
COMMENT ON COLUMN trees.Trees.Position IS 'PostGIS point for tree location in WGS84';
COMMENT ON COLUMN trees.Trees.PositionOriginal IS 'Original coordinates in source CRS before WGS84 transformation';
COMMENT ON COLUMN trees.Trees.CrownBoundary IS 'PostGIS polygon defining crown extent';
COMMENT ON COLUMN trees.Trees.TimeDelta_yrs IS 'Time elapsed since parent variant (for growth simulations)';
COMMENT ON COLUMN trees.Trees.HealthScore IS 'Tree health assessment score (0=dead, 1=optimal)';

-- Create indexes
CREATE INDEX idx_trees_parent_variant ON trees.Trees(ParentVariantID);
CREATE INDEX idx_trees_pointcloud_variant ON trees.Trees(PointCloudVariantID);
CREATE INDEX idx_trees_location ON trees.Trees(LocationID);
CREATE INDEX idx_trees_scenario ON trees.Trees(ScenarioID);
CREATE INDEX idx_trees_variant_type ON trees.Trees(VariantTypeID);
CREATE INDEX idx_trees_process ON trees.Trees(ProcessID);
CREATE INDEX idx_trees_species ON trees.Trees(SpeciesID);
CREATE INDEX idx_trees_tree_status ON trees.Trees(TreeStatusID);
CREATE INDEX idx_trees_position ON trees.Trees USING GIST (Position);
CREATE INDEX idx_trees_crown_boundary ON trees.Trees USING GIST (CrownBoundary);
CREATE INDEX idx_trees_height ON trees.Trees(Height_m);
CREATE INDEX idx_trees_created_at ON trees.Trees(CreatedAt DESC);
CREATE INDEX idx_trees_created_by ON trees.Trees(CreatedBy);

-- =============================================================================
-- STEMS TABLE (MULTI-STEM SUPPORT)
-- =============================================================================

CREATE TABLE trees.Stems (
    StemID SERIAL PRIMARY KEY,
    TreeVariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    StemNumber INTEGER NOT NULL CHECK (StemNumber >= 1),
    TaperTypeID INTEGER REFERENCES trees.TaperTypes(TaperTypeID),
    StraightnessTypeID INTEGER REFERENCES trees.StraightnessTypes(StraightnessTypeID),
    DBH_cm NUMERIC(6, 2) CHECK (DBH_cm > 0 AND DBH_cm <= 1000),
    TaperRatio NUMERIC(4, 3) CHECK (TaperRatio >= 0 AND TaperRatio <= 1),
    Sweep_cm_per_m NUMERIC(5, 2) CHECK (Sweep_cm_per_m >= 0),
    StemHeight_m NUMERIC(6, 2) CHECK (StemHeight_m > 0 AND StemHeight_m <= 200),
    StemVolume_m3 NUMERIC(10, 3) CHECK (StemVolume_m3 >= 0),
    BarkThickness_mm NUMERIC(5, 2) CHECK (BarkThickness_mm >= 0 AND BarkThickness_mm <= 200),
    WoodDensity_kg_m3 NUMERIC(6, 2) CHECK (WoodDensity_kg_m3 >= 100 AND WoodDensity_kg_m3 <= 2000),
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    UNIQUE (TreeVariantID, StemNumber)
);

COMMENT ON TABLE trees.Stems IS 'Individual stem measurements for multi-stem trees';
COMMENT ON COLUMN trees.Stems.StemNumber IS 'Stem number (1=main stem, 2+=secondary stems)';
COMMENT ON COLUMN trees.Stems.DBH_cm IS 'Diameter at breast height (1.3m) in centimeters';
COMMENT ON COLUMN trees.Stems.TaperRatio IS 'Ratio of top diameter to bottom diameter';
COMMENT ON COLUMN trees.Stems.Sweep_cm_per_m IS 'Maximum horizontal deviation per meter of height';

CREATE INDEX idx_stems_tree_variant ON trees.Stems(TreeVariantID);
CREATE INDEX idx_stems_stem_number ON trees.Stems(StemNumber);
CREATE INDEX idx_stems_taper_type ON trees.Stems(TaperTypeID);
CREATE INDEX idx_stems_straightness_type ON trees.Stems(StraightnessTypeID);
CREATE INDEX idx_stems_dbh ON trees.Stems(DBH_cm);

-- =============================================================================
-- JUNCTION TABLES
-- =============================================================================

CREATE TABLE shared.ProcessParameters_Trees (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, VariantID)
);

COMMENT ON TABLE shared.ProcessParameters_Trees IS 'Links process parameters to tree variants';

CREATE INDEX idx_pp_trees_parameter ON shared.ProcessParameters_Trees(ParameterID);
CREATE INDEX idx_pp_trees_variant ON shared.ProcessParameters_Trees(VariantID);

CREATE TABLE shared.ProcessParameters_Stems (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    StemID INTEGER NOT NULL REFERENCES trees.Stems(StemID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, StemID)
);

COMMENT ON TABLE shared.ProcessParameters_Stems IS 'Links process parameters to individual stems';

CREATE INDEX idx_pp_stems_parameter ON shared.ProcessParameters_Stems(ParameterID);
CREATE INDEX idx_pp_stems_stem ON shared.ProcessParameters_Stems(StemID);

CREATE TABLE shared.AuditLog_Trees (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, VariantID)
);

COMMENT ON TABLE shared.AuditLog_Trees IS 'Links audit log entries to tree variants';

CREATE INDEX idx_audit_trees_audit ON shared.AuditLog_Trees(AuditID);
CREATE INDEX idx_audit_trees_variant ON shared.AuditLog_Trees(VariantID);

CREATE TABLE shared.AuditLog_Stems (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    StemID INTEGER NOT NULL REFERENCES trees.Stems(StemID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, StemID)
);

COMMENT ON TABLE shared.AuditLog_Stems IS 'Links audit log entries to individual stems';

CREATE INDEX idx_audit_stems_audit ON shared.AuditLog_Stems(AuditID);
CREATE INDEX idx_audit_stems_stem ON shared.AuditLog_Stems(StemID);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to calculate basal area from DBH
CREATE OR REPLACE FUNCTION trees.calculate_basal_area(dbh_cm NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    -- Basal area = π * (DBH/2)^2, convert cm to m
    RETURN PI() * POWER(dbh_cm / 200.0, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION trees.calculate_basal_area IS 'Calculates basal area in m² from DBH in cm';

-- Function to calculate crown volume (assuming ellipsoid)
CREATE OR REPLACE FUNCTION trees.calculate_crown_volume(crown_width_m NUMERIC, crown_height_m NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    -- Volume of ellipsoid: (4/3) * π * a * b * c
    -- Assuming circular crown: a = b = crown_width/2, c = crown_height/2
    RETURN (4.0/3.0) * PI() * POWER(crown_width_m / 2.0, 2) * (crown_height_m / 2.0);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION trees.calculate_crown_volume IS 'Calculates crown volume in m³ assuming ellipsoid shape';

-- =============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- =============================================================================

CREATE OR REPLACE FUNCTION trees.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.UpdatedAt = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_trees_updated_at
    BEFORE UPDATE ON trees.Trees
    FOR EACH ROW
    EXECUTE FUNCTION trees.update_updated_at_column();

CREATE TRIGGER trigger_stems_updated_at
    BEFORE UPDATE ON trees.Stems
    FOR EACH ROW
    EXECUTE FUNCTION trees.update_updated_at_column();

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- View: Trees with computed metrics
CREATE OR REPLACE VIEW trees.trees_with_metrics AS
SELECT
    t.*,
    s.ScientificName,
    s.CommonName,
    COUNT(st.StemID) AS stem_count,
    SUM(trees.calculate_basal_area(st.DBH_cm)) AS total_basal_area_m2,
    trees.calculate_crown_volume(t.CrownWidth_m, t.Height_m - t.CrownBaseHeight_m) AS crown_volume_m3
FROM trees.Trees t
LEFT JOIN shared.Species s ON t.SpeciesID = s.SpeciesID
LEFT JOIN trees.Stems st ON t.VariantID = st.TreeVariantID
GROUP BY t.VariantID, s.SpeciesID;

COMMENT ON VIEW trees.trees_with_metrics IS 'Trees with computed metrics (basal area, crown volume, stem count)';

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA trees TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA trees TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA trees TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA trees TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA trees TO anon, authenticated, service_role;
