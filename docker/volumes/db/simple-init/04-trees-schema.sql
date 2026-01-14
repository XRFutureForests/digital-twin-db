-- =============================================================================
-- 04: TREES SCHEMA
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Tree measurement data with multi-stem support
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS trees;
SET search_path TO trees, shared, pointclouds, public, extensions;

-- =============================================================================
-- REFERENCE TABLES
-- =============================================================================

CREATE TABLE trees.TreeStatus (
    TreeStatusID SERIAL PRIMARY KEY,
    TreeStatusName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_tree_status_name CHECK (TreeStatusName IN ('healthy', 'stressed', 'declining', 'dead', 'harvested', 'missing'))
);

INSERT INTO trees.TreeStatus (TreeStatusName, Description) VALUES
    ('healthy', 'Tree shows no signs of stress or disease'),
    ('stressed', 'Tree shows signs of environmental or biotic stress'),
    ('declining', 'Tree health is deteriorating'),
    ('dead', 'Tree is no longer alive'),
    ('harvested', 'Tree has been removed through management'),
    ('missing', 'Tree cannot be located or identified');

CREATE TABLE trees.TaperTypes (
    TaperTypeID SERIAL PRIMARY KEY,
    TaperTypeName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    TypicalTaperRatioMin NUMERIC(4, 3),
    TypicalTaperRatioMax NUMERIC(4, 3)
);

INSERT INTO trees.TaperTypes (TaperTypeName, Description, TypicalTaperRatioMin, TypicalTaperRatioMax) VALUES
    ('Cylinder', 'Minimal taper, nearly constant diameter', 0.90, 1.00),
    ('Cone', 'Linear taper from base to top', 0.50, 0.70),
    ('Paraboloid', 'Curved taper, faster at base', 0.40, 0.60),
    ('Neiloid', 'Very rapid taper at base', 0.20, 0.50);

CREATE TABLE trees.StraightnessTypes (
    StraightnessTypeID SERIAL PRIMARY KEY,
    StraightnessName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    DeviationAngleMin NUMERIC(5, 2),
    DeviationAngleMax NUMERIC(5, 2)
);

INSERT INTO trees.StraightnessTypes (StraightnessName, Description, DeviationAngleMin, DeviationAngleMax) VALUES
    ('Straight', 'Minimal deviation from vertical', 0, 5),
    ('Slight_sweep', 'Minor curvature or lean', 5, 15),
    ('Moderate_sweep', 'Noticeable curvature', 15, 30),
    ('Severe_sweep', 'Significant curvature or lean', 30, 90);

CREATE TABLE trees.BranchingPatterns (
    BranchingPatternID SERIAL PRIMARY KEY,
    BranchingPatternName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT
);

INSERT INTO trees.BranchingPatterns (BranchingPatternName, Description) VALUES
    ('Alternate', 'Branches arranged alternately along stem'),
    ('Opposite', 'Branches arranged in pairs at nodes'),
    ('Whorled', 'Multiple branches arising from same node'),
    ('Spiral', 'Branches arranged in spiral pattern'),
    ('Random', 'No clear branching pattern');

CREATE TABLE trees.BarkCharacteristics (
    BarkCharacteristicID SERIAL PRIMARY KEY,
    BarkCharacteristicName VARCHAR(100) NOT NULL UNIQUE,
    Description TEXT,
    TypicalSpecies TEXT
);

INSERT INTO trees.BarkCharacteristics (BarkCharacteristicName, Description, TypicalSpecies) VALUES
    ('Smooth', 'Smooth bark with minimal texture', 'Fagus (Beech), Betula (Birch)'),
    ('Furrowed', 'Deep vertical furrows and ridges', 'Quercus (Oak), Fraxinus (Ash)'),
    ('Plated', 'Bark separates into distinct plates', 'Pinus (Pine), Liquidambar (Sweetgum)'),
    ('Exfoliating', 'Bark peels or flakes in sheets', 'Platanus (Sycamore), Acer (Maple)'),
    ('Scaly', 'Small, scale-like bark pieces', 'Cedrus (Cedar), Sequoia (Redwood)');

