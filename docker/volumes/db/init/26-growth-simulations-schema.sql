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
-- Rows from the same run share a RunID UUID.
-- TreeEntityID links to the stable physical-tree identity in trees.Trees.
-- BaseVariantID points to the trees.Trees row used as the simulation starting point.
--
-- Stand-level aggregates (BasalArea per ha, etc.) are repeated across all rows
-- in the same (RunID, ProjectionYear) group — they are stored here for convenience
-- so UE can obtain them in a single query without a separate aggregation step.

CREATE TABLE trees.GrowthSimulations (
    SimulationID         BIGSERIAL PRIMARY KEY,
    RunID                UUID NOT NULL DEFAULT gen_random_uuid(),
    TreeEntityID         UUID NOT NULL,
    BaseVariantID        INTEGER REFERENCES trees.Trees(VariantID) ON DELETE SET NULL,
    LocationID           INTEGER REFERENCES shared.Locations(LocationID) ON DELETE CASCADE,
    PlotID               INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL,
    ScenarioID           INTEGER REFERENCES shared.Scenarios(ScenarioID) ON DELETE SET NULL,
    SpeciesID            INTEGER REFERENCES shared.Species(SpeciesID) ON DELETE SET NULL,

    -- Simulator identity
    SimulatorName        VARCHAR(100) NOT NULL
                             CHECK (SimulatorName IN ('SILVA', 'FVS', 'iLand', 'manual', 'other')),
    SimulatorVersion     VARCHAR(50),

    -- Projection time
    ProjectionYear       INTEGER NOT NULL
                             CHECK (ProjectionYear >= 1900 AND ProjectionYear <= 2300),
    TimeDelta_yrs        NUMERIC(8, 2),    -- years since the base variant measurement date

    -- Per-tree dimensional projections
    Height_m             NUMERIC(6, 2)  CHECK (Height_m IS NULL OR Height_m > 0),
    DBH_cm               NUMERIC(6, 2)  CHECK (DBH_cm IS NULL OR DBH_cm > 0),
    BasalArea_m2         NUMERIC(8, 4)  CHECK (BasalArea_m2 IS NULL OR BasalArea_m2 >= 0),
    CrownWidth_m         NUMERIC(6, 2)  CHECK (CrownWidth_m IS NULL OR CrownWidth_m >= 0),
    CrownBaseHeight_m    NUMERIC(6, 2)  CHECK (CrownBaseHeight_m IS NULL OR CrownBaseHeight_m >= 0),
    Volume_m3            NUMERIC(10, 3) CHECK (Volume_m3 IS NULL OR Volume_m3 >= 0),
    Biomass_kg           NUMERIC(12, 2) CHECK (Biomass_kg IS NULL OR Biomass_kg >= 0),
    CarbonContent_kg     NUMERIC(12, 2) CHECK (CarbonContent_kg IS NULL OR CarbonContent_kg >= 0),
    HealthScore          NUMERIC(3, 2)  CHECK (HealthScore IS NULL OR (HealthScore >= 0 AND HealthScore <= 1)),

    -- Mortality flag: true = this tree dies during this projection step
    Mortality            BOOLEAN NOT NULL DEFAULT false,

    -- Stand-level aggregates (per ha, same value for all trees in a RunID+Year group)
    -- Populated when the simulator provides stand-level output alongside individual trees
    StandBasalArea_m2ha  NUMERIC(8, 4)  CHECK (StandBasalArea_m2ha IS NULL OR StandBasalArea_m2ha >= 0),
    StandVolume_m3ha     NUMERIC(10, 3) CHECK (StandVolume_m3ha IS NULL OR StandVolume_m3ha >= 0),
    StandBiomass_tha     NUMERIC(10, 3) CHECK (StandBiomass_tha IS NULL OR StandBiomass_tha >= 0),
    StandStemCount_ha    INTEGER        CHECK (StandStemCount_ha IS NULL OR StandStemCount_ha >= 0),

    -- Audit
    CreatedAt            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CreatedBy            VARCHAR(200),

    CONSTRAINT chk_crown_base_le_height
        CHECK (CrownBaseHeight_m IS NULL OR Height_m IS NULL OR CrownBaseHeight_m <= Height_m)
);

COMMENT ON TABLE trees.GrowthSimulations IS
    'Per-tree forest growth projections from SILVA, FVS, iLand, or manual estimation. '
    'One row per (RunID, TreeEntityID, ProjectionYear). '
    'RunID groups all rows produced by a single simulation run.';

COMMENT ON COLUMN trees.GrowthSimulations.RunID IS
    'UUID identifying a single simulation run. All rows with the same RunID belong '
    'to one simulator execution and can be compared as a complete forest state.';
COMMENT ON COLUMN trees.GrowthSimulations.TreeEntityID IS
    'Stable UUID of the physical tree (cross-variant identity from trees.Trees.TreeEntityID).';
