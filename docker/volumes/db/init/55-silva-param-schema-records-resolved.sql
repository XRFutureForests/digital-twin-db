-- Mirrored from supabase/migrations/20260923170000_silva_param_schema_records_resolved.sql.
-- Keep the two identical.
-- =============================================================================
-- silva param_schema: declare the three parameters its runs actually record
-- =============================================================================
-- XRFF-504. Found by test_ro_crate.py::test_reproducibility_parameters_present,
-- which asserts every key in a run's run_params is declared in the workflow's
-- param_schema. It has been failing since 2026-09-14.
--
-- XRFF-436 added three keys to what silva-connector writes without extending the
-- declared schema:
--
--   management_regime   the regime NAME the run resolved to
--   climate_pathway     the pathway NAME the run resolved to
--   climate_periods     the per-period climate deltas actually applied
--
-- THE TEST IS RIGHT, AND SO IS THE CONNECTOR. run_params holds what a run used,
-- which is the declared inputs *plus* what those inputs resolved to. `regime`
-- and `climate` are the inputs; these three are the resolution. Both belong in
-- the record -- scripts/provenance/emit_ro_crate.py emits the declared
-- parameters as the run's reproducibility record, so an undeclared key is a
-- parameter the crate silently omits while claiming to list them. 17 crates
-- would have been incomplete in a way nothing reported.
--
-- So they are declared, and marked readOnly: recorded by the run, not offered by
-- the job menu. web/jobs/index.html skips readOnly properties when building its
-- form, so the trigger page is unchanged; without that it would have grown three
-- fields nobody can usefully set.
--
-- Mirror of the migration of the same name.
-- =============================================================================

SET search_path TO shared, public;

UPDATE shared.processes
SET param_schema = jsonb_set(
    param_schema,
    '{properties}',
    (param_schema -> 'properties')
    || jsonb_build_object(
        'management_regime', jsonb_build_object(
            'type', 'string',
            'readOnly', true,
            'description',
            'Recorded, not set: the shared.management_regimes.management_regime_name '
            'the run resolved `regime` to. Written by silva-connector so the run '
            'record names the regime that was applied rather than the request.'),
        'climate_pathway', jsonb_build_object(
            'type', 'string',
            'readOnly', true,
            'description',
            'Recorded, not set: the shared.climate_pathways.climate_pathway_name '
            'the run resolved `climate` to.'),
        'climate_periods', jsonb_build_object(
            'type', 'array',
            'readOnly', true,
            'description',
            'Recorded, not set: one entry per projection period, each carrying the '
            'year and the site-property deltas applied for it. This is what makes a '
            'climate-driven run reproducible -- without it the crate records which '
            'pathway was asked for but not what was actually applied.')
    )
)
WHERE workflow_key = 'silva';

COMMENT ON COLUMN shared.processes.param_schema IS
    'JSON Schema for the workflow''s run_params. Properties marked "readOnly": '
    'true are recorded by the run rather than offered by the job menu -- '
    'web/jobs skips them when building its form, and emit_ro_crate includes them '
    'in the reproducibility record. Every key a run writes into run_params must '
    'be declared here; tests/automated/e2e/provenance/test_ro_crate.py asserts it.';
