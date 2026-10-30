-- =============================================================================
-- DB foundation for open-data acquisition: provenance, two zone write RPCs
-- =============================================================================
-- XRFF-369 (child of XRFF-368). Also lands the `param_schema` column from
-- XRFF-348, because it is the same table as PART 1 and doing it now avoids a
-- second pass over shared.Processes.
--
-- The open-data connector is the fourth member of the connector family
-- (aquarius-connector, silva-connector, pylometree): it fetches from external
-- systems and writes to the twin *only* through public RPCs -- no DB
-- credentials, no SQL, no package dependency on digital-twin-db.
-- public.bulk_upsert_sensors / public.bulk_insert_readings already give that
-- contract to the time-series landing zone. The other two landing zones --
-- static site attributes on shared.Locations, and period aggregates in
-- environments.Environments -- had no write RPC at all, so a connector would
-- have needed raw SQL. That is what PART 4 and PART 5 fix.
--
-- Shape, grants and SECURITY DEFINER below are copied from the two existing
-- bulk RPCs deliberately, including the grant to anon. That is the established
-- contract for connector writes; this migration neither widens nor narrows it.
-- If anon write access is ever revisited it should be revisited for all four
-- functions at once, not for the two new ones.
--
-- Idempotent: safe to re-run.
-- =============================================================================


-- =============================================================================
-- PART 1 -- shared.Processes: an `acquisition` category, and param_schema
-- =============================================================================
-- The category CHECK allowed detection | classification | simulation | analysis
-- | aggregation. Fetching ERA5 or SoilGrids is none of those, and filing it
-- under `aggregation` would make the provenance registry lie about what those
-- rows are -- which matters because this database is published and these rows
-- are what carry the licence and citation of every acquired value.
--
-- param_schema (XRFF-348) is the JSON Schema describing the parameters a
-- workflow accepts. XRFF-348's other two deliverables -- seed rows for the
-- existing workflows, and a view listing them for Studio and UE -- stay with
-- that issue; only the column belongs here.
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

COMMENT ON COLUMN shared.Processes.category IS
    'What kind of step this is. `acquisition` (added 2026-09-02, XRFF-369) is a '
    'fetch from an external open-data source -- ERA5, SoilGrids, a Thuenen '
    'layer -- as opposed to a computation over data already held.';

COMMENT ON COLUMN shared.Processes.param_schema IS
    'JSON Schema for the parameters this process accepts, so a caller can be '
    'told what a workflow needs without reading its code. Never holds a command '
    'line or a host path: what a workflow *does* is defined only in the '
    'runner private config, so the database can name a workflow but never '
    'define it.';


-- =============================================================================
-- PART 2 -- shared.AttributeProvenance
-- =============================================================================
-- environments.Environments carries a process_id FK; shared.Locations carries
-- nothing. Once elevation comes from a DEM and soil pH from SoilGrids v2.0
-- rather than from a forester, the twin has to be able to say which, per
-- column.
--
-- A table rather than N `*_source` columns on shared.Locations: the alternative
-- is three columns (source, fetched_at, licence) per attribute, which is a
-- schema change every time a source is added and leaves ~24 mostly-NULL columns
-- on a two-row table. One row per (location, column) instead, replaced on
-- refresh.
--
-- UNIQUE (location_id, column_name) is what makes set_location_attributes
-- idempotent -- the same structural device as ON CONFLICT (external_id) in
-- bulk_upsert_sensors.
-- =============================================================================

CREATE TABLE IF NOT EXISTS shared.AttributeProvenance (
    attribute_provenance_id serial PRIMARY KEY,
    location_id  integer NOT NULL,
    column_name  character varying(64) NOT NULL,
    process_id   integer NOT NULL,
    fetched_at   timestamp with time zone NOT NULL DEFAULT now(),
    source_uri   text,
    license      character varying(100),
    CONSTRAINT attributeprovenance_location_column_key UNIQUE (location_id, column_name)
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'attributeprovenance_location_id_fkey') THEN
        ALTER TABLE ONLY shared.AttributeProvenance
            ADD CONSTRAINT attributeprovenance_location_id_fkey
            FOREIGN KEY (location_id) REFERENCES shared.Locations(location_id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'attributeprovenance_process_id_fkey') THEN
        ALTER TABLE ONLY shared.AttributeProvenance
            ADD CONSTRAINT attributeprovenance_process_id_fkey
            FOREIGN KEY (process_id) REFERENCES shared.Processes(process_id) ON DELETE RESTRICT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_attributeprovenance_process
    ON shared.AttributeProvenance (process_id);

