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
    tree_status_id SERIAL PRIMARY KEY,
    tree_status_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_tree_status_name CHECK (tree_status_name IN ('healthy', 'stressed', 'declining', 'dead', 'harvested', 'missing'))
);

COMMENT ON TABLE trees.TreeStatus IS 'Tree health and status classification';

-- NOTE: TreeStatus data is loaded from data/lookups/tree_status.csv

CREATE TABLE trees.TaperTypes (
    taper_type_id SERIAL PRIMARY KEY,
    taper_type_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    typical_taper_ratio_min NUMERIC(4, 3) CHECK (typical_taper_ratio_min >= 0 AND typical_taper_ratio_min <= 1),
    typical_taper_ratio_max NUMERIC(4, 3) CHECK (typical_taper_ratio_max >= 0 AND typical_taper_ratio_max <= 1),
    CONSTRAINT chk_taper_ratio_order CHECK (typical_taper_ratio_min <= typical_taper_ratio_max)
);

COMMENT ON TABLE trees.TaperTypes IS 'Stem taper form classifications';
COMMENT ON COLUMN trees.TaperTypes.typical_taper_ratio_min IS 'Minimum typical taper ratio (diameter at top / diameter at bottom)';

-- NOTE: TaperTypes data is loaded from data/lookups/taper_types.csv

CREATE TABLE trees.StraightnessTypes (
    straightness_type_id SERIAL PRIMARY KEY,
    straightness_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    deviation_angle_min NUMERIC(5, 2) CHECK (deviation_angle_min >= 0 AND deviation_angle_min <= 90),
    deviation_angle_max NUMERIC(5, 2) CHECK (deviation_angle_max >= 0 AND deviation_angle_max <= 90),
    CONSTRAINT chk_deviation_order CHECK (deviation_angle_min <= deviation_angle_max)
);

COMMENT ON TABLE trees.StraightnessTypes IS 'Stem straightness classifications';

-- NOTE: StraightnessTypes data is loaded from data/lookups/straightness_types.csv

