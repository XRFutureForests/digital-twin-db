-- XR Future Forests Lab - Location/plot restructure + snake_case value naming
--
-- Two coupled cleanups, applied together because both rewrite the same rows:
--
-- 1. LOCATION MODEL. Unreal Engine loads a forest by LOCATION, so the location
--    level must be exactly the two research sites: 'mathisle' and 'ecosense'.
--    Previously the Ecosense monitoring sub-areas (DouglasFirPlot, SilverFirPlot,
--    BeechPlot, the towers, soil-intensive plots, scaffold, university) were
--    modelled as separate LOCATIONS because the Aquarius sensor sync created one
--    location per time-series LocationIdentifier. This migration demotes each of
--    those sub-areas to a PLOT under the single 'ecosense' location, re-points its
--    sensors (adds sensor.Sensors.PlotID), and drops the now-empty sub-area
--    locations. It also removes three orphaned demo locations (University Forest
--    Plot A/B, Black Forest Test Site — 0 trees / 0 sensors / 0 variants).
--    The tree inventory already sits under one location (was 'Ecosense_MixedPlot',
--    now 'ecosense'); its numbered subplots ('EcoSense Plot 1..18') are kept as a
--    second family of plots (renamed 'ecosense_plot_N') since trees reference them.
--
-- 2. SNAKE_CASE VALUES. Identifier-style string values are standardised to
--    snake_case for cross-DB consistency (Tier 1: locations/plots/scenarios/
--    variants; Tier 2: our controlled vocabularies; Tier 4: morphology
--    descriptors). Canonical standards are intentionally LEFT ALONE: Koppen
--    climate codes (Af/BWh/Cfb), USDA soil orders (Alfisol/Histosol), and species
--    common + scientific names (European Beech / Fagus sylvatica).
--    Lookup values are referenced by ID, so these renames do not affect FKs. The
--    CHECK'd vocabularies (tree_status, damage_agents, crown_classes,
--    variant_types) were already snake_case, so no constraints change here.
--
-- Idempotent: every statement is guarded (ADD COLUMN IF NOT EXISTS, ON CONFLICT
-- DO NOTHING, WHERE old_value). On a fresh build the lookup CSVs + init already
-- produce the target names/structure, so this file is a no-op there.
--
-- Dependencies: 11-shared-schema.sql, 13-trees-schema.sql, 30-load-lookup-tables.sql

BEGIN;

-- =============================================================================
-- PART A — sensor.Sensors gains PlotID (sub-area now lives at the plot level)
-- =============================================================================
ALTER TABLE sensor.Sensors
    ADD COLUMN IF NOT EXISTS PlotID INTEGER REFERENCES shared.Plots(PlotID) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sensors_plot ON sensor.Sensors(PlotID);
COMMENT ON COLUMN sensor.Sensors.PlotID IS
    'Named monitoring sub-area (plot) within the location, e.g. douglas_fir_plot. '
    'Populated from the Aquarius LocationIdentifier; the site is LocationID.';

-- =============================================================================
-- PART B — the two canonical sites (snake_case)
-- =============================================================================
UPDATE shared.Locations SET LocationName = 'ecosense' WHERE LocationName = 'Ecosense_MixedPlot';
UPDATE shared.Locations SET LocationName = 'mathisle' WHERE LocationName = 'Mathisle';

-- =============================================================================
-- PART C — demote Ecosense sub-area locations to plots under 'ecosense'
-- =============================================================================
DO $$
DECLARE
    eco_id     INT;
    new_plotid INT;
    old_locid  INT;
    i          INT;
    old_name   TEXT;
    plot_name  TEXT;
    -- old location name -> target plot name
    mapping    TEXT[][] := ARRAY[
        ['Ecosense_MixedPlot',             'mixed_plot'],
        ['Ecosense_Experiment_Scaffold',   'experiment_scaffold'],
        ['Ecosense_DouglasFirPlot',        'douglas_fir_plot'],
        ['Ecosense_SilverFirPlot',         'silver_fir_plot'],
        ['Ecosense_BeechPlot',             'beech_plot'],
        ['Ecosense_Soil_Intensive_Plot_1', 'soil_intensive_plot_1'],
        ['Ecosense_MainTower',             'main_tower'],
        ['Ecosense_DouglasFirTower',       'douglas_fir_tower'],
        ['Ecosense_BeechTower',            'beech_tower'],
        ['Ecosense_Soil_Intensive_Plot_2', 'soil_intensive_plot_2'],
        ['Ecosense_University',            'university']
    ];
