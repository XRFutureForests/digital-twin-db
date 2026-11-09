-- =============================================================================
-- Record what produced a growth simulation, and settle the queue's shape
-- =============================================================================
-- XRFF-374.
--
-- PART 1 -- trees.SimulationRuns
--
-- trees.GrowthSimulations records run_id, simulator_name/version, scenario_id
-- and projection_year, and nothing about *how* the run was configured: no seed,
-- no competition method, no mortality flag, no horizon, no base variant. Two
-- runs differing only by `--seed` are therefore indistinguishable after the
-- fact, and `--no-promote` scenario comparison -- the entire reason
-- silva-connector writes to two targets -- is unreproducible. The two runs that
-- exist today (ecosense 1495 trees, mathisle 730) record none of it.
--
-- Chosen: a real table keyed by run_id, with public.simulation_runs becoming a
-- view over it. The alternative, a `run_params jsonb` column on
-- trees.GrowthSimulations, was rejected because:
--
--   * the parameters are run-scoped and that table is (tree x year)-scoped, so
--     one blob would be repeated across 8,900 rows today and every row of every
--     future run, with nothing preventing two rows of one run from disagreeing;
--   * `base_variant` has to be a *reference*, not a string. It is the
--     reproducibility anchor -- "which forest state did this start from" -- and
--     variant names are deliberately reused and deleted (`--replace` does
--     exactly that). A FK survives that; the text 'baseline_2025' does not;
--   * public.simulation_runs already exists as a run-level aggregate. It is a
--     view that wants a table underneath it.
--
-- The FK trees.GrowthSimulations.run_id -> trees.SimulationRuns.run_id makes a
-- trajectory with no recorded parameters structurally impossible from now on.
--
-- Typed columns carry what is meaningful for *any* simulator (SILVA, FVS,
-- iLand, manual); `run_params jsonb` carries the simulator-specific rest.
-- run_params holds named parameters only -- never a reconstructed command line.
--
-- PART 2 -- shared.ProcessingJobs queue columns (XRFF-346 groundwork)
--
-- Decided here rather than left to XRFF-347/349; see the block comment there.
--
-- Idempotent: safe to re-run.
-- =============================================================================


-- =============================================================================
-- PART 1 -- trees.SimulationRuns
-- =============================================================================

CREATE TABLE IF NOT EXISTS trees.SimulationRuns (
    run_id             uuid PRIMARY KEY,

    -- What was simulated.
    location_id        integer NOT NULL,
    scenario_id        integer,
    base_variant_id    integer,
    base_year          integer,

    -- What did the simulating.
    simulator_name     character varying(100) NOT NULL,
    simulator_version  character varying(50),
    process_id         integer,

    -- How it was configured. Simulator-agnostic parameters get a column;
    -- everything simulator-specific goes in run_params.
    horizon_years      integer,
    seed               integer,
    mortality_enabled  boolean,
    promoted           boolean,
    run_params         jsonb NOT NULL DEFAULT '{}'::jsonb,

    created_at         timestamp with time zone NOT NULL DEFAULT now(),
    created_by         character varying(200),

    CONSTRAINT simulationruns_simulator_name_check
        CHECK (simulator_name::text = ANY (ARRAY['SILVA', 'FVS', 'iLand', 'manual', 'other']::text[])),
    CONSTRAINT simulationruns_horizon_years_check
        CHECK (horizon_years IS NULL OR horizon_years >= 0),
    CONSTRAINT simulationruns_base_year_check
        CHECK (base_year IS NULL OR (base_year >= 1900 AND base_year <= 2300)),
    CONSTRAINT simulationruns_run_params_is_object
        CHECK (jsonb_typeof(run_params) = 'object')
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'simulationruns_location_id_fkey') THEN
        ALTER TABLE ONLY trees.SimulationRuns
            ADD CONSTRAINT simulationruns_location_id_fkey
            FOREIGN KEY (location_id) REFERENCES shared.locations(location_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'simulationruns_scenario_id_fkey') THEN
        ALTER TABLE ONLY trees.SimulationRuns
            ADD CONSTRAINT simulationruns_scenario_id_fkey
            FOREIGN KEY (scenario_id) REFERENCES shared.scenarios(scenario_id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'simulationruns_base_variant_id_fkey') THEN
        ALTER TABLE ONLY trees.SimulationRuns
            ADD CONSTRAINT simulationruns_base_variant_id_fkey
            FOREIGN KEY (base_variant_id) REFERENCES shared.variants(variant_id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'simulationruns_process_id_fkey') THEN
        ALTER TABLE ONLY trees.SimulationRuns
            ADD CONSTRAINT simulationruns_process_id_fkey
            FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_simulationruns_location_scenario
    ON trees.SimulationRuns (location_id, scenario_id);
