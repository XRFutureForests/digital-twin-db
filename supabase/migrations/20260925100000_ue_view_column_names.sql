-- =============================================================================
-- ue_* views: rename the remaining view-layer columns to the naming convention
-- =============================================================================
-- XRFF-485 (view half) + XRFF-490 (ue_trees.competition), landed together with
-- the Unreal struct update (XRFF-492) so the two sides change in one step. The
-- JSON -> struct fill in Unreal matches by field name, so a column renamed here
-- without the struct field renamed there imports as null, silently.
--
--   ue_trees            competition                 -> has_competition
--   ue_trees            management_regime           -> management_regime_name
--   ue_trees            climate_pathway             -> climate_pathway_name
--   ue_scenarios        management_regime           -> management_regime_name
--   ue_scenarios        climate_pathway             -> climate_pathway_name
--   ue_variants         management_regime           -> management_regime_name
--   ue_variants         climate_pathway             -> climate_pathway_name
--   ue_sensors          sensor_label                -> sensor_serial_number
--   ue_sensors          sensor_type                 -> sensor_type_name
--   ue_sensors          linked_tree_species         -> linked_tree_species_name
--   ue_sensors          linked_tree_scientificname  -> linked_tree_scientific_name
--   ue_sensor_readings  sensor_type                 -> sensor_type_name
--   ue_sensor_state_at  sensor_type (OUT)           -> sensor_type_name
--
-- Views: ALTER VIEW ... RENAME COLUMN, in place -- keeps owner, grants, comment,
-- triggers and security_invoker. No view depends on any of these five.
--
-- The function's result type changes, which CREATE OR REPLACE refuses, so it
-- is dropped and recreated with its comment and grants restored explicitly.
--
-- Out of scope, deliberately: linked_tree_id / linked_tree_entity_id and
-- ue_scenarios.baseline_variant_id / climate_label (named roles, not drift).
--
-- Mirrored to init 59-ue-view-column-names.sql.
-- =============================================================================

ALTER VIEW public.ue_trees RENAME COLUMN competition TO has_competition;
ALTER VIEW public.ue_trees RENAME COLUMN management_regime TO management_regime_name;
ALTER VIEW public.ue_trees RENAME COLUMN climate_pathway TO climate_pathway_name;

ALTER VIEW public.ue_scenarios RENAME COLUMN management_regime TO management_regime_name;
ALTER VIEW public.ue_scenarios RENAME COLUMN climate_pathway TO climate_pathway_name;

ALTER VIEW public.ue_variants RENAME COLUMN management_regime TO management_regime_name;
ALTER VIEW public.ue_variants RENAME COLUMN climate_pathway TO climate_pathway_name;

ALTER VIEW public.ue_sensors RENAME COLUMN sensor_label TO sensor_serial_number;
ALTER VIEW public.ue_sensors RENAME COLUMN sensor_type TO sensor_type_name;
ALTER VIEW public.ue_sensors RENAME COLUMN linked_tree_species TO linked_tree_species_name;
ALTER VIEW public.ue_sensors RENAME COLUMN linked_tree_scientificname TO linked_tree_scientific_name;

ALTER VIEW public.ue_sensor_readings RENAME COLUMN sensor_type TO sensor_type_name;

DROP FUNCTION public.ue_sensor_state_at(timestamp with time zone, interval);

CREATE FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval DEFAULT NULL::interval)
 RETURNS TABLE(sensor_id integer, source character varying, sensor_type_name character varying, unit character varying, "timestamp" timestamp with time zone, value numeric, quality character varying, linked_tree_id integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.sensor_id,
           s.source,
           st.sensor_type_name,
           s.unit,
           r."timestamp",
           r.value,
           r.quality,
           stl.tree_id AS linked_tree_id
      FROM sensor.sensors s
      JOIN sensor.sensor_types st
        ON st.sensor_type_id = s.sensor_type_id
      LEFT JOIN sensor.sensor_tree_links stl
        ON stl.sensor_id = s.sensor_id
     CROSS JOIN LATERAL (
            -- One index seek per sensor. Both bounds are needed: the upper one
            -- is the question being asked, the lower one is what keeps this an
            -- index range scan instead of a walk back through every reading the
            -- sensor has ever produced. Its width is the caller's, or four of
            -- this sensor's stored sampling intervals.
            SELECT sr."timestamp", sr.value, sr.quality
              FROM sensor.sensor_readings sr
             WHERE sr.sensor_id = s.sensor_id
               AND sr."timestamp" <= p_timestamp
               AND sr."timestamp" >  p_timestamp
                                     - coalesce(p_lookback,
                                                (4 * s.sampling_interval_seconds) * interval '1 second')
             ORDER BY sr."timestamp" DESC
             LIMIT 1
     ) r;
$function$;

ALTER FUNCTION public.ue_sensor_state_at(timestamp with time zone, interval) OWNER TO supabase_admin;
COMMENT ON FUNCTION public.ue_sensor_state_at(timestamp with time zone, interval) IS 'Latest reading per sensor at or before p_timestamp, within p_lookback (default: 4 x the sensor''s sampling_interval_seconds -- one hour for the 15-min network, four hours for hourly series). The scene-wide counterpart to ue_sensor_readings, for driving a VR time slider from one request. Sensors with no reading in the window are absent from the result -- that is deliberate, a gap in the record must not be papered over with a stale value. `source` names the provider: an instrument network such as ''aquarius'', or a model such as ''open-meteo'' whose readings are computed rather than measured. Filter on it before showing a value as an observation. POST /rest/v1/rpc/ue_sensor_state_at  {"p_timestamp":"2025-07-15T12:00:00Z"}';
GRANT EXECUTE ON FUNCTION public.ue_sensor_state_at(timestamp with time zone, interval) TO PUBLIC, postgres, anon, authenticated, service_role;
