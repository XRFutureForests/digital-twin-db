-- XR Future Forests Lab - Tree Morphology Schema Extension
-- This migration adds tree morphology and structural classification tables
-- Based on tree anatomy terminology from Dr. Kim D. Coder (UGA Warnell School)

SET search_path TO trees, shared, public;

-- =============================================================================
-- PHANEROPHYTE HEIGHT CLASSES
-- Classifies tree forms based on the height of their primary main axis
-- =============================================================================

CREATE TABLE trees.PhanerophyteHeightClasses (
    phanerophyte_height_class_id SERIAL PRIMARY KEY,
    height_class_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    min_height_m NUMERIC(6, 2) CHECK (min_height_m >= 0),
    max_height_m NUMERIC(6, 2) CHECK (max_height_m > 0),
    CONSTRAINT chk_height_class_order CHECK (min_height_m IS NULL OR max_height_m IS NULL OR min_height_m < max_height_m)
);

COMMENT ON TABLE trees.PhanerophyteHeightClasses IS 'Tree height classification (mega/meso/micro-phanerophyte)';
COMMENT ON COLUMN trees.PhanerophyteHeightClasses.min_height_m IS 'Minimum height for this class (NULL = no lower bound)';
COMMENT ON COLUMN trees.PhanerophyteHeightClasses.max_height_m IS 'Maximum height for this class (NULL = no upper bound)';

CREATE INDEX idx_height_classes_name ON trees.PhanerophyteHeightClasses(height_class_name);

-- =============================================================================
-- CROWN ARCHITECTURES
-- Primary organizational form and branching habit relative to leader
-- =============================================================================

CREATE TABLE trees.CrownArchitectures (
    crown_architecture_id SERIAL PRIMARY KEY,
    crown_architecture_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    typical_examples TEXT
);

COMMENT ON TABLE trees.CrownArchitectures IS 'Crown architecture classification (excurrent, decurrent, etc.)';
COMMENT ON COLUMN trees.CrownArchitectures.typical_examples IS 'Example tree types with this architecture';

CREATE INDEX idx_crown_architectures_name ON trees.CrownArchitectures(crown_architecture_name);

-- =============================================================================
-- BRANCH ELONGATION HABITS
-- Which portion of crown experiences most branch elongation
-- =============================================================================