CREATE INDEX IF NOT EXISTS idx_simulationruns_created_at
    ON trees.SimulationRuns (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_simulationruns_simulator
    ON trees.SimulationRuns (simulator_name, simulator_version);

COMMENT ON TABLE trees.SimulationRuns IS
    'One row per forest growth simulation run: what was simulated, by which simulator, and with which parameters. trees.GrowthSimulations holds the per-tree result rows of a run and references this table by run_id.';
COMMENT ON COLUMN trees.SimulationRuns.base_variant_id IS
    'shared.Variants row the run was projected forward from. The reproducibility anchor: variant names are reused and deleted by --replace, so the reference is stored, not the name.';
COMMENT ON COLUMN trees.SimulationRuns.base_year IS
    'Calendar year of the base variant (year zero). First projected year = base_year + one simulator period.';
COMMENT ON COLUMN trees.SimulationRuns.horizon_years IS
    'Projection horizon in years, as requested (silva-connector: --years, a multiple of 5).';
COMMENT ON COLUMN trees.SimulationRuns.seed IS
    'Random seed. The one parameter that makes two otherwise identical runs differ, and the reason this table exists.';
COMMENT ON COLUMN trees.SimulationRuns.mortality_enabled IS
    'True if the simulator was allowed to kill trees during the run.';
COMMENT ON COLUMN trees.SimulationRuns.promoted IS
    'True if the run was promoted to the shared.Variants chain UE reads. False for a comparison-only run (silva-connector --no-promote).';
COMMENT ON COLUMN trees.SimulationRuns.run_params IS
    'Simulator-specific parameters as named keys, e.g. {"competition": "sf_polygon", "variant_prefix": "silva", "replace": true}. Named parameters only -- never a command line. An absent key on a run predating 2026-09-02 means the value was not recorded, not that it was unset.';
COMMENT ON COLUMN trees.SimulationRuns.process_id IS
    'shared.Processes row the run registered itself under (algorithm, version, citation).';

GRANT SELECT ON TABLE trees.SimulationRuns TO anon;
GRANT SELECT ON TABLE trees.SimulationRuns TO authenticated;
GRANT ALL    ON TABLE trees.SimulationRuns TO service_role;

ALTER TABLE trees.SimulationRuns ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'trees' AND tablename = 'simulationruns'
                     AND policyname = 'Simulation runs are viewable by everyone') THEN
        CREATE POLICY "Simulation runs are viewable by everyone"
            ON trees.SimulationRuns FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'trees' AND tablename = 'simulationruns'
                     AND policyname = 'Contributors can create simulation runs') THEN
        CREATE POLICY "Contributors can create simulation runs"
            ON trees.SimulationRuns FOR INSERT TO authenticated
            WITH CHECK (shared.is_contributor());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'trees' AND tablename = 'simulationruns'
                     AND policyname = 'Curators can update simulation runs') THEN
        CREATE POLICY "Curators can update simulation runs"
            ON trees.SimulationRuns FOR UPDATE TO authenticated
            USING (shared.is_curator()) WITH CHECK (shared.is_curator());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'trees' AND tablename = 'simulationruns'
                     AND policyname = 'Curators can delete simulation runs') THEN
        CREATE POLICY "Curators can delete simulation runs"
            ON trees.SimulationRuns FOR DELETE TO authenticated
            USING (shared.is_curator());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'trees' AND tablename = 'simulationruns'
                     AND policyname = 'Service role can manage all simulation runs') THEN
        CREATE POLICY "Service role can manage all simulation runs"
            ON trees.SimulationRuns TO service_role USING (true) WITH CHECK (true);
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- Back-fill the two runs that already exist.
-- -----------------------------------------------------------------------------
-- Not guessed. Every value below is read out of the database:
--
--   run_id / location_id / scenario_id / simulator_*  trees.GrowthSimulations
--   base_variant / competition / mortality / seed     the description text that
--                                                     write_period_variant()
--                                                     stamps on every simulated
--                                                     variant
--   variant_prefix                                    the variant names
--                                                     (silva_2030 ...)
--   promoted                                          variants exist for both
--                                                     run_ids
--   base_year / horizon_years                         base variant year 2025;
--                                                     last projection 2045
--   process_id                                        trees.Trees.process_id on
--                                                     the promoted variants
--
-- Both runs were `mortality FALSE`, i.e. run *without* `--mortality`. The
-- handover note claiming `--mortality` is wrong; the variant descriptions are
-- the record.
--
-- `replace` is deliberately absent from run_params: the flag leaves no trace
-- once the run has finished, so it cannot be recovered and is not invented.
-- -----------------------------------------------------------------------------

