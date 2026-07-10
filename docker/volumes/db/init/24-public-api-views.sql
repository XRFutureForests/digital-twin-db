-- Public API Views Migration
-- This migration creates views in the public schema that expose tables from other schemas
-- This allows PostgREST API to access tables using simple names (e.g., 'trees' instead of 'trees.trees')
-- Dependencies: 11-shared-schema.sql, 12-pointclouds-schema.sql, 13-trees-schema.sql, 14-sensor-schema.sql, 15-environments-schema.sql

-- =============================================================================
-- SHARED SCHEMA VIEWS
-- =============================================================================

-- Species view
CREATE OR REPLACE VIEW public.species AS
SELECT * FROM shared.species;

COMMENT ON VIEW public.species IS 'Public API view for tree species reference table';

-- Locations view
CREATE OR REPLACE VIEW public.locations AS
SELECT * FROM shared.locations;

COMMENT ON VIEW public.locations IS 'Public API view for locations reference table';

-- Campaigns view
CREATE OR REPLACE VIEW public.campaigns AS
SELECT * FROM shared.campaigns;

COMMENT ON VIEW public.campaigns IS 'Public API view for data collection campaigns';

-- Plots view
CREATE OR REPLACE VIEW public.plots AS
SELECT * FROM shared.plots;

COMMENT ON VIEW public.plots IS 'Public API view for sub-plot divisions within locations';

-- Scenarios view
CREATE OR REPLACE VIEW public.scenarios AS
SELECT * FROM shared.scenarios;

COMMENT ON VIEW public.scenarios IS 'Public API view for scenarios reference table';

-- Variants view
CREATE OR REPLACE VIEW public.variants AS
SELECT
    v.*,
    l.location_name,
    s.scenario_name,
    vt.variant_type_name
FROM shared.variants v
LEFT JOIN shared.locations  l  ON v.location_id  = l.location_id
LEFT JOIN shared.scenarios  s  ON v.scenario_id  = s.scenario_id
LEFT JOIN shared.varianttypes vt ON v.variant_type_id = vt.variant_type_id;

COMMENT ON VIEW public.variants IS 'Forest state variants with location, scenario, and type names joined. Filter by location_id+scenario_id to get the time-step list for a site+scenario combination.';

-- ManagementEvents view
CREATE OR REPLACE VIEW public.managementevents AS
SELECT * FROM shared.managementevents;

COMMENT ON VIEW public.managementevents IS 'Public API view for forest management events';

-- DisturbanceEvents view
CREATE OR REPLACE VIEW public.disturbanceevents AS
SELECT * FROM shared.disturbanceevents;

COMMENT ON VIEW public.disturbanceevents IS 'Public API view for natural disturbance events';

-- =============================================================================
-- TREES SCHEMA VIEWS
-- =============================================================================

-- Trees view
CREATE OR REPLACE VIEW public.trees AS
SELECT * FROM trees.trees;

COMMENT ON VIEW public.trees IS 'Public API view for trees table';

-- Stems view
CREATE OR REPLACE VIEW public.stems AS
SELECT * FROM trees.stems;

COMMENT ON VIEW public.stems IS 'Public API view for tree stems table';

-- PhenologyObservations view
CREATE OR REPLACE VIEW public.phenologyobservations AS
SELECT * FROM trees.phenologyobservations;

COMMENT ON VIEW public.phenologyobservations IS 'Public API view for tree phenology observations';

-- Deadwood view
CREATE OR REPLACE VIEW public.deadwood AS
SELECT * FROM trees.deadwood;

COMMENT ON VIEW public.deadwood IS 'Public API view for dead wood inventory';

-- GroundVegetation view
CREATE OR REPLACE VIEW public.groundvegetation AS
SELECT * FROM trees.groundvegetation;

COMMENT ON VIEW public.groundvegetation IS 'Public API view for ground vegetation surveys';

