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
    TreeEntityID UUID DEFAULT gen_random_uuid(),
    ParentVariantID INTEGER REFERENCES trees.Trees(VariantID) ON DELETE SET NULL,
    PointCloudVariantID INTEGER REFERENCES pointclouds.PointClouds(VariantID) ON DELETE SET NULL,
    CampaignID INTEGER REFERENCES shared.Campaigns(CampaignID) ON DELETE SET NULL,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    ScenarioID INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    VariantTypeID INTEGER NOT NULL REFERENCES shared.VariantTypes(VariantTypeID),
    ProcessID INTEGER REFERENCES shared.Processes(ProcessID) ON DELETE SET NULL,
    SpeciesID INTEGER REFERENCES shared.Species(SpeciesID) ON DELETE SET NULL,
    TreeStatusID INTEGER REFERENCES trees.TreeStatus(TreeStatusID),
    BranchingPatternID INTEGER REFERENCES trees.BranchingPatterns(BranchingPatternID),
    BarkCharacteristicID INTEGER REFERENCES trees.BarkCharacteristics(BarkCharacteristicID),
    -- Measurement metadata
    MeasurementDate DATE,
    DataSourceType VARCHAR(50) CHECK (DataSourceType IN ('lidar', 'field', 'photogrammetry', 'estimated', 'simulated')),
    -- Tree measurements
    Height_m NUMERIC(6, 2) CHECK (Height_m > 0 AND Height_m <= 200),
    HeightSource VARCHAR(50) DEFAULT 'measured',
    CrownWidth_m NUMERIC(6, 2) CHECK (CrownWidth_m >= 0 AND CrownWidth_m <= 100),
    CrownBaseHeight_m NUMERIC(6, 2) CHECK (CrownBaseHeight_m >= 0),
    CrownBoundary extensions.GEOMETRY(Polygon, 4326),
    CrownOffsetX_m NUMERIC(5, 2),
    CrownOffsetY_m NUMERIC(5, 2),
    Volume_m3 NUMERIC(10, 3) CHECK (Volume_m3 >= 0),
    Position extensions.GEOMETRY(Point, 4326) NOT NULL,
    PositionOriginal extensions.GEOMETRY,
    SourceCRS INTEGER,
    LeanAngle_deg NUMERIC(5, 2) CHECK (LeanAngle_deg >= 0 AND LeanAngle_deg <= 90),
    LeanDirection_azimuth INTEGER CHECK (LeanDirection_azimuth >= 0 AND LeanDirection_azimuth < 360),
    TimeDelta_yrs NUMERIC(8, 2),
    Age_years INTEGER CHECK (Age_years >= 0 AND Age_years <= 5000),
    HealthScore NUMERIC(3, 2) CHECK (HealthScore >= 0 AND HealthScore <= 1),
    Biomass_kg NUMERIC(12, 2) CHECK (Biomass_kg >= 0),
    CarbonContent_kg NUMERIC(12, 2) CHECK (CarbonContent_kg >= 0),
    -- Confidence and quality
    SpeciesConfidence NUMERIC(3, 2) CHECK (SpeciesConfidence >= 0 AND SpeciesConfidence <= 1),
    PositionConfidence NUMERIC(3, 2) CHECK (PositionConfidence >= 0 AND PositionConfidence <= 1),
    HeightConfidence NUMERIC(3, 2) CHECK (HeightConfidence >= 0 AND HeightConfidence <= 1),
    -- Status tracking
    StatusChangeDate DATE,
    TreeNumber INTEGER,
    FieldNotes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200),
    CONSTRAINT chk_crown_base_height CHECK (CrownBaseHeight_m IS NULL OR CrownBaseHeight_m <= Height_m)
);