INSERT INTO trees.SimulationRuns
    (run_id, location_id, scenario_id, base_variant_id, base_year,
     simulator_name, simulator_version, process_id,
     horizon_years, seed, mortality_enabled, promoted, run_params,
     created_at, created_by)
SELECT gs.run_id,
       gs.location_id,
       gs.scenario_id,
       bv.variant_id,
       bv.simulation_year,
       gs.simulator_name,
       gs.simulator_version,
       3,
       max(gs.projection_year) - bv.simulation_year,
       1,
       false,
       true,
       '{"competition": "sf_polygon", "variant_prefix": "silva"}'::jsonb,
       min(gs.created_at),
       max(gs.created_by)
FROM trees.growthsimulations gs
JOIN shared.variants bv
  ON bv.location_id = gs.location_id
 AND bv.scenario_id = gs.scenario_id
 AND bv.variant_name = 'baseline_2025'
GROUP BY gs.run_id, gs.location_id, gs.scenario_id, bv.variant_id,
         bv.simulation_year, gs.simulator_name, gs.simulator_version
ON CONFLICT (run_id) DO NOTHING;


-- -----------------------------------------------------------------------------
-- Now that every existing run has a row, make the link mandatory.
-- -----------------------------------------------------------------------------
-- The DEFAULT gen_random_uuid() on run_id goes with it: under the FK it can
-- only ever generate a value with no parent row, so it cannot produce a valid
-- insert. The writer must create the run row first -- which is the point.
-- -----------------------------------------------------------------------------

ALTER TABLE trees.growthsimulations ALTER COLUMN run_id DROP DEFAULT;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'growthsimulations_run_id_fkey') THEN
        ALTER TABLE ONLY trees.growthsimulations
            ADD CONSTRAINT growthsimulations_run_id_fkey
            FOREIGN KEY (run_id) REFERENCES trees.SimulationRuns(run_id) ON DELETE CASCADE;
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- public.simulation_runs: same eleven columns, now with the parameters appended
-- -----------------------------------------------------------------------------
-- Run-level facts come from trees.SimulationRuns; the derived counts stay an
-- aggregate over the trajectory rows so they cannot drift from what was
-- actually written.
--
-- security_invoker is deliberately NOT switched on here. This view is one of
-- the 19 that predate that convention (codebase_audit.md F14) and its readers
-- reach it as anon, who has no SELECT on trees.GrowthSimulations; turning it on
-- would break the view rather than tighten it. Replacing the body adds nothing
-- to that drift, and fixing F14 needs its own migration with the matching
-- grants. Any new view here would get security_invoker='on'; there are none.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.simulation_runs AS
 SELECT r.run_id,
        r.simulator_name,
        r.simulator_version,
        s.scenario_name,
        l.location_name,
        agg.first_year,
        agg.last_year,
        agg.year_steps,
        agg.tree_count,
        r.created_at,
        r.created_by::text AS created_by,
        -- appended 2026-09-02, XRFF-374
        r.base_year,
        r.horizon_years,
        bv.variant_name AS base_variant,
        r.seed,
        r.mortality_enabled,
        r.promoted,
        r.run_params
   FROM trees.simulationruns r
   LEFT JOIN shared.scenarios s  ON s.scenario_id = r.scenario_id
   LEFT JOIN shared.locations l  ON l.location_id = r.location_id
   LEFT JOIN shared.variants  bv ON bv.variant_id = r.base_variant_id
   LEFT JOIN LATERAL (
        SELECT min(gs.projection_year)            AS first_year,
               max(gs.projection_year)            AS last_year,
               count(DISTINCT gs.projection_year) AS year_steps,
               count(DISTINCT gs.tree_entity_id)  AS tree_count
        FROM trees.growthsimulations gs
        WHERE gs.run_id = r.run_id
   ) agg ON true;

COMMENT ON VIEW public.simulation_runs IS
    'One row per growth simulation run: identity, configuration and the size of the trajectory it produced. Backed by trees.SimulationRuns; counts aggregated from trees.GrowthSimulations.';


