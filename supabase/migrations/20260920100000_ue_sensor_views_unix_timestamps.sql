-- ue_sensors / ue_sensorreadings: append Unix epoch timestamps for Unreal.
--
-- The UE Blueprints parse the views into user-defined structs, and a struct
-- field is either a string or a number: the ISO-8601 `timestamp` lands in a
-- string field that the material and sequencer graphs then cannot compare or
-- interpolate. The earlier workaround was a second data table
-- (DT_SensorReadings_UNIX) filled by a Blueprint conversion pass over every
-- row; here the view does it once, server side.
--
-- Both columns are appended at the END of the column list so the existing
-- struct parsers (ST_Sensor, ST_SensorReading) keep working until their
-- structs grow. Integer seconds since 1970-01-01 UTC (epoch of a timestamptz
-- is timezone-independent); `latest_timestamp_unix` is NULL exactly when
-- `latest_timestamp` is.
--
-- CREATE OR REPLACE VIEW only allows columns to be appended, which is what
-- this does; body otherwise as the baseline snapshot left it. Grants and the
-- security_invoker setting carry over unchanged.

SET search_path TO public, sensor, trees, shared;

CREATE OR REPLACE VIEW public.ue_sensorreadings WITH (security_invoker='on') AS
 SELECT sr.sensor_reading_id,
    sr.sensor_id,
    st.sensor_type_name AS sensor_type,
    s.unit,
    sr."timestamp",
    sr.value,
    sr.quality,
    (extract(epoch FROM sr."timestamp"))::bigint AS timestamp_unix
   FROM ((sensor.sensorreadings sr
     JOIN sensor.sensors s ON ((sr.sensor_id = s.sensor_id)))
     JOIN sensor.sensortypes st ON ((s.sensor_type_id = st.sensor_type_id)));

COMMENT ON VIEW public.ue_sensorreadings IS 'Enriched sensor time-series for UE Blueprint. Includes sensor type, unit and timestamp_unix (epoch seconds), keyed by sensor_id. Look up the linked tree once via ue_sensors, not per reading. GET /ue_sensorreadings?sensor_id=eq.<id>&order=timestamp.desc&limit=96';

CREATE OR REPLACE VIEW public.ue_sensors WITH (security_invoker='on') AS
 SELECT s.sensor_id,
    s.source,
    s.external_id,
    s.serial_number AS sensor_label,
    (s.external_metadata ->> 'Parameter'::text) AS parameter,
    st.sensor_type_id,
    st.sensor_type_name AS sensor_type,
    s.unit,
    s.sensor_model,
    (s.external_metadata ->> 'DataOwner'::text) AS data_owner,
    s.is_active,
    s.installation_height_m,
    s.sampling_interval_seconds,
    s.installation_date,
    l.location_id,
    l.location_name,
    s.plot_id,
    p.plot_name,
    lr."timestamp" AS latest_timestamp,
    lr.value AS latest_value,
    lr.quality AS latest_quality,
    t.tree_id AS linked_tree_id,
    t.tree_entity_id AS linked_tree_entity_id,
    sp.common_name AS linked_tree_species,
    sp.scientific_name AS linked_tree_scientificname,
    t.height_m AS linked_tree_height_m,
    extensions.st_y(s."position") AS latitude,
    extensions.st_x(s."position") AS longitude,
    (extract(epoch FROM lr."timestamp"))::bigint AS latest_timestamp_unix
   FROM (((((((sensor.sensors s
     JOIN sensor.sensortypes st ON ((s.sensor_type_id = st.sensor_type_id)))
     JOIN shared.locations l ON ((s.location_id = l.location_id)))
     LEFT JOIN shared.plots p ON ((s.plot_id = p.plot_id)))
     LEFT JOIN LATERAL ( SELECT sr."timestamp",
            sr.value,
            sr.quality
           FROM sensor.sensorreadings sr
          WHERE (sr.sensor_id = s.sensor_id)
          ORDER BY sr."timestamp" DESC
         LIMIT 1) lr ON (true))
     LEFT JOIN sensor.sensor_tree_links stl ON ((stl.sensor_id = s.sensor_id)))
     LEFT JOIN trees.trees t ON ((stl.tree_id = t.tree_id)))
     LEFT JOIN shared.species sp ON ((t.species_id = sp.species_id)));

COMMENT ON VIEW public.ue_sensors IS 'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading (ISO and latest_timestamp_unix epoch seconds), and linked tree info (populated after sensor_tree_links is filled). GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>';

NOTIFY pgrst, 'reload schema';
