-- =============================================================================
-- Views: rename the last view-layer columns that break the naming convention
-- =============================================================================
-- XRFF-485, the rest after 20260925100000. Rules 6, 7, 9 and 13 of
-- scripts/utils/check_naming.py, plus three it does not see (marked *).
--
--   variants                      management_regime      -> management_regime_name
--   variants                      climate_pathway        -> climate_pathway_name
--   simulation_runs               base_variant           -> base_variant_name
--   sensor_tree_view              sensor_type            -> sensor_type_name
--   sensor_tree_view              tree_species           -> tree_species_name
--   sensor_tree_view              tree_location          -> tree_location_name
--   sensor_tree_view              sensor_active          -> is_sensor_active
--   location_environment_summary  avg_temperature        -> avg_temperature_c
--   location_environment_summary  avg_humidity           -> avg_humidity_percent
--   location_environment_summary  avg_co2 *              -> avg_co2_ppm
--   ue_scenarios                  climate_label *        -> climate_pathway_label
--   ue_climate                    variants               -> variant_names
--   ue_climate                    processes *            -> process_names
--   ue_sensors                    linked_tree_id         -> tree_id
--   ue_sensors                    linked_tree_entity_id  -> tree_entity_id
--   job_status                    job_id                 -> processing_job_id
--   ue_sensor_state_at            linked_tree_id (OUT)   -> tree_id
--
-- Views: ALTER VIEW ... RENAME COLUMN, in place -- keeps owner, grants,
-- triggers and security_invoker. No view depends on any of these eight. The
-- three view comments that name a renamed column are rewritten.
--
-- Consumers that move with this migration:
--   ue_sensors.linked_tree_entity_id is a field of ST_Sensor in XRFFL_Dev. The
--     JSON -> struct fill matches by field name, so until the struct field is
--     renamed it imports as null, silently.
--   job_status.job_id is read by web/jobs/index.html (same commit). The page
--     and this migration have to reach dt.unr together (XRFF-491).
--
-- Stay as they are, by decision: ue_scenarios.baseline_variant_id and
-- recent_changes.record_id are COALESCE results with no base column to match.
--
-- Mirrored to init 60-view-column-names-remaining.sql.
-- =============================================================================

ALTER VIEW public.variants RENAME COLUMN management_regime TO management_regime_name;
ALTER VIEW public.variants RENAME COLUMN climate_pathway TO climate_pathway_name;
COMMENT ON VIEW public.variants IS 'Forest-state variants with location/scenario/type names, parent_variant_id lineage and the scenario axes (scenario_code, management_regime_name, climate_pathway_name) joined. Filter by location_id+scenario_id and order by sort_order for a site+scenario timeline.';

ALTER VIEW public.simulation_runs RENAME COLUMN base_variant TO base_variant_name;

ALTER VIEW sensor.sensor_tree_view RENAME COLUMN sensor_type TO sensor_type_name;
ALTER VIEW sensor.sensor_tree_view RENAME COLUMN tree_species TO tree_species_name;
ALTER VIEW sensor.sensor_tree_view RENAME COLUMN tree_location TO tree_location_name;
ALTER VIEW sensor.sensor_tree_view RENAME COLUMN sensor_active TO is_sensor_active;

ALTER VIEW environments.location_environment_summary RENAME COLUMN avg_temperature TO avg_temperature_c;
ALTER VIEW environments.location_environment_summary RENAME COLUMN avg_humidity TO avg_humidity_percent;
ALTER VIEW environments.location_environment_summary RENAME COLUMN avg_co2 TO avg_co2_ppm;

ALTER VIEW public.ue_scenarios RENAME COLUMN climate_label TO climate_pathway_label;

ALTER VIEW public.ue_climate RENAME COLUMN variants TO variant_names;
ALTER VIEW public.ue_climate RENAME COLUMN processes TO process_names;
COMMENT ON VIEW public.ue_climate IS 'environments.environments merged across variant_name: one row per location, scenario, variant type and period, with each measurement column taken from whichever dataset supplied it. This is the read a scene makes -- ue_environments returns one row per dataset, which since XRFF-395 means two half-empty rows per window where a scenario picker wants one full one. `variant_names` and `process_names` carry the provenance the merge folds away; `conflicting_columns` is empty unless two datasets supplied the same measurement for the same window, in which case the value shown is an arbitrary one of them. Despite the name it also returns the scenario-less rows -- soil chemistry (both years NULL) and the measured soil aggregate -- because the grouping is by period, not by topic. GET /rest/v1/ue_climate?location_id=eq.1&scenario_name=eq.ssp370&order=start_year';

ALTER VIEW public.ue_sensors RENAME COLUMN linked_tree_id TO tree_id;
ALTER VIEW public.ue_sensors RENAME COLUMN linked_tree_entity_id TO tree_entity_id;
COMMENT ON VIEW public.ue_sensors IS 'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading (ISO and latest_timestamp_unix epoch seconds), linked tree info (populated after sensor_tree_links is filled), and the probe placement parsed from the label (placement_ring stem|middle|edge, placement_direction N|E|S|W|NE, placement_depth_cm, placement_distance_cm; NULL = the label carries none). GET /ue_sensors?tree_entity_id=eq.<tree_entity_id>';

ALTER VIEW public.job_status RENAME COLUMN job_id TO processing_job_id;

DROP FUNCTION public.ue_sensor_state_at(timestamp with time zone, interval);

CREATE FUNCTION public.ue_sensor_state_at(p_timestamp timestamp with time zone, p_lookback interval DEFAULT NULL::interval)
 RETURNS TABLE(sensor_id integer, source character varying, sensor_type_name character varying, unit character varying, "timestamp" timestamp with time zone, value numeric, quality character varying, tree_id integer)
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
           stl.tree_id
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
