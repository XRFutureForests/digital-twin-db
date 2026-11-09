-- =============================================================================
-- A flat, named view of environments.Environments for Unreal
-- =============================================================================
-- XRFF-372 fills environments.Environments with acquired climate: one row per
-- location, pathway and 30-year window, plus the scenario-less rows that carry
-- permanent site chemistry. Reading that table from Blueprint means three joins
-- to turn scenario_id, variant_type_id and process_id into text, and Blueprint's
-- object-array iteration is unreliable enough that the joins belong in SQL.
--
-- Hence this view: every column a scalar, every id accompanied by its name, and
-- the period exposed twice -- as the timestamps the column stores and as plain
-- integer years, because a year is what a scenario picker actually offers and
-- parsing a timestamptz in Blueprint to get one is pure friction.
--
-- ## Why security_invoker
--
-- Without it a view runs as its owner and hands every caller the owner's
-- visibility, which silently defeats the RLS on the base tables. XRFF-378 set
-- it on the four views that predate this one; a new view starts with it.
--
-- The lesson from that pass applies here and was checked before writing this:
-- security_invoker needs the *base tables* to be readable by the calling role,
-- not just the view. Two views in XRFF-378 had no base-table grants and broke
-- outright when the flag went on. All five tables below carry SELECT for anon
-- and authenticated, so this view works for both.
--
-- ## Reading it from Unreal
--
--   GET /rest/v1/ue_environments?location_id=eq.1&scenario_name=eq.ssp370&order=start_year
--   GET /rest/v1/ue_environments?location_id=eq.1&scenario_name=is.null
--
-- A NULL scenario_name is not a gap. It means the row is not a projection: the
-- CHELSA 1981-2010 observed climatology and the SoilGrids soil chemistry are
-- both scenario-less by construction, and labelling them would assert a pathway
-- neither has. Tell them apart by variant_name.

CREATE OR REPLACE VIEW public.ue_environments
WITH (security_invoker = on) AS
SELECT
    e.environment_id,
    e.location_id,
    l.location_name,
    e.scenario_id,
    s.scenario_name,
    e.variant_type_id,
    vt.variant_type_name,
    e.variant_name,
    e.start_date,
    e.end_date,
    EXTRACT(YEAR FROM e.start_date)::integer AS start_year,
    EXTRACT(YEAR FROM e.end_date)::integer   AS end_year,
    e.avg_temperature_c,
    e.avg_humidity_percent,
    e.total_precipitation_mm,
    e.avg_global_radiation_w_m2,
    e.avg_co2_ppm,
    e.avg_wind_speed_ms,
    e.dominant_wind_direction_deg,
    e.avg_soil_moisture_percent,
    e.avg_soil_temperature_c,
    e.soil_ph,
    e.nutrient_nitrogen_mg_kg,
    e.nutrient_phosphorus_mg_kg,
    e.nutrient_potassium_mg_kg,
    e.stress_factor,
    e.description,
    e.process_id,
    p.process_name,
    p.version  AS process_version,
    p.citation AS process_citation
FROM environments.environments e
    JOIN      shared.locations    l  ON l.location_id      = e.location_id
    LEFT JOIN shared.scenarios    s  ON s.scenario_id      = e.scenario_id
    LEFT JOIN shared.varianttypes vt ON vt.variant_type_id = e.variant_type_id
    LEFT JOIN shared.processes    p  ON p.process_id       = e.process_id;

COMMENT ON VIEW public.ue_environments IS
'environments.Environments with its location, scenario, variant type and process joined to text, '
'for Unreal. Every column is a scalar and the period is exposed as integer years as well as '
'timestamps. A NULL scenario_name means the row is not a projection (an observed climatology or a '
'permanent site property), not that a pathway is missing -- variant_name says which dataset it is. '
'GET /rest/v1/ue_environments?location_id=eq.1&scenario_name=eq.ssp370&order=start_year';

GRANT SELECT ON public.ue_environments TO anon, authenticated, service_role;