-- =============================================================================
-- SENSOR SCHEMA VIEWS
-- =============================================================================

-- Sensors view
CREATE OR REPLACE VIEW public.sensors AS
SELECT * FROM sensor.sensors;

COMMENT ON VIEW public.sensors IS 'Public API view for sensors table';

-- SensorReadings view
CREATE OR REPLACE VIEW public.sensorreadings AS
SELECT * FROM sensor.sensorreadings;

COMMENT ON VIEW public.sensorreadings IS 'Public API view for sensor readings table';

-- SensorTypes view
CREATE OR REPLACE VIEW public.sensortypes AS
SELECT * FROM sensor.sensortypes;

COMMENT ON VIEW public.sensortypes IS 'Public API view for sensor types reference table';

-- =============================================================================
-- POINTCLOUDS SCHEMA VIEWS
-- =============================================================================

-- PointClouds view
CREATE OR REPLACE VIEW public.pointclouds AS
SELECT * FROM pointclouds.pointclouds;

COMMENT ON VIEW public.pointclouds IS 'Public API view for point clouds table';

-- =============================================================================
-- ENVIRONMENTS SCHEMA VIEWS
-- =============================================================================

-- Environments view
CREATE OR REPLACE VIEW public.environments AS
SELECT * FROM environments.environments;

COMMENT ON VIEW public.environments IS 'Public API view for environments table';

-- =============================================================================
-- IMAGERY SCHEMA VIEWS
-- =============================================================================

-- Images view
CREATE OR REPLACE VIEW public.images AS
SELECT * FROM imagery.images;

COMMENT ON VIEW public.images IS 'Public API view for imagery table';

-- =============================================================================
-- TREES SCHEMA: MORPHOLOGY LOOKUP VIEWS
-- =============================================================================

CREATE OR REPLACE VIEW public.phanerophyteheightclasses AS
SELECT * FROM trees.phanerophyteheightclasses;

COMMENT ON VIEW public.phanerophyteheightclasses IS 'Public API view for phanerophyte height classes lookup table';

CREATE OR REPLACE VIEW public.crownarchitectures AS
SELECT * FROM trees.crownarchitectures;

COMMENT ON VIEW public.crownarchitectures IS 'Public API view for crown architectures lookup table';

CREATE OR REPLACE VIEW public.branchelongationhabits AS
SELECT * FROM trees.branchelongationhabits;

COMMENT ON VIEW public.branchelongationhabits IS 'Public API view for branch elongation habits lookup table';

CREATE OR REPLACE VIEW public.growthorientations AS
SELECT * FROM trees.growthorientations;

COMMENT ON VIEW public.growthorientations IS 'Public API view for growth orientations lookup table';

CREATE OR REPLACE VIEW public.shootelongationtypes AS
SELECT * FROM trees.shootelongationtypes;

COMMENT ON VIEW public.shootelongationtypes IS 'Public API view for shoot elongation types lookup table';

CREATE OR REPLACE VIEW public.crownshapes AS
SELECT * FROM trees.crownshapes;

COMMENT ON VIEW public.crownshapes IS 'Public API view for crown shapes lookup table';

CREATE OR REPLACE VIEW public.geometriccrownsolids AS
SELECT * FROM trees.geometriccrownsolids;

COMMENT ON VIEW public.geometriccrownsolids IS 'Public API view for geometric crown solids lookup table';

CREATE OR REPLACE VIEW public.axisstructures AS
SELECT * FROM trees.axisstructures;

COMMENT ON VIEW public.axisstructures IS 'Public API view for axis structures lookup table';

CREATE OR REPLACE VIEW public.growthforms AS
SELECT * FROM trees.growthforms;

COMMENT ON VIEW public.growthforms IS 'Public API view for growth forms lookup table';

-- =============================================================================
-- TREES SCHEMA: TREE CONDITION LOOKUP VIEWS
-- =============================================================================

CREATE OR REPLACE VIEW public.crownclasses AS
SELECT * FROM trees.crownclasses;