-- =============================================================================
-- PART 2 -- shared.ProcessingJobs: settle the queue columns while it is empty
-- =============================================================================
-- The table has never held a row and no runner exists yet (XRFF-349), so this
-- is the cheap moment to decide. Three questions were open.
--
-- 1. RETRY -- adopted as bookkeeping, not as automatic backoff.
--
--    `attempts` / `max_attempts` are not speculative: XRFF-349's `runner reap`
--    recovers rows whose host process is gone, and without a claim count it has
--    no stop condition -- a job whose host dies on every claim would be
--    re-claimed forever. `started_at` and `claimed_by` are what reap tests
--    ("running since when, on which host"); `submitted_at` / `completed_at`
--    alone cannot answer that. `next_attempt_at` gates the claim query, so a
--    reaped job can be held back without inventing a second status value.
--
--    max_attempts DEFAULTs to 1: no automatic retry in v1. These workflows run
--    32 s (SILVA) to 75 min (growpy) and fail for parameter or data reasons far
--    more often than transient ones, so re-running one unattended mostly burns
--    an hour to fail identically. The columns record what happened; a later
--    policy can raise the default without another migration.
--
-- 2. PRIORITY / LANES -- deliberately NOT in v1, and not as a column.
--
--    The question is whether a 32 s SILVA run must wait behind a 75 min growpy
--    run. It need not, and the answer is already in the architecture: XRFF-349
--    runs *multiple runner instances*, each claiming only the workflows its own
--    host can execute (growpy needs Blender, silva needs Docker on the DB
--    network, aquarius needs VPN reachability -- they may never be one
--    machine). That is a lane per host, enforced by each runner's local config.
--    A `priority` column no runner consults would be worse than none: it would
--    look like it does something. Add it only if two workflows ever share one
--    runner and genuinely contend.
--
-- 3. IDEMPOTENCY -- external_job_id adopted as the key. It is already UNIQUE
--    and has never been used. Nullable UNIQUE is exactly the wanted semantics:
--    an unkeyed job is unconstrained, a keyed one cannot be enqueued twice, so
--    a double-click in VR that sends the same key twice yields one job.
-- =============================================================================

ALTER TABLE shared.processingjobs
    ADD COLUMN IF NOT EXISTS started_at      timestamp with time zone,
    ADD COLUMN IF NOT EXISTS claimed_by      character varying(200),
    ADD COLUMN IF NOT EXISTS attempts        integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_attempts    integer NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS next_attempt_at timestamp with time zone;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_started_after_submitted') THEN
        ALTER TABLE shared.processingjobs
            ADD CONSTRAINT chk_started_after_submitted
            CHECK (started_at IS NULL OR started_at >= submitted_at);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_attempts_nonneg') THEN
        ALTER TABLE shared.processingjobs
            ADD CONSTRAINT chk_attempts_nonneg
            CHECK (attempts >= 0 AND max_attempts >= 1);
    END IF;
END $$;

-- Claim query support: pending jobs, oldest first.
CREATE INDEX IF NOT EXISTS idx_processing_jobs_claimable
    ON shared.processingjobs (submitted_at)
    WHERE status = 'pending';

COMMENT ON COLUMN shared.processingjobs.external_job_id IS
    'Idempotency key supplied by the caller. Already UNIQUE, and adopted as the deduplication key: enqueueing the same key twice yields one job, so a repeated request from VR or a double-clicked button cannot start the same run twice. NULL for jobs that do not need deduplication.';
COMMENT ON COLUMN shared.processingjobs.started_at IS
    'When a runner claimed the job and began executing it. NULL while pending.';
COMMENT ON COLUMN shared.processingjobs.claimed_by IS
    'Identity of the runner instance holding the job (host and process), so `runner reap` can tell a live claim from an abandoned one.';
COMMENT ON COLUMN shared.processingjobs.attempts IS
    'How many times the job has been claimed. Incremented on claim, so an abandoned job that is reaped and re-queued is not retried forever.';
COMMENT ON COLUMN shared.processingjobs.max_attempts IS
    'Claim budget. DEFAULT 1 = no automatic retry, which is the v1 policy: these workflows fail for parameter reasons far more often than transient ones.';
COMMENT ON COLUMN shared.processingjobs.next_attempt_at IS
    'Earliest time a runner may claim the job. NULL means immediately. Set by `runner reap` to hold a recovered job back.';


-- =============================================================================
-- Report
-- =============================================================================
DO $$
DECLARE
    n_runs    INT;
    n_orphan  INT;
    n_unparam INT;
BEGIN
    SELECT count(*) INTO n_runs FROM trees.SimulationRuns;

    SELECT count(DISTINCT gs.run_id) INTO n_orphan
      FROM trees.growthsimulations gs
      LEFT JOIN trees.SimulationRuns r ON r.run_id = gs.run_id
     WHERE r.run_id IS NULL;

    SELECT count(*) INTO n_unparam FROM trees.SimulationRuns WHERE seed IS NULL;

    RAISE NOTICE 'trees.SimulationRuns: % run(s); % trajectory run(s) without a run row; % run(s) with no seed recorded',
                 n_runs, n_orphan, n_unparam;
END $$;