COMMENT ON TABLE shared.AttributeProvenance IS
    'Where each value in a shared.Locations column came from: one row per '
    '(location, column), replaced when the value is refreshed. Written by '
    'public.set_location_attributes in the same transaction as the value '
    'itself, so an attribute cannot be updated without saying what produced it.';
COMMENT ON COLUMN shared.AttributeProvenance.column_name IS
    'Name of the shared.Locations column this row describes. Not FK-checkable; '
    'the allowed set is enforced by public.set_location_attributes, which is '
    'the only writer.';
COMMENT ON COLUMN shared.AttributeProvenance.process_id IS
    'shared.Processes row for the source -- its name, version, licence and '
    'citation. NOT NULL: an acquired value with no registered source is exactly '
    'what this table exists to prevent.';
COMMENT ON COLUMN shared.AttributeProvenance.fetched_at IS
    'When the value was retrieved from the source, which is not the same as '
    'when the source published it (shared.Processes.publication_date) nor when '
    'the row was written.';
COMMENT ON COLUMN shared.AttributeProvenance.source_uri IS
    'Direct reference to the fetched artefact -- API request URL, DOI, or file '
    'identifier -- so a value can be traced to one retrieval, not just to a '
    'dataset.';
COMMENT ON COLUMN shared.AttributeProvenance.license IS
    'Licence of the source value, e.g. CC-BY-4.0, Copernicus. Carried per value '
    'because this database is published and the attribution requirements travel '
    'with the data.';

GRANT SELECT ON TABLE shared.AttributeProvenance TO anon;
GRANT SELECT ON TABLE shared.AttributeProvenance TO authenticated;
GRANT ALL    ON TABLE shared.AttributeProvenance TO service_role;

GRANT USAGE ON SEQUENCE shared.attributeprovenance_attribute_provenance_id_seq
    TO authenticated, service_role;

ALTER TABLE shared.AttributeProvenance ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'shared' AND tablename = 'attributeprovenance'
                     AND policyname = 'Attribute provenance is viewable by everyone') THEN
        CREATE POLICY "Attribute provenance is viewable by everyone"
            ON shared.AttributeProvenance FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'shared' AND tablename = 'attributeprovenance'
                     AND policyname = 'Contributors can record attribute provenance') THEN
        CREATE POLICY "Contributors can record attribute provenance"
            ON shared.AttributeProvenance FOR INSERT TO authenticated
            WITH CHECK (shared.is_contributor());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'shared' AND tablename = 'attributeprovenance'
                     AND policyname = 'Contributors can update attribute provenance') THEN
        CREATE POLICY "Contributors can update attribute provenance"
            ON shared.AttributeProvenance FOR UPDATE TO authenticated
            USING (shared.is_contributor()) WITH CHECK (shared.is_contributor());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'shared' AND tablename = 'attributeprovenance'
                     AND policyname = 'Curators can delete attribute provenance') THEN
        CREATE POLICY "Curators can delete attribute provenance"
            ON shared.AttributeProvenance FOR DELETE TO authenticated
            USING (shared.is_curator());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE schemaname = 'shared' AND tablename = 'attributeprovenance'
                     AND policyname = 'Service role can manage all attribute provenance') THEN
        CREATE POLICY "Service role can manage all attribute provenance"
            ON shared.AttributeProvenance TO service_role USING (true) WITH CHECK (true);
    END IF;
END $$;

-- PostgREST reaches `shared` only under an explicit Accept-Profile header, so
-- provenance would be invisible to every default-profile client without this
-- view. security_invoker is on -- the caller's RLS applies, which is why the
-- base-table SELECT grants above are not optional (the XRFF-378 lesson).
CREATE OR REPLACE VIEW public.attributeprovenance
WITH (security_invoker = on) AS
 SELECT ap.attribute_provenance_id,
        ap.location_id,
        l.location_name,
        ap.column_name,
        ap.process_id,
        p.process_name,
        p.version AS process_version,
        p.citation,
        ap.fetched_at,
        ap.source_uri,
        ap.license
   FROM shared.attributeprovenance ap
   JOIN shared.locations l ON l.location_id = ap.location_id
   JOIN shared.processes p ON p.process_id  = ap.process_id;

COMMENT ON VIEW public.attributeprovenance IS
    'Where every acquired shared.Locations value came from, with the name, '
    'version and citation of the source resolved from shared.Processes.';

GRANT SELECT ON TABLE public.attributeprovenance TO anon, authenticated;
GRANT ALL    ON TABLE public.attributeprovenance TO service_role;