COMMENT ON VIEW public.crownclasses IS 'Public API view for crown classes (competitive/social position) lookup table';

CREATE OR REPLACE VIEW public.damageagents AS
SELECT * FROM trees.damageagents;

COMMENT ON VIEW public.damageagents IS 'Public API view for damage agents lookup table';

-- =============================================================================
-- GRANT PERMISSIONS
-- =============================================================================

-- Grant SELECT to anon and authenticated users on all public views
GRANT SELECT ON public.species TO anon, authenticated;
GRANT SELECT ON public.locations TO anon, authenticated;
GRANT SELECT ON public.campaigns TO anon, authenticated;
GRANT SELECT ON public.trees TO anon, authenticated;
GRANT SELECT ON public.stems TO anon, authenticated;
GRANT SELECT ON public.sensors TO anon, authenticated;
GRANT SELECT ON public.sensorreadings TO anon, authenticated;
GRANT SELECT ON public.sensortypes TO anon, authenticated;
GRANT SELECT ON public.pointclouds TO anon, authenticated;
GRANT SELECT ON public.environments TO anon, authenticated;
GRANT SELECT ON public.plots TO anon, authenticated;
GRANT SELECT ON public.managementevents TO anon, authenticated;
GRANT SELECT ON public.disturbanceevents TO anon, authenticated;
GRANT SELECT ON public.phenologyobservations TO anon, authenticated;
GRANT SELECT ON public.deadwood TO anon, authenticated;
GRANT SELECT ON public.groundvegetation TO anon, authenticated;
GRANT SELECT ON public.images TO anon, authenticated;
GRANT SELECT ON public.phanerophyteheightclasses TO anon, authenticated;
GRANT SELECT ON public.crownarchitectures TO anon, authenticated;
GRANT SELECT ON public.branchelongationhabits TO anon, authenticated;
GRANT SELECT ON public.growthorientations TO anon, authenticated;
GRANT SELECT ON public.shootelongationtypes TO anon, authenticated;
GRANT SELECT ON public.crownshapes TO anon, authenticated;
GRANT SELECT ON public.geometriccrownsolids TO anon, authenticated;
GRANT SELECT ON public.axisstructures TO anon, authenticated;
GRANT SELECT ON public.growthforms TO anon, authenticated;
GRANT SELECT ON public.crownclasses TO anon, authenticated;
GRANT SELECT ON public.damageagents TO anon, authenticated;
GRANT SELECT ON public.scenarios TO anon, authenticated;
GRANT SELECT ON public.variants TO anon, authenticated;

-- Grant INSERT/UPDATE/DELETE to authenticated users on data tables
GRANT INSERT, UPDATE, DELETE ON public.campaigns TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.trees TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.stems TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.sensors TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.sensorreadings TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.pointclouds TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.environments TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.plots TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.managementevents TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.disturbanceevents TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.phenologyobservations TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.deadwood TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.groundvegetation TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.images TO authenticated;

-- Grant INSERT/UPDATE/DELETE to service_role on all tables (for admin operations)
GRANT ALL ON public.species TO service_role;
GRANT ALL ON public.locations TO service_role;
GRANT ALL ON public.campaigns TO service_role;
GRANT ALL ON public.trees TO service_role;
GRANT ALL ON public.stems TO service_role;
GRANT ALL ON public.sensors TO service_role;
GRANT ALL ON public.sensorreadings TO service_role;
GRANT ALL ON public.sensortypes TO service_role;
GRANT ALL ON public.pointclouds TO service_role;
GRANT ALL ON public.environments TO service_role;
GRANT ALL ON public.plots TO service_role;
GRANT ALL ON public.managementevents TO service_role;
GRANT ALL ON public.disturbanceevents TO service_role;
GRANT ALL ON public.phenologyobservations TO service_role;
GRANT ALL ON public.deadwood TO service_role;
GRANT ALL ON public.groundvegetation TO service_role;
GRANT ALL ON public.images TO service_role;
GRANT ALL ON public.phanerophyteheightclasses TO service_role;
GRANT ALL ON public.crownarchitectures TO service_role;
GRANT ALL ON public.branchelongationhabits TO service_role;
GRANT ALL ON public.growthorientations TO service_role;
GRANT ALL ON public.shootelongationtypes TO service_role;
GRANT ALL ON public.crownshapes TO service_role;
GRANT ALL ON public.geometriccrownsolids TO service_role;
GRANT ALL ON public.axisstructures TO service_role;
GRANT ALL ON public.growthforms TO service_role;
GRANT ALL ON public.crownclasses TO service_role;
GRANT ALL ON public.damageagents TO service_role;
GRANT ALL ON public.scenarios TO service_role;
GRANT ALL ON public.variants TO service_role;

