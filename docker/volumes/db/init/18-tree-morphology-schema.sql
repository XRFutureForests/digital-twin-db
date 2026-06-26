-- XR Future Forests Lab - Tree Morphology Schema Extension
-- This migration adds tree morphology and structural classification tables
-- Based on tree anatomy terminology from Dr. Kim D. Coder (UGA Warnell School)

SET search_path TO trees, shared, public;

-- =============================================================================
-- PHANEROPHYTE HEIGHT CLASSES
-- Classifies tree forms based on the height of their primary main axis
-- =============================================================================

CREATE TABLE trees.PhanerophyteHeightClasses (
    PhanerophyteHeightClassID SERIAL PRIMARY KEY,
    HeightClassName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    MinHeight_m NUMERIC(6, 2) CHECK (MinHeight_m >= 0),
    MaxHeight_m NUMERIC(6, 2) CHECK (MaxHeight_m > 0),
    CONSTRAINT chk_height_class_order CHECK (MinHeight_m IS NULL OR MaxHeight_m IS NULL OR MinHeight_m < MaxHeight_m)
);

COMMENT ON TABLE trees.PhanerophyteHeightClasses IS 'Tree height classification (mega/meso/micro-phanerophyte)';
COMMENT ON COLUMN trees.PhanerophyteHeightClasses.MinHeight_m IS 'Minimum height for this class (NULL = no lower bound)';
COMMENT ON COLUMN trees.PhanerophyteHeightClasses.MaxHeight_m IS 'Maximum height for this class (NULL = no upper bound)';

CREATE INDEX idx_height_classes_name ON trees.PhanerophyteHeightClasses(HeightClassName);

-- =============================================================================
-- CROWN ARCHITECTURES
-- Primary organizational form and branching habit relative to leader
-- =============================================================================

CREATE TABLE trees.CrownArchitectures (
    CrownArchitectureID SERIAL PRIMARY KEY,
    CrownArchitectureName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    TypicalExamples TEXT
);

COMMENT ON TABLE trees.CrownArchitectures IS 'Crown architecture classification (excurrent, decurrent, etc.)';
COMMENT ON COLUMN trees.CrownArchitectures.TypicalExamples IS 'Example tree types with this architecture';

CREATE INDEX idx_crown_architectures_name ON trees.CrownArchitectures(CrownArchitectureName);

-- =============================================================================
-- BRANCH ELONGATION HABITS
-- Which portion of crown experiences most branch elongation
-- =============================================================================

