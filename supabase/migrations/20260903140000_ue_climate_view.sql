-- =============================================================================
-- One row per period, merged across the datasets that filled it
-- =============================================================================
-- `public.ue_environments` (20260903110000) is one row per
-- environments.Environments row, which is what a provenance reader wants: each
-- row carries the process that produced it.
--
-- That stopped being what *Unreal* wants the moment a second dataset started
-- filling a different column of the same window. XRFF-395 added the SSP CO2
-- pathways under their own `variant_name` -- deliberately, because
-- upsert_environment overwrites process_id unconditionally and a shared row's
-- surviving provenance would otherwise depend on which source ran last. The
-- consequence lands here:
--
--   GET /ue_environments?location_id=eq.1&scenario_name=eq.ssp370
--
--   variant_name | start_year | avg_temperature_c | avg_co2_ppm
--   chelsa       |       2011 |             10.85 |
--   ssp-co2      |       2011 |                   |      436.83
--   chelsa       |       2041 |             12.11 |
--   ssp-co2      |       2041 |                   |      570.92
--
-- Six half-empty rows where a scenario picker wants three full ones, and a
-- Blueprint would have to merge them itself -- in a language whose object-array
-- iteration is the reason ue_environments exists at all.
--
-- Hence this view: the same rows, grouped by the natural key **minus
-- variant_name**, with each measurement column taken from whichever dataset
-- supplied it. `ue_environments` keeps its per-row contract; this one is the
-- read a scene makes.
--
-- ## Not only climate, despite the name
--
-- The grouping is by *period*, not by topic, so the scenario-less rows come
-- through too: SoilGrids chemistry (no period at all, both years NULL) and the
-- measured soil aggregate from XRFF-397 (its own 2025 window). They are not
-- folded into the projection rows -- a permanent site property has no window to
-- join on, and asserting it belongs to 2071-2100 would be an invention.
--
-- ## When two datasets fill the same column
--
-- Today none do, and each column has exactly one writer. If that changes, the
-- value returned is `max()` -- an arbitrary pick -- so the view reports it
-- rather than hiding it: `conflicting_columns` names every column more than one
-- variant supplied a value for. An empty array is the normal state, and a
-- non-empty one means two datasets disagree about a number and somebody has to
-- decide which is right.
--
-- `variants` and `processes` carry the provenance the merge would otherwise
-- lose, so a reader can still ask where a row came from without going back to
-- ue_environments.
--
-- security_invoker: as for every view added since XRFF-378. The base tables all
-- carry SELECT for anon and authenticated, which is what makes it work.
-- =============================================================================

