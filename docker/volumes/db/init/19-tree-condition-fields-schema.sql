-- XR Future Forests Lab - Tree Condition & Competitive Status Schema Extension
-- Adds the per-tree variables identified as standard across published forest
-- inventory designs (USDA FIA, NEON Woody Vegetation Structure, ICP Forests
-- crown condition monitoring) but missing from the original schema:
--   - Crown social/competitive position (FIA CCLCD, NEON canopyPosition)
--   - Individual damage/mortality agent (FIA AGENTCD)
--   - Defoliation / discolouration / crown transparency as independently
--     tracked percentages (ICP Forests Level I/II), rather than collapsing
--     condition into a single health_score
--   - Richer TreeStatus granularity (NEON plantStatus: downed, broken)

SET search_path TO trees, shared, pointclouds, public;

-- =============================================================================
-- CROWN CLASSES (competitive/social position)
-- =============================================================================

CREATE TABLE trees.CrownClasses (
    crown_class_id SERIAL PRIMARY KEY,
    crown_class_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_crown_class_name CHECK (crown_class_name IN (
        'dominant', 'co_dominant', 'intermediate', 'overtopped', 'open_grown'
    ))
);

COMMENT ON TABLE trees.CrownClasses IS 'Crown social/competitive position classification (FIA CCLCD / NEON canopyPosition analog)';

CREATE INDEX idx_crown_classes_name ON trees.CrownClasses(crown_class_name);

-- NOTE: CrownClasses data is loaded from data/lookups/crown_classes.csv

-- =============================================================================
-- DAMAGE AGENTS (cause of decline/mortality)
-- =============================================================================

CREATE TABLE trees.DamageAgents (
    damage_agent_id SERIAL PRIMARY KEY,
    damage_agent_name VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_damage_agent_name CHECK (damage_agent_name IN (
        'none', 'insect', 'disease', 'fire', 'wind', 'snow_ice', 'drought',
        'mechanical', 'animal', 'human_activity', 'competition', 'unknown'
    ))
);

COMMENT ON TABLE trees.DamageAgents IS 'Cause of tree damage, decline, or mortality (FIA AGENTCD analog)';

CREATE INDEX idx_damage_agents_name ON trees.DamageAgents(damage_agent_name);

-- NOTE: DamageAgents data is loaded from data/lookups/damage_agents.csv

-- =============================================================================
-- TREESTATUS: ADD NEON-STYLE STRUCTURAL STATUSES (downed, broken)
-- =============================================================================
-- The original CHECK constraint only allowed healthy/stressed/declining/dead/
-- harvested/missing. NEON's plantStatus distinguishes standing dead from
-- downed and broken trees, which matters for deadwood/safety/visual state.

ALTER TABLE trees.TreeStatus DROP CONSTRAINT IF EXISTS chk_tree_status_name;
ALTER TABLE trees.TreeStatus ADD CONSTRAINT chk_tree_status_name CHECK (tree_status_name IN (
    'healthy', 'stressed', 'declining', 'dead', 'harvested', 'missing', 'downed', 'broken'
));

-- NOTE: New rows are loaded from the updated data/lookups/tree_status.csv

-- =============================================================================
-- ADD CONDITION COLUMNS TO TREES TABLE
-- =============================================================================

ALTER TABLE trees.Trees
    ADD COLUMN IF NOT EXISTS crown_class_id INTEGER REFERENCES trees.CrownClasses(crown_class_id),
    ADD COLUMN IF NOT EXISTS damage_agent_id INTEGER REFERENCES trees.DamageAgents(damage_agent_id),
    ADD COLUMN IF NOT EXISTS Defoliation_percent NUMERIC(5, 2) CHECK (Defoliation_percent >= 0 AND Defoliation_percent <= 100),
    ADD COLUMN IF NOT EXISTS Discolouration_percent NUMERIC(5, 2) CHECK (Discolouration_percent >= 0 AND Discolouration_percent <= 100),
    ADD COLUMN IF NOT EXISTS crown_transparency_percent NUMERIC(5, 2) CHECK (crown_transparency_percent >= 0 AND crown_transparency_percent <= 100);

COMMENT ON COLUMN trees.Trees.crown_class_id IS 'Crown competitive/social position (dominant/co_dominant/intermediate/overtopped/open_grown)';
COMMENT ON COLUMN trees.Trees.damage_agent_id IS 'Primary agent responsible for observed damage or decline, if any';
COMMENT ON COLUMN trees.Trees.Defoliation_percent IS 'ICP Forests-style defoliation assessment (0-100%, in 5% steps by convention)';
COMMENT ON COLUMN trees.Trees.Discolouration_percent IS 'ICP Forests-style foliage discolouration assessment (0-100%)';
COMMENT ON COLUMN trees.Trees.crown_transparency_percent IS 'ICP Forests-style crown transparency assessment (0-100%)';

CREATE INDEX IF NOT EXISTS idx_trees_crown_class ON trees.Trees(crown_class_id);
CREATE INDEX IF NOT EXISTS idx_trees_damage_agent ON trees.Trees(damage_agent_id);
