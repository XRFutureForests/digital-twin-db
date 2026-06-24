-- XR Future Forests Lab - Tree Condition & Competitive Status Schema Extension
-- Adds the per-tree variables identified as standard across published forest
-- inventory designs (USDA FIA, NEON Woody Vegetation Structure, ICP Forests
-- crown condition monitoring) but missing from the original schema:
--   - Crown social/competitive position (FIA CCLCD, NEON canopyPosition)
--   - Individual damage/mortality agent (FIA AGENTCD)
--   - Defoliation / discolouration / crown transparency as independently
--     tracked percentages (ICP Forests Level I/II), rather than collapsing
--     condition into a single HealthScore
--   - Richer TreeStatus granularity (NEON plantStatus: downed, broken)

SET search_path TO trees, shared, pointclouds, public;

-- =============================================================================
-- CROWN CLASSES (competitive/social position)
-- =============================================================================

CREATE TABLE trees.CrownClasses (
    CrownClassID SERIAL PRIMARY KEY,
    CrownClassName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_crown_class_name CHECK (CrownClassName IN (
        'dominant', 'co_dominant', 'intermediate', 'overtopped', 'open_grown'
    ))
);

COMMENT ON TABLE trees.CrownClasses IS 'Crown social/competitive position classification (FIA CCLCD / NEON canopyPosition analog)';

CREATE INDEX idx_crown_classes_name ON trees.CrownClasses(CrownClassName);

-- NOTE: CrownClasses data is loaded from data/lookups/crown_classes.csv

-- =============================================================================
-- DAMAGE AGENTS (cause of decline/mortality)
-- =============================================================================

CREATE TABLE trees.DamageAgents (
    DamageAgentID SERIAL PRIMARY KEY,
    DamageAgentName VARCHAR(50) NOT NULL UNIQUE,
    Description TEXT,
    CONSTRAINT chk_damage_agent_name CHECK (DamageAgentName IN (
        'none', 'insect', 'disease', 'fire', 'wind', 'snow_ice', 'drought',
        'mechanical', 'animal', 'human_activity', 'competition', 'unknown'
    ))
);

COMMENT ON TABLE trees.DamageAgents IS 'Cause of tree damage, decline, or mortality (FIA AGENTCD analog)';

CREATE INDEX idx_damage_agents_name ON trees.DamageAgents(DamageAgentName);

-- NOTE: DamageAgents data is loaded from data/lookups/damage_agents.csv

-- =============================================================================
-- TREESTATUS: ADD NEON-STYLE STRUCTURAL STATUSES (downed, broken)
-- =============================================================================
-- The original CHECK constraint only allowed healthy/stressed/declining/dead/
-- harvested/missing. NEON's plantStatus distinguishes standing dead from
-- downed and broken trees, which matters for deadwood/safety/visual state.

ALTER TABLE trees.TreeStatus DROP CONSTRAINT IF EXISTS chk_tree_status_name;
ALTER TABLE trees.TreeStatus ADD CONSTRAINT chk_tree_status_name CHECK (TreeStatusName IN (
    'healthy', 'stressed', 'declining', 'dead', 'harvested', 'missing', 'downed', 'broken'
));

-- NOTE: New rows are loaded from the updated data/lookups/tree_status.csv

-- =============================================================================
-- ADD CONDITION COLUMNS TO TREES TABLE
-- =============================================================================

ALTER TABLE trees.Trees
    ADD COLUMN IF NOT EXISTS CrownClassID INTEGER REFERENCES trees.CrownClasses(CrownClassID),
    ADD COLUMN IF NOT EXISTS DamageAgentID INTEGER REFERENCES trees.DamageAgents(DamageAgentID),
    ADD COLUMN IF NOT EXISTS Defoliation_percent NUMERIC(5, 2) CHECK (Defoliation_percent >= 0 AND Defoliation_percent <= 100),
    ADD COLUMN IF NOT EXISTS Discolouration_percent NUMERIC(5, 2) CHECK (Discolouration_percent >= 0 AND Discolouration_percent <= 100),
    ADD COLUMN IF NOT EXISTS CrownTransparency_percent NUMERIC(5, 2) CHECK (CrownTransparency_percent >= 0 AND CrownTransparency_percent <= 100);

COMMENT ON COLUMN trees.Trees.CrownClassID IS 'Crown competitive/social position (dominant/co_dominant/intermediate/overtopped/open_grown)';
COMMENT ON COLUMN trees.Trees.DamageAgentID IS 'Primary agent responsible for observed damage or decline, if any';
COMMENT ON COLUMN trees.Trees.Defoliation_percent IS 'ICP Forests-style defoliation assessment (0-100%, in 5% steps by convention)';
COMMENT ON COLUMN trees.Trees.Discolouration_percent IS 'ICP Forests-style foliage discolouration assessment (0-100%)';
COMMENT ON COLUMN trees.Trees.CrownTransparency_percent IS 'ICP Forests-style crown transparency assessment (0-100%)';

CREATE INDEX IF NOT EXISTS idx_trees_crown_class ON trees.Trees(CrownClassID);
CREATE INDEX IF NOT EXISTS idx_trees_damage_agent ON trees.Trees(DamageAgentID);
