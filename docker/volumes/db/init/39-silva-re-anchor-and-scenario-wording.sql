-- =============================================================================
-- silva: expose --re-anchor, and stop `scenario` implying it drives the model
-- =============================================================================
-- Mirror of supabase/migrations/20260910120000_silva_re_anchor_and_scenario_wording.sql
-- (identical body) so a fresh `docker compose up` produces the same menu as a
-- migrated database.

-- Expose --re-anchor through the workflow menu, and stop `scenario` implying
-- something it does not do.
--
-- Two small corrections to the `silva` param_schema. Both are about the gap
-- between what the CLI can do and what a person requesting a run can see.
--
-- 1. RE_ANCHOR WAS UNREACHABLE
--
-- run_simulation.R has had `--re-anchor` since XRFF-409: project from the
-- newest *measured* variant at this location rather than the named
-- `base_variant`, when a re-survey has landed and the named anchor has gone
-- stale. It was never added to param_schema, and `additionalProperties: false`
-- means request_job() rejects it -- so the capability existed on the command
-- line and could not be requested through the queue, the page, or Unreal.
--
-- Nothing else has to change for it to work: the runner's build_argv() turns
-- `re_anchor` into `--re-anchor` generically, the same way it derives every
-- other flag. This is the whole fix.
--
-- 2. `scenario` NAMES THE OUTPUT, NOT THE PHYSICS
--
-- The old description -- "shared.Scenarios.scenario_name to write into" -- was
-- accurate and still misread, because the same table now also holds `ssp126`,
-- `ssp370` and `ssp585` from the open-data work (XRFF-395). A reader who sees
-- "scenario" beside those names reasonably concludes that picking one changes
-- the projection.
--
-- It does not. SILVA's inputs are the site conditions on shared.Locations --
-- forest growth region, elevation, slope, aspect, soil moistness, soil nutrient
-- supply -- and no climate series reaches the model at all. `scenario` selects
-- which (location, scenario, variant_name) triple to read as the base state and
-- which bucket to write the results into. Two runs differing only by `scenario`
-- would produce identical trees under different labels.
--
-- Today the question is academic: only `natural_growth` holds tree variants, so
-- any other scenario fails at resolve_variant() with a clear message. It stops
-- being academic the moment someone seeds a baseline under an SSP name, which
-- is exactly the kind of thing that looks like progress and silently is not.
--
-- Both edits target whichever row currently holds workflow_key = 'silva' rather
-- than a process_id, because the key moves to a new row on a silvaR version
-- bump (silva-connector's ensure_silva_process) and process_ids differ between
-- deployments. jsonb_set on two paths, so the other ten properties are
-- untouched and re-running this is a no-op.
--
-- Consumer grep per AGENTS.md: silva-connector reads this row generically in
-- ensure_silva_process() and copies description + param_schema forward on a
-- version bump, so the addition survives one. digital-twin-dashboard does not
-- read shared.Processes at all.

UPDATE shared.Processes
SET param_schema = jsonb_set(
        jsonb_set(
            param_schema,
            '{properties,re_anchor}',
            jsonb_build_object(
                'type', 'boolean',
                'default', false,
                'description',
                'Project from the newest measured state at this location instead '
                'of base_variant, if a re-survey has made base_variant stale. '
                'Does nothing when it is already the newest. The result is a new '
                'chain, not a rewrite: the prefix becomes silva<anchor year> so '
                'the existing chain stays intact and each chain says which '
                'observation set it came from.')),
        '{properties,scenario,description}',
        to_jsonb(
            'Which (location, scenario, variant_name) triple to read as the base '
            'state, and which scenario to write the results into; '
            'shared.Scenarios.scenario_name. This labels the run -- it is NOT a '
            'climate scenario and does not change the projection. SILVA reads its '
            'site conditions from shared.Locations (growth region, elevation, '
            'slope, aspect, soil), and no climate series reaches the model. Only '
            'natural_growth currently holds tree variants; the ssp* rows in the '
            'same table describe acquired climate data, not forest states.'::text))
WHERE workflow_key = 'silva';