-- =============================================================================
-- PART 3 -- the natural key environments.Environments never had
-- =============================================================================
-- The table has a surrogate PK and no unique constraint, so nothing stops two
-- rows describing the same (location, scenario, variant, period) and there is
-- no conflict target for an idempotent upsert. A nightly refresh that
-- double-writes is worse than no refresh, so the key is made structural rather
-- than left to the caller to respect.
--
-- NULLS NOT DISTINCT (PG15) is required, not cosmetic: scenario_id, start_date
-- and end_date are all nullable, and under the default NULLS DISTINCT two
-- refreshes of an open-ended, scenario-less row would never collide and would
-- insert twice.
--
-- Free to add: the table is empty (verified 2026-09-02).
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_environments_natural_key
    ON environments.Environments
       (location_id, scenario_id, variant_type_id, variant_name, start_date, end_date)
    NULLS NOT DISTINCT;

COMMENT ON INDEX environments.uq_environments_natural_key IS
    'Natural key of an environment row, and the conflict target of '
    'public.upsert_environment. variant_name is part of it so that two '
    'differently-named projections of the same period stay distinct rows.';


-- =============================================================================
-- PART 4 -- public.set_location_attributes
-- =============================================================================
-- The static-site-attribute landing zone. Patches shared.Locations columns and
-- writes the matching shared.AttributeProvenance rows in the same transaction,
-- so a value and its source can never disagree.
--
-- p_process_id is required. Registering the source in shared.Processes first is
-- the price of writing an attribute, and it is what carries the licence and
-- citation into a published database.
--
-- An unknown or non-settable key raises rather than being skipped: a connector
-- running unattended under the XRFF-346 runner learns about a typo from a
-- non-zero exit code, not from a value that silently never arrived. This is the
-- same reasoning as the exit-code contract in AGENTS.md.
--
-- The allowlist is deliberately narrow. It is the set of site attributes an
-- external dataset can legitimately supply; identity, geometry and audit
-- columns are not settable through this path at all.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_location_attributes(
    p_location_id integer,
    p_attributes  jsonb,
    p_process_id  integer,
    p_source_uri  text DEFAULT NULL,
    p_license     character varying DEFAULT NULL,
    p_fetched_at  timestamp with time zone DEFAULT now()
) RETURNS TABLE(out_written_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'shared'
    AS $$
DECLARE
    c_settable CONSTANT text[] := ARRAY[
        'elevation_m', 'slope_deg', 'aspect',
        'soil_type_id', 'climate_zone_id',
        'forest_growth_region', 'soil_moistness', 'soil_nutrient_supply'
    ];
    v_rejected text[];
    v_column   text;
    v_type     text;
    v_count    integer := 0;
BEGIN
    IF p_attributes IS NULL OR jsonb_typeof(p_attributes) <> 'object' THEN
        RAISE EXCEPTION 'p_attributes must be a JSON object, got %',
            COALESCE(jsonb_typeof(p_attributes), 'null');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM shared.locations WHERE location_id = p_location_id) THEN
        RAISE EXCEPTION 'no such location: %', p_location_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'no such process: % -- register the source in shared.Processes first',
            p_process_id;
    END IF;

    SELECT array_agg(k ORDER BY k) INTO v_rejected
      FROM jsonb_object_keys(p_attributes) AS k
     WHERE k <> ALL (c_settable);

    IF v_rejected IS NOT NULL THEN
        RAISE EXCEPTION 'not settable through set_location_attributes: % (settable: %)',
            array_to_string(v_rejected, ', '), array_to_string(c_settable, ', ');
    END IF;

    FOR v_column IN SELECT k FROM jsonb_object_keys(p_attributes) AS k ORDER BY k
    LOOP
        SELECT format_type(a.atttypid, a.atttypmod) INTO v_type
          FROM pg_attribute a
         WHERE a.attrelid = 'shared.locations'::regclass
           AND a.attname  = v_column
           AND a.attnum > 0 AND NOT a.attisdropped;

        -- The cast is to the column's own declared type, so a bad value fails
        -- here rather than being coerced into something plausible.
        EXECUTE format('UPDATE shared.locations SET %I = $1::%s WHERE location_id = $2',
                       v_column, v_type)
          USING p_attributes ->> v_column, p_location_id;

        INSERT INTO shared.attributeprovenance
            (location_id, column_name, process_id, fetched_at, source_uri, license)
        VALUES (p_location_id, v_column, p_process_id, p_fetched_at, p_source_uri, p_license)
        ON CONFLICT (location_id, column_name) DO UPDATE SET
            process_id = EXCLUDED.process_id,
            fetched_at = EXCLUDED.fetched_at,
            source_uri = EXCLUDED.source_uri,
            license    = EXCLUDED.license;

        v_count := v_count + 1;
    END LOOP;

    RETURN QUERY SELECT v_count;