COMMENT ON COLUMN trees.GrowthSimulations.BaseVariantID IS
    'trees.Trees row used as the simulation input (baseline measurement).';
COMMENT ON COLUMN trees.GrowthSimulations.ProjectionYear IS
    'Calendar year this projection describes.';
COMMENT ON COLUMN trees.GrowthSimulations.Mortality IS
    'True if this tree dies in this projection time step.';
COMMENT ON COLUMN trees.GrowthSimulations.StandBasalArea_m2ha IS
    'Stand-level basal area (m²/ha) — same value repeated for all trees in this RunID+Year.';

-- =============================================================================
-- INDEXES
-- =============================================================================

-- Primary query pattern: get all trees in a run at a given year
CREATE INDEX idx_growthsim_run_year
    ON trees.GrowthSimulations (RunID, ProjectionYear);

-- Per-tree time series
CREATE INDEX idx_growthsim_entity_run
    ON trees.GrowthSimulations (TreeEntityID, RunID);

-- Scenario + year (UE "show forest in year X for scenario Y")
CREATE INDEX idx_growthsim_scenario_year
    ON trees.GrowthSimulations (ScenarioID, ProjectionYear);

-- Location-scoped queries
CREATE INDEX idx_growthsim_location_year
    ON trees.GrowthSimulations (LocationID, ProjectionYear);

-- Simulator-specific lookups
CREATE INDEX idx_growthsim_simulator
    ON trees.GrowthSimulations (SimulatorName, ScenarioID);

-- =============================================================================
-- PUBLIC API VIEWS
-- =============================================================================

-- growth_simulations: flat view with scenario name and species name resolved
-- Primary UE query target for the Time Machine feature
CREATE OR REPLACE VIEW public.growth_simulations AS
SELECT
    gs.SimulationID,
    gs.RunID,
    gs.TreeEntityID,
    gs.BaseVariantID,
    gs.LocationID,
    gs.PlotID,
    gs.ScenarioID,
    s.ScenarioName       AS scenarioname,
    sp.CommonName        AS speciesname,
    sp.ScientificName    AS scientificname,
    gs.SimulatorName     AS simulatorname,
    gs.SimulatorVersion  AS simulatorversion,
    gs.ProjectionYear    AS projectionyear,
    gs.TimeDelta_yrs     AS timedelta_yrs,
    gs.Height_m          AS height_m,
    gs.DBH_cm            AS dbh_cm,
    gs.BasalArea_m2      AS basalarea_m2,
    gs.CrownWidth_m      AS crownwidth_m,
    gs.CrownBaseHeight_m AS crownbaseheight_m,
    gs.Volume_m3         AS volume_m3,
    gs.Biomass_kg        AS biomass_kg,
    gs.CarbonContent_kg  AS carboncontent_kg,
    gs.HealthScore       AS healthscore,
    gs.Mortality         AS mortality,
    gs.StandBasalArea_m2ha  AS standbasalarea_m2ha,
    gs.StandVolume_m3ha     AS standvolume_m3ha,
    gs.StandBiomass_tha     AS standbio_tha,
    gs.StandStemCount_ha    AS standstemcount_ha,
    gs.CreatedAt,
    gs.CreatedBy
FROM trees.GrowthSimulations gs
LEFT JOIN shared.Scenarios s  ON gs.ScenarioID = s.ScenarioID
LEFT JOIN shared.Species   sp ON gs.SpeciesID  = sp.SpeciesID;

COMMENT ON VIEW public.growth_simulations IS
    'Flat view of growth simulation projections with scenario and species names resolved. '
    'Filter by scenarioname + projectionyear to get a full forest state for UE Time Machine.';

-- simulation_runs: one row per unique simulation run — useful for populating a run selector
CREATE OR REPLACE VIEW public.simulation_runs AS
SELECT
    gs.RunID                            AS runid,
    gs.SimulatorName                    AS simulatorname,
    gs.SimulatorVersion                 AS simulatorversion,
    s.ScenarioName                      AS scenarioname,
    l.LocationName                      AS locationname,
    MIN(gs.ProjectionYear)              AS first_year,
    MAX(gs.ProjectionYear)              AS last_year,
    COUNT(DISTINCT gs.ProjectionYear)   AS year_steps,
    COUNT(DISTINCT gs.TreeEntityID)     AS tree_count,
    MAX(gs.CreatedAt)                   AS created_at,
    MAX(gs.CreatedBy)                   AS created_by
FROM trees.GrowthSimulations gs
LEFT JOIN shared.Scenarios s  ON gs.ScenarioID  = s.ScenarioID
LEFT JOIN shared.Locations l  ON gs.LocationID  = l.LocationID
GROUP BY gs.RunID, gs.SimulatorName, gs.SimulatorVersion, s.ScenarioName, l.LocationName;

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
GRANT USAGE, SELECT ON SEQUENCE trees.growthsimulations_simulationid_seq TO authenticated;