-- =============================================================================
-- INSTEAD OF TRIGGERS FOR INSERTABLE/UPDATABLE VIEWS
-- =============================================================================

-- Campaigns INSERT trigger
CREATE OR REPLACE FUNCTION public.campaigns_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO shared.campaigns (
        campaign_name, campaign_type, location_id, start_date, end_date,
        description, methodology, equipment, personnel,
        created_by, updated_by
    ) VALUES (
        NEW.campaign_name, NEW.campaign_type, NEW.location_id, NEW.start_date, NEW.end_date,
        NEW.description, NEW.methodology, NEW.equipment, NEW.personnel,
        NEW.created_by, NEW.updated_by
    ) RETURNING campaign_id INTO NEW.campaign_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campaigns_insert_trigger
INSTEAD OF INSERT ON public.campaigns
FOR EACH ROW EXECUTE FUNCTION public.campaigns_insert();

-- Campaigns UPDATE trigger
CREATE OR REPLACE FUNCTION public.campaigns_update()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE shared.campaigns SET
        campaign_name = NEW.campaign_name,
        campaign_type = NEW.campaign_type,
        location_id = NEW.location_id,
        start_date = NEW.start_date,
        end_date = NEW.end_date,
        description = NEW.description,
        methodology = NEW.methodology,
        equipment = NEW.equipment,
        personnel = NEW.personnel,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE campaign_id = OLD.campaign_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campaigns_update_trigger
INSTEAD OF UPDATE ON public.campaigns
FOR EACH ROW EXECUTE FUNCTION public.campaigns_update();

-- Campaigns DELETE trigger
CREATE OR REPLACE FUNCTION public.campaigns_delete()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM shared.campaigns WHERE campaign_id = OLD.campaign_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER campaigns_delete_trigger
INSTEAD OF DELETE ON public.campaigns
FOR EACH ROW EXECUTE FUNCTION public.campaigns_delete();

