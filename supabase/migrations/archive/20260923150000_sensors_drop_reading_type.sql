-- =============================================================================
-- sensor.Sensors: drop the unused reading_type, align source to TEXT
-- =============================================================================
-- XRFF-489 follow-up, part of XRFF-494. The first destructive change in this
-- sequence -- it removes a column -- so it is deliberately separate from the
-- unit-vocabulary migration that surfaced both items.
--
-- reading_type: 1,418 rows, all NULL. No writer, no reader, no view but this
-- one, and the only reference anywhere in the workspace was the naming
-- checker's own exception list. It is debris.
--
-- source: varchar here and text in its three siblings
-- (shared.ProcessMetrics, trees.CrownFoliageProfiles, trees.Roots) -- the only
-- column name in the database carrying two types.
--
-- Both changes are refused while a view selects the column ("cannot alter type
-- of a column used by a view or rule"), so public.Sensors is dropped and
-- recreated. public.ue_sensors selects source as well and had to go with it;
-- it is recreated VERBATIM, because its column names are the Unreal DataTable
-- contract and nothing about them changes here.
--
-- A plain CREATE VIEW restores none of what a DROP takes with it, and losing
-- any one of them is silent. All five are restored explicitly and asserted in a
-- transaction before this was applied: security_invoker='on', owner
-- supabase_admin, the view comment, GRANT ALL to the four roles, and the three
-- INSTEAD OF triggers. That check is here because the same omission cost two
-- views their security_invoker setting earlier in this work.
--
-- sensors_update() assigned reading_type; that assignment goes with the column.
--
-- Mirrored to init 53-sensors-drop-reading-type.sql.
-- =============================================================================

-- 1. Rebuild public.Sensors without reading_type, and retype source.
--    Both changes are refused while the view selects the columns, so the
--    view is dropped and recreated. Its security_invoker setting, owner,
--    comment, grants and three INSTEAD OF triggers are all restored
--    explicitly below -- a plain CREATE VIEW restores none of them, and
--    losing any one is silent.
DROP VIEW public.ue_sensors;
DROP VIEW public.sensors;

ALTER TABLE sensor.sensors DROP COLUMN reading_type;
ALTER TABLE sensor.sensors ALTER COLUMN source TYPE TEXT;

CREATE VIEW public.sensors WITH (security_invoker = 'on') AS
SELECT sensors.sensor_id,
    sensors.location_id,
    sensors.sensor_type_id,
    sensors.campaign_id,
    sensors.plot_id,
    sensors.sensor_model,
    sensors.serial_number,
    sensors."position",
    sensors.position_original,
    sensors.source_crs,
    sensors.installation_date,
    sensors.installation_height_m,
    sensors.decommission_date,
    sensors.calibration_date,
    sensors.next_calibration_date,
    sensors.sampling_interval_seconds,
    sensors.unit,
    sensors.min_value,
    sensors.max_value,
    sensors.accuracy,
    sensors.battery_level_percent,
    sensors.is_active,
    sensors.maintenance_notes,
    sensors.created_at,
    sensors.updated_at,
    sensors.created_by,
    sensors.updated_by,
    sensors.source,
    sensors.external_id,
    sensors.external_metadata
   FROM sensor.sensors;

ALTER VIEW public.sensors OWNER TO supabase_admin;
COMMENT ON VIEW public.sensors IS 'Public API view for sensors table';
GRANT ALL ON TABLE public.sensors TO postgres, anon, authenticated, service_role;

-- 2. The three INSTEAD OF triggers, recreated verbatim.
CREATE TRIGGER sensors_delete_trigger INSTEAD OF DELETE ON public.sensors FOR EACH ROW EXECUTE FUNCTION sensors_delete();
CREATE TRIGGER sensors_insert_trigger INSTEAD OF INSERT ON public.sensors FOR EACH ROW EXECUTE FUNCTION sensors_insert();
CREATE TRIGGER sensors_update_trigger INSTEAD OF UPDATE ON public.sensors FOR EACH ROW EXECUTE FUNCTION sensors_update();

-- 3. sensors_update() set reading_type; that assignment goes with the column.
CREATE OR REPLACE FUNCTION public.sensors_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE sensor.sensors SET
        location_id = NEW.location_id,
        sensor_type_id = NEW.sensor_type_id,
        campaign_id = NEW.campaign_id,
        sensor_model = NEW.sensor_model,
        serial_number = NEW.serial_number,
        position = NEW.position,
        position_original = NEW.position_original,
        source_crs = NEW.source_crs,
        installation_date = NEW.installation_date,
        installation_height_m = NEW.installation_height_m,
        decommission_date = NEW.decommission_date,
        calibration_date = NEW.calibration_date,
        next_calibration_date = NEW.next_calibration_date,
        sampling_interval_seconds = NEW.sampling_interval_seconds,
        unit = NEW.unit,
        min_value = NEW.min_value,
        max_value = NEW.max_value,
        accuracy = NEW.accuracy,
        battery_level_percent = NEW.battery_level_percent,
        is_active = NEW.is_active,
        maintenance_notes = NEW.maintenance_notes,
        external_id = NEW.external_id,
        external_metadata = NEW.external_metadata,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE sensor_id = OLD.sensor_id;
    RETURN NEW;
END;
$function$;

-- 4. public.ue_sensors selects sensor.Sensors.source too, so it had to be
--    dropped with the rest. Recreated VERBATIM: its column names are the
--    Unreal DataTable contract and nothing about them changes here.
CREATE VIEW public.ue_sensors WITH (security_invoker=on) AS
SELECT s.sensor_id,
    s.source,
    s.external_id,
    s.serial_number AS sensor_label,
    s.external_metadata ->> 'Parameter'::text AS parameter,
    st.sensor_type_id,
    st.sensor_type_name AS sensor_type,
    s.unit,
    s.sensor_model,
    s.external_metadata ->> 'DataOwner'::text AS data_owner,
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
    st_y(s."position") AS latitude,
    st_x(s."position") AS longitude,
    EXTRACT(epoch FROM lr."timestamp")::bigint AS latest_timestamp_unix
   FROM sensor.sensors s
     JOIN sensor.sensor_types st ON s.sensor_type_id = st.sensor_type_id
     JOIN shared.locations l ON s.location_id = l.location_id
     LEFT JOIN shared.plots p ON s.plot_id = p.plot_id
     LEFT JOIN LATERAL ( SELECT sr."timestamp",
            sr.value,
            sr.quality
           FROM sensor.sensor_readings sr
          WHERE sr.sensor_id = s.sensor_id
          ORDER BY sr."timestamp" DESC
         LIMIT 1) lr ON true
     LEFT JOIN sensor.sensor_tree_links stl ON stl.sensor_id = s.sensor_id
     LEFT JOIN trees.trees t ON stl.tree_id = t.tree_id
     LEFT JOIN shared.species sp ON t.species_id = sp.species_id;

ALTER VIEW public.ue_sensors OWNER TO supabase_admin;
COMMENT ON VIEW public.ue_sensors IS 'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading (ISO and latest_timestamp_unix epoch seconds), and linked tree info (populated after sensor_tree_links is filled). GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>';
GRANT ALL ON TABLE public.ue_sensors TO postgres, anon, authenticated, service_role;
