-- =============================================================================
-- REFERENCE DATA 2026-11-09 (XRFF-661)
-- =============================================================================
-- The rows a fresh init held on 2026-11-09: the lookup tables loaded from
-- data/lookups/*.csv and the rows earlier migrations seeded (workflow menu in
-- shared.processes, management regimes, climate pathways, units, the lookup
-- registry, the census plots). Data-only pg_dump with triggers disabled, so
-- created_by and the derived columns keep their recorded values.
-- The CSVs stay the source of truth: refresh-lookups.sql reloads them at the
-- end of every fresh init, and scripts/admin/refresh_lookups.py at run time.
-- =============================================================================

--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: units; Type: TABLE DATA; Schema: sensor; Owner: supabase_admin
--

SET SESSION AUTHORIZATION DEFAULT;

ALTER TABLE sensor.units DISABLE TRIGGER ALL;

COPY sensor.units (unit_id, unit_name, unit_display, description) FROM stdin;
1	deg_c	°C	degrees Celsius
2	percent	%	percent
3	m3_m3	m³/m³	volumetric water content
4	l_hr	l/hr	litres per hour
5	g_h	g/h	grams per hour
6	w_m2	W/m²	irradiance
7	m_s	m/s	metres per second
8	deg	°	degrees of arc
9	mpa	MPa	megapascal
10	hpa	hPa	hectopascal
11	bar	bar	bar
12	mv	mV	millivolt
13	mm	mm	millimetre
14	ppm	ppm	parts per million
15	lux	lux	illuminance
\.


ALTER TABLE sensor.units ENABLE TRIGGER ALL;

--
-- Data for Name: sensor_types; Type: TABLE DATA; Schema: sensor; Owner: supabase_admin
--

ALTER TABLE sensor.sensor_types DISABLE TRIGGER ALL;

COPY sensor.sensor_types (sensor_type_id, sensor_type_name, description, typical_unit, typical_range_min, typical_range_max) FROM stdin;
13	leaf_wetness	Leaf surface moisture	\N	0.0000	15.0000
2	temperature	Air or soil temperature sensor	deg_c	-50.0000	60.0000
3	humidity	Relative humidity sensor	percent	0.0000	100.0000
4	co2	Carbon dioxide concentration sensor	ppm	200.0000	2000.0000
5	light	Light intensity or PAR sensor	lux	0.0000	200000.0000
6	soil_moisture	Soil volumetric water content	percent	0.0000	100.0000
7	wind_speed	Wind speed anemometer	m_s	0.0000	50.0000
8	wind_direction	Wind direction vane	deg	0.0000	360.0000
9	precipitation	Rain gauge	mm	0.0000	500.0000
10	barometric_pressure	Atmospheric pressure	hpa	900.0000	1100.0000
11	solar_radiation	Solar irradiance	w_m2	0.0000	1500.0000
12	soil_temperature	Subsurface soil temperature	deg_c	-20.0000	40.0000
14	sap_flow	Tree sap flow rate	g_h	0.0000	10000.0000
15	stem_radial_variation	Dendrometer readings for stem radial variation	mv	0.0000	5000.0000
1	stem_water_potential	Stem xylem water potential read through a pressure transducer. Negative under tension.	mpa	-10.0000	1.0000
\.


ALTER TABLE sensor.sensor_types ENABLE TRIGGER ALL;

--
-- Data for Name: climate_pathways; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.climate_pathways DISABLE TRIGGER ALL;

COPY shared.climate_pathways (climate_pathway_id, climate_pathway_name, label, description, created_at) FROM stdin;
0	historical	historical	Observed 1981-2010 climatology (CHELSA), held constant. What every projection before 2026-09-14 used implicitly through silvaR's growth-region table.	2026-11-09 11:17:43.161929+00
1	ssp126	SSP1-2.6	CMIP6 SSP1-2.6, sustainability / low emissions. CHELSA 30-year windows 2011-2040, 2041-2070, 2071-2100 plus SSP CO2.	2026-11-09 11:17:43.161929+00
2	ssp370	SSP3-7.0	CMIP6 SSP3-7.0, regional rivalry / high emissions.	2026-11-09 11:17:43.161929+00
3	ssp585	SSP5-8.5	CMIP6 SSP5-8.5, fossil-fuelled development / very high emissions.	2026-11-09 11:17:43.161929+00
\.


ALTER TABLE shared.climate_pathways ENABLE TRIGGER ALL;

--
-- Data for Name: climate_zones; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.climate_zones DISABLE TRIGGER ALL;

COPY shared.climate_zones (climate_zone_id, climate_zone_name, description) FROM stdin;
1	Af	Tropical rainforest
2	Am	Tropical monsoon
3	Aw	Tropical savanna
4	BWh	Hot desert
5	BWk	Cold desert
6	BSh	Hot semi-arid
7	BSk	Cold semi-arid
8	Csa	Hot-summer Mediterranean
9	Csb	Warm-summer Mediterranean
10	Cfa	Humid subtropical
11	Cfb	Oceanic
12	Cfc	Subpolar oceanic
13	Dfa	Hot-summer humid continental
14	Dfb	Warm-summer humid continental
15	Dfc	Subarctic
16	Dfd	Extremely cold subarctic
17	ET	Tundra
18	EF	Ice cap
\.


ALTER TABLE shared.climate_zones ENABLE TRIGGER ALL;

--
-- Data for Name: soil_types; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.soil_types DISABLE TRIGGER ALL;

COPY shared.soil_types (soil_type_id, soil_type_name, description) FROM stdin;
1	Alfisol	Moderately leached soils with high native fertility
2	Andisol	Soils formed in volcanic ash
3	Aridisol	Desert soils with low organic matter
4	Entisol	Young soils with little profile development
5	Gelisol	Permafrost-affected soils
6	Histosol	Organic soils (peat and muck)
7	Inceptisol	Young soils with minimal horizon development
8	Mollisol	Grassland soils with thick dark surface layer
9	Oxisol	Highly weathered tropical soils
10	Spodosol	Acidic forest soils with organic accumulation
11	Ultisol	Highly weathered acidic forest soils
12	Vertisol	Clay-rich soils that shrink and swell
\.


ALTER TABLE shared.soil_types ENABLE TRIGGER ALL;

--
-- Data for Name: locations; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.locations DISABLE TRIGGER ALL;

COPY shared.locations (location_id, location_name, boundary, center_point, description, elevation_m, slope_deg, aspect, soil_type_id, climate_zone_id, created_at, updated_at, created_by, updated_by, forest_growth_region, soil_moistness, soil_nutrient_supply, crs_epsg) FROM stdin;
1	ecosense	\N	0101000020E6100000C251F2EA1C831F406B813D2652224840	Ecosense sensor-network research site in the University of Freiburg forest (mixed species; named monitoring sub-areas are plots)	445.00	10.00	NW	1	11	2026-11-09 11:17:42.92551+00	\N	system	\N	99.73.04	5	3	32632
2	mathisle	\N	0101000020E6100000931804560E2D2040E17A14AE47F14740	Mathisle field research area - University of Freiburg	998.00	9.40	N	\N	\N	2026-11-09 11:17:42.92551+00	\N	system	\N	99.73.13	5	3	32632
3	tratice	\N	0101000020E610000034828DEBDFC52E40842BA0504F3B4740	PathFinder superplot Tratice (Slovenia); European forest category 7.2; 0.25 ha census plot measured with mobile laser scanning 2023-2024 (3Dtrees.earth dataset 3604). Field inventory only.	\N	\N	\N	\N	\N	2026-11-09 11:17:42.92551+00	\N	system	\N	\N	\N	\N	3794
4	krucmanove	\N	0101000020E61000000D1AFA27B8E02B40874D64E6022F4740	PathFinder superplot Krucmanove (Slovenia); European forest category 3.2; 0.25 ha census plot measured with mobile laser scanning 2023-2024 (3Dtrees.earth dataset 3603). Field inventory only.	\N	\N	\N	\N	\N	2026-11-09 11:17:42.92551+00	\N	system	\N	\N	\N	\N	3794
5	goettingen2	\N	0101000020E6100000F60A0BEE07EC2340224F92AE99C84940	PathFinder superplot Göttingen 2 (Germany); European forest category 6; 0.25 ha census plot measured with mobile laser scanning 2023-2024 (3Dtrees.earth dataset 3592). Field inventory only.	\N	\N	\N	\N	\N	2026-11-09 11:17:42.92551+00	\N	system	\N	\N	\N	\N	25832
6	valsain	\N	0101000020E61000009C6A2DCC422B10C04606B98B30674440	PathFinder superplot Valsaín (Spain); European forest category 10.4; 0.25 ha census plot measured with mobile laser scanning 2023-2024 (3Dtrees.earth dataset 3608). Field inventory only.	\N	\N	\N	\N	\N	2026-11-09 11:17:42.92551+00	\N	system	\N	\N	\N	\N	25830
7	vallombrosa_douglas	\N	0101000020E610000016C3D50110272740F623456458E34540	PathFinder superplot Vallombrosa Douglasia (Italy); European forest category 14.2; 0.25 ha census plot measured with mobile laser scanning 2023-2024 (3Dtrees.earth dataset 3595). Field inventory only.	\N	\N	\N	\N	\N	2026-11-09 11:17:42.92551+00	\N	system	\N	\N	\N	\N	25832
\.


ALTER TABLE shared.locations ENABLE TRIGGER ALL;

--
-- Data for Name: lookup_registry; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.lookup_registry DISABLE TRIGGER ALL;

COPY shared.lookup_registry (logical_key, schema_name, table_name, csv_file, csv_columns, natural_key, description) FROM stdin;
axis_structures	trees	axis_structures	axis_structures.csv	{axis_structure_name,description}	axis_structure_name	\N
bark_characteristics	trees	bark_characteristics	bark_characteristics.csv	{bark_characteristic_name,description,typical_species}	bark_characteristic_name	\N
branch_elongation_habits	trees	branch_elongation_habits	branch_elongation_habits.csv	{elongation_habit_name,description}	elongation_habit_name	\N
branching_patterns	trees	branching_patterns	branching_patterns.csv	{branching_pattern_name,description}	branching_pattern_name	\N
climate_zones	shared	climate_zones	climate_zones.csv	{climate_zone_name,description}	climate_zone_name	\N
crown_architectures	trees	crown_architectures	crown_architectures.csv	{crown_architecture_name,description,typical_examples}	crown_architecture_name	\N
crown_classes	trees	crown_classes	crown_classes.csv	{crown_class_name,description}	crown_class_name	\N
crown_shapes	trees	crown_shapes	crown_shapes.csv	{crown_shape_name,description}	crown_shape_name	\N
damage_agents	trees	damage_agents	damage_agents.csv	{damage_agent_name,description}	damage_agent_name	\N
data_source_types	trees	data_source_types	data_source_types.csv	{data_source_type_name,description}	data_source_type_name	\N
geometric_crown_solids	trees	geometric_crown_solids	geometric_crown_solids.csv	{geometric_crown_solid_name,description,relative_lateral_area,relative_volume,relative_drag}	geometric_crown_solid_name	\N
growth_forms	trees	growth_forms	growth_forms.csv	{growth_form_name,description}	growth_form_name	\N
growth_orientations	trees	growth_orientations	growth_orientations.csv	{growth_orientation_name,description}	growth_orientation_name	\N
height_classes	trees	phanerophyte_height_classes	phanerophyte_height_classes.csv	{height_class_name,description,min_height_m,max_height_m}	height_class_name	\N
sensor_types	sensor	sensor_types	sensor_types.csv	{sensor_type_name,description,typical_unit,typical_range_min,typical_range_max}	sensor_type_name	\N
shoot_elongation_types	trees	shoot_elongation_types	shoot_elongation_types.csv	{shoot_elongation_type_name,description}	shoot_elongation_type_name	\N
soil_types	shared	soil_types	soil_types.csv	{soil_type_name,description}	soil_type_name	\N
species	shared	species	species.csv	{common_name,scientific_name,max_height_m,max_dbh_cm,typical_lifespan_years,growth_rate,shade_tolerance,is_deciduous,gbif_key,gbif_accepted_name}	scientific_name	\N
straightness_types	trees	straightness_types	straightness_types.csv	{straightness_type_name,description,deviation_angle_min_deg,deviation_angle_max_deg}	straightness_type_name	\N
taper_types	trees	taper_types	taper_types.csv	{taper_type_name,description,typical_taper_ratio_min,typical_taper_ratio_max}	taper_type_name	\N
tree_status	trees	tree_status	tree_status.csv	{tree_status_name,description}	tree_status_name	\N
variant_types	shared	variant_types	variant_types.csv	{variant_type_name,description}	variant_type_name	\N
\.


ALTER TABLE shared.lookup_registry ENABLE TRIGGER ALL;

--
-- Data for Name: management_regimes; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.management_regimes DISABLE TRIGGER ALL;

COPY shared.management_regimes (management_regime_id, management_regime_name, description, silva_rules, created_at) FROM stdin;
0	none	No forest state. Scenarios with this regime are landing zones for acquired data (climate pathways) and hold no tree variants.	\N	2026-11-09 11:17:43.160721+00
1	natural_growth	Unmanaged natural development: growth, competition and natural mortality only. No intervention.	\N	2026-11-09 11:17:43.160721+00
2	crop_tree_thinning	Crop-tree (Z-Baum) thinning with target-diameter harvest: the standard Baden-Wuerttemberg regime for EVEN-AGED beech-conifer stands (ecosense: 47-year beech with admixed Douglas fir, fir, spruce, larch, oak). Every second 5-year period the two strongest same-species competitors of each crop tree are removed (beech 80, Douglas fir 100, spruce and fir 150 crop trees per ha; a species with fewer stems per ha than crop trees is left alone); trees above target diameter (beech and Douglas fir 60 cm, fir 55 cm, spruce 45 cm) are harvested with probability 0.5 per period. Minor admixed species are retained. Removal is capped at 25 percent of a species per intervention. Not for two-storied stands: grid-based crop-tree selection there picks the overstory and cuts it. PROVISIONAL -- textbook defaults, not yet reviewed by a forester (2026-09-14).	{"rules": [{"metric": "G", "species": "Fagus sylvatica", "guide_curve": "schober", "intervention": {"type": "every_n_periods", "value": 2}, "n_competitors": 2, "thinning_type": "crop_tree", "crop_trees_per_ha": 80}, {"metric": "G", "species": "Pseudotsuga menziesii", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 2}, "n_competitors": 2, "thinning_type": "crop_tree", "crop_trees_per_ha": 100}, {"metric": "G", "species": "Picea abies", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 2}, "n_competitors": 2, "thinning_type": "crop_tree", "crop_trees_per_ha": 150}, {"metric": "G", "species": "Abies alba", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 2}, "n_competitors": 2, "thinning_type": "crop_tree", "crop_trees_per_ha": 150}, {"metric": "G", "species": "Fagus sylvatica", "guide_curve": "schober", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "thinning_type": "target_diameter", "target_probability": 0.5}, {"metric": "G", "species": "Pseudotsuga menziesii", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "thinning_type": "target_diameter", "target_probability": 0.5}, {"metric": "G", "species": "Picea abies", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 45, "thinning_type": "target_diameter", "target_probability": 0.5}, {"metric": "G", "species": "Abies alba", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 55, "thinning_type": "target_diameter", "target_probability": 0.5}], "removal_method": "simplified", "max_removal_fraction": 0.25}	2026-11-09 11:17:43.160721+00
3	target_diameter_harvest	Single-tree selection by target diameter (Zielstaerkennutzung / Plenterung): the regime for UNEVEN-AGED, two-storied spruce-fir-beech mountain mixed stands of the southern Black Forest (mathisle: a young spruce-fir-beech layer under ~120 old spruce and fir of 40-90 cm). Each 5-year period, trees above target diameter (spruce 45 cm, fir 55 cm, beech and Douglas fir 60 cm) are harvested with probability 0.3, so the overstory is removed gradually as the understorey grows into it; no crop-tree selection, no thinning of the young layer. Removal is capped at 25 percent of a species per period. PROVISIONAL -- textbook defaults, not yet reviewed by a forester (2026-09-14).	{"rules": [{"metric": "G", "species": "Picea abies", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 45, "thinning_type": "target_diameter", "target_probability": 0.3}, {"metric": "G", "species": "Abies alba", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 55, "thinning_type": "target_diameter", "target_probability": 0.3}, {"metric": "G", "species": "Fagus sylvatica", "guide_curve": "schober", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "thinning_type": "target_diameter", "target_probability": 0.3}, {"metric": "G", "species": "Pseudotsuga menziesii", "guide_curve": "assmann_franz", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "thinning_type": "target_diameter", "target_probability": 0.3}], "removal_method": "simplified", "max_removal_fraction": 0.25}	2026-11-09 11:17:43.160721+00
\.


ALTER TABLE shared.management_regimes ENABLE TRIGGER ALL;

--
-- Data for Name: plots; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.plots DISABLE TRIGGER ALL;

COPY shared.plots (plot_id, location_id, plot_name, plot_number, area_m2, boundary, center_point, description, created_at, updated_at, created_by, updated_by, sampling_design_id, stratum_id, parent_plot_id, sampling_weight, area_source) FROM stdin;
1	1	ecosense_plot_1	1	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
2	1	ecosense_plot_2	2	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
3	1	ecosense_plot_3	3	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
4	1	ecosense_plot_4	4	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
5	1	ecosense_plot_5	5	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
6	1	ecosense_plot_6	6	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
7	1	ecosense_plot_7	7	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
8	1	ecosense_plot_8	8	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
9	1	ecosense_plot_9	9	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
10	1	ecosense_plot_10	10	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
11	1	ecosense_plot_11	11	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
12	1	ecosense_plot_12	12	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
13	1	ecosense_plot_13	13	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
14	1	ecosense_plot_14	14	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
15	1	ecosense_plot_15	15	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
16	1	ecosense_plot_16	16	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
17	1	ecosense_plot_17	17	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
18	1	ecosense_plot_18	18	\N	\N	\N	\N	2026-11-09 11:17:42.942586+00	\N	init	\N	\N	\N	\N	1.000000	\N
19	2	mathisle	1	\N	\N	\N	\N	2026-11-09 11:17:42.944087+00	\N	init	\N	\N	\N	\N	1.000000	\N
\.


ALTER TABLE shared.plots ENABLE TRIGGER ALL;

--
-- Data for Name: processes; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.processes DISABLE TRIGGER ALL;

COPY shared.processes (process_id, process_name, algorithm_name, version, description, author, publication_date, citation, category, created_at, updated_at, param_schema, workflow_key) FROM stdin;
2	Aquarius Sensor Sync	Aquarius Publish API time-series pull (aquarius-connector)	0.1.0	Pull sensor readings from the Aquarius Publish API into sensor.Readings. Takes minutes. Idempotent on both sides -- re-running a window updates the same rows rather than duplicating them, so an overlapping window is safe. Without from/to it re-pulls a rolling window of the last days_back days; give from/to to backfill a specific historical period. Every sync overwrites sensor_model with a placeholder, so aquarius-enrich must run immediately afterwards, every time.	XR Future Forests Lab	\N	\N	acquisition	2026-11-09 11:17:42.772572+00	\N	{"type": "object", "required": [], "properties": {"to": {"type": "string", "pattern": "^\\\\d{4}-\\\\d{2}-\\\\d{2}$", "description": "End of the window, ISO date. Must be later than `from`."}, "from": {"type": "string", "pattern": "^\\\\d{4}-\\\\d{2}-\\\\d{2}$", "description": "Start of an explicit historical window, ISO date. Must be given with `to`."}, "days_back": {"type": "integer", "default": 30, "maximum": 365, "minimum": 1, "description": "Rolling window size in days. Ignored when from/to are given."}, "sensor_type": {"type": "string", "description": "Restrict the pull to one digital-twin sensor type. Omit for all types."}}, "dependentRequired": {"to": ["from"], "from": ["to"]}, "additionalProperties": false}	aquarius-sync
3	Aquarius Sensor Metadata Enrichment	Aquarius location/parameter metadata backfill (aquarius-connector)	0.1.0	Restore real sensor metadata -- model, manufacturer, installation details -- that aquarius-sync overwrites with a placeholder on every run. Seconds. Takes no parameters. Run it after every sync; running it on its own is harmless.	XR Future Forests Lab	\N	\N	acquisition	2026-11-09 11:17:42.773302+00	\N	{"type": "object", "required": [], "properties": {}, "dependentRequired": {}, "additionalProperties": false}	aquarius-enrich
4	Tree Model Generation	Procedural tree assembly pipeline (growpy)	0.4.0	Generate the 3D tree assemblies Unreal places, one species at a time. Slow: 23-75 minutes per species-height batch, and step 4 needs Blender, so it runs on a different host from the other workflows. Writes files, not database rows. Use dry_run=true first to see what it would do, and max_height to cut a test run short.	XR Future Forests Lab	\N	\N	simulation	2026-11-09 11:17:42.774001+00	\N	{"type": "object", "required": ["species"], "properties": {"steps": {"type": "string", "default": "4", "pattern": "^(all|[1-4](,[1-4])*)$", "description": "Pipeline steps to run: 1 prepare-assets, 2 convert-twigs, 3 create-models, 4 generate-forest. Comma-separated, or \\"all\\"."}, "dry_run": {"type": "boolean", "default": false, "description": "Print what would run without executing it."}, "species": {"type": "string", "description": "Single species by common name, e.g. \\"European Beech\\"."}, "workers": {"type": "integer", "default": 4, "maximum": 16, "minimum": 1, "description": "Parallel workers for step 4. 1 = sequential."}, "max_height": {"type": "number", "default": 0, "maximum": 60, "minimum": 0, "description": "Cap tree height in metres for step 4, for faster test runs. 0 = no limit."}}, "dependentRequired": {}, "additionalProperties": false}	growpy
5	Soil Aggregates from Sensor Readings	Quarter-balanced nested mean over sensor.SensorReadings	1.0	Mean soil moisture and soil temperature for a location and year, derived from the twin own sensor readings. Four nested means give equal weight to each sensor within a day, each day within a quarter, and each quarter within the year, so the value is not weighted by sampling density. Readings outside the range sensor.SensorTypes declares for the quantity are excluded. A year without at least four qualifying quarters produces no row. Sensor depth is not recorded in the twin, so the value is a mean across the depths the network sits at, not a profile.	XR Future Forests Lab	\N	\N	aggregation	2026-11-09 11:17:43.036673+00	\N	\N	\N
1	Forest Growth Simulation	SILVA (silvaR)	0.0.0.9000	Project a variant forward with the SILVA growth model and write the result back as a chain of simulated_growth variants, one per 5-year period, into the scenario named by the management regime and climate pathway (regime, climate). A 20-year run takes about 60 s for ecosense (1,495 trees) and 20 s for mathisle (730); cost grows with the horizon and, steeply, with the number of trees. dry_run=true simulates and writes nothing, which is the way to see what a run would do before doing it. Appends to trees.GrowthSimulations, which accumulates -- running it twice gives two comparable runs, not a corrupted one. A promoting run refuses variant names that already exist in the target scenario: use no_promote=true to record a trajectory for comparison without touching the chain Unreal reads, or replace=true only when you do mean to overwrite it.	Pretzsch, Biber & Dursky (silvaR implementation: Torben Hilmers, TUM)	\N	Pretzsch, H., Biber, P. & Dursky, J. (2002). The single tree-based stand simulator SILVA: construction, application and evaluation. Forest Ecology and Management, 162(1), 3-21. doi:10.1016/S0378-1127(02)00047-6	simulation	2026-11-09 11:17:42.771214+00	\N	{"type": "object", "required": ["location"], "properties": {"seed": {"type": "integer", "default": 1, "description": "Random seed. Recorded on the run, so two runs differing only by seed stay distinguishable."}, "years": {"type": "integer", "default": 20, "maximum": 100, "minimum": 5, "multipleOf": 5, "description": "Projection horizon. One SILVA period is 5 years, so this must be a multiple of 5."}, "regime": {"enum": ["natural_growth", "crop_tree_thinning", "target_diameter_harvest"], "type": "string", "default": "natural_growth", "description": "Management regime; shared.ManagementRegimes.regime_name. natural_growth projects with no intervention. crop_tree_thinning (even-aged stands, ecosense) and target_diameter_harvest (two-storied spruce-fir-beech, mathisle) apply the silvaR preset stored on that row between periods and write removed trees as tree_status harvested (standing dead from mortality stays dead). Turn mortality on for a managed run. The presets are provisional until a forester has reviewed them."}, "climate": {"enum": ["historical", "ssp126", "ssp370", "ssp585"], "type": "string", "default": "historical", "description": "Climate pathway; shared.ClimatePathways.pathway_name. historical holds the observed 1981-2010 climatology constant (every projection before 2026-09-14). An SSP applies, per 5-year period, the CHELSA temperature delta and precipitation ratio of the 30-year window that period falls in (2011-2040, 2041-2070, 2071-2100) and that window's SSP CO2, to SILVA's site conditions. Only temperature, precipitation and CO2 are perturbed; vegetation-period length is not. Projections past 2100 are refused. Data comes from environments.Environments for this location."}, "dry_run": {"type": "boolean", "default": false, "description": "Simulate and report, write nothing."}, "replace": {"type": "boolean", "default": false, "description": "Delete existing simulated_growth variants of the same name first."}, "location": {"type": "string", "description": "Site to simulate; shared.Locations.location_name."}, "scenario": {"type": "string", "description": "Optional. Output scenario name. Left out (the normal case) it is derived from regime and climate -- natural_growth, natural_growth_ssp370, crop_tree_thinning, crop_tree_thinning_ssp585 -- and created at this location if absent. Given, it must either not exist yet or already carry the same regime and climate; the run refuses to write a projection into a scenario whose axes say something else."}, "mortality": {"type": "boolean", "default": false, "description": "Let SILVA kill trees. Dead trees stay in every later variant as standing dead stems (tree_status dead). Off by default so existing calls keep their meaning; recommended on for every new chain, and for any managed run."}, "re_anchor": {"type": "boolean", "default": false, "description": "Project from the newest measured state at this location instead of base_variant, if a re-survey has made base_variant stale. Does nothing when it is already the newest. The result is a new chain, not a rewrite: the prefix becomes silva<anchor year> so the existing chain stays intact and each chain says which observation set it came from."}, "no_promote": {"type": "boolean", "default": false, "description": "Write the trajectory but do not promote it to variants."}, "competition": {"enum": ["sf_polygon", "rect_sum", "legacy"], "type": "string", "default": "sf_polygon", "description": "Neighbour competition method."}, "base_variant": {"type": "string", "default": "baseline_2025", "description": "Variant to project forward."}, "base_scenario": {"type": "string", "default": "natural_growth", "description": "Scenario holding the measured state to project from (with base_variant). The measured baselines live in natural_growth; a managed or climate run starts from the same measured trees and writes into its own scenario."}, "variant_prefix": {"type": "string", "default": "silva", "description": "New variants are named <prefix>_<year>."}, "climate_pathway": {"type": "string", "readOnly": true, "description": "Recorded, not set: the shared.climate_pathways.climate_pathway_name the run resolved `climate` to."}, "climate_periods": {"type": "array", "readOnly": true, "description": "Recorded, not set: one entry per projection period, each carrying the year and the site-property deltas applied for it. This is what makes a climate-driven run reproducible -- without it the crate records which pathway was asked for but not what was actually applied."}, "management_regime": {"type": "string", "readOnly": true, "description": "Recorded, not set: the shared.management_regimes.management_regime_name the run resolved `regime` to. Written by silva-connector so the run record names the regime that was applied rather than the request."}}, "dependentRequired": {}, "additionalProperties": false}	silva
\.


ALTER TABLE shared.processes ENABLE TRIGGER ALL;

--
-- Data for Name: species; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.species DISABLE TRIGGER ALL;

COPY shared.species (species_id, common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name, created_at, updated_at, leaf_type) FROM stdin;
1	European Beech	Fagus sylvatica	40.00	150.00	300	moderate	high	t	2882316	Fagus sylvatica	2026-11-09 11:17:42.903208+00	\N	broadleaf
2	European Oak	Quercus robur	35.00	200.00	500	slow	moderate	t	2878688	Quercus robur	2026-11-09 11:17:42.903208+00	\N	broadleaf
3	Norway Spruce	Picea abies	50.00	150.00	200	fast	high	f	5284884	Picea abies	2026-11-09 11:17:42.903208+00	\N	needleleaf
4	Silver Fir	Abies alba	50.00	200.00	500	moderate	very_high	f	2685484	Abies alba	2026-11-09 11:17:42.903208+00	\N	needleleaf
5	Scots Pine	Pinus sylvestris	35.00	100.00	300	moderate	low	f	5285637	Pinus sylvestris	2026-11-09 11:17:42.903208+00	\N	needleleaf
6	Douglas Fir	Pseudotsuga menziesii	60.00	180.00	500	fast	moderate	f	2685796	Pseudotsuga menziesii	2026-11-09 11:17:42.903208+00	\N	needleleaf
7	European Larch	Larix decidua	40.00	100.00	300	fast	low	t	2686212	Larix decidua	2026-11-09 11:17:42.903208+00	\N	needleleaf
8	Norway Maple	Acer platanoides	25.00	100.00	200	moderate	moderate	t	3189846	Acer platanoides	2026-11-09 11:17:42.903208+00	\N	broadleaf
9	Sycamore Maple	Acer pseudoplatanus	35.00	120.00	400	moderate	moderate	t	3189870	Acer pseudoplatanus	2026-11-09 11:17:42.903208+00	\N	broadleaf
10	Wild Cherry	Prunus avium	25.00	80.00	100	fast	low	t	3020791	Prunus avium	2026-11-09 11:17:42.903208+00	\N	broadleaf
11	Wild Service Tree	Torminalis glaberrima	25.00	60.00	200	slow	moderate	t	3012567	Torminalis glaberrima	2026-11-09 11:17:42.903208+00	\N	broadleaf
12	Silver Birch	Betula pendula	25.00	60.00	80	fast	low	t	5334357	Betula pendula	2026-11-09 11:17:42.903208+00	\N	broadleaf
13	Common Ash	Fraxinus excelsior	35.00	150.00	250	fast	low	t	5385657	Fraxinus excelsior	2026-11-09 11:17:42.903208+00	\N	broadleaf
14	Small-leaved Linden	Tilia cordata	30.00	120.00	500	moderate	high	t	2436527	Tilia cordata	2026-11-09 11:17:42.903208+00	\N	broadleaf
15	Lawson Cypress	Chamaecyparis lawsoniana	\N	\N	\N	\N	\N	f	2683866	Chamaecyparis lawsoniana	2026-11-09 11:17:42.903208+00	\N	needleleaf
16	Holly	Ilex aquifolium	\N	\N	\N	\N	\N	f	5414222	Ilex aquifolium	2026-11-09 11:17:42.903208+00	\N	broadleaf
17	Wych Elm	Ulmus glabra	\N	\N	\N	\N	\N	t	5361866	Ulmus glabra	2026-11-09 11:17:42.903208+00	\N	broadleaf
\.


ALTER TABLE shared.species ENABLE TRIGGER ALL;

--
-- Data for Name: variant_types; Type: TABLE DATA; Schema: shared; Owner: supabase_admin
--

ALTER TABLE shared.variant_types DISABLE TRIGGER ALL;

COPY shared.variant_types (variant_type_id, variant_type_name, description) FROM stdin;
1	original	Original data from field measurements or sensors
2	processed	Data processed by automated algorithms
3	manual	Manually entered or corrected data
4	simulated_growth	Data from growth simulation models
5	user_input	User-defined or modified data in XR environment
6	sensor_derived	Aggregated or derived from sensor readings
7	model_output	Output from external models (SILVA or climate models)
8	repeat_measurement	Repeat measurement from subsequent inventory campaigns
\.


ALTER TABLE shared.variant_types ENABLE TRIGGER ALL;

--
-- Data for Name: axis_structures; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.axis_structures DISABLE TRIGGER ALL;

COPY trees.axis_structures (axis_structure_id, axis_structure_name, description) FROM stdin;
1	single_leader	Single uppermost portion of the main axis (monopodial)
2	polycormic	Tree possessing several strong vertical axes
\.


ALTER TABLE trees.axis_structures ENABLE TRIGGER ALL;

--
-- Data for Name: bark_characteristics; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.bark_characteristics DISABLE TRIGGER ALL;

COPY trees.bark_characteristics (bark_characteristic_id, bark_characteristic_name, description, typical_species) FROM stdin;
1	smooth	Smooth bark with minimal texture	Fagus (Beech) and Betula (Birch)
2	furrowed	Deep vertical furrows and ridges	Quercus (Oak) and Fraxinus (Ash)
3	plated	Bark separates into distinct plates	Pinus (Pine) and Liquidambar (Sweetgum)
4	exfoliating	Bark peels or flakes in sheets	Platanus (Sycamore) and Acer (Maple)
5	scaly	Small scale-like bark pieces	Cedrus (Cedar) and Sequoia (Redwood)
\.


ALTER TABLE trees.bark_characteristics ENABLE TRIGGER ALL;

--
-- Data for Name: branch_elongation_habits; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.branch_elongation_habits DISABLE TRIGGER ALL;

COPY trees.branch_elongation_habits (elongation_habit_id, elongation_habit_name, description) FROM stdin;
1	acrotony	Upper branches elongate the most
2	mesotony	Middle branches elongate the most
3	basitony	Lower branches elongate the most
\.


ALTER TABLE trees.branch_elongation_habits ENABLE TRIGGER ALL;

--
-- Data for Name: branching_patterns; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.branching_patterns DISABLE TRIGGER ALL;

COPY trees.branching_patterns (branching_pattern_id, branching_pattern_name, description) FROM stdin;
1	alternate	Branches arranged alternately along stem
2	opposite	Branches arranged in pairs at nodes
3	whorled	Multiple branches arising from same node
4	spiral	Branches arranged in spiral pattern
5	random	No clear branching pattern
\.


ALTER TABLE trees.branching_patterns ENABLE TRIGGER ALL;

--
-- Data for Name: crown_architectures; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_architectures DISABLE TRIGGER ALL;

COPY trees.crown_architectures (crown_architecture_id, crown_architecture_name, description, typical_examples) FROM stdin;
1	excurrent	Single dominant vertical leader forming a conical crown	Conifers (spruce; fir; pine)
2	decurrent	Multiple dominant branches with no central axis resulting in a spreading crown	Oaks; maples; elms
3	abcurrent	Aerial terminal bud and leaves (palm-like forms)	Palms; tree ferns
4	adcurrent	Basal buds and leaves (ground-hugging forms)	Yucca; grass trees
5	bicurrent	Irregular forked branching with thick green stems	Cacti; some succulents
\.


ALTER TABLE trees.crown_architectures ENABLE TRIGGER ALL;

--
-- Data for Name: crown_classes; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_classes DISABLE TRIGGER ALL;

COPY trees.crown_classes (crown_class_id, crown_class_name, description) FROM stdin;
1	dominant	Crown extends above the general canopy level with full overhead light exposure
2	co_dominant	Crown forms part of the general canopy level with above-average light exposure
3	intermediate	Crown is shorter than co-dominant trees but receives some direct overhead light
4	overtopped	Crown is entirely below the general canopy level and receives only diffuse light
5	open_grown	Tree grew with no canopy competition and has a full undamaged crown
\.


ALTER TABLE trees.crown_classes ENABLE TRIGGER ALL;

--
-- Data for Name: crown_shapes; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.crown_shapes DISABLE TRIGGER ALL;

COPY trees.crown_shapes (crown_shape_id, crown_shape_name, description) FROM stdin;
1	pyramidal	Broad-based triangular crown tapering to apex
2	conical	Narrow cone-shaped crown
3	columnar	Tall narrow cylindrical crown (spindle-shaped)
4	fastigiate	Very narrow upright crown with branches close to trunk
5	ellipsoidal	Ellipse-shaped crown taller than wide
6	ovoid	Egg-shaped crown wider at base
7	globose	Spherical or circular crown
8	broad	Wide spreading crown
9	vase	Upward-spreading branches forming vase shape
10	umbrella	Flat-topped spreading crown
11	irregular	Asymmetric or no defined shape
12	weeping	Pendulous drooping branches
\.


ALTER TABLE trees.crown_shapes ENABLE TRIGGER ALL;

--
-- Data for Name: damage_agents; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.damage_agents DISABLE TRIGGER ALL;

COPY trees.damage_agents (damage_agent_id, damage_agent_name, description) FROM stdin;
1	none	No observable damage agent
2	insect	Damage from insect infestation or boring
3	disease	Damage from fungal bacterial or viral pathogens
4	fire	Damage from wildfire or prescribed burn
5	wind	Damage from windthrow or windsnap
6	snow_ice	Damage from snow loading or ice accumulation
7	drought	Damage or decline attributable to water stress
8	mechanical	Damage from human or machine impact such as logging or vehicles
9	animal	Damage from browsing bark stripping or other animal activity
10	human_activity	Damage from direct human activity other than mechanical equipment
11	competition	Decline attributable to competitive suppression by neighboring trees
12	unknown	Damage agent could not be determined
\.


ALTER TABLE trees.damage_agents ENABLE TRIGGER ALL;

--
-- Data for Name: data_source_types; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.data_source_types DISABLE TRIGGER ALL;

COPY trees.data_source_types (data_source_type_id, data_source_type_name, description) FROM stdin;
1	field	Direct measurement in the field by personnel
2	lidar	Derived from a LiDAR point cloud scan
3	photogrammetry	Derived from photogrammetry or SfM processing
4	estimated	Estimated from allometric or statistical models
5	simulated	Generated by a growth simulator or seed script
\.


ALTER TABLE trees.data_source_types ENABLE TRIGGER ALL;

--
-- Data for Name: geometric_crown_solids; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.geometric_crown_solids DISABLE TRIGGER ALL;

COPY trees.geometric_crown_solids (geometric_crown_solid_id, geometric_crown_solid_name, description, relative_lateral_area, relative_volume, relative_drag) FROM stdin;
1	cylinder	Square/cylindrical crown shape	1.00	0.80	1.00
2	round_edge_cylinder	Cylinder with rounded edges	0.90	0.70	0.84
3	elongated_spheroid	Vertically elongated sphere	0.80	0.60	0.68
4	spheroid	Standard spherical shape	0.70	0.50	0.53
5	expanded_paraboloid	Wide parabolic shape	0.60	0.50	0.54
6	paraboloid	Standard parabolic shape	0.50	0.40	0.42
7	fat_cone	Wide conical shape	0.40	0.30	0.29
8	cone	Standard conical shape	0.30	0.25	0.17
9	neiloid	Narrow tapered shape (reverse cone)	0.20	0.20	0.08
10	thin_neiloid	Very narrow tapered shape	0.10	0.10	0.01
\.


ALTER TABLE trees.geometric_crown_solids ENABLE TRIGGER ALL;

--
-- Data for Name: growth_forms; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.growth_forms DISABLE TRIGGER ALL;

COPY trees.growth_forms (growth_form_id, growth_form_name, description) FROM stdin;
1	diplocaulescent	Plant with a main axis and branches
2	dendroid	Plant with a tall erect main axis and many branches
3	arborescent	Any tree-like growth form
4	phanerophyte	Tree form with resting buds positioned well above soil surface
\.


ALTER TABLE trees.growth_forms ENABLE TRIGGER ALL;

--
-- Data for Name: growth_orientations; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.growth_orientations DISABLE TRIGGER ALL;

COPY trees.growth_orientations (growth_orientation_id, growth_orientation_name, description) FROM stdin;
1	orthotropic	Shoots possessing a vertical growth habit
2	plagiotrophic	Shoots possessing a horizontal growth habit
\.


ALTER TABLE trees.growth_orientations ENABLE TRIGGER ALL;

--
-- Data for Name: phanerophyte_height_classes; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.phanerophyte_height_classes DISABLE TRIGGER ALL;

COPY trees.phanerophyte_height_classes (height_class_id, height_class_name, description, min_height_m, max_height_m) FROM stdin;
1	megaphanerophyte	Tree forms exceeding 30m in height	30.00	\N
2	mesophanerophyte	Tree forms between 8m and 30m tall	8.00	30.00
3	microphanerophyte	Tree forms between 2m and 8m tall	2.00	8.00
\.


ALTER TABLE trees.phanerophyte_height_classes ENABLE TRIGGER ALL;

--
-- Data for Name: root_system_types; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.root_system_types DISABLE TRIGGER ALL;

COPY trees.root_system_types (root_system_type_id, root_system_type_name, description) FROM stdin;
1	tap_root	Single dominant vertical root descending from the root collar (Koestler et al. 1968 Pfahlwurzel type); Guerrero Inigez 2017 tap root model
2	heart_root	Multiple oblique roots radiating from the root collar with no single dominant axis (Koestler et al. 1968 Herzwurzel type); Guerrero Inigez 2017 heart-shaped root model
3	lateral_root	Shallow roots spreading horizontally near the surface with no dominant vertical axis (Koestler et al. 1968 Flachwurzel/Senkerwurzel type); Guerrero Inigez 2017 lateral/surface root model
\.


ALTER TABLE trees.root_system_types ENABLE TRIGGER ALL;

--
-- Data for Name: shoot_elongation_types; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.shoot_elongation_types DISABLE TRIGGER ALL;

COPY trees.shoot_elongation_types (shoot_elongation_type_id, shoot_elongation_type_name, description) FROM stdin;
1	long_shoots	Internode growth is allowed to fully elongate
2	short_shoots	Internode growth is constrained but not stopped
3	spur_shoots	Internodes elongate only slightly
\.


ALTER TABLE trees.shoot_elongation_types ENABLE TRIGGER ALL;

--
-- Data for Name: straightness_types; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.straightness_types DISABLE TRIGGER ALL;

COPY trees.straightness_types (straightness_type_id, straightness_type_name, description, deviation_angle_min_deg, deviation_angle_max_deg) FROM stdin;
1	straight	Minimal deviation from vertical	0.00	5.00
2	slight_sweep	Minor curvature or lean	5.00	15.00
3	moderate_sweep	Noticeable curvature	15.00	30.00
4	severe_sweep	Significant curvature or lean	30.00	90.00
\.


ALTER TABLE trees.straightness_types ENABLE TRIGGER ALL;

--
-- Data for Name: taper_types; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.taper_types DISABLE TRIGGER ALL;

COPY trees.taper_types (taper_type_id, taper_type_name, description, typical_taper_ratio_min, typical_taper_ratio_max) FROM stdin;
1	cylinder	Minimal taper nearly constant diameter	0.900	1.000
2	cone	Linear taper from base to top	0.500	0.700
3	paraboloid	Curved taper faster at base	0.400	0.600
4	neiloid	Very rapid taper at base	0.200	0.500
\.


ALTER TABLE trees.taper_types ENABLE TRIGGER ALL;

--
-- Data for Name: tree_part_types; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.tree_part_types DISABLE TRIGGER ALL;

COPY trees.tree_part_types (part_type_id, part_type_name, description) FROM stdin;
1	root	Below-ground structural root system (CityGML Root feature class); no QSM cylinder representation yet, see trees.Roots
2	trunk	Main stem from base to first major branch (CityGML Trunk feature class); QSM cylinders with branch_order = 0
3	branch	Woody structure above the twig radius threshold (CityGML Branch feature class); QSM cylinders with branch_order >= 1
4	twig	Terminal woody structure at or below the twig radius threshold (CityGML Twig feature class)
5	leaf	Foliage (CityGML Leaf feature class); out of scope for QSM (wood-only skeleton), see trees.CrownFoliageProfiles for density/distribution instead
6	crown	Aggregate above-crown-base structure (CityGML Crown feature class); not a single cylinder, implicit in trees.Trees.crown_base_height_m
\.


ALTER TABLE trees.tree_part_types ENABLE TRIGGER ALL;

--
-- Data for Name: tree_status; Type: TABLE DATA; Schema: trees; Owner: supabase_admin
--

ALTER TABLE trees.tree_status DISABLE TRIGGER ALL;

COPY trees.tree_status (tree_status_id, tree_status_name, description) FROM stdin;
1	healthy	Tree shows no signs of stress or disease
2	stressed	Tree shows signs of environmental or biotic stress
3	declining	Tree health is deteriorating
4	dead	Tree is no longer alive
5	harvested	Tree has been removed through management
6	missing	Tree cannot be located or identified
7	downed	Tree has fallen but is not standing dead
8	broken	Stem or main trunk is broken above breast height
\.


ALTER TABLE trees.tree_status ENABLE TRIGGER ALL;

--
-- Name: sensor_types_sensor_type_id_seq; Type: SEQUENCE SET; Schema: sensor; Owner: supabase_admin
--

SELECT pg_catalog.setval('sensor.sensor_types_sensor_type_id_seq', 16, true);


--
-- Name: units_unit_id_seq; Type: SEQUENCE SET; Schema: sensor; Owner: supabase_admin
--

SELECT pg_catalog.setval('sensor.units_unit_id_seq', 15, true);


--
-- Name: climate_zones_climate_zone_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.climate_zones_climate_zone_id_seq', 18, true);


--
-- Name: locations_location_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.locations_location_id_seq', 7, true);


--
-- Name: plots_plot_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.plots_plot_id_seq', 19, true);


--
-- Name: processes_process_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.processes_process_id_seq', 5, true);


--
-- Name: soil_types_soil_type_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.soil_types_soil_type_id_seq', 12, true);


--
-- Name: species_species_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.species_species_id_seq', 20, true);


--
-- Name: variant_types_variant_type_id_seq; Type: SEQUENCE SET; Schema: shared; Owner: supabase_admin
--

SELECT pg_catalog.setval('shared.variant_types_variant_type_id_seq', 8, true);


--
-- Name: axis_structures_axis_structure_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.axis_structures_axis_structure_id_seq', 2, true);


--
-- Name: bark_characteristics_bark_characteristic_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.bark_characteristics_bark_characteristic_id_seq', 5, true);


--
-- Name: branch_elongation_habits_elongation_habit_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.branch_elongation_habits_elongation_habit_id_seq', 3, true);


--
-- Name: branching_patterns_branching_pattern_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.branching_patterns_branching_pattern_id_seq', 5, true);


--
-- Name: crown_architectures_crown_architecture_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.crown_architectures_crown_architecture_id_seq', 5, true);


--
-- Name: crown_classes_crown_class_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.crown_classes_crown_class_id_seq', 5, true);


--
-- Name: crown_shapes_crown_shape_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.crown_shapes_crown_shape_id_seq', 12, true);


--
-- Name: damage_agents_damage_agent_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.damage_agents_damage_agent_id_seq', 12, true);


--
-- Name: data_source_types_data_source_type_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.data_source_types_data_source_type_id_seq', 5, true);


--
-- Name: geometric_crown_solids_geometric_crown_solid_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.geometric_crown_solids_geometric_crown_solid_id_seq', 10, true);


--
-- Name: growth_forms_growth_form_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.growth_forms_growth_form_id_seq', 4, true);


--
-- Name: growth_orientations_growth_orientation_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.growth_orientations_growth_orientation_id_seq', 2, true);


--
-- Name: phanerophyte_height_classes_height_class_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.phanerophyte_height_classes_height_class_id_seq', 3, true);


--
-- Name: root_system_types_root_system_type_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.root_system_types_root_system_type_id_seq', 3, true);


--
-- Name: shoot_elongation_types_shoot_elongation_type_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.shoot_elongation_types_shoot_elongation_type_id_seq', 3, true);


--
-- Name: straightness_types_straightness_type_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.straightness_types_straightness_type_id_seq', 4, true);


--
-- Name: taper_types_taper_type_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.taper_types_taper_type_id_seq', 4, true);


--
-- Name: tree_part_types_part_type_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.tree_part_types_part_type_id_seq', 6, true);


--
-- Name: tree_status_tree_status_id_seq; Type: SEQUENCE SET; Schema: trees; Owner: supabase_admin
--

SELECT pg_catalog.setval('trees.tree_status_tree_status_id_seq', 8, true);


--
-- PostgreSQL database dump complete
--

