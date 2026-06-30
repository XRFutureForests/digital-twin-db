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
    l.locationname,
    s.scenarioname,
    vt.varianttypename
FROM shared.variants v
LEFT JOIN shared.locations  l  ON v.locationid  = l.locationid
LEFT JOIN shared.scenarios  s  ON v.scenarioid  = s.scenarioid
LEFT JOIN shared.varianttypes vt ON v.varianttypeid = vt.varianttypeid;

COMMENT ON VIEW public.variants IS 'Forest state variants with location, scenario, and type names joined. Filter by locationid+scenarioid to get the time-step list for a site+scenario combination.';

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
        campaignname, campaigntype, locationid, startdate, enddate,
        description, methodology, equipment, personnel,
        createdby, updatedby
    ) VALUES (
        NEW.campaignname, NEW.campaigntype, NEW.locationid, NEW.startdate, NEW.enddate,
        NEW.description, NEW.methodology, NEW.equipment, NEW.personnel,
        NEW.createdby, NEW.updatedby
    ) RETURNING campaignid INTO NEW.campaignid;
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
        campaignname = NEW.campaignname,
        campaigntype = NEW.campaigntype,
        locationid = NEW.locationid,
        startdate = NEW.startdate,
        enddate = NEW.enddate,
        description = NEW.description,
        methodology = NEW.methodology,
        equipment = NEW.equipment,
        personnel = NEW.personnel,
        updatedat = NOW(),
        updatedby = NEW.updatedby
    WHERE campaignid = OLD.campaignid;
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
    DELETE FROM shared.campaigns WHERE campaignid = OLD.campaignid;
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
        treeentityid, variantid, parenttreeid, pointcloudid, campaignid,
        locationid, plotid, scenarioid, varianttypeid, processid,
        speciesid, treestatusid, branchingpatternid, barkcharacteristicid,
        measurementdate, datasourcetypeid,
        height_m, crownwidth_m, crownbaseheight_m, crownboundary,
        crownoffsetx_m, crownoffsety_m, volume_m3,
        position, positionoriginal, sourcecrs,
        leanangle_deg, leandirection_azimuth, timedelta_yrs, age_years,
        healthscore, biomass_kg, carboncontent_kg,
        speciesconfidence, positionconfidence, heightconfidence,
        crownclassid, damageagentid, defoliation_percent, discolouration_percent, crowntransparency_percent,
        statuschangedate, fieldnotes, createdby, updatedby
    ) VALUES (
        COALESCE(NEW.treeentityid, gen_random_uuid()), NEW.variantid, NEW.parenttreeid, NEW.pointcloudid, NEW.campaignid,
        NEW.locationid, NEW.plotid, NEW.scenarioid, NEW.varianttypeid, NEW.processid,
        NEW.speciesid, NEW.treestatusid, NEW.branchingpatternid, NEW.barkcharacteristicid,
        NEW.measurementdate, NEW.datasourcetypeid,
        NEW.height_m, NEW.crownwidth_m, NEW.crownbaseheight_m, NEW.crownboundary,
        NEW.crownoffsetx_m, NEW.crownoffsety_m, NEW.volume_m3,
        NEW.position, NEW.positionoriginal, NEW.sourcecrs,
        NEW.leanangle_deg, NEW.leandirection_azimuth, NEW.timedelta_yrs, NEW.age_years,
        NEW.healthscore, NEW.biomass_kg, NEW.carboncontent_kg,
        NEW.speciesconfidence, NEW.positionconfidence, NEW.heightconfidence,
        NEW.crownclassid, NEW.damageagentid, NEW.defoliation_percent, NEW.discolouration_percent, NEW.crowntransparency_percent,
        NEW.statuschangedate, NEW.fieldnotes, NEW.createdby, NEW.updatedby
    ) RETURNING treeid INTO NEW.treeid;
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
        treeentityid = NEW.treeentityid,
        variantid = NEW.variantid,
        parenttreeid = NEW.parenttreeid,
        pointcloudid = NEW.pointcloudid,
        campaignid = NEW.campaignid,
        locationid = NEW.locationid,
        plotid = NEW.plotid,
        scenarioid = NEW.scenarioid,
        varianttypeid = NEW.varianttypeid,
        processid = NEW.processid,
        speciesid = NEW.speciesid,
        treestatusid = NEW.treestatusid,
        branchingpatternid = NEW.branchingpatternid,
        barkcharacteristicid = NEW.barkcharacteristicid,
        measurementdate = NEW.measurementdate,
        datasourcetypeid = NEW.datasourcetypeid,
        height_m = NEW.height_m,
        crownwidth_m = NEW.crownwidth_m,
        crownbaseheight_m = NEW.crownbaseheight_m,
        crownboundary = NEW.crownboundary,
        crownoffsetx_m = NEW.crownoffsetx_m,
        crownoffsety_m = NEW.crownoffsety_m,
        volume_m3 = NEW.volume_m3,
        position = NEW.position,
        positionoriginal = NEW.positionoriginal,
        sourcecrs = NEW.sourcecrs,
        leanangle_deg = NEW.leanangle_deg,
        leandirection_azimuth = NEW.leandirection_azimuth,
        timedelta_yrs = NEW.timedelta_yrs,
        age_years = NEW.age_years,
        healthscore = NEW.healthscore,
        biomass_kg = NEW.biomass_kg,
        carboncontent_kg = NEW.carboncontent_kg,
        speciesconfidence = NEW.speciesconfidence,
        positionconfidence = NEW.positionconfidence,
        heightconfidence = NEW.heightconfidence,
        crownclassid = NEW.crownclassid,
        damageagentid = NEW.damageagentid,
        defoliation_percent = NEW.defoliation_percent,
        discolouration_percent = NEW.discolouration_percent,
        crowntransparency_percent = NEW.crowntransparency_percent,
        statuschangedate = NEW.statuschangedate,
        fieldnotes = NEW.fieldnotes,
        updatedat = NOW(),
        updatedby = NEW.updatedby
    WHERE treeid = OLD.treeid;
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
    DELETE FROM trees.trees WHERE treeid = OLD.treeid;
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
        locationid = NEW.locationid,
        sensortypeid = NEW.sensortypeid,
        campaignid = NEW.campaignid,
        sensormodel = NEW.sensormodel,
        serialnumber = NEW.serialnumber,
        position = NEW.position,
        positionoriginal = NEW.positionoriginal,
        sourcecrs = NEW.sourcecrs,
        installationdate = NEW.installationdate,
        installationheight_m = NEW.installationheight_m,
        decommissiondate = NEW.decommissiondate,
        calibrationdate = NEW.calibrationdate,
        nextcalibrationdate = NEW.nextcalibrationdate,
        samplinginterval_seconds = NEW.samplinginterval_seconds,
        readingtype = NEW.readingtype,
        unit = NEW.unit,
        minvalue = NEW.minvalue,
        maxvalue = NEW.maxvalue,
        accuracy = NEW.accuracy,
        batterylevel_percent = NEW.batterylevel_percent,
        isactive = NEW.isactive,
        maintenancenotes = NEW.maintenancenotes,
        externalid = NEW.externalid,
        externalmetadata = NEW.externalmetadata,
        updatedat = NOW(),
        updatedby = NEW.updatedby
    WHERE sensorid = OLD.sensorid;
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
    DELETE FROM sensor.sensors WHERE sensorid = OLD.sensorid;
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
    INSERT INTO sensor.sensorreadings (sensorid, timestamp, value, quality, scenarioid, batteryvoltage, signalstrength, notes)
    VALUES (NEW.sensorid, NEW.timestamp, NEW.value, NEW.quality, NEW.scenarioid, NEW.batteryvoltage, NEW.signalstrength, NEW.notes);
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
        locationid, plotname, plotnumber, area_m2,
        boundary, centerpoint, description,
        createdby, updatedby
    ) VALUES (
        NEW.locationid, NEW.plotname, NEW.plotnumber, NEW.area_m2,
        NEW.boundary, NEW.centerpoint, NEW.description,
        NEW.createdby, NEW.updatedby
    ) RETURNING plotid INTO NEW.plotid;
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
        locationid, plotid, eventtype, eventdate, enddate,
        description, affectedarea_m2, performedby, notes,
        createdby, updatedby
    ) VALUES (
        NEW.locationid, NEW.plotid, NEW.eventtype, NEW.eventdate, NEW.enddate,
        NEW.description, NEW.affectedarea_m2, NEW.performedby, NEW.notes,
        NEW.createdby, NEW.updatedby
    ) RETURNING managementeventid INTO NEW.managementeventid;
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
        locationid, plotid, disturbancetype, eventdate, enddate,
        severity, affectedarea_m2, description, notes,
        createdby, updatedby
    ) VALUES (
        NEW.locationid, NEW.plotid, NEW.disturbancetype, NEW.eventdate, NEW.enddate,
        NEW.severity, NEW.affectedarea_m2, NEW.description, NEW.notes,
        NEW.createdby, NEW.updatedby
    ) RETURNING disturbanceeventid INTO NEW.disturbanceeventid;
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
        treeid, observationdate, phenophasetype,
        phenophasestatus, intensity_percent, observer, notes, createdby
    ) VALUES (
        NEW.treeid, NEW.observationdate, NEW.phenophasetype,
        NEW.phenophasestatus, NEW.intensity_percent, NEW.observer, NEW.notes, NEW.createdby
    ) RETURNING phenologyobservationid INTO NEW.phenologyobservationid;
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
        locationid, plotid, treeid, speciesid,
        woodtype, length_m, diameter_cm, decayclass,
        volume_m3, position, measurementdate, notes, createdby
    ) VALUES (
        NEW.locationid, NEW.plotid, NEW.treeid, NEW.speciesid,
        NEW.woodtype, NEW.length_m, NEW.diameter_cm, NEW.decayclass,
        NEW.volume_m3, NEW.position, NEW.measurementdate, NEW.notes, NEW.createdby
    ) RETURNING deadwoodid INTO NEW.deadwoodid;
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
        locationid, plotid, speciesname, coverpercent,
        height_cm, layer, measurementdate, notes, createdby
    ) VALUES (
        NEW.locationid, NEW.plotid, NEW.speciesname, NEW.coverpercent,
        NEW.height_cm, NEW.layer, NEW.measurementdate, NEW.notes, NEW.createdby
    ) RETURNING groundvegetationid INTO NEW.groundvegetationid;
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
        locationid, plotid, campaignid, capturedate,
        filepath, fileformat, resolution_px, cameramodel,
        position, altitude_m, heading_deg, pitch_deg, roll_deg,
        groundsampledistance_cm, description, createdby, updatedby
    ) VALUES (
        NEW.locationid, NEW.plotid, NEW.campaignid, NEW.capturedate,
        NEW.filepath, NEW.fileformat, NEW.resolution_px, NEW.cameramodel,
        NEW.position, NEW.altitude_m, NEW.heading_deg, NEW.pitch_deg, NEW.roll_deg,
        NEW.groundsampledistance_cm, NEW.description, NEW.createdby, NEW.updatedby
    ) RETURNING imageid INTO NEW.imageid;
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
GRANT USAGE ON SEQUENCE shared.campaigns_campaignid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.trees_treeid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE sensor.sensors_sensorid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE sensor.sensorreadings_sensorreadingid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.stems_stemid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.plots_plotid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.managementevents_managementeventid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.disturbanceevents_disturbanceeventid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.phenologyobservations_phenologyobservationid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.deadwood_deadwoodid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.groundvegetation_groundvegetationid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE imagery.images_imageid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE pointclouds.scannertypes_scannertypeid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE pointclouds.scanners_scannerid_seq TO authenticated, service_role;
GRANT USAGE ON SEQUENCE shared.variants_variantid_seq TO authenticated, service_role;