BEGIN
    SELECT LocationID INTO eco_id FROM shared.Locations WHERE LocationName = 'ecosense';
    IF eco_id IS NULL THEN
        RAISE EXCEPTION 'ecosense location not found — cannot restructure';
    END IF;

    FOR i IN 1 .. array_length(mapping, 1) LOOP
        old_name  := mapping[i][1];
        plot_name := mapping[i][2];

        -- Ensure the plot exists under ecosense
        INSERT INTO shared.Plots (LocationID, PlotName, CreatedBy)
        VALUES (eco_id, plot_name, 'migration-36')
        ON CONFLICT (LocationID, PlotName) DO NOTHING;
        SELECT PlotID INTO new_plotid
        FROM shared.Plots WHERE LocationID = eco_id AND PlotName = plot_name;

        IF old_name = 'Ecosense_MixedPlot' THEN
            -- MixedPlot was renamed to 'ecosense' in Part B; its own sensors are
            -- already on eco_id and just need the mixed_plot plot assigned.
            UPDATE sensor.Sensors
            SET PlotID = new_plotid
            WHERE LocationID = eco_id AND PlotID IS NULL;
        ELSE
            SELECT LocationID INTO old_locid FROM shared.Locations WHERE LocationName = old_name;
            IF old_locid IS NOT NULL THEN
                UPDATE sensor.Sensors
                SET LocationID = eco_id, PlotID = new_plotid
                WHERE LocationID = old_locid;
                DELETE FROM shared.Locations WHERE LocationID = old_locid;
            END IF;
        END IF;
    END LOOP;
END $$;

-- =============================================================================
-- PART D — tree subplots to snake_case (kept: trees reference these plots)
-- =============================================================================
UPDATE shared.Plots SET PlotName = 'ecosense_plot_' || PlotNumber
    WHERE PlotName LIKE 'EcoSense Plot %';
UPDATE shared.Plots SET PlotName = 'mathisle'
    WHERE PlotName = 'Mathisle';

-- =============================================================================
-- PART E — remove orphaned demo locations
-- =============================================================================
DELETE FROM shared.Locations
    WHERE LocationName IN (
        'University Forest Plot A', 'University Forest Plot B', 'Black Forest Test Site'
    );

