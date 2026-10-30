-- =============================================================================
-- shared.Processes as a readable workflow menu
-- =============================================================================
-- XRFF-348. Makes shared.Processes answer a question it could not answer
-- before: "what can I ask this system to run, and what does it need from me?"
--
-- shared.Processes is first and foremost a *provenance* registry -- eight
-- tables FK onto it to record what produced a value, and those rows carry the
-- citation and licence this database is published with. Most of its rows are
-- therefore not runnable at all: "Tree Age Estimation" names an algorithm that
-- already ran, not a button. This migration adds the small amount of structure
-- that lets the two kinds of row coexist in one table without lying about
-- either.
--
-- WHAT MARKS A ROW RUNNABLE -- decided here, because request_job() (XRFF-347)
-- and the runner (XRFF-349) both depend on the answer:
--
--   `workflow_key`, not a NULL param_schema.
--
-- One column does two jobs, and neither is served by overloading param_schema:
--
--   * It is the *machine* name. `process_name` is a human title -- 'Forest
--     Growth Simulation' -- and it is UNIQUE only together with `version`.
--     request_job('silva', ...) needs a short, stable, single-column key that
--     survives a version bump, and workflows.toml on the runner host needs the
--     same string to match against.
--   * It is the flag. `workflow_key IS NULL` means "provenance only, not
--     runnable". A NULL param_schema cannot carry that meaning: a runnable
--     workflow that takes no parameters legitimately has `{}`, and documenting
--     the inputs of a past analysis would silently make it requestable.
--
-- UNIQUE, so exactly one row per workflow is runnable at any time. On a
-- version bump the key is handed over to the new row rather than duplicated --
-- see silva-connector's ensure_silva_process(), which does exactly that.
--
-- PARAM_SCHEMA SHAPE -- the contract request_job() validates against:
-- a JSON Schema draft-07 subset, deliberately small enough to validate in
-- plpgsql. Supported keywords, and nothing else:
--
--   object level:  type ("object"), properties, required, additionalProperties
--                  (always false), dependentRequired
--   per property:  type (string|integer|number|boolean), description, default,
--                  enum, minimum, maximum, multipleOf, pattern
--
-- "--years must be a multiple of 5" is `multipleOf: 5` -- a real JSON Schema
-- keyword, not a convention invented here. "--from and --to must be given
-- together" is `dependentRequired`. Anything not expressible in that subset
-- stays in the CLI, which enforces it anyway; param_schema documents and
-- pre-checks, it does not replace the tool's own argument validation.
--
-- The parameters exposed are a *curated* subset of each CLI, not a mirror of
-- it. growpy's pipeline takes 26 flags; five of them are meaningful to someone
-- requesting a run, and the rest are host and debugging concerns that belong
-- in the runner's private config.
--
-- NO COMMAND STRINGS. Nothing here says how a workflow is invoked. The runner
-- refuses any workflow_key absent from its local workflows.toml, so the
-- database can name a workflow but never define what it executes.
--
-- Idempotent: safe to re-run.
--
-- NOTE ON PART 1: the param_schema column and the `acquisition` category are
-- also created by 20260902140000_open_data_landing_zones.sql (XRFF-369), which
-- was in flight in a parallel session when this was written. Both statements
-- are idempotent and converge on the same result, so the two migrations are
-- order-independent and either can land alone. The duplication is deliberate;
-- collapse it only once both are merged.
-- =============================================================================


-- =============================================================================
-- PART 1 -- param_schema column and the `acquisition` category
-- =============================================================================
-- Fetching sensor readings from Aquarius is not detection, classification,
-- simulation, analysis or aggregation. Filing it under one of those would make
-- the provenance registry misdescribe the rows that carry the licence of every
-- acquired value.
-- =============================================================================

ALTER TABLE shared.Processes DROP CONSTRAINT IF EXISTS processes_category_check;
ALTER TABLE shared.Processes
    ADD CONSTRAINT processes_category_check
    CHECK (category::text = ANY (ARRAY[
        'detection', 'classification', 'simulation',
        'analysis', 'aggregation', 'acquisition'
    ]::text[]));

ALTER TABLE shared.Processes
    ADD COLUMN IF NOT EXISTS param_schema jsonb;

ALTER TABLE shared.Processes DROP CONSTRAINT IF EXISTS processes_param_schema_is_object;
ALTER TABLE shared.Processes
    ADD CONSTRAINT processes_param_schema_is_object
    CHECK (param_schema IS NULL OR jsonb_typeof(param_schema) = 'object');