CREATE TABLE trees.BranchingPatterns (
    branching_pattern_id SERIAL PRIMARY KEY,
    branching_pattern_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.BranchingPatterns IS 'Branch arrangement patterns on stems';

-- NOTE: BranchingPatterns data is loaded from data/lookups/branching_patterns.csv

CREATE TABLE trees.BarkCharacteristics (
    bark_characteristic_id SERIAL PRIMARY KEY,
    bark_characteristic_name VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    typical_species TEXT
);

COMMENT ON TABLE trees.BarkCharacteristics IS 'Bark texture and appearance classifications';

-- NOTE: BarkCharacteristics data is loaded from data/lookups/bark_characteristics.csv

CREATE TABLE trees.DataSourceTypes (
    data_source_type_id   SERIAL PRIMARY KEY,
    data_source_type_name VARCHAR(50) NOT NULL UNIQUE,
    Description        TEXT
);
COMMENT ON TABLE trees.DataSourceTypes IS 'How tree measurement data was collected or generated';
-- NOTE: DataSourceTypes data is loaded from data/lookups/datasource_types.csv

-- Create indexes on reference tables
CREATE INDEX idx_tree_status_name ON trees.TreeStatus(tree_status_name);
CREATE INDEX idx_taper_types_name ON trees.TaperTypes(taper_type_name);
CREATE INDEX idx_straightness_types_name ON trees.StraightnessTypes(straightness_name);
CREATE INDEX idx_branching_patterns_name ON trees.BranchingPatterns(branching_pattern_name);
CREATE INDEX idx_bark_characteristics_name ON trees.BarkCharacteristics(bark_characteristic_name);

-- =============================================================================
-- TREES TABLE (VARIANT-BASED WITH MULTI-STEM SUPPORT)
-- =============================================================================

CREATE TABLE trees.Trees (
    tree_id SERIAL PRIMARY KEY,
    tree_entity_id UUID DEFAULT gen_random_uuid(),
    variant_id INTEGER REFERENCES shared.Variants(variant_id) ON DELETE SET NULL,
    parent_tree_id INTEGER REFERENCES trees.Trees(tree_id) ON DELETE SET NULL,
    point_cloud_id INTEGER REFERENCES pointclouds.PointClouds(point_cloud_id) ON DELETE SET NULL,
    campaign_id INTEGER REFERENCES shared.Campaigns(campaign_id) ON DELETE SET NULL,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    scenario_id INTEGER REFERENCES shared.Scenarios(scenario_id) ON DELETE SET NULL,
    variant_type_id INTEGER NOT NULL REFERENCES shared.VariantTypes(variant_type_id),
    process_id INTEGER REFERENCES shared.Processes(process_id) ON DELETE SET NULL,
    species_id INTEGER REFERENCES shared.Species(species_id) ON DELETE SET NULL,
    tree_status_id INTEGER REFERENCES trees.TreeStatus(tree_status_id),
    branching_pattern_id INTEGER REFERENCES trees.BranchingPatterns(branching_pattern_id),
    bark_characteristic_id INTEGER REFERENCES trees.BarkCharacteristics(bark_characteristic_id),
    -- Measurement metadata
    measurement_date DATE,
    data_source_type_id   INTEGER REFERENCES trees.DataSourceTypes(data_source_type_id) ON DELETE SET NULL,
    -- Tree measurements
    Height_m NUMERIC(6, 2) CHECK (Height_m > 0 AND Height_m <= 200),
    height_source VARCHAR(50) DEFAULT 'measured',
    crown_width_m NUMERIC(6, 2) CHECK (crown_width_m >= 0 AND crown_width_m <= 100),
    crown_base_height_m NUMERIC(6, 2) CHECK (crown_base_height_m >= 0),
    crown_boundary extensions.GEOMETRY(Polygon, 4326),
    crown_offset_x_m NUMERIC(5, 2),
    crown_offset_y_m NUMERIC(5, 2),
    Volume_m3 NUMERIC(10, 3) CHECK (Volume_m3 >= 0),
    Position extensions.GEOMETRY(Point, 4326) NOT NULL,
    position_original extensions.GEOMETRY,
    source_crs INTEGER,
    lean_angle_deg NUMERIC(5, 2) CHECK (lean_angle_deg >= 0 AND lean_angle_deg <= 90),
    lean_direction_azimuth INTEGER CHECK (lean_direction_azimuth >= 0 AND lean_direction_azimuth < 360),
    time_delta_yrs NUMERIC(8, 2),
    Age_years INTEGER CHECK (Age_years >= 0 AND Age_years <= 5000),
    health_score NUMERIC(3, 2) CHECK (health_score >= 0 AND health_score <= 1),
    Biomass_kg NUMERIC(12, 2) CHECK (Biomass_kg >= 0),
    carbon_content_kg NUMERIC(12, 2) CHECK (carbon_content_kg >= 0),
    -- Confidence and quality
    species_confidence NUMERIC(3, 2) CHECK (species_confidence >= 0 AND species_confidence <= 1),
    position_confidence NUMERIC(3, 2) CHECK (position_confidence >= 0 AND position_confidence <= 1),
    height_confidence NUMERIC(3, 2) CHECK (height_confidence >= 0 AND height_confidence <= 1),
    -- Status tracking
    status_change_date DATE,
    tree_number INTEGER,
    field_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    created_by VARCHAR(200),
    updated_by VARCHAR(200),
    CONSTRAINT chk_crown_base_height CHECK (crown_base_height_m IS NULL OR crown_base_height_m <= Height_m)
);

COMMENT ON TABLE trees.Trees IS 'Tree measurement and simulation records with spatial positions';
COMMENT ON COLUMN trees.Trees.tree_id IS 'Unique row identifier for this tree record';
COMMENT ON COLUMN trees.Trees.tree_entity_id IS 'Persistent UUID identifying the physical tree across all variants';
COMMENT ON COLUMN trees.Trees.variant_id IS 'Forest state group — all trees sharing this variant_id belong to the same time step within a scenario. Use for UE time-travel switching.';
COMMENT ON COLUMN trees.Trees.parent_tree_id IS 'Parent tree record for tracking growth or modifications';
COMMENT ON COLUMN trees.Trees.point_cloud_id IS 'Source point cloud if tree was detected from LiDAR';
COMMENT ON COLUMN trees.Trees.campaign_id IS 'Data collection campaign this measurement belongs to';
COMMENT ON COLUMN trees.Trees.measurement_date IS 'Actual date of field measurement (may differ from created_at)';
COMMENT ON COLUMN trees.Trees.data_source_type_id IS 'FK to trees.DataSourceTypes — how the data was collected or generated';
COMMENT ON COLUMN trees.Trees.Position IS 'PostGIS point for tree location in WGS84';
COMMENT ON COLUMN trees.Trees.position_original IS 'Original coordinates in source CRS before WGS84 transformation';
COMMENT ON COLUMN trees.Trees.crown_boundary IS 'PostGIS polygon defining crown extent';
COMMENT ON COLUMN trees.Trees.crown_offset_x_m IS 'Crown center offset from trunk position (X/East-West in meters)';
COMMENT ON COLUMN trees.Trees.crown_offset_y_m IS 'Crown center offset from trunk position (Y/North-South in meters)';
COMMENT ON COLUMN trees.Trees.time_delta_yrs IS 'Time elapsed since parent variant (for growth simulations)';
COMMENT ON COLUMN trees.Trees.health_score IS 'Tree health assessment score (0=dead, 1=optimal)';
COMMENT ON COLUMN trees.Trees.species_confidence IS 'Confidence in species identification (0-1)';
COMMENT ON COLUMN trees.Trees.position_confidence IS 'Confidence in position accuracy (0-1)';
COMMENT ON COLUMN trees.Trees.height_confidence IS 'Confidence in height measurement (0-1)';
COMMENT ON COLUMN trees.Trees.status_change_date IS 'Date when tree status changed (e.g., mortality date)';
COMMENT ON COLUMN trees.Trees.plot_id IS 'Sub-plot within the location where tree is located';
COMMENT ON COLUMN trees.Trees.tree_number IS 'Local tree identifier within the location/plot (e.g., 62 in ecosense plot 4, or 367 in mathisle)';
COMMENT ON COLUMN trees.Trees.source_crs IS 'EPSG code of original coordinate reference system for position_original';

-- Create indexes
CREATE INDEX idx_trees_variant ON trees.Trees(variant_id);
CREATE INDEX idx_trees_parent ON trees.Trees(parent_tree_id);
CREATE INDEX idx_trees_pointcloud ON trees.Trees(point_cloud_id);
CREATE INDEX idx_trees_location ON trees.Trees(location_id);
CREATE INDEX idx_trees_scenario ON trees.Trees(scenario_id);
CREATE INDEX idx_trees_variant_type ON trees.Trees(variant_type_id);
CREATE INDEX idx_trees_process ON trees.Trees(process_id);
CREATE INDEX idx_trees_species ON trees.Trees(species_id);
CREATE INDEX idx_trees_tree_status ON trees.Trees(tree_status_id);
CREATE INDEX idx_trees_position ON trees.Trees USING GIST (Position);
CREATE INDEX idx_trees_crown_boundary ON trees.Trees USING GIST (crown_boundary);
CREATE INDEX idx_trees_height ON trees.Trees(Height_m);
CREATE INDEX idx_trees_created_at ON trees.Trees(created_at DESC);
CREATE INDEX idx_trees_created_by ON trees.Trees(created_by);
CREATE INDEX idx_trees_tree_entity ON trees.Trees(tree_entity_id);
CREATE INDEX idx_trees_campaign ON trees.Trees(campaign_id);
CREATE INDEX idx_trees_measurement_date ON trees.Trees(measurement_date DESC);
CREATE INDEX idx_trees_datasource_type ON trees.Trees(data_source_type_id);
CREATE INDEX idx_trees_plot ON trees.Trees(plot_id);
CREATE INDEX idx_trees_tree_number ON trees.Trees(tree_number);

-- =============================================================================
-- STEMS TABLE (MULTI-STEM SUPPORT)
-- =============================================================================

CREATE TABLE trees.Stems (
    stem_id SERIAL PRIMARY KEY,
    tree_id INTEGER NOT NULL REFERENCES trees.Trees(tree_id) ON DELETE CASCADE,
    stem_number INTEGER NOT NULL CHECK (stem_number >= 1),
    taper_type_id INTEGER REFERENCES trees.TaperTypes(taper_type_id),
    straightness_type_id INTEGER REFERENCES trees.StraightnessTypes(straightness_type_id),
    DBH_cm NUMERIC(6, 2) CHECK (DBH_cm > 0 AND DBH_cm <= 1000),
    taper_ratio NUMERIC(4, 3) CHECK (taper_ratio >= 0 AND taper_ratio <= 1),
    Sweep_cm_per_m NUMERIC(5, 2) CHECK (Sweep_cm_per_m >= 0),
    stem_height_m NUMERIC(6, 2) CHECK (stem_height_m > 0 AND stem_height_m <= 200),
    stem_volume_m3 NUMERIC(10, 3) CHECK (stem_volume_m3 >= 0),
    bark_thickness_mm NUMERIC(5, 2) CHECK (bark_thickness_mm >= 0 AND bark_thickness_mm <= 200),
    wood_density_kg_m3 NUMERIC(6, 2) CHECK (wood_density_kg_m3 >= 100 AND wood_density_kg_m3 <= 2000),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (tree_id, stem_number)
);

COMMENT ON TABLE trees.Stems IS 'Individual stem measurements for multi-stem trees';
COMMENT ON COLUMN trees.Stems.stem_number IS 'Stem number (1=main stem, 2+=secondary stems)';
COMMENT ON COLUMN trees.Stems.DBH_cm IS 'Diameter at breast height (1.3m) in centimeters';
COMMENT ON COLUMN trees.Stems.taper_ratio IS 'Ratio of top diameter to bottom diameter';
COMMENT ON COLUMN trees.Stems.Sweep_cm_per_m IS 'Maximum horizontal deviation per meter of height';

CREATE INDEX idx_stems_tree ON trees.Stems(tree_id);
CREATE INDEX idx_stems_stem_number ON trees.Stems(stem_number);
CREATE INDEX idx_stems_taper_type ON trees.Stems(taper_type_id);
CREATE INDEX idx_stems_straightness_type ON trees.Stems(straightness_type_id);
CREATE INDEX idx_stems_dbh ON trees.Stems(DBH_cm);

-- =============================================================================
-- JUNCTION TABLES
-- =============================================================================

CREATE TABLE shared.ProcessParameters_Trees (
    process_parameter_id INTEGER NOT NULL REFERENCES shared.ProcessParameters(process_parameter_id) ON DELETE CASCADE,
    tree_id INTEGER NOT NULL REFERENCES trees.Trees(tree_id) ON DELETE CASCADE,
    PRIMARY KEY (process_parameter_id, tree_id)
);

COMMENT ON TABLE shared.ProcessParameters_Trees IS 'Links process parameters to tree records';

CREATE INDEX idx_pp_trees_parameter ON shared.ProcessParameters_Trees(process_parameter_id);
CREATE INDEX idx_pp_trees_tree ON shared.ProcessParameters_Trees(tree_id);

CREATE TABLE shared.ProcessParameters_Stems (
    process_parameter_id INTEGER NOT NULL REFERENCES shared.ProcessParameters(process_parameter_id) ON DELETE CASCADE,
    stem_id INTEGER NOT NULL REFERENCES trees.Stems(stem_id) ON DELETE CASCADE,
    PRIMARY KEY (process_parameter_id, stem_id)
);

COMMENT ON TABLE shared.ProcessParameters_Stems IS 'Links process parameters to individual stems';

CREATE INDEX idx_pp_stems_parameter ON shared.ProcessParameters_Stems(process_parameter_id);
CREATE INDEX idx_pp_stems_stem ON shared.ProcessParameters_Stems(stem_id);

CREATE TABLE shared.AuditLog_Trees (
    audit_id BIGINT NOT NULL REFERENCES shared.AuditLog(audit_id) ON DELETE CASCADE,
    tree_id INTEGER NOT NULL REFERENCES trees.Trees(tree_id) ON DELETE CASCADE,
    PRIMARY KEY (audit_id, tree_id)
);

COMMENT ON TABLE shared.AuditLog_Trees IS 'Links audit log entries to tree records';

CREATE INDEX idx_audit_trees_audit ON shared.AuditLog_Trees(audit_id);
CREATE INDEX idx_audit_trees_tree ON shared.AuditLog_Trees(tree_id);

CREATE TABLE shared.AuditLog_Stems (
    audit_id BIGINT NOT NULL REFERENCES shared.AuditLog(audit_id) ON DELETE CASCADE,
    stem_id INTEGER NOT NULL REFERENCES trees.Stems(stem_id) ON DELETE CASCADE,
    PRIMARY KEY (audit_id, stem_id)
);


COMMENT ON TABLE shared.AuditLog_Stems IS 'Links audit log entries to individual stems';

CREATE INDEX idx_audit_stems_audit ON shared.AuditLog_Stems(audit_id);
CREATE INDEX idx_audit_stems_stem ON shared.AuditLog_Stems(stem_id);

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
    NEW.updated_at = NOW();
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
    s.scientific_name,
    s.common_name,
    COUNT(st.stem_id) AS stem_count,
    SUM(trees.calculate_basal_area(st.DBH_cm)) AS total_basal_area_m2,
    trees.calculate_crown_volume(t.crown_width_m, t.Height_m - t.crown_base_height_m) AS crown_volume_m3
FROM trees.Trees t
LEFT JOIN shared.Species s ON t.species_id = s.species_id
LEFT JOIN trees.Stems st ON t.tree_id = st.tree_id
GROUP BY t.tree_id, s.species_id;

COMMENT ON VIEW trees.trees_with_metrics IS 'Trees with computed metrics (basal area, crown volume, stem count)';

-- =============================================================================
-- PHENOLOGY OBSERVATIONS
-- =============================================================================

CREATE TABLE trees.PhenologyObservations (
    phenology_observation_id SERIAL PRIMARY KEY,
    tree_id INTEGER NOT NULL REFERENCES trees.Trees(tree_id) ON DELETE CASCADE,
    observation_date DATE NOT NULL,
    phenophase_type VARCHAR(50) NOT NULL CHECK (phenophase_type IN (
        'bud_break', 'leaf_out', 'flowering', 'fruit_set',
        'leaf_color', 'leaf_fall', 'dormancy'
    )),
    phenophase_status VARCHAR(50) CHECK (phenophase_status IN (
        'not_started', 'beginning', 'intermediate', 'peak', 'ending', 'completed'
    )),
    Intensity_percent NUMERIC(5, 2) CHECK (Intensity_percent >= 0 AND Intensity_percent <= 100),
    Observer VARCHAR(200),
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by VARCHAR(200)
);

COMMENT ON TABLE trees.PhenologyObservations IS 'Tree phenology observations tracking seasonal development phases';
COMMENT ON COLUMN trees.PhenologyObservations.phenophase_type IS 'Type of phenological phase being observed';
COMMENT ON COLUMN trees.PhenologyObservations.phenophase_status IS 'Current status of the phenophase';
COMMENT ON COLUMN trees.PhenologyObservations.Intensity_percent IS 'Intensity of the phenophase (0-100%)';

CREATE INDEX idx_phenology_tree ON trees.PhenologyObservations(tree_id);
CREATE INDEX idx_phenology_date ON trees.PhenologyObservations(observation_date DESC);
CREATE INDEX idx_phenology_type ON trees.PhenologyObservations(phenophase_type);

-- =============================================================================
-- DEADWOOD INVENTORY
-- =============================================================================

CREATE TABLE trees.Deadwood (
    deadwood_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    tree_id INTEGER REFERENCES trees.Trees(tree_id) ON DELETE SET NULL,
    species_id INTEGER REFERENCES shared.Species(species_id) ON DELETE SET NULL,
    wood_type VARCHAR(50) NOT NULL CHECK (wood_type IN ('standing', 'fallen', 'stump', 'branch')),
    Length_m NUMERIC(6, 2) CHECK (Length_m > 0),
    Diameter_cm NUMERIC(6, 2) CHECK (Diameter_cm > 0),
    decay_class INTEGER CHECK (decay_class >= 1 AND decay_class <= 5),
    Volume_m3 NUMERIC(10, 3) CHECK (Volume_m3 >= 0),
    Position extensions.GEOMETRY(Point, 4326),
    measurement_date DATE,
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by VARCHAR(200)
);

COMMENT ON TABLE trees.Deadwood IS 'Dead wood inventory including standing dead, fallen logs, stumps, and branches';
COMMENT ON COLUMN trees.Deadwood.wood_type IS 'Type of dead wood: standing, fallen, stump, or branch';
COMMENT ON COLUMN trees.Deadwood.decay_class IS 'Decay stage from 1 (fresh) to 5 (fully decomposed)';
COMMENT ON COLUMN trees.Deadwood.tree_id IS 'Optional link to known dead tree record';

CREATE INDEX idx_deadwood_location ON trees.Deadwood(location_id);
CREATE INDEX idx_deadwood_plot ON trees.Deadwood(plot_id);
CREATE INDEX idx_deadwood_tree ON trees.Deadwood(tree_id);
CREATE INDEX idx_deadwood_species ON trees.Deadwood(species_id);
CREATE INDEX idx_deadwood_type ON trees.Deadwood(wood_type);
CREATE INDEX idx_deadwood_position ON trees.Deadwood USING GIST (Position);

-- =============================================================================
-- GROUND VEGETATION SURVEYS
-- =============================================================================

CREATE TABLE trees.GroundVegetation (
    ground_vegetation_id SERIAL PRIMARY KEY,
    location_id INTEGER NOT NULL REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    species_name VARCHAR(200),
    cover_percent NUMERIC(5, 2) CHECK (cover_percent >= 0 AND cover_percent <= 100),
    Height_cm NUMERIC(6, 2) CHECK (Height_cm >= 0),
    Layer VARCHAR(50) CHECK (Layer IN ('herb', 'shrub', 'moss', 'litter', 'fern', 'grass')),
    measurement_date DATE,
    Notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by VARCHAR(200)
);

COMMENT ON TABLE trees.GroundVegetation IS 'Ground vegetation survey records by plot and layer';
COMMENT ON COLUMN trees.GroundVegetation.cover_percent IS 'Estimated cover percentage (0-100)';
COMMENT ON COLUMN trees.GroundVegetation.Layer IS 'Vegetation layer: herb, shrub, moss, litter, fern, grass';

CREATE INDEX idx_groundveg_location ON trees.GroundVegetation(location_id);
CREATE INDEX idx_groundveg_plot ON trees.GroundVegetation(plot_id);
CREATE INDEX idx_groundveg_layer ON trees.GroundVegetation(Layer);
CREATE INDEX idx_groundveg_date ON trees.GroundVegetation(measurement_date DESC);

-- =============================================================================
-- DISTURBANCE EVENTS - TREES JUNCTION TABLE
-- =============================================================================

CREATE TABLE shared.DisturbanceEvents_Trees (
    disturbance_event_id INTEGER NOT NULL REFERENCES shared.DisturbanceEvents(disturbance_event_id) ON DELETE CASCADE,
    tree_id INTEGER NOT NULL REFERENCES trees.Trees(tree_id) ON DELETE CASCADE,
    damage_level VARCHAR(50) CHECK (damage_level IN ('none', 'light', 'moderate', 'severe', 'destroyed')),
    Notes TEXT,
    PRIMARY KEY (disturbance_event_id, tree_id)
);

COMMENT ON TABLE shared.DisturbanceEvents_Trees IS 'Links disturbance events to affected individual trees with damage assessment';
COMMENT ON COLUMN shared.DisturbanceEvents_Trees.damage_level IS 'Level of damage to individual tree';

CREATE INDEX idx_dist_trees_event ON shared.DisturbanceEvents_Trees(disturbance_event_id);
CREATE INDEX idx_dist_trees_tree ON shared.DisturbanceEvents_Trees(tree_id);

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA trees TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA trees TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA trees TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA trees TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA trees TO anon, authenticated, service_role;
