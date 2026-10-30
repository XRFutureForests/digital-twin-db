-- =============================================================================
-- Soil moisture and temperature aggregates, derived from the twin's own sensors
-- =============================================================================
-- XRFF-397. `environments.Environments.avg_soil_moisture_percent` and
-- `avg_soil_temperature_c` are NULL, while the twin already holds 35 M readings
-- from 1,280 soil sensors. Aggregating them into a period row turns an existing,
-- unexploited asset into the *measured* counterpart of the acquired climate
-- rows, and gives the projections something observed to be compared against.
--
-- ## Why this is a database function and not an open-data source
--
-- The issue asked the question and the schema answers it. Every other writer of
-- these rows fetches from outside and writes in; this one reads the twin and
-- writes back, so it has no provider, no licence, no citation, no coverage
-- polygon, no input file and no endpoint -- which is nearly every field of the
-- connector's source contract, all of them fictions. It also cannot live in a
-- connector for a plainer reason: aggregating 35 M readings means shipping them
-- over PostgREST first.
--
-- The schema already had both slots waiting:
--
--   shared.Processes.category   = 'aggregation'  (as opposed to 'acquisition')
--   shared.VariantTypes id 6    = 'sensor_derived'
--                                 "Aggregated or derived from sensor readings"
--
-- A view was the other candidate and cannot work: the acceptance criterion is
-- that the *columns* carry a value, and a view cannot fill a column of a table.
--
-- No `workflow_key` on the process row. A runnable row is one the XRFF-346
-- runner can execute from its local workflows.toml, and the runner shells out
-- to connector CLIs -- it has no way to call a SQL function today. XRFF-380
-- decides how refreshes get triggered; adding the key here would put a workflow
-- on the menu that nothing can run.
--
-- ## The aggregation, stated rather than implied
--
-- Four nested means, each level giving its members equal weight:
--
--   1. per sensor per day   -- so a sensor logging every minute does not
--                              outvote one logging hourly
--   2. across sensors, per day
--   3. across days, per quarter
--   4. across the four quarters -> the value written
--
-- The nesting is not decoration. The readings arrive in four month-long
-- windows, one per quarter, and their volumes differ by up to a factor of ten
-- between windows (14.9 M readings in Q2 against 1.4 M in Q4 for soil
-- temperature). A flat mean over all readings is therefore weighted by
-- *sampling density*, not by time: it returns 10.75 degC where the balanced
-- mean is 10.59, and the difference is an artefact of when the loggers happened
-- to be busy. The quarterly profile the balanced form produces -- 4.18, 10.76,
-- 16.69, 10.71 degC -- is a plain annual soil-temperature cycle; the flat one
-- flattens it.
--
-- ## What is refused rather than guessed
--
--   * **A year missing a quarter.** Four quarters of at least
--     `p_min_days_per_quarter` measured days each, or no row. A mean over a
--     year that is 60% summer is a summer mean wearing a year's label, and
--     nothing downstream could tell.
--   * **Mixed units.** 129 soil-moisture sensors declare `m^3/m^3` and 507
--     declare `%`. Today only the `%` ones have readings, so a mean is
--     unit-safe by accident; the day one of the others reports, averaging 0.22
--     with 22 would produce a number no instrument measured. A location-year
--     whose sensors of one type disagree on the unit is skipped, and says so.
--   * **Values outside the type's declared range.** `sensor.SensorTypes`
--     already carries `typical_range_min`/`max` (-20..40 degC, 0..100 %), and
--     the readings contain -999 and -100 sentinels and negative water contents.
--     That column is the filter -- a threshold the database already published,
--     rather than one invented here. It removes 0.10% of moisture readings and
--     0.0098% of temperature ones.
--
-- ## Depth is not recorded, and the row says so
--
-- The issue asked for a depth-weighted aggregate, as SoilGrids chemistry does
-- over 0-30 cm. It cannot be done: `installation_height_m` is NULL on all 1,280
-- soil sensors and their `external_metadata` carries only a label, a parameter
-- name and a site identifier. The value is therefore a mean across whatever
-- depths the network happens to sit at, which the row's description states
-- outright rather than leaving a reader to assume a profile.
--
-- Idempotent: safe to re-run, and re-running refreshes the same rows.
-- =============================================================================


