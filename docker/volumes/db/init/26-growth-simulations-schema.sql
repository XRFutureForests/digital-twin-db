-- XR Future Forests Lab — Growth Simulations Schema
-- XRFF-243: per-tree projections from forest growth simulators (SILVA, FVS, iLand, etc.)
-- Dependencies: 13-trees-schema.sql, 24-public-api-views.sql, 25-forest-state-views.sql

SET search_path TO trees, shared, public;

-- =============================================================================
-- GROWTH SIMULATIONS TABLE
-- =============================================================================
-- Stores per-tree dimensional projections at discrete time steps produced by
-- external forest growth simulators (SILVA, FVS, iLand, or manual estimation).
--
-- One row = one tree entity at one projected year under one simulation run.
-- Rows from the same run share a run_id UUID.
-- tree_entity_id links to the stable physical-tree identity in trees.Trees.
-- base_tree_id points to the trees.Trees row used as the simulation starting point.
--
-- Stand-level aggregates (BasalArea per ha, etc.) are repeated across all rows
-- in the same (run_id, projection_year) group — they are stored here for convenience
-- so UE can obtain them in a single query without a separate aggregation step.

CREATE TABLE trees.GrowthSimulations (
    growth_simulation_id   BIGSERIAL PRIMARY KEY,
    run_id                UUID NOT NULL DEFAULT gen_random_uuid(),
    tree_entity_id         UUID NOT NULL,
    base_tree_id           INTEGER REFERENCES trees.Trees(tree_id) ON DELETE SET NULL,
    location_id           INTEGER REFERENCES shared.Locations(location_id) ON DELETE CASCADE,
    plot_id               INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL,
    scenario_id           INTEGER REFERENCES shared.Scenarios(scenario_id) ON DELETE SET NULL,
    species_id            INTEGER REFERENCES shared.Species(species_id) ON DELETE SET NULL,

    -- Simulator identity
    simulator_name        VARCHAR(100) NOT NULL
                             CHECK (simulator_name IN ('SILVA', 'FVS', 'iLand', 'manual', 'other')),
    simulator_version     VARCHAR(50),

    -- Projection time
    projection_year       INTEGER NOT NULL
                             CHECK (projection_year >= 1900 AND projection_year <= 2300),
    time_delta_yrs        NUMERIC(8, 2),    -- years since the base variant measurement date

    -- Per-tree dimensional projections
    Height_m             NUMERIC(6, 2)  CHECK (Height_m IS NULL OR Height_m > 0),
    DBH_cm               NUMERIC(6, 2)  CHECK (DBH_cm IS NULL OR DBH_cm > 0),
    basal_area_m2         NUMERIC(8, 4)  CHECK (basal_area_m2 IS NULL OR basal_area_m2 >= 0),
    crown_width_m         NUMERIC(6, 2)  CHECK (crown_width_m IS NULL OR crown_width_m >= 0),
    crown_base_height_m    NUMERIC(6, 2)  CHECK (crown_base_height_m IS NULL OR crown_base_height_m >= 0),
    Volume_m3            NUMERIC(10, 3) CHECK (Volume_m3 IS NULL OR Volume_m3 >= 0),
    Biomass_kg           NUMERIC(12, 2) CHECK (Biomass_kg IS NULL OR Biomass_kg >= 0),
    carbon_content_kg     NUMERIC(12, 2) CHECK (carbon_content_kg IS NULL OR carbon_content_kg >= 0),
    health_score          NUMERIC(3, 2)  CHECK (health_score IS NULL OR (health_score >= 0 AND health_score <= 1)),

    -- Mortality flag: true = this tree dies during this projection step
    Mortality            BOOLEAN NOT NULL DEFAULT false,

    -- Stand-level aggregates (per ha, same value for all trees in a run_id+Year group)
    -- Populated when the simulator provides stand-level output alongside individual trees
    stand_basal_area_m2ha  NUMERIC(8, 4)  CHECK (stand_basal_area_m2ha IS NULL OR stand_basal_area_m2ha >= 0),
    stand_volume_m3ha     NUMERIC(10, 3) CHECK (stand_volume_m3ha IS NULL OR stand_volume_m3ha >= 0),
    stand_biomass_tha     NUMERIC(10, 3) CHECK (stand_biomass_tha IS NULL OR stand_biomass_tha >= 0),
    stand_stem_count_ha    INTEGER        CHECK (stand_stem_count_ha IS NULL OR stand_stem_count_ha >= 0),

    -- Audit
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by            VARCHAR(200),

    CONSTRAINT chk_crown_base_le_height
        CHECK (crown_base_height_m IS NULL OR Height_m IS NULL OR crown_base_height_m <= Height_m)
);

COMMENT ON TABLE trees.GrowthSimulations IS
    'Per-tree forest growth projections from SILVA, FVS, iLand, or manual estimation. '
    'One row per (run_id, tree_entity_id, projection_year). '
    'run_id groups all rows produced by a single simulation run.';

COMMENT ON COLUMN trees.GrowthSimulations.run_id IS
    'UUID identifying a single simulation run. All rows with the same run_id belong '
    'to one simulator execution and can be compared as a complete forest state.';
COMMENT ON COLUMN trees.GrowthSimulations.tree_entity_id IS
    'Stable UUID of the physical tree (cross-variant identity from trees.Trees.tree_entity_id).';