-- Trees INSERT trigger
CREATE OR REPLACE FUNCTION public.trees_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.trees (
        tree_entity_id, variant_id, parent_tree_id, point_cloud_id, campaign_id,
        location_id, plot_id, scenario_id, variant_type_id, process_id,
        species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
        measurement_date, data_source_type_id,
        height_m, crown_width_m, crown_base_height_m, crown_boundary,
        crown_offset_x_m, crown_offset_y_m, volume_m3,
        position, position_original, source_crs,
        lean_angle_deg, lean_direction_azimuth, time_delta_yrs, age_years,
        health_score, biomass_kg, carbon_content_kg,
        species_confidence, position_confidence, height_confidence,
        crown_class_id, damage_agent_id, defoliation_percent, discolouration_percent, crown_transparency_percent,
        status_change_date, field_notes, created_by, updated_by
    ) VALUES (
        COALESCE(NEW.tree_entity_id, gen_random_uuid()), NEW.variant_id, NEW.parent_tree_id, NEW.point_cloud_id, NEW.campaign_id,
        NEW.location_id, NEW.plot_id, NEW.scenario_id, NEW.variant_type_id, NEW.process_id,
        NEW.species_id, NEW.tree_status_id, NEW.branching_pattern_id, NEW.bark_characteristic_id,
        NEW.measurement_date, NEW.data_source_type_id,
        NEW.height_m, NEW.crown_width_m, NEW.crown_base_height_m, NEW.crown_boundary,
        NEW.crown_offset_x_m, NEW.crown_offset_y_m, NEW.volume_m3,
        NEW.position, NEW.position_original, NEW.source_crs,
        NEW.lean_angle_deg, NEW.lean_direction_azimuth, NEW.time_delta_yrs, NEW.age_years,
        NEW.health_score, NEW.biomass_kg, NEW.carbon_content_kg,
        NEW.species_confidence, NEW.position_confidence, NEW.height_confidence,
        NEW.crown_class_id, NEW.damage_agent_id, NEW.defoliation_percent, NEW.discolouration_percent, NEW.crown_transparency_percent,
        NEW.status_change_date, NEW.field_notes, NEW.created_by, NEW.updated_by
    ) RETURNING tree_id INTO NEW.tree_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trees_insert_trigger
INSTEAD OF INSERT ON public.trees
FOR EACH ROW EXECUTE FUNCTION public.trees_insert();

-- Trees UPDATE trigger
CREATE OR REPLACE FUNCTION public.trees_update()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE trees.trees SET
        tree_entity_id = NEW.tree_entity_id,
        variant_id = NEW.variant_id,
        parent_tree_id = NEW.parent_tree_id,
        point_cloud_id = NEW.point_cloud_id,
        campaign_id = NEW.campaign_id,
        location_id = NEW.location_id,
        plot_id = NEW.plot_id,
        scenario_id = NEW.scenario_id,
        variant_type_id = NEW.variant_type_id,
        process_id = NEW.process_id,
        species_id = NEW.species_id,
        tree_status_id = NEW.tree_status_id,
        branching_pattern_id = NEW.branching_pattern_id,
        bark_characteristic_id = NEW.bark_characteristic_id,
        measurement_date = NEW.measurement_date,
        data_source_type_id = NEW.data_source_type_id,
        height_m = NEW.height_m,
        crown_width_m = NEW.crown_width_m,
        crown_base_height_m = NEW.crown_base_height_m,
        crown_boundary = NEW.crown_boundary,
        crown_offset_x_m = NEW.crown_offset_x_m,
        crown_offset_y_m = NEW.crown_offset_y_m,
        volume_m3 = NEW.volume_m3,
        position = NEW.position,
        position_original = NEW.position_original,
        source_crs = NEW.source_crs,
        lean_angle_deg = NEW.lean_angle_deg,
        lean_direction_azimuth = NEW.lean_direction_azimuth,
        time_delta_yrs = NEW.time_delta_yrs,
        age_years = NEW.age_years,
        health_score = NEW.health_score,
        biomass_kg = NEW.biomass_kg,
        carbon_content_kg = NEW.carbon_content_kg,
        species_confidence = NEW.species_confidence,
        position_confidence = NEW.position_confidence,
        height_confidence = NEW.height_confidence,
        crown_class_id = NEW.crown_class_id,
        damage_agent_id = NEW.damage_agent_id,
        defoliation_percent = NEW.defoliation_percent,
        discolouration_percent = NEW.discolouration_percent,
        crown_transparency_percent = NEW.crown_transparency_percent,
        status_change_date = NEW.status_change_date,
        field_notes = NEW.field_notes,
        updated_at = NOW(),
        updated_by = NEW.updated_by
    WHERE tree_id = OLD.tree_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trees_update_trigger
INSTEAD OF UPDATE ON public.trees
FOR EACH ROW EXECUTE FUNCTION public.trees_update();