CREATE OR REPLACE VIEW public.ue_climate
WITH (security_invoker = on) AS
SELECT
    e.location_id,
    max(l.location_name)                                    AS location_name,
    e.scenario_id,
    max(s.scenario_name)                                    AS scenario_name,
    e.variant_type_id,
    max(vt.variant_type_name)                               AS variant_type_name,
    e.start_date,
    e.end_date,
    EXTRACT(YEAR FROM e.start_date)::integer                AS start_year,
    EXTRACT(YEAR FROM e.end_date)::integer                  AS end_year,

    max(e.avg_temperature_c)                                AS avg_temperature_c,
    max(e.avg_humidity_percent)                             AS avg_humidity_percent,
    max(e.total_precipitation_mm)                           AS total_precipitation_mm,
    max(e.avg_global_radiation_w_m2)                        AS avg_global_radiation_w_m2,
    max(e.avg_co2_ppm)                                      AS avg_co2_ppm,
    max(e.avg_wind_speed_ms)                                AS avg_wind_speed_ms,
    max(e.dominant_wind_direction_deg)                      AS dominant_wind_direction_deg,
    max(e.avg_soil_moisture_percent)                        AS avg_soil_moisture_percent,
    max(e.avg_soil_temperature_c)                           AS avg_soil_temperature_c,
    max(e.soil_ph)                                          AS soil_ph,
    max(e.nutrient_nitrogen_mg_kg)                          AS nutrient_nitrogen_mg_kg,
    max(e.nutrient_phosphorus_mg_kg)                        AS nutrient_phosphorus_mg_kg,
    max(e.nutrient_potassium_mg_kg)                         AS nutrient_potassium_mg_kg,
    max(e.stress_factor)                                    AS stress_factor,

    -- Provenance the merge would otherwise lose.
    array_agg(DISTINCT e.variant_name ORDER BY e.variant_name)          AS variants,
    array_agg(DISTINCT p.process_name ORDER BY p.process_name)
        FILTER (WHERE p.process_name IS NOT NULL)                       AS processes,
    count(*)::integer                                                   AS row_count,

    -- Empty in the normal case. A name in here means two datasets supplied the
    -- same measurement for the same window and the value above is an arbitrary
    -- one of them.
    array_remove(ARRAY[
        CASE WHEN count(e.avg_temperature_c)           > 1 THEN 'avg_temperature_c'           END,
        CASE WHEN count(e.avg_humidity_percent)        > 1 THEN 'avg_humidity_percent'        END,
        CASE WHEN count(e.total_precipitation_mm)      > 1 THEN 'total_precipitation_mm'      END,
        CASE WHEN count(e.avg_global_radiation_w_m2)   > 1 THEN 'avg_global_radiation_w_m2'   END,
        CASE WHEN count(e.avg_co2_ppm)                 > 1 THEN 'avg_co2_ppm'                 END,
        CASE WHEN count(e.avg_wind_speed_ms)           > 1 THEN 'avg_wind_speed_ms'           END,
        CASE WHEN count(e.dominant_wind_direction_deg) > 1 THEN 'dominant_wind_direction_deg' END,
        CASE WHEN count(e.avg_soil_moisture_percent)   > 1 THEN 'avg_soil_moisture_percent'   END,
        CASE WHEN count(e.avg_soil_temperature_c)      > 1 THEN 'avg_soil_temperature_c'      END,
        CASE WHEN count(e.soil_ph)                     > 1 THEN 'soil_ph'                     END,
        CASE WHEN count(e.nutrient_nitrogen_mg_kg)     > 1 THEN 'nutrient_nitrogen_mg_kg'     END,
        CASE WHEN count(e.nutrient_phosphorus_mg_kg)   > 1 THEN 'nutrient_phosphorus_mg_kg'   END,
        CASE WHEN count(e.nutrient_potassium_mg_kg)    > 1 THEN 'nutrient_potassium_mg_kg'    END,
        CASE WHEN count(e.stress_factor)               > 1 THEN 'stress_factor'               END
    ], NULL)                                                            AS conflicting_columns
FROM environments.environments e
    JOIN      shared.locations    l  ON l.location_id      = e.location_id
    LEFT JOIN shared.scenarios    s  ON s.scenario_id      = e.scenario_id
    LEFT JOIN shared.varianttypes vt ON vt.variant_type_id = e.variant_type_id
    LEFT JOIN shared.processes    p  ON p.process_id       = e.process_id
GROUP BY e.location_id, e.scenario_id, e.variant_type_id, e.start_date, e.end_date;

COMMENT ON VIEW public.ue_climate IS
'environments.Environments merged across variant_name: one row per location, scenario, variant '
'type and period, with each measurement column taken from whichever dataset supplied it. This is '
'the read a scene makes -- ue_environments returns one row per dataset, which since XRFF-395 means '
'two half-empty rows per window where a scenario picker wants one full one. `variants` and '
'`processes` carry the provenance the merge folds away; `conflicting_columns` is empty unless two '
'datasets supplied the same measurement for the same window, in which case the value shown is an '
'arbitrary one of them. Despite the name it also returns the scenario-less rows -- soil chemistry '
'(both years NULL) and the measured soil aggregate -- because the grouping is by period, not by '
'topic. GET /rest/v1/ue_climate?location_id=eq.1&scenario_name=eq.ssp370&order=start_year';

GRANT SELECT ON public.ue_climate TO anon, authenticated, service_role;
