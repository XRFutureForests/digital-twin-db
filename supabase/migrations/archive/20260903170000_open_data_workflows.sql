-- =============================================================================
-- Put the open-data refreshes on the job queue -- the ones that can actually run
-- unattended
-- =============================================================================
-- XRFF-380. The open-data connector should be triggered through the XRFF-346
-- control plane rather than growing a scheduler of its own. A workflow is
-- *declared* here (`workflow_key` + `param_schema`, public) and *defined* in
-- `config/workflows.toml` on the host (private, gitignored, holds the command).
-- The runner claims a job only when the key appears in both, which is what makes
-- a command string in the database impossible.
--
-- Why five keys and not the three the issue proposed
-- --------------------------------------------------
-- XRFF-380 asked for `open-data-static`, `open-data-weather` and
-- `open-data-scenarios`, each covering a group of sources. The connector's CLI
-- fetches **one source for one location** per invocation (`open-data fetch
-- --source X --location N`), so a grouped key would need either a new CLI verb
-- or the source passed as a parameter.
--
-- Checking `open-data sources` -- which prints each source's declared contract
-- (XRFF-393) -- settles it, and rules out `open-data-static` entirely:
--
--   eu-dtm                file      requires --dem <path>
--   koppen-geiger         file      requires --layer <path>
--   thuenen-wuchsbezirke  file      requires --layer <path>
--   chelsa                file      requires --layer <path>
--   manual                operator  values arrive as --set, i.e. a human
--   soilgrids             hybrid    requires nothing
--   soilgrids-chemistry   http      requires nothing
--   ssp-co2               bundled   requires nothing
--   pvgis                 http      requires nothing
--   open-meteo            http      requires --start / --end
--
-- **Four sources require a path on the host filesystem.** Queuing them would
-- mean putting a host path in the database and handing it to a subprocess --
-- data rather than a command, but host-specific state the database has no
-- business holding, and it would make one queue unusable across several hosts.
-- Three of the four are what `open-data-static` was to have contained. So the
-- static group is not declared at all: its one runnable member, `soilgrids`,
-- gets its own key, and the file-backed sources stay a deliberate CLI-only
-- operation.
--
-- The remaining five each get one key, named for what they acquire rather than
-- who provides it -- the `aquarius-sync` / `aquarius-enrich` convention. Keys
-- sit on the source's existing `category = 'acquisition'` row, so each already
-- carries its real citation and licence, and a key moves with a version bump
-- exactly as XRFF-348 established for `silva`.
--
-- `--overwrite` is deliberately NOT declarable
-- --------------------------------------------
-- A queued job that can silently replace a stored site attribute is a footgun,
-- and `additionalProperties: false` is what keeps it out. Without the flag a
-- disagreement is reported and nothing is written, which is the right default
-- for an unattended run. Adding a site is still served: a new location has no
-- stored value to disagree with. An operator who genuinely means to overwrite
-- runs the CLI by hand.
--
-- Mirrored to init 37-open-data-workflows.sql.
-- =============================================================================

SET search_path TO shared, public;


-- open-meteo. The only one of the five that genuinely needs a schedule: a
-- nightly window of hourly weather into the virtual sensors. Both dates are
-- required because the source declares them as required inputs.
UPDATE shared.processes SET
    workflow_key = 'open-data-weather',
    param_schema = jsonb_build_object(
        'type', 'object',
        'required', jsonb_build_array('location', 'start', 'end'),
        'additionalProperties', false,
        'properties', jsonb_build_object(
            'location', jsonb_build_object(
                'type', 'integer', 'minimum', 1,
                'description', 'shared.Locations id to fetch for.'),
            'start', jsonb_build_object(
                'type', 'string', 'pattern', '^\d{4}-\d{2}-\d{2}$',
                'description', 'First day of the window, ISO date.'),
            'end', jsonb_build_object(
                'type', 'string', 'pattern', '^\d{4}-\d{2}-\d{2}$',
                'description', 'Last day of the window, ISO date.')))
WHERE process_name = 'Open data acquisition: open-meteo';


-- PVGIS. Serves 2005-2023 and nothing else, and refuses a part-year window, so
-- the bounds are constrained here too rather than only in the connector -- a bad
-- request is then refused before a job is ever queued. Both or neither.
UPDATE shared.processes SET
    workflow_key = 'open-data-radiation',
    param_schema = jsonb_build_object(
        'type', 'object',
        'required', jsonb_build_array('location'),
        'additionalProperties', false,
        'dependentRequired', jsonb_build_object(
            'start', jsonb_build_array('end'),
            'end', jsonb_build_array('start')),
        'properties', jsonb_build_object(
            'location', jsonb_build_object(
                'type', 'integer', 'minimum', 1,
                'description', 'shared.Locations id to fetch for.'),
            'start', jsonb_build_object(
                'type', 'string', 'pattern', '^20(0[5-9]|1\d|2[0-3])-01-01$',
                'description', 'Optional narrowing. Whole calendar years only, '
                               'and PVGIS serves 2005-2023: any other date is '
                               'refused. Omit both for the whole record.'),
            'end', jsonb_build_object(
                'type', 'string', 'pattern', '^20(0[5-9]|1\d|2[0-3])-12-31$',
                'description', 'Optional narrowing. Whole calendar years only, '
                               'within 2005-2023.')))