-- =============================================================================
-- PART 2 -- workflow_key
-- =============================================================================

ALTER TABLE shared.Processes
    ADD COLUMN IF NOT EXISTS workflow_key character varying(50);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'processes_workflow_key_key') THEN
        ALTER TABLE shared.Processes
            ADD CONSTRAINT processes_workflow_key_key UNIQUE (workflow_key);
    END IF;
END $$;

-- A runnable row must document its parameters, even when it takes none ({}).
-- This is what keeps `workflow_key IS NOT NULL` a sufficient test for
-- request_job(): if the key is there, there is a schema to validate against.
ALTER TABLE shared.Processes DROP CONSTRAINT IF EXISTS processes_runnable_has_param_schema;
ALTER TABLE shared.Processes
    ADD CONSTRAINT processes_runnable_has_param_schema
    CHECK (workflow_key IS NULL OR param_schema IS NOT NULL);

COMMENT ON COLUMN shared.Processes.category IS
    'What kind of step this is. `acquisition` (added 2026-09-02) is a fetch '
    'from an external system -- Aquarius, ERA5, SoilGrids -- as opposed to a '
    'computation over data already held.';

COMMENT ON COLUMN shared.Processes.param_schema IS
    'JSON Schema (draft-07 subset) for the parameters this workflow accepts, '
    'so a caller can be told what it needs without reading its code. Supported '
    'keywords: type, properties, required, additionalProperties, '
    'dependentRequired, description, default, enum, minimum, maximum, '
    'multipleOf, pattern. Never holds a command line or a host path: what a '
    'workflow *does* is defined only in the runner private config, so the '
    'database can name a workflow but never define it.';

COMMENT ON COLUMN shared.Processes.workflow_key IS
    'Short machine name of a runnable workflow -- the string request_job() '
    'takes and the runner matches against its local workflows.toml. NULL means '
    'the row is provenance only: it records what produced some data and cannot '
    'be requested. UNIQUE, so exactly one row (one version) is runnable per '
    'workflow; on a version bump the key is moved to the new row, not copied.';


-- =============================================================================
-- PART 3 -- seed the menu
-- =============================================================================
-- Descriptions are written for a colleague deciding whether to press the
-- button: what it changes, roughly how long it takes, and what it costs to be
-- wrong. The algorithm-level description stays on the provenance rows.
-- =============================================================================

-- silva -- seeded here, not merely updated. On a fresh database this row does
-- not exist: silva-connector's ensure_silva_process() creates it on first run.
-- An UPDATE would match nothing there, and the connector -- which carries the
-- key over rather than authoring it -- would then insert a keyless row,
-- leaving SILVA permanently unrequestable on every new deployment. Seeding it
-- under the exact identity that function looks up, (process_name,
-- algorithm_name, version), means the connector finds and reuses this row
-- instead of adding a second Forest Growth Simulation.
INSERT INTO shared.Processes
    (process_name, algorithm_name, version, category, workflow_key,
     author, citation, description, param_schema)