-- Trees DELETE trigger
CREATE OR REPLACE FUNCTION public.trees_delete()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM trees.trees WHERE tree_id = OLD.tree_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trees_delete_trigger
INSTEAD OF DELETE ON public.trees
FOR EACH ROW EXECUTE FUNCTION public.trees_delete();

-- Sensors INSERT trigger
CREATE OR REPLACE FUNCTION public.sensors_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sensor.sensors SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensors_insert_trigger
INSTEAD OF INSERT ON public.sensors
FOR EACH ROW EXECUTE FUNCTION public.sensors_insert();

-- Sensors UPDATE trigger
CREATE OR REPLACE FUNCTION public.sensors_update()
RETURNS TRIGGER AS $$
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
        reading_type = NEW.reading_type,
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
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensors_update_trigger
INSTEAD OF UPDATE ON public.sensors
FOR EACH ROW EXECUTE FUNCTION public.sensors_update();

-- Sensors DELETE trigger
CREATE OR REPLACE FUNCTION public.sensors_delete()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM sensor.sensors WHERE sensor_id = OLD.sensor_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensors_delete_trigger
INSTEAD OF DELETE ON public.sensors
FOR EACH ROW EXECUTE FUNCTION public.sensors_delete();

-- SensorReadings INSERT trigger
CREATE OR REPLACE FUNCTION public.sensorreadings_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO sensor.sensorreadings (sensor_id, timestamp, value, quality, scenario_id, battery_voltage, signal_strength, notes)
    VALUES (NEW.sensor_id, NEW.timestamp, NEW.value, NEW.quality, NEW.scenario_id, NEW.battery_voltage, NEW.signal_strength, NEW.notes);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sensorreadings_insert_trigger
INSTEAD OF INSERT ON public.sensorreadings
FOR EACH ROW EXECUTE FUNCTION public.sensorreadings_insert();

-- PointClouds INSERT trigger
CREATE OR REPLACE FUNCTION public.pointclouds_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO pointclouds.pointclouds SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pointclouds_insert_trigger
INSTEAD OF INSERT ON public.pointclouds
FOR EACH ROW EXECUTE FUNCTION public.pointclouds_insert();

-- Environments INSERT trigger
CREATE OR REPLACE FUNCTION public.environments_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO environments.environments SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER environments_insert_trigger
INSTEAD OF INSERT ON public.environments
FOR EACH ROW EXECUTE FUNCTION public.environments_insert();

-- Stems INSERT trigger
CREATE OR REPLACE FUNCTION public.stems_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.stems SELECT NEW.*;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stems_insert_trigger
INSTEAD OF INSERT ON public.stems
FOR EACH ROW EXECUTE FUNCTION public.stems_insert();

-- Plots INSERT trigger
CREATE OR REPLACE FUNCTION public.plots_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO shared.plots (
        location_id, plot_name, plot_number, area_m2,
        boundary, center_point, description,
        created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_name, NEW.plot_number, NEW.area_m2,
        NEW.boundary, NEW.center_point, NEW.description,
        NEW.created_by, NEW.updated_by
    ) RETURNING plot_id INTO NEW.plot_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER plots_insert_trigger
INSTEAD OF INSERT ON public.plots
FOR EACH ROW EXECUTE FUNCTION public.plots_insert();

-- ManagementEvents INSERT trigger
CREATE OR REPLACE FUNCTION public.managementevents_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO shared.managementevents (
        location_id, plot_id, event_type, event_date, end_date,
        description, affected_area_m2, performed_by, notes,
        created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.event_type, NEW.event_date, NEW.end_date,
        NEW.description, NEW.affected_area_m2, NEW.performed_by, NEW.notes,
        NEW.created_by, NEW.updated_by
    ) RETURNING management_event_id INTO NEW.management_event_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER managementevents_insert_trigger
INSTEAD OF INSERT ON public.managementevents
FOR EACH ROW EXECUTE FUNCTION public.managementevents_insert();