-- =============================================================================
-- PART 1 -- the provenance row
-- =============================================================================
-- `aggregation`, not `acquisition`: nothing was fetched. No citation, because
-- there is no external work to cite -- the inputs are the lab's own sensors,
-- and the method is described here.
-- =============================================================================

INSERT INTO shared.Processes
    (process_name, algorithm_name, version, category, author, description)
VALUES (
    'Soil Aggregates from Sensor Readings',
    'Quarter-balanced nested mean over sensor.SensorReadings',
    '1.0',
    'aggregation',
    'XR Future Forests Lab',
    'Mean soil moisture and soil temperature for a location and year, derived '
    'from the twin own sensor readings. Four nested means give equal weight to '
    'each sensor within a day, each day within a quarter, and each quarter '
    'within the year, so the value is not weighted by sampling density. '
    'Readings outside the range sensor.SensorTypes declares for the quantity '
    'are excluded. A year without at least four qualifying quarters produces no '
    'row. Sensor depth is not recorded in the twin, so the value is a mean '
    'across the depths the network sits at, not a profile.')
ON CONFLICT (process_name, version) DO UPDATE SET
    algorithm_name = EXCLUDED.algorithm_name,
    category       = EXCLUDED.category,
    description    = EXCLUDED.description;


-- =============================================================================
-- PART 2 -- refresh_soil_aggregates()
-- =============================================================================
-- Returns one row per (location, year) it considered, saying what it did and --
-- for anything it did not write -- why. A caller that only counted successes
-- would not notice a site quietly dropping out of coverage, which is the
-- failure this function exists to make visible.
--
-- The two quantities are judged **separately**. A site whose moisture sensors
-- have gone quiet still has good soil temperature, and suppressing the column
-- it can support would throw away a measurement to punish a missing one. The
-- status line then names what was written and what was refused.
--
-- Writes through public.upsert_environment rather than INSERTing directly, so
-- there stays exactly one write path into environments.Environments and one
-- settable-column allowlist. The RPC merges, so a refresh cannot null out a
-- column another source filled -- including the sibling column this run
-- refused.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.refresh_soil_aggregates(
    p_location_id integer DEFAULT NULL,
    p_year integer DEFAULT NULL,
    p_min_days_per_quarter integer DEFAULT 7,
    p_dry_run boolean DEFAULT false
) RETURNS TABLE(
    out_location_id integer,
    out_year integer,
    out_start_date date,
    out_end_date date,
    out_avg_soil_moisture_percent numeric,
    out_avg_soil_temperature_c numeric,
    out_environment_id integer,
    out_status text
)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'shared', 'sensor', 'environments'
    AS $$
DECLARE
    v_process_id integer;
    v_row record;
    v_values jsonb;
    v_environment_id integer;
    v_description text;
    v_written text[];
    v_refused text[];
    v_first date;
    v_last date;
