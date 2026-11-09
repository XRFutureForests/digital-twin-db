-- Expose management regime and climate pathway on the silva workflow menu.
--
-- silva-connector's run_simulation.R gained three options on 2026-09-14:
--
--   --regime <name>         shared.ManagementRegimes.regime_name; the silvaR
--                           thinning preset stored on that row is applied
--                           between periods (XRFF-436)
--   --climate <name>        shared.ClimatePathways.pathway_name; the CHELSA
--                           temperature/precipitation deltas and SSP CO2 the
--                           open-data connector acquired for that pathway are
--                           applied to SILVA's site conditions, per period, by
--                           the 30-year window each period falls in
--   --base-scenario <name>  where the measured state lives (natural_growth)
--
-- and `scenario` changed meaning: it is now an optional override of the
-- OUTPUT scenario name. Left out, the run derives it from the two axes with
-- the naming grammar in migration 20260914100000 -- natural_growth,
-- natural_growth_ssp370, crop_tree_thinning, crop_tree_thinning_ssp585 --
-- and creates the row if it does not exist. The 2026-09-10 wording that a
-- scenario "does not change the projection" was true then and is not now:
-- the projection is changed by regime and climate, and the scenario is the
-- bucket named after them.
--
-- `mortality` loses its stale reason. The write path it said was missing has
-- existed since 2026-09-03 (writeback.R writes tree_status_id); it stays off
-- by default only so an existing call keeps its meaning. Managed runs should
-- turn it on.
--
-- Both axes are enums so the /jobs/ page renders a dropdown. Adding a regime
-- or pathway therefore means a lookup row AND an enum entry here -- the
-- lookup is the truth, the enum is the menu, and the connector checks the
-- lookup regardless.
--
-- Targets whichever row holds workflow_key = 'silva', as 20260910120000 does,
-- and uses jsonb_set per path so re-running is a no-op.

UPDATE shared.Processes
SET param_schema = param_schema
    || jsonb_build_object('properties',
        (param_schema->'properties')
        || jsonb_build_object(
            'regime', jsonb_build_object(
                'type', 'string',
                'enum', jsonb_build_array('natural_growth', 'crop_tree_thinning', 'target_diameter_harvest'),
                'default', 'natural_growth',
                'description',
                'Management regime; shared.ManagementRegimes.regime_name. natural_growth '
                'projects with no intervention. crop_tree_thinning (even-aged stands, '
                'ecosense) and target_diameter_harvest (two-storied spruce-fir-beech, '
                'mathisle) apply the silvaR preset stored on that row between periods '
                'and write removed trees as tree_status harvested (standing dead from '
                'mortality stays dead). Turn mortality on for a managed run. The presets '
                'are provisional until a forester has reviewed them.'),
            'climate', jsonb_build_object(
                'type', 'string',
                'enum', jsonb_build_array('historical', 'ssp126', 'ssp370', 'ssp585'),
                'default', 'historical',
                'description',
                'Climate pathway; shared.ClimatePathways.pathway_name. historical holds '
                'the observed 1981-2010 climatology constant (every projection before '
                '2026-09-14). An SSP applies, per 5-year period, the CHELSA temperature '
                'delta and precipitation ratio of the 30-year window that period falls '
                'in (2011-2040, 2041-2070, 2071-2100) and that window''s SSP CO2, to '
                'SILVA''s site conditions. Only temperature, precipitation and CO2 are '
                'perturbed; vegetation-period length is not. Projections past 2100 are '
                'refused. Data comes from environments.Environments for this location.'),
            'base_scenario', jsonb_build_object(
                'type', 'string',
                'default', 'natural_growth',
                'description',
                'Scenario holding the measured state to project from (with base_variant). '
                'The measured baselines live in natural_growth; a managed or climate run '
                'starts from the same measured trees and writes into its own scenario.'),
            'scenario', jsonb_build_object(
                'type', 'string',
                'description',
                'Optional. Output scenario name. Left out (the normal case) it is derived '
                'from regime and climate -- natural_growth, natural_growth_ssp370, '
                'crop_tree_thinning, crop_tree_thinning_ssp585 -- and created at this '
                'location if absent. Given, it must either not exist yet or already carry '
                'the same regime and climate; the run refuses to write a projection into '
                'a scenario whose axes say something else.'),
            'mortality', jsonb_build_object(
                'type', 'boolean',
                'default', false,
                'description',
                'Let SILVA kill trees. Dead trees stay in every later variant as standing '
                'dead stems (tree_status dead). Off by default so existing calls keep '
                'their meaning; recommended on for every new chain, and for any managed '
                'run.'))),
    description =
        'Project a variant forward with the SILVA growth model and write the result back '
        'as a chain of simulated_growth variants, one per 5-year period, into the scenario '
        'named by the management regime and climate pathway (regime, climate). A 20-year '
        'run takes about 60 s for ecosense (1,495 trees) and 20 s for mathisle (730); cost '
        'grows with the horizon and, steeply, with the number of trees. dry_run=true '
        'simulates and writes nothing, which is the way to see what a run would do before '
        'doing it. Appends to trees.GrowthSimulations, which accumulates -- running it '
        'twice gives two comparable runs, not a corrupted one. A promoting run refuses '
        'variant names that already exist in the target scenario: use no_promote=true to '
        'record a trajectory for comparison without touching the chain Unreal reads, or '
        'replace=true only when you do mean to overwrite it.'
WHERE workflow_key = 'silva';