-- DisturbanceEvents INSERT trigger
CREATE OR REPLACE FUNCTION public.disturbanceevents_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO shared.disturbanceevents (
        location_id, plot_id, disturbance_type, event_date, end_date,
        severity, affected_area_m2, description, notes,
        created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.disturbance_type, NEW.event_date, NEW.end_date,
        NEW.severity, NEW.affected_area_m2, NEW.description, NEW.notes,
        NEW.created_by, NEW.updated_by
    ) RETURNING disturbance_event_id INTO NEW.disturbance_event_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER disturbanceevents_insert_trigger
INSTEAD OF INSERT ON public.disturbanceevents
FOR EACH ROW EXECUTE FUNCTION public.disturbanceevents_insert();

-- PhenologyObservations INSERT trigger
CREATE OR REPLACE FUNCTION public.phenologyobservations_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.phenologyobservations (
        tree_id, observation_date, phenophase_type,
        phenophase_status, intensity_percent, observer, notes, created_by
    ) VALUES (
        NEW.tree_id, NEW.observation_date, NEW.phenophase_type,
        NEW.phenophase_status, NEW.intensity_percent, NEW.observer, NEW.notes, NEW.created_by
    ) RETURNING phenology_observation_id INTO NEW.phenology_observation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER phenologyobservations_insert_trigger
INSTEAD OF INSERT ON public.phenologyobservations
FOR EACH ROW EXECUTE FUNCTION public.phenologyobservations_insert();