BEGIN
    SELECT process_id INTO v_process_id
      FROM shared.Processes
     WHERE process_name = 'Soil Aggregates from Sensor Readings'
       AND version = '1.0';

    IF v_process_id IS NULL THEN
        RAISE EXCEPTION 'the Soil Aggregates process row is missing -- '
                        'migration 20260903130000 did not fully apply';
    END IF;

    FOR v_row IN
        WITH reading AS (
            -- One row per accepted reading, carrying everything the nesting
            -- needs. The range filter is the sensor type's own declaration.
            SELECT s.location_id,
                   st.sensor_type_name                       AS quantity,
                   s.unit                                    AS unit,
                   r.sensor_id,
                   (r.timestamp AT TIME ZONE 'UTC')::date    AS day,
                   EXTRACT(YEAR    FROM r.timestamp AT TIME ZONE 'UTC')::integer AS yr,
                   EXTRACT(QUARTER FROM r.timestamp AT TIME ZONE 'UTC')::integer AS qtr,
                   r.value
              FROM sensor.SensorReadings r
              JOIN sensor.Sensors        s  USING (sensor_id)
              JOIN sensor.SensorTypes    st USING (sensor_type_id)
             WHERE st.sensor_type_name IN ('soil_moisture', 'soil_temperature')
               AND r.value BETWEEN st.typical_range_min AND st.typical_range_max
               AND (p_location_id IS NULL OR s.location_id = p_location_id)
               AND (p_year IS NULL
                    OR EXTRACT(YEAR FROM r.timestamp AT TIME ZONE 'UTC')::integer = p_year)
        ),
        -- Level 1: a sensor's own day.
        sensor_day AS (
            SELECT location_id, quantity, yr, qtr, day, sensor_id, avg(value) AS v
              FROM reading GROUP BY 1, 2, 3, 4, 5, 6
        ),
        -- Level 2: the day across sensors.
        day_mean AS (
            SELECT location_id, quantity, yr, qtr, day, avg(v) AS v
              FROM sensor_day GROUP BY 1, 2, 3, 4, 5
        ),
        -- Level 3: the quarter across its measured days.
        quarter_mean AS (
            SELECT location_id, quantity, yr, qtr, avg(v) AS v, count(*) AS days
              FROM day_mean GROUP BY 1, 2, 3, 4
        ),
        -- Level 4: the year across its qualifying quarters, plus the count
        -- needed to judge whether the year may be written at all.
        year_mean AS (
            SELECT location_id, quantity, yr,
                   avg(v)  FILTER (WHERE days >= p_min_days_per_quarter) AS v,
                   count(*) FILTER (WHERE days >= p_min_days_per_quarter) AS quarters
              FROM quarter_mean GROUP BY 1, 2, 3
        ),
        -- Units are checked over every reading of the quantity, not only the
        -- qualifying quarters: a second unit anywhere in the year means the
        -- series is not one series.
        units AS (
            SELECT location_id, quantity, yr, count(DISTINCT unit) AS units,
                   min(day) AS first_day, max(day) AS last_day
              FROM reading GROUP BY 1, 2, 3
        ),
        per_quantity AS (
            SELECT y.location_id, y.quantity, y.yr, y.v, y.quarters,
                   u.units, u.first_day, u.last_day
              FROM year_mean y JOIN units u USING (location_id, quantity, yr)
        )
        SELECT location_id,
               yr,
               max(v)         FILTER (WHERE quantity = 'soil_moisture')    AS moisture,
               max(quarters)  FILTER (WHERE quantity = 'soil_moisture')    AS moisture_quarters,
               max(units)     FILTER (WHERE quantity = 'soil_moisture')    AS moisture_units,
               min(first_day) FILTER (WHERE quantity = 'soil_moisture')    AS moisture_first,
               max(last_day)  FILTER (WHERE quantity = 'soil_moisture')    AS moisture_last,
               max(v)         FILTER (WHERE quantity = 'soil_temperature') AS temperature,
               max(quarters)  FILTER (WHERE quantity = 'soil_temperature') AS temperature_quarters,
               max(units)     FILTER (WHERE quantity = 'soil_temperature') AS temperature_units,
               min(first_day) FILTER (WHERE quantity = 'soil_temperature') AS temperature_first,
               max(last_day)  FILTER (WHERE quantity = 'soil_temperature') AS temperature_last
          FROM per_quantity
         GROUP BY 1, 2
         ORDER BY 1, 2
    LOOP
        out_location_id := v_row.location_id;
        out_year        := v_row.yr;
        out_environment_id := NULL;
        out_avg_soil_moisture_percent := NULL;
        out_avg_soil_temperature_c    := NULL;
        v_written := ARRAY[]::text[];
        v_refused := ARRAY[]::text[];
        v_values  := '{}'::jsonb;
        v_first   := NULL;
        v_last    := NULL;

        -- soil moisture
        IF v_row.moisture_units IS NULL THEN
            NULL;  -- the quantity is simply not measured here
        ELSIF v_row.moisture_units > 1 THEN
            v_refused := v_refused || format(
                'soil moisture: sensors report %s different units, so a mean would '
                'mix scales', v_row.moisture_units);
        ELSIF v_row.moisture_quarters < 4 THEN
            v_refused := v_refused || format(
                'soil moisture: only %s of 4 quarters have %s or more measured days, '
                'so an annual mean would be a seasonal one',
                v_row.moisture_quarters, p_min_days_per_quarter);
        ELSE
            out_avg_soil_moisture_percent := round(v_row.moisture::numeric, 3);
            v_values := v_values || jsonb_build_object(
                'avg_soil_moisture_percent', out_avg_soil_moisture_percent);
            v_written := v_written || 'soil moisture'::text;
            v_first := least(v_first, v_row.moisture_first);
            v_last  := greatest(v_last, v_row.moisture_last);
        END IF;

        -- soil temperature
        IF v_row.temperature_units IS NULL THEN
            NULL;
        ELSIF v_row.temperature_units > 1 THEN
            v_refused := v_refused || format(
                'soil temperature: sensors report %s different units, so a mean would '
                'mix scales', v_row.temperature_units);
        ELSIF v_row.temperature_quarters < 4 THEN
            v_refused := v_refused || format(
                'soil temperature: only %s of 4 quarters have %s or more measured days, '
                'so an annual mean would be a seasonal one',
                v_row.temperature_quarters, p_min_days_per_quarter);
        ELSE
            out_avg_soil_temperature_c := round(v_row.temperature::numeric, 3);
            v_values := v_values || jsonb_build_object(
                'avg_soil_temperature_c', out_avg_soil_temperature_c);
            v_written := v_written || 'soil temperature'::text;
            v_first := least(v_first, v_row.temperature_first);
            v_last  := greatest(v_last, v_row.temperature_last);
        END IF;

        IF v_values = '{}'::jsonb THEN
            out_status := 'skipped -- ' || array_to_string(v_refused, '; ');
            RETURN NEXT;
            CONTINUE;
        END IF;

        -- The window is the one the written quantities were measured over, not
        -- the calendar year they fall in and not a refused quantity's span.
        out_start_date := v_first;
        out_end_date   := v_last;

        v_description := format(
            'Measured %s at this location, %s to %s. Quarter-balanced nested mean: '
            'each sensor weighted equally within a day, each day within its quarter, '
            'each of the 4 quarters within the year, so the value is not weighted by '
            'sampling density. Readings outside the range sensor.SensorTypes declares '
            'for the quantity are excluded. Sensor depth is not recorded in the twin, '
            'so this is a mean across the depths the network sits at, not a profile.',
            array_to_string(v_written, ' and '), v_first, v_last);

        IF p_dry_run THEN
            out_status := 'dry run: ' || v_description;
            IF array_length(v_refused, 1) IS NOT NULL THEN
                out_status := out_status || ' Refused -- ' || array_to_string(v_refused, '; ');
            END IF;
            RETURN NEXT;
            CONTINUE;
        END IF;

        SELECT e.out_environment_id INTO v_environment_id
          FROM public.upsert_environment(
                   p_location_id      => v_row.location_id,
                   -- 6 = sensor_derived, "Aggregated or derived from sensor
                   -- readings". Not 7/model_output: nothing was modelled.
                   p_variant_type_id  => 6,
                   p_variant_name     => 'twin-sensors',
                   p_process_id       => v_process_id,
                   p_values           => v_values,
                   -- No scenario. This is what was measured, not a projection,
                   -- and a scenario_id would assert a pathway it does not have.
                   p_scenario_id      => NULL,
                   p_start_date       => v_first::timestamptz,
                   p_end_date         => (v_last + 1)::timestamptz - interval '1 second',
                   p_description      => v_description
               ) AS e;

        IF v_environment_id IS NULL THEN
            RAISE EXCEPTION 'upsert_environment returned no environment_id for '
                            'location % year %', v_row.location_id, v_row.yr;
        END IF;

        out_environment_id := v_environment_id;
        out_status := 'written: ' || array_to_string(v_written, ' and ');
        IF array_length(v_refused, 1) IS NOT NULL THEN
            out_status := out_status || '; refused -- ' || array_to_string(v_refused, '; ');
        END IF;
        RETURN NEXT;
    END LOOP;

    RETURN;
END;
$$;

COMMENT ON FUNCTION public.refresh_soil_aggregates(integer, integer, integer, boolean) IS
    'Derive avg_soil_moisture_percent and avg_soil_temperature_c for each '
    'location and year from the twin own sensor readings, and write them to '
    'environments.Environments under variant_name ''twin-sensors''. The value is '
    'a quarter-balanced nested mean -- equal weight per sensor within a day, per '
    'day within a quarter, per quarter within the year -- because the readings '
    'arrive in four month-long windows whose volumes differ tenfold, and a flat '
    'mean would be weighted by sampling density rather than by time. The two '
    'quantities are judged separately, so a site can contribute the column it '
    'supports. Returns one row per location-year considered, including what it '
    'refused: a quantity without four quarters of at least p_min_days_per_quarter '
    'measured days, or whose sensors disagree on the unit, is skipped with a '
    'reason rather than averaged. Idempotent.';

GRANT EXECUTE ON FUNCTION public.refresh_soil_aggregates(integer, integer, integer, boolean)
    TO authenticated, service_role;