COMMENT ON TABLE trees.Trees IS 'Tree measurement and simulation variants with spatial positions';
COMMENT ON COLUMN trees.Trees.VariantID IS 'Unique identifier for this tree variant';
COMMENT ON COLUMN trees.Trees.TreeEntityID IS 'Persistent UUID identifying the physical tree across all variants';
COMMENT ON COLUMN trees.Trees.ParentVariantID IS 'Parent variant for tracking growth or modifications';
COMMENT ON COLUMN trees.Trees.PointCloudVariantID IS 'Source point cloud variant if tree was detected from LiDAR';
COMMENT ON COLUMN trees.Trees.CampaignID IS 'Data collection campaign this measurement belongs to';
COMMENT ON COLUMN trees.Trees.MeasurementDate IS 'Actual date of field measurement (may differ from CreatedAt)';
COMMENT ON COLUMN trees.Trees.DataSourceType IS 'How the data was collected (lidar, field, photogrammetry, estimated, simulated)';
COMMENT ON COLUMN trees.Trees.Position IS 'PostGIS point for tree location in WGS84';
COMMENT ON COLUMN trees.Trees.PositionOriginal IS 'Original coordinates in source CRS before WGS84 transformation';
COMMENT ON COLUMN trees.Trees.CrownBoundary IS 'PostGIS polygon defining crown extent';
COMMENT ON COLUMN trees.Trees.CrownOffsetX_m IS 'Crown center offset from trunk position (X/East-West in meters)';
COMMENT ON COLUMN trees.Trees.CrownOffsetY_m IS 'Crown center offset from trunk position (Y/North-South in meters)';
COMMENT ON COLUMN trees.Trees.TimeDelta_yrs IS 'Time elapsed since parent variant (for growth simulations)';
COMMENT ON COLUMN trees.Trees.HealthScore IS 'Tree health assessment score (0=dead, 1=optimal)';
COMMENT ON COLUMN trees.Trees.SpeciesConfidence IS 'Confidence in species identification (0-1)';
COMMENT ON COLUMN trees.Trees.PositionConfidence IS 'Confidence in position accuracy (0-1)';
COMMENT ON COLUMN trees.Trees.HeightConfidence IS 'Confidence in height measurement (0-1)';
COMMENT ON COLUMN trees.Trees.StatusChangeDate IS 'Date when tree status changed (e.g., mortality date)';
COMMENT ON COLUMN trees.Trees.PlotID IS 'Sub-plot within the location where tree is located';
COMMENT ON COLUMN trees.Trees.TreeNumber IS 'Local tree identifier within the location/plot (e.g., 62 in ecosense plot 4, or 367 in mathisle)';
COMMENT ON COLUMN trees.Trees.SourceCRS IS 'EPSG code of original coordinate reference system for PositionOriginal';

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
CREATE INDEX idx_trees_tree_entity ON trees.Trees(TreeEntityID);
CREATE INDEX idx_trees_campaign ON trees.Trees(CampaignID);
CREATE INDEX idx_trees_measurement_date ON trees.Trees(MeasurementDate DESC);
CREATE INDEX idx_trees_data_source ON trees.Trees(DataSourceType);
CREATE INDEX idx_trees_plot ON trees.Trees(PlotID);
CREATE INDEX idx_trees_tree_number ON trees.Trees(TreeNumber);

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

-- =============================================================================
-- PHENOLOGY OBSERVATIONS
-- =============================================================================

CREATE TABLE trees.PhenologyObservations (
    ObservationID SERIAL PRIMARY KEY,
    TreeVariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    ObservationDate DATE NOT NULL,
    PhenophaseType VARCHAR(50) NOT NULL CHECK (PhenophaseType IN (
        'bud_break', 'leaf_out', 'flowering', 'fruit_set',
        'leaf_color', 'leaf_fall', 'dormancy'
    )),
    PhenophaseStatus VARCHAR(50) CHECK (PhenophaseStatus IN (
        'not_started', 'beginning', 'intermediate', 'peak', 'ending', 'completed'
    )),
    Intensity_percent NUMERIC(5, 2) CHECK (Intensity_percent >= 0 AND Intensity_percent <= 100),
    Observer VARCHAR(200),
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    CreatedBy VARCHAR(200)
);

COMMENT ON TABLE trees.PhenologyObservations IS 'Tree phenology observations tracking seasonal development phases';
COMMENT ON COLUMN trees.PhenologyObservations.PhenophaseType IS 'Type of phenological phase being observed';
COMMENT ON COLUMN trees.PhenologyObservations.PhenophaseStatus IS 'Current status of the phenophase';
COMMENT ON COLUMN trees.PhenologyObservations.Intensity_percent IS 'Intensity of the phenophase (0-100%)';

CREATE INDEX idx_phenology_tree ON trees.PhenologyObservations(TreeVariantID);
CREATE INDEX idx_phenology_date ON trees.PhenologyObservations(ObservationDate DESC);
CREATE INDEX idx_phenology_type ON trees.PhenologyObservations(PhenophaseType);

-- =============================================================================
-- DEADWOOD INVENTORY
-- =============================================================================