VALUES (
    'Forest Growth Simulation',
    'SILVA (silvaR)',
    '0.0.0.9000',
    'simulation',
    'silva',
    'Pretzsch, Biber & Dursky (silvaR implementation: Torben Hilmers, TUM)',
    'Pretzsch, H., Biber, P. & Dursky, J. (2002). The single tree-based stand '
    'simulator SILVA: construction, application and evaluation. Forest Ecology '
    'and Management, 162(1), 3-21. doi:10.1016/S0378-1127(02)00047-6',
    'Project a variant forward with the SILVA growth model and write the '
    'result back as a chain of simulated_growth variants, one per 5-year '
    'period. Takes about 30 s for ecosense (1,495 trees), 10 s for '
    'mathisle. Appends to trees.GrowthSimulations, which accumulates -- '
    'running it twice gives two comparable runs, not a corrupted one. '
    'Use replace=true only to overwrite variants of the same name, and '
    'no_promote=true to compare a scenario without touching the variant '
    'chain Unreal reads.',
    jsonb_build_object(
        'type', 'object',
        'additionalProperties', false,
        'required', jsonb_build_array('location'),
        'dependentRequired', jsonb_build_object(),
        'properties', jsonb_build_object(
            'location', jsonb_build_object(
                'type', 'string',
                'description', 'Site to simulate; shared.Locations.location_name.'),
            'scenario', jsonb_build_object(
                'type', 'string', 'default', 'natural_growth',
                'description', 'shared.Scenarios.scenario_name to write into.'),
            'base_variant', jsonb_build_object(
                'type', 'string', 'default', 'baseline_2025',
                'description', 'Variant to project forward.'),
            'years', jsonb_build_object(
                'type', 'integer', 'default', 20,
                'multipleOf', 5, 'minimum', 5, 'maximum', 100,
                'description', 'Projection horizon. One SILVA period is 5 years, so this must be a multiple of 5.'),
            'competition', jsonb_build_object(
                'type', 'string', 'default', 'sf_polygon',
                'enum', jsonb_build_array('sf_polygon', 'rect_sum', 'legacy'),
                'description', 'Neighbour competition method.'),
            'mortality', jsonb_build_object(
                'type', 'boolean', 'default', false,
                'description', 'Let SILVA kill trees. Off by default: the twin has no tree_status write path yet.'),
            'seed', jsonb_build_object(
                'type', 'integer', 'default', 1,
                'description', 'Random seed. Recorded on the run, so two runs differing only by seed stay distinguishable.'),
            'variant_prefix', jsonb_build_object(
                'type', 'string', 'default', 'silva',
                'description', 'New variants are named <prefix>_<year>.'),
            'replace', jsonb_build_object(
                'type', 'boolean', 'default', false,
                'description', 'Delete existing simulated_growth variants of the same name first.'),
            'no_promote', jsonb_build_object(
                'type', 'boolean', 'default', false,
                'description', 'Write the trajectory but do not promote it to variants.'),
            'dry_run', jsonb_build_object(
                'type', 'boolean', 'default', false,
                'description', 'Simulate and report, write nothing.')
        )))
ON CONFLICT (process_name, version) DO UPDATE SET
    workflow_key = EXCLUDED.workflow_key,
    category     = EXCLUDED.category,
    description  = EXCLUDED.description,
    param_schema = EXCLUDED.param_schema;

-- aquarius-sync
INSERT INTO shared.Processes
    (process_name, algorithm_name, version, category, workflow_key, author, description, param_schema)
VALUES (
    'Aquarius Sensor Sync',
    'Aquarius Publish API time-series pull (aquarius-connector)',
    '0.1.0',
    'acquisition',
    'aquarius-sync',
    'XR Future Forests Lab',
    'Pull sensor readings from the Aquarius Publish API into sensor.Readings. '
    'Takes minutes. Idempotent on both sides -- re-running a window updates the '
    'same rows rather than duplicating them, so an overlapping window is safe. '
    'Without from/to it re-pulls a rolling window of the last days_back days; '
    'give from/to to backfill a specific historical period. Every sync '
    'overwrites sensor_model with a placeholder, so aquarius-enrich must run '
    'immediately afterwards, every time.',
    jsonb_build_object(
        'type', 'object',
        'additionalProperties', false,
        'required', jsonb_build_array(),
        'dependentRequired', jsonb_build_object(
            'from', jsonb_build_array('to'),
            'to', jsonb_build_array('from')),
        'properties', jsonb_build_object(
            'days_back', jsonb_build_object(
                'type', 'integer', 'default', 30, 'minimum', 1, 'maximum', 365,
                'description', 'Rolling window size in days. Ignored when from/to are given.'),
            'from', jsonb_build_object(
                'type', 'string', 'pattern', '^\d{4}-\d{2}-\d{2}$',
                'description', 'Start of an explicit historical window, ISO date. Must be given with `to`.'),
            'to', jsonb_build_object(
                'type', 'string', 'pattern', '^\d{4}-\d{2}-\d{2}$',
                'description', 'End of the window, ISO date. Must be later than `from`.'),
            'sensor_type', jsonb_build_object(
                'type', 'string',
                'description', 'Restrict the pull to one digital-twin sensor type. Omit for all types.')
        )))
ON CONFLICT (process_name, version) DO UPDATE SET
    workflow_key = EXCLUDED.workflow_key,
    category     = EXCLUDED.category,
    description  = EXCLUDED.description,
    param_schema = EXCLUDED.param_schema;

-- aquarius-enrich
INSERT INTO shared.Processes
    (process_name, algorithm_name, version, category, workflow_key, author, description, param_schema)