-- =============================================================================
-- TREES TABLE
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
    TreeID VARCHAR(100),
    QRCode VARCHAR(500),
    Height_m NUMERIC(6, 2) CHECK (Height_m > 0 AND Height_m <= 200),
    CrownWidth_m NUMERIC(6, 2) CHECK (CrownWidth_m >= 0),
    CrownBaseHeight_m NUMERIC(6, 2) CHECK (CrownBaseHeight_m >= 0),
    CrownBoundary GEOMETRY(Polygon, 4326),
    Volume_m3 NUMERIC(10, 3) CHECK (Volume_m3 >= 0),
    Position GEOMETRY(Point, 4326) NOT NULL,
    PositionOriginal GEOMETRY,
    LeanAngle_deg NUMERIC(5, 2) CHECK (LeanAngle_deg >= 0 AND LeanAngle_deg <= 90),
    LeanDirection_azimuth INTEGER CHECK (LeanDirection_azimuth >= 0 AND LeanDirection_azimuth < 360),
    TimeDelta_yrs NUMERIC(8, 2),
    Age_years INTEGER CHECK (Age_years >= 0),
    HealthScore NUMERIC(3, 2) CHECK (HealthScore >= 0 AND HealthScore <= 1),
    Biomass_kg NUMERIC(12, 2) CHECK (Biomass_kg >= 0),
    CarbonContent_kg NUMERIC(12, 2) CHECK (CarbonContent_kg >= 0),
    FieldNotes TEXT,
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    CreatedBy VARCHAR(200),
    UpdatedBy VARCHAR(200)
);

COMMENT ON TABLE trees.Trees IS 'Tree measurement and simulation variants with spatial positions';

-- Create indexes
CREATE INDEX idx_trees_location ON trees.Trees(LocationID);
CREATE INDEX idx_trees_species ON trees.Trees(SpeciesID);
CREATE INDEX idx_trees_position ON trees.Trees USING GIST (Position);
CREATE INDEX idx_trees_tree_id ON trees.Trees(TreeID);
CREATE INDEX idx_trees_created_at ON trees.Trees(CreatedAt DESC);

-- =============================================================================
-- STEMS TABLE
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
    StemHeight_m NUMERIC(6, 2) CHECK (StemHeight_m > 0),
    StemVolume_m3 NUMERIC(10, 3) CHECK (StemVolume_m3 >= 0),
    BarkThickness_mm NUMERIC(5, 2) CHECK (BarkThickness_mm >= 0),
    WoodDensity_kg_m3 NUMERIC(6, 2) CHECK (WoodDensity_kg_m3 >= 100 AND WoodDensity_kg_m3 <= 2000),
    CreatedAt TIMESTAMPTZ DEFAULT NOW(),
    UpdatedAt TIMESTAMPTZ,
    UNIQUE (TreeVariantID, StemNumber)
);

COMMENT ON TABLE trees.Stems IS 'Individual stem measurements for multi-stem trees';

CREATE INDEX idx_stems_tree_variant ON trees.Stems(TreeVariantID);
CREATE INDEX idx_stems_dbh ON trees.Stems(DBH_cm);

-- =============================================================================
-- JUNCTION TABLES
-- =============================================================================

CREATE TABLE shared.ProcessParameters_Trees (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, VariantID)
);

CREATE TABLE shared.ProcessParameters_Stems (
    ParameterID INTEGER NOT NULL REFERENCES shared.ProcessParameters(ParameterID) ON DELETE CASCADE,
    StemID INTEGER NOT NULL REFERENCES trees.Stems(StemID) ON DELETE CASCADE,
    PRIMARY KEY (ParameterID, StemID)
);

CREATE TABLE shared.AuditLog_Trees (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    VariantID INTEGER NOT NULL REFERENCES trees.Trees(VariantID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, VariantID)
);

CREATE TABLE shared.AuditLog_Stems (
    AuditID BIGINT NOT NULL REFERENCES shared.AuditLog(AuditID) ON DELETE CASCADE,
    StemID INTEGER NOT NULL REFERENCES trees.Stems(StemID) ON DELETE CASCADE,
    PRIMARY KEY (AuditID, StemID)
);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION trees.calculate_basal_area(dbh_cm NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN PI() * POWER(dbh_cm / 200.0, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION trees.calculate_basal_area IS 'Calculates basal area in m² from DBH in cm';

-- =============================================================================
-- TRIGGERS
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

DO $$
BEGIN
    RAISE NOTICE '✅ Trees schema created';
END
$$;