-- Deadwood INSERT trigger
CREATE OR REPLACE FUNCTION public.deadwood_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.deadwood (
        location_id, plot_id, tree_id, species_id,
        wood_type, length_m, diameter_cm, decay_class,
        volume_m3, position, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.tree_id, NEW.species_id,
        NEW.wood_type, NEW.length_m, NEW.diameter_cm, NEW.decay_class,
        NEW.volume_m3, NEW.position, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING deadwood_id INTO NEW.deadwood_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER deadwood_insert_trigger
INSTEAD OF INSERT ON public.deadwood
FOR EACH ROW EXECUTE FUNCTION public.deadwood_insert();

-- GroundVegetation INSERT trigger
CREATE OR REPLACE FUNCTION public.groundvegetation_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO trees.groundvegetation (
        location_id, plot_id, species_name, cover_percent,
        height_cm, layer, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.species_name, NEW.cover_percent,
        NEW.height_cm, NEW.layer, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING ground_vegetation_id INTO NEW.ground_vegetation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER groundvegetation_insert_trigger
INSTEAD OF INSERT ON public.groundvegetation
FOR EACH ROW EXECUTE FUNCTION public.groundvegetation_insert();

-- Images INSERT trigger
CREATE OR REPLACE FUNCTION public.images_insert()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO imagery.images (
        location_id, plot_id, campaign_id, capture_date,
        file_path, file_format, resolution_px, camera_model,
        position, altitude_m, heading_deg, pitch_deg, roll_deg,
        ground_sample_distance_cm, description, created_by, updated_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.campaign_id, NEW.capture_date,
        NEW.file_path, NEW.file_format, NEW.resolution_px, NEW.camera_model,
        NEW.position, NEW.altitude_m, NEW.heading_deg, NEW.pitch_deg, NEW.roll_deg,
        NEW.ground_sample_distance_cm, NEW.description, NEW.created_by, NEW.updated_by
    ) RETURNING image_id INTO NEW.image_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER images_insert_trigger
INSTEAD OF INSERT ON public.images
FOR EACH ROW EXECUTE FUNCTION public.images_insert();

COMMENT ON FUNCTION public.campaigns_insert() IS 'INSTEAD OF INSERT trigger function for public.campaigns view';
COMMENT ON FUNCTION public.campaigns_update() IS 'INSTEAD OF UPDATE trigger function for public.campaigns view';
COMMENT ON FUNCTION public.campaigns_delete() IS 'INSTEAD OF DELETE trigger function for public.campaigns view';
COMMENT ON FUNCTION public.trees_insert() IS 'INSTEAD OF INSERT trigger function for public.trees view';
COMMENT ON FUNCTION public.trees_update() IS 'INSTEAD OF UPDATE trigger function for public.trees view';
COMMENT ON FUNCTION public.trees_delete() IS 'INSTEAD OF DELETE trigger function for public.trees view';
COMMENT ON FUNCTION public.sensors_insert() IS 'INSTEAD OF INSERT trigger function for public.sensors view';
COMMENT ON FUNCTION public.sensorreadings_insert() IS 'INSTEAD OF INSERT trigger function for public.sensorreadings view';
COMMENT ON FUNCTION public.pointclouds_insert() IS 'INSTEAD OF INSERT trigger function for public.pointclouds view';
COMMENT ON FUNCTION public.environments_insert() IS 'INSTEAD OF INSERT trigger function for public.environments view';
COMMENT ON FUNCTION public.stems_insert() IS 'INSTEAD OF INSERT trigger function for public.stems view';
COMMENT ON FUNCTION public.plots_insert() IS 'INSTEAD OF INSERT trigger function for public.plots view';
COMMENT ON FUNCTION public.managementevents_insert() IS 'INSTEAD OF INSERT trigger function for public.managementevents view';
COMMENT ON FUNCTION public.disturbanceevents_insert() IS 'INSTEAD OF INSERT trigger function for public.disturbanceevents view';
COMMENT ON FUNCTION public.phenologyobservations_insert() IS 'INSTEAD OF INSERT trigger function for public.phenologyobservations view';
COMMENT ON FUNCTION public.deadwood_insert() IS 'INSTEAD OF INSERT trigger function for public.deadwood view';
COMMENT ON FUNCTION public.groundvegetation_insert() IS 'INSTEAD OF INSERT trigger function for public.groundvegetation view';
COMMENT ON FUNCTION public.images_insert() IS 'INSTEAD OF INSERT trigger function for public.images view';

-- Enable RLS on views (inherits from underlying tables)
ALTER VIEW public.campaigns SET (security_invoker = on);
ALTER VIEW public.trees SET (security_invoker = on);
ALTER VIEW public.sensors SET (security_invoker = on);
ALTER VIEW public.sensorreadings SET (security_invoker = on);
ALTER VIEW public.pointclouds SET (security_invoker = on);
ALTER VIEW public.environments SET (security_invoker = on);
ALTER VIEW public.stems SET (security_invoker = on);
ALTER VIEW public.species SET (security_invoker = on);
ALTER VIEW public.locations SET (security_invoker = on);
ALTER VIEW public.sensortypes SET (security_invoker = on);
ALTER VIEW public.plots SET (security_invoker = on);
ALTER VIEW public.managementevents SET (security_invoker = on);
ALTER VIEW public.disturbanceevents SET (security_invoker = on);
ALTER VIEW public.phenologyobservations SET (security_invoker = on);
ALTER VIEW public.deadwood SET (security_invoker = on);
ALTER VIEW public.groundvegetation SET (security_invoker = on);
ALTER VIEW public.images SET (security_invoker = on);
ALTER VIEW public.scenarios SET (security_invoker = on);
ALTER VIEW public.variants SET (security_invoker = on);

-- Grant USAGE on sequences to allow auto-incrementing IDs
GRANT USAGE ON SEQUENCE shared.campaigns_campaign_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.trees_tree_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE sensor.sensors_sensor_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE sensor.sensorreadings_sensor_reading_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.stems_stem_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.plots_plot_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.managementevents_management_event_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.disturbanceevents_disturbance_event_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.phenologyobservations_phenology_observation_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.deadwood_deadwood_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.groundvegetation_ground_vegetation_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE imagery.images_image_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE pointclouds.scannertypes_scanner_type_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE pointclouds.scanners_scanner_id_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.variants_variant_id_seq TO authenticated, service_role;
