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
--    sensors (adds sensor.Sensors.plot_id), and drops the now-empty sub-area
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
-- PART A — sensor.Sensors gains plot_id (sub-area now lives at the plot level)
-- =============================================================================
ALTER TABLE sensor.Sensors
    ADD COLUMN IF NOT EXISTS plot_id INTEGER REFERENCES shared.Plots(plot_id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sensors_plot ON sensor.Sensors(plot_id);
COMMENT ON COLUMN sensor.Sensors.plot_id IS
    'Named monitoring sub-area (plot) within the location, e.g. douglas_fir_plot. '
    'Populated from the location identifier of the external sensor sync; the site is location_id.';

-- =============================================================================
-- PART B — the two canonical sites (snake_case)
-- =============================================================================
UPDATE shared.Locations SET location_name = 'ecosense' WHERE location_name = 'Ecosense_MixedPlot';
UPDATE shared.Locations SET location_name = 'mathisle' WHERE location_name = 'Mathisle';

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
    v_plot_name TEXT;
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
    SELECT location_id INTO eco_id FROM shared.Locations WHERE location_name = 'ecosense';
    IF eco_id IS NULL THEN
        RAISE EXCEPTION 'ecosense location not found — cannot restructure';
    END IF;

    FOR i IN 1 .. array_length(mapping, 1) LOOP
        old_name    := mapping[i][1];
        v_plot_name := mapping[i][2];

        -- Ensure the plot exists under ecosense
        INSERT INTO shared.Plots (location_id, plot_name, created_by)
        VALUES (eco_id, v_plot_name, 'migration-36')
        ON CONFLICT (location_id, plot_name) DO NOTHING;
        SELECT plot_id INTO new_plotid
        FROM shared.Plots WHERE location_id = eco_id AND plot_name = v_plot_name;

        IF old_name = 'Ecosense_MixedPlot' THEN
            -- MixedPlot was renamed to 'ecosense' in Part B; its own sensors are
            -- already on eco_id and just need the mixed_plot plot assigned.
            UPDATE sensor.Sensors
            SET plot_id = new_plotid
            WHERE location_id = eco_id AND plot_id IS NULL;
        ELSE
            SELECT location_id INTO old_locid FROM shared.Locations WHERE location_name = old_name;
            IF old_locid IS NOT NULL THEN
                UPDATE sensor.Sensors
                SET location_id = eco_id, plot_id = new_plotid
                WHERE location_id = old_locid;
                DELETE FROM shared.Locations WHERE location_id = old_locid;
            END IF;
        END IF;
    END LOOP;
END $$;

-- =============================================================================
-- PART D — tree subplots to snake_case (kept: trees reference these plots)
-- =============================================================================
UPDATE shared.Plots SET plot_name = 'ecosense_plot_' || plot_number
    WHERE plot_name LIKE 'EcoSense Plot %';
UPDATE shared.Plots SET plot_name = 'mathisle'
    WHERE plot_name = 'Mathisle';

-- =============================================================================
-- PART E — remove orphaned demo locations
-- =============================================================================
DELETE FROM shared.Locations
    WHERE location_name IN (
        'University Forest Plot A', 'University Forest Plot B', 'Black Forest Test Site'
    );

-- =============================================================================
-- PART F — snake_case value renames (Tier 1 scenarios/variants, Tier 2 vocabs,
--          Tier 4 morphology). Tier 3 canonical standards intentionally omitted.
-- =============================================================================
-- Tier 1: scenarios
UPDATE shared.scenarios SET scenario_name = 'climate_change_2050' WHERE scenario_name = 'Climate_Change_2050';
UPDATE shared.scenarios SET scenario_name = 'climate_change_2100' WHERE scenario_name = 'Climate_Change_2100';
UPDATE shared.scenarios SET scenario_name = 'current_conditions' WHERE scenario_name = 'Current_Conditions';
UPDATE shared.scenarios SET scenario_name = 'drought_test' WHERE scenario_name = 'Drought_Test';
UPDATE shared.scenarios SET scenario_name = 'ecosense_growth_2035' WHERE scenario_name = 'Ecosense_Growth_2035';
UPDATE shared.scenarios SET scenario_name = 'ecosense_growth_2045' WHERE scenario_name = 'Ecosense_Growth_2045';
UPDATE shared.scenarios SET scenario_name = 'heat_wave' WHERE scenario_name = 'Heat_Wave';
UPDATE shared.scenarios SET scenario_name = 'increased_co2' WHERE scenario_name = 'Increased_CO2';
UPDATE shared.scenarios SET scenario_name = 'management_thinning' WHERE scenario_name = 'Management_Thinning';
UPDATE shared.scenarios SET scenario_name = 'mathisle_growth_2035' WHERE scenario_name = 'Mathisle_Growth_2035';
UPDATE shared.scenarios SET scenario_name = 'mathisle_growth_2045' WHERE scenario_name = 'Mathisle_Growth_2045';
UPDATE shared.scenarios SET scenario_name = 'no_management' WHERE scenario_name = 'No_Management';
-- Tier 1: variants
UPDATE shared.variants SET variant_name = 'baseline_2025' WHERE variant_name = 'Baseline_2025';
UPDATE shared.variants SET variant_name = 'growth_2035' WHERE variant_name = 'Growth_2035';
UPDATE shared.variants SET variant_name = 'growth_2045' WHERE variant_name = 'Growth_2045';
-- Tier 2: sensor types
UPDATE sensor.sensortypes SET sensor_type_name = 'barometric_pressure' WHERE sensor_type_name = 'Barometric_Pressure';
UPDATE sensor.sensortypes SET sensor_type_name = 'co2' WHERE sensor_type_name = 'CO2';
UPDATE sensor.sensortypes SET sensor_type_name = 'humidity' WHERE sensor_type_name = 'Humidity';
UPDATE sensor.sensortypes SET sensor_type_name = 'leaf_wetness' WHERE sensor_type_name = 'Leaf_Wetness';
UPDATE sensor.sensortypes SET sensor_type_name = 'light' WHERE sensor_type_name = 'Light';
UPDATE sensor.sensortypes SET sensor_type_name = 'precipitation' WHERE sensor_type_name = 'Precipitation';
UPDATE sensor.sensortypes SET sensor_type_name = 'sap_flow' WHERE sensor_type_name = 'Sap_Flow';
UPDATE sensor.sensortypes SET sensor_type_name = 'soil_moisture' WHERE sensor_type_name = 'Soil_Moisture';
UPDATE sensor.sensortypes SET sensor_type_name = 'soil_temperature' WHERE sensor_type_name = 'Soil_Temperature';
UPDATE sensor.sensortypes SET sensor_type_name = 'solar_radiation' WHERE sensor_type_name = 'Solar_Radiation';
UPDATE sensor.sensortypes SET sensor_type_name = 'stem_radial_variation' WHERE sensor_type_name = 'Stem_Radial_Variation';
UPDATE sensor.sensortypes SET sensor_type_name = 'temperature' WHERE sensor_type_name = 'Temperature';
UPDATE sensor.sensortypes SET sensor_type_name = 'wind_direction' WHERE sensor_type_name = 'Wind_Direction';
UPDATE sensor.sensortypes SET sensor_type_name = 'wind_speed' WHERE sensor_type_name = 'Wind_Speed';
-- Tier 2: straightness types
UPDATE trees.straightnesstypes SET straightness_name = 'moderate_sweep' WHERE straightness_name = 'Moderate_sweep';
UPDATE trees.straightnesstypes SET straightness_name = 'severe_sweep' WHERE straightness_name = 'Severe_sweep';
UPDATE trees.straightnesstypes SET straightness_name = 'slight_sweep' WHERE straightness_name = 'Slight_sweep';
UPDATE trees.straightnesstypes SET straightness_name = 'straight' WHERE straightness_name = 'Straight';
-- Tier 4: morphology descriptors
UPDATE trees.barkcharacteristics SET bark_characteristic_name = 'exfoliating' WHERE bark_characteristic_name = 'Exfoliating';
UPDATE trees.barkcharacteristics SET bark_characteristic_name = 'furrowed' WHERE bark_characteristic_name = 'Furrowed';
UPDATE trees.barkcharacteristics SET bark_characteristic_name = 'plated' WHERE bark_characteristic_name = 'Plated';
UPDATE trees.barkcharacteristics SET bark_characteristic_name = 'scaly' WHERE bark_characteristic_name = 'Scaly';
UPDATE trees.barkcharacteristics SET bark_characteristic_name = 'smooth' WHERE bark_characteristic_name = 'Smooth';
UPDATE trees.branchingpatterns SET branching_pattern_name = 'alternate' WHERE branching_pattern_name = 'Alternate';
UPDATE trees.branchingpatterns SET branching_pattern_name = 'opposite' WHERE branching_pattern_name = 'Opposite';
UPDATE trees.branchingpatterns SET branching_pattern_name = 'random' WHERE branching_pattern_name = 'Random';
UPDATE trees.branchingpatterns SET branching_pattern_name = 'spiral' WHERE branching_pattern_name = 'Spiral';
UPDATE trees.branchingpatterns SET branching_pattern_name = 'whorled' WHERE branching_pattern_name = 'Whorled';
UPDATE trees.crownshapes SET crown_shape_name = 'broad' WHERE crown_shape_name = 'Broad';
UPDATE trees.crownshapes SET crown_shape_name = 'columnar' WHERE crown_shape_name = 'Columnar';
UPDATE trees.crownshapes SET crown_shape_name = 'conical' WHERE crown_shape_name = 'Conical';
UPDATE trees.crownshapes SET crown_shape_name = 'ellipsoidal' WHERE crown_shape_name = 'Ellipsoidal';
UPDATE trees.crownshapes SET crown_shape_name = 'fastigiate' WHERE crown_shape_name = 'Fastigiate';
UPDATE trees.crownshapes SET crown_shape_name = 'globose' WHERE crown_shape_name = 'Globose';
UPDATE trees.crownshapes SET crown_shape_name = 'irregular' WHERE crown_shape_name = 'Irregular';
UPDATE trees.crownshapes SET crown_shape_name = 'ovoid' WHERE crown_shape_name = 'Ovoid';
UPDATE trees.crownshapes SET crown_shape_name = 'pyramidal' WHERE crown_shape_name = 'Pyramidal';
UPDATE trees.crownshapes SET crown_shape_name = 'umbrella' WHERE crown_shape_name = 'Umbrella';
UPDATE trees.crownshapes SET crown_shape_name = 'vase' WHERE crown_shape_name = 'Vase';
UPDATE trees.crownshapes SET crown_shape_name = 'weeping' WHERE crown_shape_name = 'Weeping';
UPDATE trees.crownarchitectures SET crown_architecture_name = 'abcurrent' WHERE crown_architecture_name = 'Abcurrent';
UPDATE trees.crownarchitectures SET crown_architecture_name = 'adcurrent' WHERE crown_architecture_name = 'Adcurrent';
UPDATE trees.crownarchitectures SET crown_architecture_name = 'bicurrent' WHERE crown_architecture_name = 'Bicurrent';
UPDATE trees.crownarchitectures SET crown_architecture_name = 'decurrent' WHERE crown_architecture_name = 'Decurrent';
UPDATE trees.crownarchitectures SET crown_architecture_name = 'excurrent' WHERE crown_architecture_name = 'Excurrent';
UPDATE trees.growthforms SET growth_form_name = 'arborescent' WHERE growth_form_name = 'Arborescent';
UPDATE trees.growthforms SET growth_form_name = 'dendroid' WHERE growth_form_name = 'Dendroid';
UPDATE trees.growthforms SET growth_form_name = 'diplocaulescent' WHERE growth_form_name = 'Diplocaulescent';
UPDATE trees.growthforms SET growth_form_name = 'phanerophyte' WHERE growth_form_name = 'Phanerophyte';
UPDATE trees.growthorientations SET growth_orientation_name = 'orthotropic' WHERE growth_orientation_name = 'Orthotropic';
UPDATE trees.growthorientations SET growth_orientation_name = 'plagiotrophic' WHERE growth_orientation_name = 'Plagiotrophic';
UPDATE trees.phanerophyteheightclasses SET height_class_name = 'megaphanerophyte' WHERE height_class_name = 'Megaphanerophyte';
UPDATE trees.phanerophyteheightclasses SET height_class_name = 'mesophanerophyte' WHERE height_class_name = 'Mesophanerophyte';
UPDATE trees.phanerophyteheightclasses SET height_class_name = 'microphanerophyte' WHERE height_class_name = 'Microphanerophyte';
UPDATE trees.axisstructures SET axis_structure_name = 'polycormic' WHERE axis_structure_name = 'Polycormic';
UPDATE trees.axisstructures SET axis_structure_name = 'single_leader' WHERE axis_structure_name = 'Single Leader';
UPDATE trees.tapertypes SET taper_type_name = 'cone' WHERE taper_type_name = 'Cone';
UPDATE trees.tapertypes SET taper_type_name = 'cylinder' WHERE taper_type_name = 'Cylinder';
UPDATE trees.tapertypes SET taper_type_name = 'neiloid' WHERE taper_type_name = 'Neiloid';
UPDATE trees.tapertypes SET taper_type_name = 'paraboloid' WHERE taper_type_name = 'Paraboloid';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'cone' WHERE geometric_solid_name = 'Cone';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'cylinder' WHERE geometric_solid_name = 'Cylinder';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'elongated_spheroid' WHERE geometric_solid_name = 'Elongated Spheroid';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'expanded_paraboloid' WHERE geometric_solid_name = 'Expanded Paraboloid';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'fat_cone' WHERE geometric_solid_name = 'Fat Cone';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'neiloid' WHERE geometric_solid_name = 'Neiloid';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'paraboloid' WHERE geometric_solid_name = 'Paraboloid';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'round_edge_cylinder' WHERE geometric_solid_name = 'Round Edge Cylinder';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'spheroid' WHERE geometric_solid_name = 'Spheroid';
UPDATE trees.geometriccrownsolids SET geometric_solid_name = 'thin_neiloid' WHERE geometric_solid_name = 'Thin Neiloid';
UPDATE trees.shootelongationtypes SET shoot_elongation_type_name = 'long_shoots' WHERE shoot_elongation_type_name = 'Long Shoots';
UPDATE trees.shootelongationtypes SET shoot_elongation_type_name = 'short_shoots' WHERE shoot_elongation_type_name = 'Short Shoots';
UPDATE trees.shootelongationtypes SET shoot_elongation_type_name = 'spur_shoots' WHERE shoot_elongation_type_name = 'Spur Shoots';
UPDATE trees.branchelongationhabits SET elongation_habit_name = 'acrotony' WHERE elongation_habit_name = 'Acrotony';
UPDATE trees.branchelongationhabits SET elongation_habit_name = 'basitony' WHERE elongation_habit_name = 'Basitony';
UPDATE trees.branchelongationhabits SET elongation_habit_name = 'mesotony' WHERE elongation_habit_name = 'Mesotony';

COMMIT;