END;
$$;

COMMENT ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone) IS
    'Sets site attributes on one shared.Locations row from an open-data source '
    'and records where each came from, atomically. p_attributes is a JSON '
    'object of column name to value, restricted to elevation_m, slope_deg, '
    'aspect, soil_type_id, climate_zone_id, forest_growth_region, '
    'soil_moistness and soil_nutrient_supply; any other key raises. Idempotent: '
    're-running with the same input leaves one provenance row per column. '
    'Returns the number of columns written.';

GRANT ALL ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone) TO postgres;
GRANT ALL ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.set_location_attributes(integer, jsonb, integer, text, character varying, timestamp with time zone) TO service_role;


-- =============================================================================
-- PART 5 -- public.upsert_environment
-- =============================================================================
-- The period-aggregate / scenario landing zone: one environments.Environments
-- row per (location, scenario, variant type, variant name, period). A CMIP6
-- SSP2-4.5 mean for 2041-2070 is one call; no new schema is needed for a
-- climate scenario because this table was built for exactly that.
--
-- Merge, not replace: a measurement key that is absent from p_values leaves the
-- stored value alone, so two sources can populate different columns of the same
-- period row without erasing each other. The cost is that this RPC cannot set a
-- value back to NULL; deleting the row is how you reset one.
--
-- Provenance is p_process_id, which the table already carries as an FK -- the
-- licence and citation of the dataset live on that shared.Processes row. It is
-- required here for the same reason as in set_location_attributes.
--
-- The temporal window is not optional bookkeeping: an avg_temperature_c with no
-- start_date/end_date is uninterpretable later, and the aggregation method
-- belongs in the shared.Processes row.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.upsert_environment(
    p_location_id     integer,
    p_variant_type_id integer,
    p_variant_name    character varying,
    p_process_id      integer,
    p_values          jsonb DEFAULT '{}'::jsonb,
    p_scenario_id     integer DEFAULT NULL,
    p_start_date      timestamp with time zone DEFAULT NULL,
    p_end_date        timestamp with time zone DEFAULT NULL,
    p_description     text DEFAULT NULL
) RETURNS TABLE(out_environment_id integer, out_inserted boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'shared', 'environments'
    AS $$
DECLARE
    c_settable CONSTANT text[] := ARRAY[
        'avg_temperature_c', 'avg_humidity_percent', 'total_precipitation_mm',
        'avg_global_radiation_w_m2', 'avg_co2_ppm', 'avg_wind_speed_ms',
        'dominant_wind_direction_deg', 'avg_soil_moisture_percent',
        'avg_soil_temperature_c', 'soil_ph', 'nutrient_nitrogen_mg_kg',
        'nutrient_phosphorus_mg_kg', 'nutrient_potassium_mg_kg', 'stress_factor'
    ];
    v_rejected text[];
BEGIN
    IF p_values IS NULL OR jsonb_typeof(p_values) <> 'object' THEN
        RAISE EXCEPTION 'p_values must be a JSON object, got %',
            COALESCE(jsonb_typeof(p_values), 'null');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'no such process: % -- register the source in shared.Processes first',
            p_process_id;
    END IF;

    SELECT array_agg(k ORDER BY k) INTO v_rejected
      FROM jsonb_object_keys(p_values) AS k
     WHERE k <> ALL (c_settable);

    IF v_rejected IS NOT NULL THEN
        RAISE EXCEPTION 'not settable through upsert_environment: % (settable: %)',
            array_to_string(v_rejected, ', '), array_to_string(c_settable, ', ');
    END IF;

    RETURN QUERY
    INSERT INTO environments.environments AS e (
        location_id, scenario_id, variant_type_id, variant_name,
        start_date, end_date, process_id, description,
        avg_temperature_c, avg_humidity_percent, total_precipitation_mm,
        avg_global_radiation_w_m2, avg_co2_ppm, avg_wind_speed_ms,
        dominant_wind_direction_deg, avg_soil_moisture_percent,
        avg_soil_temperature_c, soil_ph, nutrient_nitrogen_mg_kg,
        nutrient_phosphorus_mg_kg, nutrient_potassium_mg_kg, stress_factor
    )
    SELECT p_location_id, p_scenario_id, p_variant_type_id, p_variant_name,
           p_start_date, p_end_date, p_process_id, p_description,
           v.avg_temperature_c, v.avg_humidity_percent, v.total_precipitation_mm,
           v.avg_global_radiation_w_m2, v.avg_co2_ppm, v.avg_wind_speed_ms,
           v.dominant_wind_direction_deg, v.avg_soil_moisture_percent,
           v.avg_soil_temperature_c, v.soil_ph, v.nutrient_nitrogen_mg_kg,
           v.nutrient_phosphorus_mg_kg, v.nutrient_potassium_mg_kg, v.stress_factor
      FROM jsonb_populate_record(NULL::environments.environments, p_values) AS v
    ON CONFLICT (location_id, scenario_id, variant_type_id, variant_name, start_date, end_date)
    DO UPDATE SET
        process_id                  = EXCLUDED.process_id,
        description                 = COALESCE(EXCLUDED.description,                 e.description),
        avg_temperature_c           = COALESCE(EXCLUDED.avg_temperature_c,           e.avg_temperature_c),
        avg_humidity_percent        = COALESCE(EXCLUDED.avg_humidity_percent,        e.avg_humidity_percent),
        total_precipitation_mm      = COALESCE(EXCLUDED.total_precipitation_mm,      e.total_precipitation_mm),
        avg_global_radiation_w_m2   = COALESCE(EXCLUDED.avg_global_radiation_w_m2,   e.avg_global_radiation_w_m2),
        avg_co2_ppm                 = COALESCE(EXCLUDED.avg_co2_ppm,                 e.avg_co2_ppm),
        avg_wind_speed_ms           = COALESCE(EXCLUDED.avg_wind_speed_ms,           e.avg_wind_speed_ms),
        dominant_wind_direction_deg = COALESCE(EXCLUDED.dominant_wind_direction_deg, e.dominant_wind_direction_deg),
        avg_soil_moisture_percent   = COALESCE(EXCLUDED.avg_soil_moisture_percent,   e.avg_soil_moisture_percent),
        avg_soil_temperature_c      = COALESCE(EXCLUDED.avg_soil_temperature_c,      e.avg_soil_temperature_c),
        soil_ph                     = COALESCE(EXCLUDED.soil_ph,                     e.soil_ph),
        nutrient_nitrogen_mg_kg     = COALESCE(EXCLUDED.nutrient_nitrogen_mg_kg,     e.nutrient_nitrogen_mg_kg),
        nutrient_phosphorus_mg_kg   = COALESCE(EXCLUDED.nutrient_phosphorus_mg_kg,   e.nutrient_phosphorus_mg_kg),
        nutrient_potassium_mg_kg    = COALESCE(EXCLUDED.nutrient_potassium_mg_kg,    e.nutrient_potassium_mg_kg),
        stress_factor               = COALESCE(EXCLUDED.stress_factor,               e.stress_factor)
    RETURNING e.environment_id, (e.xmax = 0);
END;
$$;

COMMENT ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text) IS
    'Creates or refreshes the one environments.Environments row for a '
    '(location, scenario, variant type, variant name, period) and records the '
    'producing process. p_values is a JSON object of measurement column to '
    'value; any other key raises. Absent keys leave the stored value alone, so '
    'two sources can fill different columns of the same period. Idempotent: '
    'calling twice with identical input leaves exactly one row. Returns the '
    'environment_id and whether the row was newly inserted.';

GRANT ALL ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text) TO postgres;
GRANT ALL ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text) TO anon;
GRANT ALL ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text) TO authenticated;
GRANT ALL ON FUNCTION public.upsert_environment(integer, integer, character varying, integer, jsonb, integer, timestamp with time zone, timestamp with time zone, text) TO service_role;


-- =============================================================================
-- Report
-- =============================================================================
DO $$
DECLARE
    n_categories INT;
    n_prov       INT;
    n_rpcs       INT;
BEGIN
    SELECT count(*) INTO n_categories
      FROM unnest(ARRAY['detection', 'classification', 'simulation',
                        'analysis', 'aggregation', 'acquisition']) AS c
     WHERE pg_get_constraintdef(
             (SELECT oid FROM pg_constraint WHERE conname = 'processes_category_check')
           ) LIKE '%' || c || '%';

    SELECT count(*) INTO n_prov FROM shared.attributeprovenance;

    SELECT count(*) INTO n_rpcs
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('set_location_attributes', 'upsert_environment');

    RAISE NOTICE 'XRFF-369: % of 6 process categories allowed, % provenance rows, % of 2 zone RPCs present',
        n_categories, n_prov, n_rpcs;
END $$;