CREATE TABLE trees.BranchElongationHabits (
    branch_elongation_habit_id SERIAL PRIMARY KEY,
    elongation_habit_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.BranchElongationHabits IS 'Branch elongation patterns determining crown shape (acrotony, mesotony, basitony)';

CREATE INDEX idx_elongation_habits_name ON trees.BranchElongationHabits(elongation_habit_name);

-- =============================================================================
-- GROWTH ORIENTATIONS
-- Directional growth habit of woody extensions
-- =============================================================================

CREATE TABLE trees.GrowthOrientations (
    growth_orientation_id SERIAL PRIMARY KEY,
    growth_orientation_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.GrowthOrientations IS 'Shoot growth orientation (orthotropic=vertical, plagiotrophic=horizontal)';

CREATE INDEX idx_growth_orientations_name ON trees.GrowthOrientations(growth_orientation_name);

-- =============================================================================
-- SHOOT ELONGATION TYPES
-- Categorizes twigs by internode elongation
-- =============================================================================

CREATE TABLE trees.ShootElongationTypes (
    shoot_elongation_type_id SERIAL PRIMARY KEY,
    shoot_elongation_type_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.ShootElongationTypes IS 'Shoot elongation classification (long, short, spur shoots)';

CREATE INDEX idx_shoot_elongation_types_name ON trees.ShootElongationTypes(shoot_elongation_type_name);

-- =============================================================================
-- CROWN SHAPES
-- Visual appearance and internal branching habit descriptions
-- =============================================================================

CREATE TABLE trees.CrownShapes (
    crown_shape_id SERIAL PRIMARY KEY,
    crown_shape_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.CrownShapes IS 'Common crown shape descriptions (pyramidal, conical, globose, etc.)';

CREATE INDEX idx_crown_shapes_name ON trees.CrownShapes(crown_shape_name);

-- =============================================================================
-- GEOMETRIC CROWN SOLIDS
-- Crown represented as solid geometric shapes for simulation calculations
-- =============================================================================

CREATE TABLE trees.GeometricCrownSolids (
    geometric_solid_id SERIAL PRIMARY KEY,
    geometric_solid_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    relative_lateral_area NUMERIC(4, 2) CHECK (relative_lateral_area >= 0 AND relative_lateral_area <= 1),
    relative_volume NUMERIC(4, 2) CHECK (relative_volume >= 0 AND relative_volume <= 1),
    relative_drag NUMERIC(4, 2) CHECK (relative_drag >= 0 AND relative_drag <= 1)
);

COMMENT ON TABLE trees.GeometricCrownSolids IS 'Geometric crown shape models for simulation (area, volume, drag calculations)';
COMMENT ON COLUMN trees.GeometricCrownSolids.relative_lateral_area IS 'Relative frontal/lateral area (1.0 = cylinder baseline)';
COMMENT ON COLUMN trees.GeometricCrownSolids.relative_volume IS 'Relative crown volume (1.0 = cylinder baseline)';
COMMENT ON COLUMN trees.GeometricCrownSolids.relative_drag IS 'Relative wind drag coefficient (1.0 = cylinder baseline)';

CREATE INDEX idx_geometric_solids_name ON trees.GeometricCrownSolids(geometric_solid_name);

-- =============================================================================
-- AXIS STRUCTURES
-- Configuration of tree's primary vertical support system
-- =============================================================================

CREATE TABLE trees.AxisStructures (
    axis_structure_id SERIAL PRIMARY KEY,
    axis_structure_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.AxisStructures IS 'Main axis configuration (single leader vs polycormic)';

CREATE INDEX idx_axis_structures_name ON trees.AxisStructures(axis_structure_name);

-- =============================================================================
-- GROWTH FORMS
-- Broad scientific terms for overall axis and branching nature
-- =============================================================================

CREATE TABLE trees.GrowthForms (
    growth_form_id SERIAL PRIMARY KEY,
    growth_form_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT
);

COMMENT ON TABLE trees.GrowthForms IS 'General growth form classification (dendroid, arborescent, etc.)';

CREATE INDEX idx_growth_forms_name ON trees.GrowthForms(growth_form_name);

-- =============================================================================
-- ADD MORPHOLOGY COLUMNS TO TREES TABLE
-- =============================================================================

ALTER TABLE trees.Trees
    ADD COLUMN IF NOT EXISTS height_class_id INTEGER REFERENCES trees.PhanerophyteHeightClasses(phanerophyte_height_class_id),
    ADD COLUMN IF NOT EXISTS crown_architecture_id INTEGER REFERENCES trees.CrownArchitectures(crown_architecture_id),
    ADD COLUMN IF NOT EXISTS elongation_habit_id INTEGER REFERENCES trees.BranchElongationHabits(branch_elongation_habit_id),
    ADD COLUMN IF NOT EXISTS growth_orientation_id INTEGER REFERENCES trees.GrowthOrientations(growth_orientation_id),
    ADD COLUMN IF NOT EXISTS shoot_elongation_type_id INTEGER REFERENCES trees.ShootElongationTypes(shoot_elongation_type_id),
    ADD COLUMN IF NOT EXISTS crown_shape_id INTEGER REFERENCES trees.CrownShapes(crown_shape_id),
    ADD COLUMN IF NOT EXISTS geometric_solid_id INTEGER REFERENCES trees.GeometricCrownSolids(geometric_solid_id),
    ADD COLUMN IF NOT EXISTS axis_structure_id INTEGER REFERENCES trees.AxisStructures(axis_structure_id),
    ADD COLUMN IF NOT EXISTS growth_form_id INTEGER REFERENCES trees.GrowthForms(growth_form_id),
    ADD COLUMN IF NOT EXISTS live_crown_ratio NUMERIC(4, 3) GENERATED ALWAYS AS (
        CASE 
            WHEN Height_m IS NOT NULL AND Height_m > 0 AND crown_base_height_m IS NOT NULL 
            THEN (Height_m - crown_base_height_m) / Height_m 
            ELSE NULL 
        END
    ) STORED;

COMMENT ON COLUMN trees.Trees.height_class_id IS 'Phanerophyte height classification';
COMMENT ON COLUMN trees.Trees.crown_architecture_id IS 'Crown architecture type (excurrent, decurrent, etc.)';
COMMENT ON COLUMN trees.Trees.elongation_habit_id IS 'Branch elongation pattern (acrotony, mesotony, basitony)';
COMMENT ON COLUMN trees.Trees.growth_orientation_id IS 'Predominant growth orientation (orthotropic/plagiotrophic)';
COMMENT ON COLUMN trees.Trees.shoot_elongation_type_id IS 'Typical shoot elongation type';
COMMENT ON COLUMN trees.Trees.crown_shape_id IS 'Observed crown shape';
COMMENT ON COLUMN trees.Trees.geometric_solid_id IS 'Geometric model for crown volume/drag calculations';
COMMENT ON COLUMN trees.Trees.axis_structure_id IS 'Main axis structure (single leader/polycormic)';
COMMENT ON COLUMN trees.Trees.growth_form_id IS 'General growth form classification';
COMMENT ON COLUMN trees.Trees.live_crown_ratio IS 'Computed ratio of live crown height to total tree height';

-- Create indexes for the new foreign keys
CREATE INDEX IF NOT EXISTS idx_trees_height_class ON trees.Trees(height_class_id);
CREATE INDEX IF NOT EXISTS idx_trees_crown_architecture ON trees.Trees(crown_architecture_id);
CREATE INDEX IF NOT EXISTS idx_trees_elongation_habit ON trees.Trees(elongation_habit_id);
CREATE INDEX IF NOT EXISTS idx_trees_growth_orientation ON trees.Trees(growth_orientation_id);
CREATE INDEX IF NOT EXISTS idx_trees_shoot_elongation ON trees.Trees(shoot_elongation_type_id);
CREATE INDEX IF NOT EXISTS idx_trees_crown_shape ON trees.Trees(crown_shape_id);
CREATE INDEX IF NOT EXISTS idx_trees_geometric_solid ON trees.Trees(geometric_solid_id);
CREATE INDEX IF NOT EXISTS idx_trees_axis_structure ON trees.Trees(axis_structure_id);
CREATE INDEX IF NOT EXISTS idx_trees_growth_form ON trees.Trees(growth_form_id);
CREATE INDEX IF NOT EXISTS idx_trees_live_crown_ratio ON trees.Trees(live_crown_ratio);

-- =============================================================================
-- FUNCTION: Auto-assign height class based on tree height
-- =============================================================================

CREATE OR REPLACE FUNCTION trees.assign_height_class()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.Height_m IS NOT NULL AND NEW.height_class_id IS NULL THEN
        SELECT phanerophyte_height_class_id INTO NEW.height_class_id
        FROM trees.PhanerophyteHeightClasses
        WHERE (min_height_m IS NULL OR NEW.Height_m >= min_height_m)
          AND (max_height_m IS NULL OR NEW.Height_m < max_height_m)
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