VALUES (
    'Aquarius Sensor Metadata Enrichment',
    'Aquarius location/parameter metadata backfill (aquarius-connector)',
    '0.1.0',
    'acquisition',
    'aquarius-enrich',
    'XR Future Forests Lab',
    'Restore real sensor metadata -- model, manufacturer, installation details '
    '-- that aquarius-sync overwrites with a placeholder on every run. Seconds. '
    'Takes no parameters. Run it after every sync; running it on its own is '
    'harmless.',
    jsonb_build_object(
        'type', 'object',
        'additionalProperties', false,
        'required', jsonb_build_array(),
        'dependentRequired', jsonb_build_object(),
        'properties', jsonb_build_object()))
ON CONFLICT (process_name, version) DO UPDATE SET
    workflow_key = EXCLUDED.workflow_key,
    category     = EXCLUDED.category,
    description  = EXCLUDED.description,
    param_schema = EXCLUDED.param_schema;

-- growpy
INSERT INTO shared.Processes
    (process_name, algorithm_name, version, category, workflow_key, author, description, param_schema)
VALUES (
    'Tree Model Generation',
    'Procedural tree assembly pipeline (growpy)',
    '0.4.0',
    'simulation',
    'growpy',
    'XR Future Forests Lab',
    'Generate the 3D tree assemblies Unreal places, one species at a time. '
    'Slow: 23-75 minutes per species-height batch, and step 4 needs Blender, so '
    'it runs on a different host from the other workflows. Writes files, not '
    'database rows. Use dry_run=true first to see what it would do, and '
    'max_height to cut a test run short.',
    jsonb_build_object(
        'type', 'object',
        'additionalProperties', false,
        'required', jsonb_build_array('species'),
        'dependentRequired', jsonb_build_object(),
        'properties', jsonb_build_object(
            'species', jsonb_build_object(
                'type', 'string',
                'description', 'Single species by common name, e.g. "European Beech".'),
            'steps', jsonb_build_object(
                'type', 'string', 'default', '4',
                'pattern', '^(all|[1-4](,[1-4])*)$',
                'description', 'Pipeline steps to run: 1 prepare-assets, 2 convert-twigs, 3 create-models, 4 generate-forest. Comma-separated, or "all".'),
            'max_height', jsonb_build_object(
                'type', 'number', 'default', 0, 'minimum', 0, 'maximum', 60,
                'description', 'Cap tree height in metres for step 4, for faster test runs. 0 = no limit.'),
            'workers', jsonb_build_object(
                'type', 'integer', 'default', 4, 'minimum', 1, 'maximum', 16,
                'description', 'Parallel workers for step 4. 1 = sequential.'),
            'dry_run', jsonb_build_object(
                'type', 'boolean', 'default', false,
                'description', 'Print what would run without executing it.')
        )))
ON CONFLICT (process_name, version) DO UPDATE SET
    workflow_key = EXCLUDED.workflow_key,
    category     = EXCLUDED.category,
    description  = EXCLUDED.description,
    param_schema = EXCLUDED.param_schema;


-- =============================================================================
-- PART 4 -- public.workflows
-- =============================================================================
-- The menu, without the provenance rows. This is what Studio's table view and
-- the "Requesting a job" doc page point at; shared.Processes stays the full
-- registry.
--
-- security_invoker='on': the view is not an anon-facing Unreal endpoint, so it
-- carries the setting new views are supposed to carry. shared.Processes'
-- "Processes are viewable by everyone" SELECT policy is what makes it readable
-- through the view.
--
-- param_schema is returned as jsonb, not flattened. Unreal does not read this
-- view -- a Blueprint asks for a job, it does not browse the menu -- so the
-- flat-scalar rule does not bind here.
-- =============================================================================

DROP VIEW IF EXISTS public.workflows;
CREATE VIEW public.workflows
    WITH (security_invoker = 'on') AS
SELECT
    p.workflow_key,
    p.process_name,
    p.description,
    p.category,
    p.version,
    p.param_schema
FROM shared.Processes p
WHERE p.workflow_key IS NOT NULL;

COMMENT ON VIEW public.workflows IS
    'The workflows that can be requested with request_job(), one row each, with '
    'the JSON Schema of the parameters each accepts. A row here is a name and a '
    'contract only -- what it executes is defined solely in the runner private '
    'config on the host that runs it.';

GRANT SELECT ON public.workflows TO anon, authenticated, service_role;