COMMENT ON COLUMN trees.GrowthSimulations.base_tree_id IS
    'trees.Trees row (tree_id) used as the simulation input (baseline measurement).';
COMMENT ON COLUMN trees.GrowthSimulations.projection_year IS
    'Calendar year this projection describes.';
COMMENT ON COLUMN trees.GrowthSimulations.Mortality IS
    'True if this tree dies in this projection time step.';
COMMENT ON COLUMN trees.GrowthSimulations.stand_basal_area_m2ha IS
    'Stand-level basal area (m²/ha) — same value repeated for all trees in this run_id+Year.';

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Primary query pattern: get all trees in a run at a given year
CREATE INDEX idx_growthsim_run_year
    ON trees.GrowthSimulations (run_id, projection_year);

-- Per-tree time series
CREATE INDEX idx_growthsim_entity_run
    ON trees.GrowthSimulations (tree_entity_id, run_id);

-- Scenario + year (UE "show forest in year X for scenario Y")
CREATE INDEX idx_growthsim_scenario_year
    ON trees.GrowthSimulations (scenario_id, projection_year);

-- Location-scoped queries
CREATE INDEX idx_growthsim_location_year
    ON trees.GrowthSimulations (location_id, projection_year);

-- Simulator-specific lookups
CREATE INDEX idx_growthsim_simulator
    ON trees.GrowthSimulations (simulator_name, scenario_id);

-- =============================================================================
-- PUBLIC API VIEWS
-- =============================================================================

-- growth_simulations: flat view with scenario name and species name resolved
-- Primary UE query target for the Time Machine feature
CREATE OR REPLACE VIEW public.growth_simulations AS
SELECT
    gs.growth_simulation_id,
    gs.run_id,
    gs.tree_entity_id,
    gs.base_tree_id,
    gs.location_id,
    gs.plot_id,
    gs.scenario_id,
    s.scenario_name       AS scenario_name,
    sp.common_name        AS species_name,
    sp.scientific_name    AS scientific_name,
    gs.simulator_name     AS simulator_name,
    gs.simulator_version  AS simulator_version,
    gs.projection_year    AS projection_year,
    gs.time_delta_yrs     AS time_delta_yrs,
    gs.Height_m          AS height_m,
    gs.DBH_cm            AS dbh_cm,
    gs.basal_area_m2      AS basal_area_m2,
    gs.crown_width_m      AS crown_width_m,
    gs.crown_base_height_m AS crown_base_height_m,
    gs.Volume_m3         AS volume_m3,
    gs.Biomass_kg        AS biomass_kg,
    gs.carbon_content_kg  AS carbon_content_kg,
    gs.health_score       AS health_score,
    gs.Mortality         AS mortality,
    gs.stand_basal_area_m2ha  AS stand_basal_area_m2ha,
    gs.stand_volume_m3ha     AS stand_volume_m3ha,
    gs.stand_biomass_tha     AS standbio_tha,
    gs.stand_stem_count_ha    AS stand_stem_count_ha,
    gs.created_at,
    gs.created_by
FROM trees.GrowthSimulations gs
LEFT JOIN shared.Scenarios s  ON gs.scenario_id = s.scenario_id
LEFT JOIN shared.Species   sp ON gs.species_id  = sp.species_id;

COMMENT ON VIEW public.growth_simulations IS
    'Flat view of growth simulation projections with scenario and species names resolved. '
    'Filter by scenario_name + projection_year to get a full forest state for UE Time Machine.';

-- simulation_runs: one row per unique simulation run — useful for populating a run selector
CREATE OR REPLACE VIEW public.simulation_runs AS
SELECT
    gs.run_id                            AS run_id,
    gs.simulator_name                    AS simulator_name,
    gs.simulator_version                 AS simulator_version,
    s.scenario_name                      AS scenario_name,
    l.location_name                      AS location_name,
    MIN(gs.projection_year)              AS first_year,
    MAX(gs.projection_year)              AS last_year,
    COUNT(DISTINCT gs.projection_year)   AS year_steps,
    COUNT(DISTINCT gs.tree_entity_id)     AS tree_count,
    MAX(gs.created_at)                   AS created_at,
    MAX(gs.created_by)                   AS created_by
FROM trees.GrowthSimulations gs
LEFT JOIN shared.Scenarios s  ON gs.scenario_id  = s.scenario_id
LEFT JOIN shared.Locations l  ON gs.location_id  = l.location_id
GROUP BY gs.run_id, gs.simulator_name, gs.simulator_version, s.scenario_name, l.location_name;

COMMENT ON VIEW public.simulation_runs IS
    'Summary of each simulation run: simulator, scenario, year range, tree count. '
    'Use to populate a run selector UI before querying growth_simulations.';

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON public.growth_simulations  TO anon, authenticated;
GRANT SELECT ON public.simulation_runs     TO anon, authenticated;
GRANT ALL    ON public.growth_simulations  TO service_role;
GRANT ALL    ON public.simulation_runs     TO service_role;

-- authenticated role can write simulation output (SILVA write-back via XRFF-245)
GRANT INSERT, UPDATE ON trees.GrowthSimulations TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE trees.growthsimulations_growth_simulation_id_seq TO authenticated;