-- =============================================================================
-- PART F — snake_case value renames (Tier 1 scenarios/variants, Tier 2 vocabs,
--          Tier 4 morphology). Tier 3 canonical standards intentionally omitted.
-- =============================================================================
-- Tier 1: scenarios
UPDATE shared.scenarios SET scenarioname = 'climate_change_2050' WHERE scenarioname = 'Climate_Change_2050';
UPDATE shared.scenarios SET scenarioname = 'climate_change_2100' WHERE scenarioname = 'Climate_Change_2100';
UPDATE shared.scenarios SET scenarioname = 'current_conditions' WHERE scenarioname = 'Current_Conditions';
UPDATE shared.scenarios SET scenarioname = 'drought_test' WHERE scenarioname = 'Drought_Test';
UPDATE shared.scenarios SET scenarioname = 'ecosense_growth_2035' WHERE scenarioname = 'Ecosense_Growth_2035';
UPDATE shared.scenarios SET scenarioname = 'ecosense_growth_2045' WHERE scenarioname = 'Ecosense_Growth_2045';
UPDATE shared.scenarios SET scenarioname = 'heat_wave' WHERE scenarioname = 'Heat_Wave';
UPDATE shared.scenarios SET scenarioname = 'increased_co2' WHERE scenarioname = 'Increased_CO2';
UPDATE shared.scenarios SET scenarioname = 'management_thinning' WHERE scenarioname = 'Management_Thinning';
UPDATE shared.scenarios SET scenarioname = 'mathisle_growth_2035' WHERE scenarioname = 'Mathisle_Growth_2035';
UPDATE shared.scenarios SET scenarioname = 'mathisle_growth_2045' WHERE scenarioname = 'Mathisle_Growth_2045';
UPDATE shared.scenarios SET scenarioname = 'no_management' WHERE scenarioname = 'No_Management';
-- Tier 1: variants
UPDATE shared.variants SET variantname = 'baseline_2025' WHERE variantname = 'Baseline_2025';
UPDATE shared.variants SET variantname = 'growth_2035' WHERE variantname = 'Growth_2035';
UPDATE shared.variants SET variantname = 'growth_2045' WHERE variantname = 'Growth_2045';
-- Tier 2: sensor types
UPDATE sensor.sensortypes SET sensortypename = 'barometric_pressure' WHERE sensortypename = 'Barometric_Pressure';
UPDATE sensor.sensortypes SET sensortypename = 'co2' WHERE sensortypename = 'CO2';
UPDATE sensor.sensortypes SET sensortypename = 'humidity' WHERE sensortypename = 'Humidity';
UPDATE sensor.sensortypes SET sensortypename = 'leaf_wetness' WHERE sensortypename = 'Leaf_Wetness';
UPDATE sensor.sensortypes SET sensortypename = 'light' WHERE sensortypename = 'Light';
UPDATE sensor.sensortypes SET sensortypename = 'precipitation' WHERE sensortypename = 'Precipitation';
UPDATE sensor.sensortypes SET sensortypename = 'sap_flow' WHERE sensortypename = 'Sap_Flow';
UPDATE sensor.sensortypes SET sensortypename = 'soil_moisture' WHERE sensortypename = 'Soil_Moisture';
UPDATE sensor.sensortypes SET sensortypename = 'soil_temperature' WHERE sensortypename = 'Soil_Temperature';
UPDATE sensor.sensortypes SET sensortypename = 'solar_radiation' WHERE sensortypename = 'Solar_Radiation';
UPDATE sensor.sensortypes SET sensortypename = 'stem_radial_variation' WHERE sensortypename = 'Stem_Radial_Variation';
UPDATE sensor.sensortypes SET sensortypename = 'temperature' WHERE sensortypename = 'Temperature';
UPDATE sensor.sensortypes SET sensortypename = 'wind_direction' WHERE sensortypename = 'Wind_Direction';
UPDATE sensor.sensortypes SET sensortypename = 'wind_speed' WHERE sensortypename = 'Wind_Speed';
-- Tier 2: straightness types
UPDATE trees.straightnesstypes SET straightnessname = 'moderate_sweep' WHERE straightnessname = 'Moderate_sweep';
UPDATE trees.straightnesstypes SET straightnessname = 'severe_sweep' WHERE straightnessname = 'Severe_sweep';
UPDATE trees.straightnesstypes SET straightnessname = 'slight_sweep' WHERE straightnessname = 'Slight_sweep';
UPDATE trees.straightnesstypes SET straightnessname = 'straight' WHERE straightnessname = 'Straight';
-- Tier 4: morphology descriptors
UPDATE trees.barkcharacteristics SET barkcharacteristicname = 'exfoliating' WHERE barkcharacteristicname = 'Exfoliating';
UPDATE trees.barkcharacteristics SET barkcharacteristicname = 'furrowed' WHERE barkcharacteristicname = 'Furrowed';
UPDATE trees.barkcharacteristics SET barkcharacteristicname = 'plated' WHERE barkcharacteristicname = 'Plated';
UPDATE trees.barkcharacteristics SET barkcharacteristicname = 'scaly' WHERE barkcharacteristicname = 'Scaly';
UPDATE trees.barkcharacteristics SET barkcharacteristicname = 'smooth' WHERE barkcharacteristicname = 'Smooth';
UPDATE trees.branchingpatterns SET branchingpatternname = 'alternate' WHERE branchingpatternname = 'Alternate';
UPDATE trees.branchingpatterns SET branchingpatternname = 'opposite' WHERE branchingpatternname = 'Opposite';
UPDATE trees.branchingpatterns SET branchingpatternname = 'random' WHERE branchingpatternname = 'Random';
UPDATE trees.branchingpatterns SET branchingpatternname = 'spiral' WHERE branchingpatternname = 'Spiral';
UPDATE trees.branchingpatterns SET branchingpatternname = 'whorled' WHERE branchingpatternname = 'Whorled';
UPDATE trees.crownshapes SET crownshapename = 'broad' WHERE crownshapename = 'Broad';
UPDATE trees.crownshapes SET crownshapename = 'columnar' WHERE crownshapename = 'Columnar';
UPDATE trees.crownshapes SET crownshapename = 'conical' WHERE crownshapename = 'Conical';
UPDATE trees.crownshapes SET crownshapename = 'ellipsoidal' WHERE crownshapename = 'Ellipsoidal';
UPDATE trees.crownshapes SET crownshapename = 'fastigiate' WHERE crownshapename = 'Fastigiate';
UPDATE trees.crownshapes SET crownshapename = 'globose' WHERE crownshapename = 'Globose';
UPDATE trees.crownshapes SET crownshapename = 'irregular' WHERE crownshapename = 'Irregular';
UPDATE trees.crownshapes SET crownshapename = 'ovoid' WHERE crownshapename = 'Ovoid';
UPDATE trees.crownshapes SET crownshapename = 'pyramidal' WHERE crownshapename = 'Pyramidal';
UPDATE trees.crownshapes SET crownshapename = 'umbrella' WHERE crownshapename = 'Umbrella';
UPDATE trees.crownshapes SET crownshapename = 'vase' WHERE crownshapename = 'Vase';
UPDATE trees.crownshapes SET crownshapename = 'weeping' WHERE crownshapename = 'Weeping';
UPDATE trees.crownarchitectures SET crownarchitecturename = 'abcurrent' WHERE crownarchitecturename = 'Abcurrent';
UPDATE trees.crownarchitectures SET crownarchitecturename = 'adcurrent' WHERE crownarchitecturename = 'Adcurrent';
UPDATE trees.crownarchitectures SET crownarchitecturename = 'bicurrent' WHERE crownarchitecturename = 'Bicurrent';
UPDATE trees.crownarchitectures SET crownarchitecturename = 'decurrent' WHERE crownarchitecturename = 'Decurrent';
UPDATE trees.crownarchitectures SET crownarchitecturename = 'excurrent' WHERE crownarchitecturename = 'Excurrent';
UPDATE trees.growthforms SET growthformname = 'arborescent' WHERE growthformname = 'Arborescent';
UPDATE trees.growthforms SET growthformname = 'dendroid' WHERE growthformname = 'Dendroid';
UPDATE trees.growthforms SET growthformname = 'diplocaulescent' WHERE growthformname = 'Diplocaulescent';
UPDATE trees.growthforms SET growthformname = 'phanerophyte' WHERE growthformname = 'Phanerophyte';
UPDATE trees.growthorientations SET growthorientationname = 'orthotropic' WHERE growthorientationname = 'Orthotropic';
UPDATE trees.growthorientations SET growthorientationname = 'plagiotrophic' WHERE growthorientationname = 'Plagiotrophic';
UPDATE trees.phanerophyteheightclasses SET heightclassname = 'megaphanerophyte' WHERE heightclassname = 'Megaphanerophyte';
UPDATE trees.phanerophyteheightclasses SET heightclassname = 'mesophanerophyte' WHERE heightclassname = 'Mesophanerophyte';
UPDATE trees.phanerophyteheightclasses SET heightclassname = 'microphanerophyte' WHERE heightclassname = 'Microphanerophyte';
UPDATE trees.axisstructures SET axisstructurename = 'polycormic' WHERE axisstructurename = 'Polycormic';
UPDATE trees.axisstructures SET axisstructurename = 'single_leader' WHERE axisstructurename = 'Single Leader';
UPDATE trees.tapertypes SET tapertypename = 'cone' WHERE tapertypename = 'Cone';
UPDATE trees.tapertypes SET tapertypename = 'cylinder' WHERE tapertypename = 'Cylinder';
UPDATE trees.tapertypes SET tapertypename = 'neiloid' WHERE tapertypename = 'Neiloid';
UPDATE trees.tapertypes SET tapertypename = 'paraboloid' WHERE tapertypename = 'Paraboloid';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'cone' WHERE geometricsolidname = 'Cone';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'cylinder' WHERE geometricsolidname = 'Cylinder';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'elongated_spheroid' WHERE geometricsolidname = 'Elongated Spheroid';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'expanded_paraboloid' WHERE geometricsolidname = 'Expanded Paraboloid';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'fat_cone' WHERE geometricsolidname = 'Fat Cone';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'neiloid' WHERE geometricsolidname = 'Neiloid';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'paraboloid' WHERE geometricsolidname = 'Paraboloid';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'round_edge_cylinder' WHERE geometricsolidname = 'Round Edge Cylinder';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'spheroid' WHERE geometricsolidname = 'Spheroid';
UPDATE trees.geometriccrownsolids SET geometricsolidname = 'thin_neiloid' WHERE geometricsolidname = 'Thin Neiloid';
UPDATE trees.shootelongationtypes SET shootelongationtypename = 'long_shoots' WHERE shootelongationtypename = 'Long Shoots';
UPDATE trees.shootelongationtypes SET shootelongationtypename = 'short_shoots' WHERE shootelongationtypename = 'Short Shoots';
UPDATE trees.shootelongationtypes SET shootelongationtypename = 'spur_shoots' WHERE shootelongationtypename = 'Spur Shoots';
UPDATE trees.branchelongationhabits SET elongationhabitname = 'acrotony' WHERE elongationhabitname = 'Acrotony';
UPDATE trees.branchelongationhabits SET elongationhabitname = 'basitony' WHERE elongationhabitname = 'Basitony';
UPDATE trees.branchelongationhabits SET elongationhabitname = 'mesotony' WHERE elongationhabitname = 'Mesotony';

COMMIT;