CREATE TABLE trees.Deadwood (
    DeadwoodID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    TreeVariantID INTEGER REFERENCES trees.Trees(VariantID) ON DELETE SET NULL,
    SpeciesID INTEGER REFERENCES shared.Species(SpeciesID) ON DELETE SET NULL,
    WoodType VARCHAR(50) NOT NULL CHECK (WoodType IN ('standing', 'fallen', 'stump', 'branch')),
    Length_m NUMERIC(6, 2) CHECK (Length_m > 0),
    Diameter_cm NUMERIC(6, 2) CHECK (Diameter_cm > 0),
    DecayClass INTEGER CHECK (DecayClass >= 1 AND DecayClass <= 5),
    Volume_m3 NUMERIC(10, 3) CHECK (Volume_m3 >= 0),
    Position extensions.GEOMETRY(Point, 4326),
    MeasurementDate DATE,
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    CreatedBy VARCHAR(200)
);

COMMENT ON TABLE trees.Deadwood IS 'Dead wood inventory including standing dead, fallen logs, stumps, and branches';
COMMENT ON COLUMN trees.Deadwood.WoodType IS 'Type of dead wood: standing, fallen, stump, or branch';
COMMENT ON COLUMN trees.Deadwood.DecayClass IS 'Decay stage from 1 (fresh) to 5 (fully decomposed)';
COMMENT ON COLUMN trees.Deadwood.TreeVariantID IS 'Optional link to known dead tree variant';

CREATE INDEX idx_deadwood_location ON trees.Deadwood(LocationID);
CREATE INDEX idx_deadwood_plot ON trees.Deadwood(PlotID);
CREATE INDEX idx_deadwood_tree ON trees.Deadwood(TreeVariantID);
CREATE INDEX idx_deadwood_species ON trees.Deadwood(SpeciesID);
CREATE INDEX idx_deadwood_type ON trees.Deadwood(WoodType);
CREATE INDEX idx_deadwood_position ON trees.Deadwood USING GIST (Position);

-- =============================================================================
-- GROUND VEGETATION SURVEYS
-- =============================================================================

CREATE TABLE trees.GroundVegetation (
    VegetationID SERIAL PRIMARY KEY,
    LocationID INTEGER NOT NULL REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    SpeciesName VARCHAR(200),
    CoverPercent NUMERIC(5, 2) CHECK (CoverPercent >= 0 AND CoverPercent <= 100),
    Height_cm NUMERIC(6, 2) CHECK (Height_cm >= 0),
    Layer VARCHAR(50) CHECK (Layer IN ('herb', 'shrub', 'moss', 'litter', 'fern', 'grass')),
    MeasurementDate DATE,
    Notes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    CreatedBy VARCHAR(200)
);

COMMENT ON TABLE trees.GroundVegetation IS 'Ground vegetation survey records by plot and layer';
COMMENT ON COLUMN trees.GroundVegetation.CoverPercent IS 'Estimated cover percentage (0-100)';
COMMENT ON COLUMN trees.GroundVegetation.Layer IS 'Vegetation layer: herb, shrub, moss, litter, fern, grass';

CREATE INDEX idx_groundveg_location ON trees.GroundVegetation(LocationID);
CREATE INDEX idx_groundveg_plot ON trees.GroundVegetation(PlotID);
CREATE INDEX idx_groundveg_layer ON trees.GroundVegetation(Layer);
CREATE INDEX idx_groundveg_date ON trees.GroundVegetation(MeasurementDate DESC);

-- =============================================================================
-- DISTURBANCE EVENTS - TREES JUNCTION TABLE
-- =============================================================================

CREATE TABLE shared.DisturbanceEvents_Trees (
    EventID INTEGER NOT NULL REFERENCES shared.DisturbanceEvents(EventID) ON DELETE CASCADE,
    TreeVariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    DamageLevel VARCHAR(50) CHECK (DamageLevel IN ('none', 'light', 'moderate', 'severe', 'destroyed')),
    Notes TEXT,
    PRIMARY KEY (EventID, TreeVariantID)
);

COMMENT ON TABLE shared.DisturbanceEvents_Trees IS 'Links disturbance events to affected individual trees with damage assessment';
COMMENT ON COLUMN shared.DisturbanceEvents_Trees.DamageLevel IS 'Level of damage to individual tree';

CREATE INDEX idx_dist_trees_event ON shared.DisturbanceEvents_Trees(EventID);
CREATE INDEX idx_dist_trees_tree ON shared.DisturbanceEvents_Trees(TreeVariantID);

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA trees TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA trees TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA trees TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA trees TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA trees TO anon, authenticated, service_role;