CREATE TABLE trees.BranchElongationHabits (
    BranchElongationHabitID SERIAL PRIMARY KEY,
    ElongationHabitName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.BranchElongationHabits IS 'Branch elongation patterns determining crown shape (acrotony, mesotony, basitony)';

CREATE INDEX idx_elongation_habits_name ON trees.BranchElongationHabits(ElongationHabitName);

-- =============================================================================
-- GROWTH ORIENTATIONS
-- Directional growth habit of woody extensions
-- =============================================================================

CREATE TABLE trees.GrowthOrientations (
    GrowthOrientationID SERIAL PRIMARY KEY,
    GrowthOrientationName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.GrowthOrientations IS 'Shoot growth orientation (orthotropic=vertical, plagiotrophic=horizontal)';

CREATE INDEX idx_growth_orientations_name ON trees.GrowthOrientations(GrowthOrientationName);

-- =============================================================================
-- SHOOT ELONGATION TYPES
-- Categorizes twigs by internode elongation
-- =============================================================================

CREATE TABLE trees.ShootElongationTypes (
    ShootElongationTypeID SERIAL PRIMARY KEY,
    ShootElongationTypeName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.ShootElongationTypes IS 'Shoot elongation classification (long, short, spur shoots)';

CREATE INDEX idx_shoot_elongation_types_name ON trees.ShootElongationTypes(ShootElongationTypeName);

-- =============================================================================
-- CROWN SHAPES
-- Visual appearance and internal branching habit descriptions
-- =============================================================================

CREATE TABLE trees.CrownShapes (
    CrownShapeID SERIAL PRIMARY KEY,
    CrownShapeName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.CrownShapes IS 'Common crown shape descriptions (pyramidal, conical, globose, etc.)';

CREATE INDEX idx_crown_shapes_name ON trees.CrownShapes(CrownShapeName);

-- =============================================================================
-- GEOMETRIC CROWN SOLIDS
-- Crown represented as solid geometric shapes for simulation calculations
-- =============================================================================

CREATE TABLE trees.GeometricCrownSolids (
    GeometricSolidID SERIAL PRIMARY KEY,
    GeometricSolidName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    RelativeLateralArea NUMERIC(4, 2) CHECK (RelativeLateralArea >= 0 AND RelativeLateralArea <= 1),
    RelativeVolume NUMERIC(4, 2) CHECK (RelativeVolume >= 0 AND RelativeVolume <= 1),
    RelativeDrag NUMERIC(4, 2) CHECK (RelativeDrag >= 0 AND RelativeDrag <= 1)
);

COMMENT ON TABLE trees.GeometricCrownSolids IS 'Geometric crown shape models for simulation (area, volume, drag calculations)';
COMMENT ON COLUMN trees.GeometricCrownSolids.RelativeLateralArea IS 'Relative frontal/lateral area (1.0 = cylinder baseline)';
COMMENT ON COLUMN trees.GeometricCrownSolids.RelativeVolume IS 'Relative crown volume (1.0 = cylinder baseline)';
COMMENT ON COLUMN trees.GeometricCrownSolids.RelativeDrag IS 'Relative wind drag coefficient (1.0 = cylinder baseline)';

CREATE INDEX idx_geometric_solids_name ON trees.GeometricCrownSolids(GeometricSolidName);

-- =============================================================================
-- AXIS STRUCTURES
-- Configuration of tree's primary vertical support system
-- =============================================================================

CREATE TABLE trees.AxisStructures (
    AxisStructureID SERIAL PRIMARY KEY,
    AxisStructureName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.AxisStructures IS 'Main axis configuration (single leader vs polycormic)';

CREATE INDEX idx_axis_structures_name ON trees.AxisStructures(AxisStructureName);

-- =============================================================================
-- GROWTH FORMS
-- Broad scientific terms for overall axis and branching nature
-- =============================================================================

CREATE TABLE trees.GrowthForms (
    GrowthFormID SERIAL PRIMARY KEY,
    GrowthFormName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.GrowthForms IS 'General growth form classification (dendroid, arborescent, etc.)';

CREATE INDEX idx_growth_forms_name ON trees.GrowthForms(GrowthFormName);

-- =============================================================================
-- ADD MORPHOLOGY COLUMNS TO TREES TABLE
-- =============================================================================

ALTER TABLE trees.Trees
    ADD COLUMN IF NOT EXISTS HeightClassID INTEGER REFERENCES trees.PhanerophyteHeightClasses(PhanerophyteHeightClassID),
    ADD COLUMN IF NOT EXISTS CrownArchitectureID INTEGER REFERENCES trees.CrownArchitectures(CrownArchitectureID),
    ADD COLUMN IF NOT EXISTS ElongationHabitID INTEGER REFERENCES trees.BranchElongationHabits(BranchElongationHabitID),
    ADD COLUMN IF NOT EXISTS GrowthOrientationID INTEGER REFERENCES trees.GrowthOrientations(GrowthOrientationID),
    ADD COLUMN IF NOT EXISTS ShootElongationTypeID INTEGER REFERENCES trees.ShootElongationTypes(ShootElongationTypeID),
    ADD COLUMN IF NOT EXISTS CrownShapeID INTEGER REFERENCES trees.CrownShapes(CrownShapeID),
    ADD COLUMN IF NOT EXISTS GeometricSolidID INTEGER REFERENCES trees.GeometricCrownSolids(GeometricSolidID),
    ADD COLUMN IF NOT EXISTS AxisStructureID INTEGER REFERENCES trees.AxisStructures(AxisStructureID),
    ADD COLUMN IF NOT EXISTS GrowthFormID INTEGER REFERENCES trees.GrowthForms(GrowthFormID),
    ADD COLUMN IF NOT EXISTS LiveCrownRatio NUMERIC(4, 3) GENERATED ALWAYS AS (
        CASE 
            WHEN Height_m IS NOT NULL AND Height_m > 0 AND CrownBaseHeight_m IS NOT NULL 
            THEN (Height_m - CrownBaseHeight_m) / Height_m 
            ELSE NULL 
        END
    ) STORED;

COMMENT ON COLUMN trees.Trees.HeightClassID IS 'Phanerophyte height classification';
COMMENT ON COLUMN trees.Trees.CrownArchitectureID IS 'Crown architecture type (excurrent, decurrent, etc.)';
COMMENT ON COLUMN trees.Trees.ElongationHabitID IS 'Branch elongation pattern (acrotony, mesotony, basitony)';
COMMENT ON COLUMN trees.Trees.GrowthOrientationID IS 'Predominant growth orientation (orthotropic/plagiotrophic)';
COMMENT ON COLUMN trees.Trees.ShootElongationTypeID IS 'Typical shoot elongation type';
COMMENT ON COLUMN trees.Trees.CrownShapeID IS 'Observed crown shape';
COMMENT ON COLUMN trees.Trees.GeometricSolidID IS 'Geometric model for crown volume/drag calculations';
COMMENT ON COLUMN trees.Trees.AxisStructureID IS 'Main axis structure (single leader/polycormic)';
COMMENT ON COLUMN trees.Trees.GrowthFormID IS 'General growth form classification';
COMMENT ON COLUMN trees.Trees.LiveCrownRatio IS 'Computed ratio of live crown height to total tree height';

-- Create indexes for the new foreign keys
CREATE INDEX IF NOT EXISTS idx_trees_height_class ON trees.Trees(HeightClassID);
CREATE INDEX IF NOT EXISTS idx_trees_crown_architecture ON trees.Trees(CrownArchitectureID);
CREATE INDEX IF NOT EXISTS idx_trees_elongation_habit ON trees.Trees(ElongationHabitID);
CREATE INDEX IF NOT EXISTS idx_trees_growth_orientation ON trees.Trees(GrowthOrientationID);
CREATE INDEX IF NOT EXISTS idx_trees_shoot_elongation ON trees.Trees(ShootElongationTypeID);
CREATE INDEX IF NOT EXISTS idx_trees_crown_shape ON trees.Trees(CrownShapeID);
CREATE INDEX IF NOT EXISTS idx_trees_geometric_solid ON trees.Trees(GeometricSolidID);
CREATE INDEX IF NOT EXISTS idx_trees_axis_structure ON trees.Trees(AxisStructureID);
CREATE INDEX IF NOT EXISTS idx_trees_growth_form ON trees.Trees(GrowthFormID);
CREATE INDEX IF NOT EXISTS idx_trees_live_crown_ratio ON trees.Trees(LiveCrownRatio);

-- =============================================================================
-- FUNCTION: Auto-assign height class based on tree height
-- =============================================================================

CREATE OR REPLACE FUNCTION trees.assign_height_class()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Height_m IS NOT NULL AND NEW.HeightClassID IS NULL THEN
        SELECT PhanerophyteHeightClassID INTO NEW.HeightClassID
        FROM trees.PhanerophyteHeightClasses
        WHERE (MinHeight_m IS NULL OR NEW.Height_m >= MinHeight_m)
          AND (MaxHeight_m IS NULL OR NEW.Height_m < MaxHeight_m)
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_trees_assign_height_class
    BEFORE INSERT OR UPDATE OF Height_m ON trees.Trees
    FOR EACH ROW
    EXECUTE FUNCTION trees.assign_height_class();

COMMENT ON FUNCTION trees.assign_height_class() IS 'Auto-assigns phanerophyte height class based on tree height';