WHERE process_name = 'Open data acquisition: pvgis';


-- SSP CO2 pathways. Bundled package data: no network, no raster, and the only
-- source whose value does not vary with location -- but `--location` is still
-- required, because the row it writes is keyed to one.
UPDATE shared.processes SET
    workflow_key = 'open-data-co2',
    param_schema = jsonb_build_object(
        'type', 'object',
        'required', jsonb_build_array('location'),
        'additionalProperties', false,
        'dependentRequired', jsonb_build_object(
            'start', jsonb_build_array('end'),
            'end', jsonb_build_array('start')),
        'properties', jsonb_build_object(
            'location', jsonb_build_object(
                'type', 'integer', 'minimum', 1,
                'description', 'shared.Locations id to write the rows for.'),
            'start', jsonb_build_object(
                'type', 'string', 'pattern', '^\d{4}-\d{2}-\d{2}$',
                'description', 'Optional narrowing to one window. Omit both to '
                               'write every scenario period.'),
            'end', jsonb_build_object(
                'type', 'string', 'pattern', '^\d{4}-\d{2}-\d{2}$',
                'description', 'Optional narrowing to one window.')))
WHERE process_name = 'Open data acquisition: ssp-co2';


-- SoilGrids soil chemistry (pH, nitrogen) into the scenario zone. Takes no
-- window: the product is a single present-day property map.
UPDATE shared.processes SET
    workflow_key = 'open-data-soil-chemistry',
    param_schema = jsonb_build_object(
        'type', 'object',
        'required', jsonb_build_array('location'),
        'additionalProperties', false,
        'properties', jsonb_build_object(
            'location', jsonb_build_object(
                'type', 'integer', 'minimum', 1,
                'description', 'shared.Locations id to fetch for.')))
WHERE process_name = 'Open data acquisition: soilgrids-chemistry';


-- SoilGrids WRB class into shared.Locations. Hybrid: it queries the REST
-- endpoint when handed no layer, which is exactly the unattended path. Its
-- `--layer` option is deliberately absent from this schema -- see the note on
-- host paths above.
UPDATE shared.processes SET
    workflow_key = 'open-data-soil-class',
    param_schema = jsonb_build_object(
        'type', 'object',
        'required', jsonb_build_array('location'),
        'additionalProperties', false,
        'properties', jsonb_build_object(
            'location', jsonb_build_object(
                'type', 'integer', 'minimum', 1,
                'description', 'shared.Locations id to fetch for.')))
WHERE process_name = 'Open data acquisition: soilgrids';


-- Fail loudly if a process_name drifted -- but only about rows that exist.
--
-- The original check asserted a flat five keys, and that was wrong on a fresh
-- database: these five rows are created by the connector's ensure_process() at
-- registration time, not by any init file, so on a first build the UPDATEs
-- above match nothing, the count is 0, and init aborts with exit 3 before it
-- reaches any later file. Caught by the fresh-init test on 2026-09-09 (XRFF-427).
--
-- Counting by algorithm_name rather than by the keys themselves keeps the drift
-- detection the original was for, and adds one: a source version bump makes a
-- *second* row for the same algorithm_name that no UPDATE here will ever key,
-- so 6 rows against 5 keys now raises instead of silently shipping a workflow
-- the runner's config expects and the database no longer declares.
DO $$
DECLARE
    n_rows integer;
    n_keys integer;
BEGIN
    SELECT COUNT(*) INTO n_rows FROM shared.processes
     WHERE category = 'acquisition'
       AND algorithm_name IN ('open-meteo', 'pvgis', 'ssp-co2',
                              'soilgrids-chemistry', 'soilgrids');

    SELECT COUNT(*) INTO n_keys FROM shared.processes
     WHERE workflow_key IN ('open-data-weather', 'open-data-radiation',
                            'open-data-co2', 'open-data-soil-chemistry',
                            'open-data-soil-class');

    IF n_rows = 0 THEN
        RAISE NOTICE 'no open-data source rows yet -- fresh database. Nothing '
                     'to do here: the connector writes workflow_key and '
                     'param_schema itself when it registers its sources '
                     '(open_data/processes.py, XRFF-427). The UPDATEs above are '
                     'a backfill for rows registered before that change.';
    ELSIF n_keys <> n_rows THEN
        RAISE EXCEPTION 'expected a workflow key on each of the % open-data '
                        'source rows, found %', n_rows, n_keys;
    END IF;
END $$;
