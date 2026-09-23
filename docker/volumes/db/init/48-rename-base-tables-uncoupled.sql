-- Mirrored from supabase/migrations/20260923100000_rename_base_tables_uncoupled.sql.
-- Fresh builds get the renames here; existing databases get them from the
-- migration. 10-baseline-schema.sql still creates the squashed names, so on a
-- fresh init this renames what the baseline just built -- the documented shape
-- of this history: additive files, the baseline is never edited.
-- Keep the two identical.
-- =============================================================================
-- Tier 1, part 1: 34 base tables to snake_case (no external consumer)
-- =============================================================================
-- XRFF-497, part of XRFF-494. Owner direction 2026-09-23: the database should be
-- well structured and clean, period -- everything downstream adjusts.
--
-- Columns in this database have always been snake_case; tables never were.
-- `CREATE TABLE trees.GrowthSimulations` unquoted stores `growthsimulations` --
-- PostgreSQL folds unquoted identifiers to lowercase, which is how the word
-- boundaries were lost. The docs render PascalCase because that is what the DDL
-- said; the database never held it.
--
-- WHY THESE 34 AND NOT ALL 52. The split is by coordination cost, not by schema.
-- These have zero references in digital-twin-dashboard, silva-connector,
-- aquarius-connector and open-data-connector, or are referenced only inside this
-- repo. The remaining 18 move in the next migration, together with the consumer
-- commits that follow them. Nothing here can break another repo.
--
-- WHAT POSTGRES DOES NOT DO. Renaming a table updates FK constraints, indexes,
-- sequences, dependent VIEW definitions and RLS policies automatically -- views
-- were verified to follow on dev, definition and all. It does NOT touch plpgsql
-- function bodies, not even static SQL: bodies are stored as text and re-parsed
-- at call time, so a renamed table breaks every function naming it, at call time
-- rather than here. The 11 functions at the end of this file are rewritten for
-- that reason, and `scripts/utils/check_naming.py` (XRFF-495) asserts none is
-- left stale.
--
-- A PK/UNIQUE constraint and its backing index share a name and ALTER TABLE ...
-- RENAME CONSTRAINT renames both, so only plain indexes get an ALTER INDEX here.
--
-- COLUMN RENAMES RIDING ALONG. XRFF-487 shortens three lookup PKs rather than
-- lengthening their labels, because the short stem is already what the FK columns
-- in trees.trees use -- after this the FK matches its parent's PK name, so no FK
-- column changes. This is not tidiness riding along: snake_casing
-- phanerophyteheightclasses alone takes its sequence to 60 bytes against a
-- 63-byte limit that Postgres enforces by silently truncating. Shortening the PK
-- in the same migration takes it to 47.
--
-- trees.assign_height_class() is the trap worth naming. A BEFORE INSERT OR UPDATE
-- trigger populates height_class_id on every tree insert and every height change,
-- so its body has to move with the table and the column or every insert fails.
--
-- Generated from the verified rename map in XRFF-497, not written by hand: each
-- target name is attested by the table's own PK stem, its label column, its seed
-- CSV filename, or composition from two independently attested parts.
--
-- Mirror of the migration of the same name.
-- =============================================================================

-- 1. Tables.
ALTER TABLE forest_floor.groundvegetation RENAME TO ground_vegetation;
ALTER TABLE pointclouds.pointclouds RENAME TO point_clouds;
ALTER TABLE pointclouds.scannertypes RENAME TO scanner_types;
ALTER TABLE shared.attributeprovenance RENAME TO attribute_provenance;
ALTER TABLE shared.disturbanceevents RENAME TO disturbance_events;
ALTER TABLE shared.disturbanceevents_trees RENAME TO disturbance_events_trees;
ALTER TABLE shared.managementevents RENAME TO management_events;
ALTER TABLE shared.processmetrics RENAME TO process_metrics;
ALTER TABLE shared.processparameters RENAME TO process_parameters;
ALTER TABLE shared.processparameters_environments RENAME TO process_parameters_environments;
ALTER TABLE shared.processparameters_pointclouds RENAME TO process_parameters_point_clouds;
ALTER TABLE shared.processparameters_stems RENAME TO process_parameters_stems;
ALTER TABLE shared.processparameters_trees RENAME TO process_parameters_trees;
ALTER TABLE trees.axisstructures RENAME TO axis_structures;
ALTER TABLE trees.barkcharacteristics RENAME TO bark_characteristics;
ALTER TABLE trees.branchelongationhabits RENAME TO branch_elongation_habits;
ALTER TABLE trees.branchingpatterns RENAME TO branching_patterns;
ALTER TABLE trees.crownarchitectures RENAME TO crown_architectures;
ALTER TABLE trees.crownclasses RENAME TO crown_classes;
ALTER TABLE trees.crownfoliageprofiles RENAME TO crown_foliage_profiles;
ALTER TABLE trees.crownshapes RENAME TO crown_shapes;
ALTER TABLE trees.damageagents RENAME TO damage_agents;
ALTER TABLE trees.geometriccrownsolids RENAME TO geometric_crown_solids;
ALTER TABLE trees.growthforms RENAME TO growth_forms;
ALTER TABLE trees.growthorientations RENAME TO growth_orientations;
ALTER TABLE trees.phanerophyteheightclasses RENAME TO phanerophyte_height_classes;
ALTER TABLE trees.phenologyobservations RENAME TO phenology_observations;
ALTER TABLE trees.qsmcylinders RENAME TO qsm_cylinders;
ALTER TABLE trees.rootsystemtypes RENAME TO root_system_types;
ALTER TABLE trees.shootelongationtypes RENAME TO shoot_elongation_types;
ALTER TABLE trees.straightnesstypes RENAME TO straightness_types;
ALTER TABLE trees.tapertypes RENAME TO taper_types;
ALTER TABLE trees.treegraphedges RENAME TO tree_graph_edges;
ALTER TABLE trees.treeparttypes RENAME TO tree_part_types;

-- 2. Sequences.
ALTER SEQUENCE forest_floor.groundvegetation_ground_vegetation_id_seq RENAME TO ground_vegetation_ground_vegetation_id_seq;
ALTER SEQUENCE pointclouds.pointclouds_point_cloud_id_seq RENAME TO point_clouds_point_cloud_id_seq;
ALTER SEQUENCE pointclouds.scannertypes_scanner_type_id_seq RENAME TO scanner_types_scanner_type_id_seq;
ALTER SEQUENCE shared.attributeprovenance_attribute_provenance_id_seq RENAME TO attribute_provenance_attribute_provenance_id_seq;
ALTER SEQUENCE shared.disturbanceevents_disturbance_event_id_seq RENAME TO disturbance_events_disturbance_event_id_seq;
ALTER SEQUENCE shared.managementevents_management_event_id_seq RENAME TO management_events_management_event_id_seq;
ALTER SEQUENCE shared.processmetrics_process_metric_id_seq RENAME TO process_metrics_process_metric_id_seq;
ALTER SEQUENCE shared.processparameters_process_parameter_id_seq RENAME TO process_parameters_process_parameter_id_seq;
ALTER SEQUENCE trees.axisstructures_axis_structure_id_seq RENAME TO axis_structures_axis_structure_id_seq;
ALTER SEQUENCE trees.barkcharacteristics_bark_characteristic_id_seq RENAME TO bark_characteristics_bark_characteristic_id_seq;
ALTER SEQUENCE trees.branchelongationhabits_branch_elongation_habit_id_seq RENAME TO branch_elongation_habits_branch_elongation_habit_id_seq;
ALTER SEQUENCE trees.branchingpatterns_branching_pattern_id_seq RENAME TO branching_patterns_branching_pattern_id_seq;
ALTER SEQUENCE trees.crownarchitectures_crown_architecture_id_seq RENAME TO crown_architectures_crown_architecture_id_seq;
ALTER SEQUENCE trees.crownclasses_crown_class_id_seq RENAME TO crown_classes_crown_class_id_seq;
ALTER SEQUENCE trees.crownfoliageprofiles_profile_id_seq RENAME TO crown_foliage_profiles_profile_id_seq;
ALTER SEQUENCE trees.crownshapes_crown_shape_id_seq RENAME TO crown_shapes_crown_shape_id_seq;
ALTER SEQUENCE trees.damageagents_damage_agent_id_seq RENAME TO damage_agents_damage_agent_id_seq;
ALTER SEQUENCE trees.geometriccrownsolids_geometric_solid_id_seq RENAME TO geometric_crown_solids_geometric_solid_id_seq;
ALTER SEQUENCE trees.growthforms_growth_form_id_seq RENAME TO growth_forms_growth_form_id_seq;
ALTER SEQUENCE trees.growthorientations_growth_orientation_id_seq RENAME TO growth_orientations_growth_orientation_id_seq;
ALTER SEQUENCE trees.phanerophyteheightclasses_phanerophyte_height_class_id_seq RENAME TO phanerophyte_height_classes_phanerophyte_height_class_id_seq;
ALTER SEQUENCE trees.phenologyobservations_phenology_observation_id_seq RENAME TO phenology_observations_phenology_observation_id_seq;
ALTER SEQUENCE trees.qsmcylinders_cylinder_id_seq RENAME TO qsm_cylinders_cylinder_id_seq;
ALTER SEQUENCE trees.rootsystemtypes_root_system_type_id_seq RENAME TO root_system_types_root_system_type_id_seq;
ALTER SEQUENCE trees.shootelongationtypes_shoot_elongation_type_id_seq RENAME TO shoot_elongation_types_shoot_elongation_type_id_seq;
ALTER SEQUENCE trees.straightnesstypes_straightness_type_id_seq RENAME TO straightness_types_straightness_type_id_seq;
ALTER SEQUENCE trees.tapertypes_taper_type_id_seq RENAME TO taper_types_taper_type_id_seq;
ALTER SEQUENCE trees.treegraphedges_edge_id_seq RENAME TO tree_graph_edges_edge_id_seq;
ALTER SEQUENCE trees.treeparttypes_part_type_id_seq RENAME TO tree_part_types_part_type_id_seq;

-- 3. Indexes.
ALTER INDEX pointclouds.idx_pointclouds_campaign RENAME TO idx_point_clouds_campaign;
ALTER INDEX pointclouds.idx_pointclouds_created_at RENAME TO idx_point_clouds_created_at;
ALTER INDEX pointclouds.idx_pointclouds_created_by RENAME TO idx_point_clouds_created_by;
ALTER INDEX pointclouds.idx_pointclouds_location RENAME TO idx_point_clouds_location;
ALTER INDEX pointclouds.idx_pointclouds_parent RENAME TO idx_point_clouds_parent;
ALTER INDEX pointclouds.idx_pointclouds_platform_type RENAME TO idx_point_clouds_platform_type;
ALTER INDEX pointclouds.idx_pointclouds_process RENAME TO idx_point_clouds_process;
ALTER INDEX pointclouds.idx_pointclouds_processing_status RENAME TO idx_point_clouds_processing_status;
ALTER INDEX pointclouds.idx_pointclouds_scan_bounds RENAME TO idx_point_clouds_scan_bounds;
ALTER INDEX pointclouds.idx_pointclouds_scan_date RENAME TO idx_point_clouds_scan_date;
ALTER INDEX pointclouds.idx_pointclouds_scanner RENAME TO idx_point_clouds_scanner;
ALTER INDEX pointclouds.idx_pointclouds_scenario RENAME TO idx_point_clouds_scenario;
ALTER INDEX pointclouds.idx_pointclouds_variant_type RENAME TO idx_point_clouds_variant_type;
ALTER INDEX shared.idx_attributeprovenance_process RENAME TO idx_attribute_provenance_process;
ALTER INDEX trees.idx_crownfoliageprofiles_tree RENAME TO idx_crown_foliage_profiles_tree;
ALTER INDEX trees.idx_qsmcylinders_qsm_branch_order RENAME TO idx_qsm_cylinders_qsm_branch_order;
ALTER INDEX trees.idx_qsmcylinders_qsm_parent RENAME TO idx_qsm_cylinders_qsm_parent;
ALTER INDEX trees.idx_treegraphedges_qsm RENAME TO idx_tree_graph_edges_qsm;
ALTER INDEX trees.idx_treegraphedges_qsm_type RENAME TO idx_tree_graph_edges_qsm_type;

-- 4. Constraints.
ALTER TABLE forest_floor.ground_vegetation RENAME CONSTRAINT groundvegetation_cover_percent_check TO ground_vegetation_cover_percent_check;
ALTER TABLE forest_floor.ground_vegetation RENAME CONSTRAINT groundvegetation_height_cm_check TO ground_vegetation_height_cm_check;
ALTER TABLE forest_floor.ground_vegetation RENAME CONSTRAINT groundvegetation_layer_check TO ground_vegetation_layer_check;
ALTER TABLE forest_floor.ground_vegetation RENAME CONSTRAINT groundvegetation_location_id_fkey TO ground_vegetation_location_id_fkey;
ALTER TABLE forest_floor.ground_vegetation RENAME CONSTRAINT groundvegetation_pkey TO ground_vegetation_pkey;
ALTER TABLE forest_floor.ground_vegetation RENAME CONSTRAINT groundvegetation_plot_id_fkey TO ground_vegetation_plot_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_campaign_id_fkey TO point_clouds_campaign_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_file_size_mb_check TO point_clouds_file_size_mb_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_flight_altitude_m_check TO point_clouds_flight_altitude_m_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_flight_speed_ms_check TO point_clouds_flight_speed_ms_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_location_id_fkey TO point_clouds_location_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_overlap_percent_check TO point_clouds_overlap_percent_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_parent_point_cloud_id_fkey TO point_clouds_parent_point_cloud_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_pkey TO point_clouds_pkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_platform_type_check TO point_clouds_platform_type_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_point_count_check TO point_clouds_point_count_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_point_density_per_m2_check TO point_clouds_point_density_per_m2_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_process_id_fkey TO point_clouds_process_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_processing_progress_check TO point_clouds_processing_progress_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_processing_status_check TO point_clouds_processing_status_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_scan_angle_deg_check TO point_clouds_scan_angle_deg_check;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_scanner_id_fkey TO point_clouds_scanner_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_scenario_id_fkey TO point_clouds_scenario_id_fkey;
ALTER TABLE pointclouds.point_clouds RENAME CONSTRAINT pointclouds_variant_type_id_fkey TO point_clouds_variant_type_id_fkey;
ALTER TABLE pointclouds.scanner_types RENAME CONSTRAINT scannertypes_pkey TO scanner_types_pkey;
ALTER TABLE pointclouds.scanner_types RENAME CONSTRAINT scannertypes_scanner_type_name_key TO scanner_types_scanner_type_name_key;
ALTER TABLE shared.attribute_provenance RENAME CONSTRAINT attributeprovenance_location_column_key TO attribute_provenance_location_column_key;
ALTER TABLE shared.attribute_provenance RENAME CONSTRAINT attributeprovenance_location_id_fkey TO attribute_provenance_location_id_fkey;
ALTER TABLE shared.attribute_provenance RENAME CONSTRAINT attributeprovenance_pkey TO attribute_provenance_pkey;
ALTER TABLE shared.attribute_provenance RENAME CONSTRAINT attributeprovenance_process_id_fkey TO attribute_provenance_process_id_fkey;
ALTER TABLE shared.disturbance_events RENAME CONSTRAINT disturbanceevents_affected_area_m2_check TO disturbance_events_affected_area_m2_check;
ALTER TABLE shared.disturbance_events RENAME CONSTRAINT disturbanceevents_disturbance_type_check TO disturbance_events_disturbance_type_check;
ALTER TABLE shared.disturbance_events RENAME CONSTRAINT disturbanceevents_location_id_fkey TO disturbance_events_location_id_fkey;
ALTER TABLE shared.disturbance_events RENAME CONSTRAINT disturbanceevents_pkey TO disturbance_events_pkey;
ALTER TABLE shared.disturbance_events RENAME CONSTRAINT disturbanceevents_plot_id_fkey TO disturbance_events_plot_id_fkey;
ALTER TABLE shared.disturbance_events RENAME CONSTRAINT disturbanceevents_severity_check TO disturbance_events_severity_check;
ALTER TABLE shared.disturbance_events_trees RENAME CONSTRAINT disturbanceevents_trees_damage_level_check TO disturbance_events_trees_damage_level_check;
ALTER TABLE shared.disturbance_events_trees RENAME CONSTRAINT disturbanceevents_trees_disturbance_event_id_fkey TO disturbance_events_trees_disturbance_event_id_fkey;
ALTER TABLE shared.disturbance_events_trees RENAME CONSTRAINT disturbanceevents_trees_pkey TO disturbance_events_trees_pkey;
ALTER TABLE shared.disturbance_events_trees RENAME CONSTRAINT disturbanceevents_trees_tree_id_fkey TO disturbance_events_trees_tree_id_fkey;
ALTER TABLE shared.management_events RENAME CONSTRAINT managementevents_affected_area_m2_check TO management_events_affected_area_m2_check;
ALTER TABLE shared.management_events RENAME CONSTRAINT managementevents_event_type_check TO management_events_event_type_check;
ALTER TABLE shared.management_events RENAME CONSTRAINT managementevents_location_id_fkey TO management_events_location_id_fkey;
ALTER TABLE shared.management_events RENAME CONSTRAINT managementevents_pkey TO management_events_pkey;
ALTER TABLE shared.management_events RENAME CONSTRAINT managementevents_plot_id_fkey TO management_events_plot_id_fkey;
ALTER TABLE shared.process_metrics RENAME CONSTRAINT processmetrics_pkey TO process_metrics_pkey;
ALTER TABLE shared.process_metrics RENAME CONSTRAINT processmetrics_process_id_fkey TO process_metrics_process_id_fkey;
ALTER TABLE shared.process_parameters RENAME CONSTRAINT processparameters_data_type_check TO process_parameters_data_type_check;
ALTER TABLE shared.process_parameters RENAME CONSTRAINT processparameters_pkey TO process_parameters_pkey;
ALTER TABLE shared.process_parameters_environments RENAME CONSTRAINT processparameters_environments_environment_id_fkey TO process_parameters_environments_environment_id_fkey;
ALTER TABLE shared.process_parameters_environments RENAME CONSTRAINT processparameters_environments_pkey TO process_parameters_environments_pkey;
ALTER TABLE shared.process_parameters_environments RENAME CONSTRAINT processparameters_environments_process_parameter_id_fkey TO process_parameters_environments_process_parameter_id_fkey;
ALTER TABLE shared.process_parameters_point_clouds RENAME CONSTRAINT processparameters_pointclouds_pkey TO process_parameters_point_clouds_pkey;
ALTER TABLE shared.process_parameters_point_clouds RENAME CONSTRAINT processparameters_pointclouds_point_cloud_id_fkey TO process_parameters_point_clouds_point_cloud_id_fkey;
ALTER TABLE shared.process_parameters_point_clouds RENAME CONSTRAINT processparameters_pointclouds_process_parameter_id_fkey TO process_parameters_point_clouds_process_parameter_id_fkey;
ALTER TABLE shared.process_parameters_stems RENAME CONSTRAINT processparameters_stems_pkey TO process_parameters_stems_pkey;
ALTER TABLE shared.process_parameters_stems RENAME CONSTRAINT processparameters_stems_process_parameter_id_fkey TO process_parameters_stems_process_parameter_id_fkey;
ALTER TABLE shared.process_parameters_stems RENAME CONSTRAINT processparameters_stems_stem_id_fkey TO process_parameters_stems_stem_id_fkey;
ALTER TABLE shared.process_parameters_trees RENAME CONSTRAINT processparameters_trees_pkey TO process_parameters_trees_pkey;
ALTER TABLE shared.process_parameters_trees RENAME CONSTRAINT processparameters_trees_process_parameter_id_fkey TO process_parameters_trees_process_parameter_id_fkey;
ALTER TABLE shared.process_parameters_trees RENAME CONSTRAINT processparameters_trees_tree_id_fkey TO process_parameters_trees_tree_id_fkey;
ALTER TABLE trees.axis_structures RENAME CONSTRAINT axisstructures_axis_structure_name_key TO axis_structures_axis_structure_name_key;
ALTER TABLE trees.axis_structures RENAME CONSTRAINT axisstructures_pkey TO axis_structures_pkey;
ALTER TABLE trees.bark_characteristics RENAME CONSTRAINT barkcharacteristics_bark_characteristic_name_key TO bark_characteristics_bark_characteristic_name_key;
ALTER TABLE trees.bark_characteristics RENAME CONSTRAINT barkcharacteristics_pkey TO bark_characteristics_pkey;
ALTER TABLE trees.branch_elongation_habits RENAME CONSTRAINT branchelongationhabits_elongation_habit_name_key TO branch_elongation_habits_elongation_habit_name_key;
ALTER TABLE trees.branch_elongation_habits RENAME CONSTRAINT branchelongationhabits_pkey TO branch_elongation_habits_pkey;
ALTER TABLE trees.branching_patterns RENAME CONSTRAINT branchingpatterns_branching_pattern_name_key TO branching_patterns_branching_pattern_name_key;
ALTER TABLE trees.branching_patterns RENAME CONSTRAINT branchingpatterns_pkey TO branching_patterns_pkey;
ALTER TABLE trees.crown_architectures RENAME CONSTRAINT crownarchitectures_crown_architecture_name_key TO crown_architectures_crown_architecture_name_key;
ALTER TABLE trees.crown_architectures RENAME CONSTRAINT crownarchitectures_pkey TO crown_architectures_pkey;
ALTER TABLE trees.crown_classes RENAME CONSTRAINT crownclasses_crown_class_name_key TO crown_classes_crown_class_name_key;
ALTER TABLE trees.crown_classes RENAME CONSTRAINT crownclasses_pkey TO crown_classes_pkey;
ALTER TABLE trees.crown_foliage_profiles RENAME CONSTRAINT crownfoliageprofiles_distribution_type_check TO crown_foliage_profiles_distribution_type_check;
ALTER TABLE trees.crown_foliage_profiles RENAME CONSTRAINT crownfoliageprofiles_pkey TO crown_foliage_profiles_pkey;
ALTER TABLE trees.crown_foliage_profiles RENAME CONSTRAINT crownfoliageprofiles_process_id_fkey TO crown_foliage_profiles_process_id_fkey;
ALTER TABLE trees.crown_foliage_profiles RENAME CONSTRAINT crownfoliageprofiles_source_check TO crown_foliage_profiles_source_check;
ALTER TABLE trees.crown_foliage_profiles RENAME CONSTRAINT crownfoliageprofiles_total_leaf_area_m2_check TO crown_foliage_profiles_total_leaf_area_m2_check;
ALTER TABLE trees.crown_foliage_profiles RENAME CONSTRAINT crownfoliageprofiles_tree_id_fkey TO crown_foliage_profiles_tree_id_fkey;
ALTER TABLE trees.crown_shapes RENAME CONSTRAINT crownshapes_crown_shape_name_key TO crown_shapes_crown_shape_name_key;
ALTER TABLE trees.crown_shapes RENAME CONSTRAINT crownshapes_pkey TO crown_shapes_pkey;
ALTER TABLE trees.damage_agents RENAME CONSTRAINT damageagents_damage_agent_name_key TO damage_agents_damage_agent_name_key;
ALTER TABLE trees.damage_agents RENAME CONSTRAINT damageagents_pkey TO damage_agents_pkey;
ALTER TABLE trees.geometric_crown_solids RENAME CONSTRAINT geometriccrownsolids_geometric_solid_name_key TO geometric_crown_solids_geometric_solid_name_key;
ALTER TABLE trees.geometric_crown_solids RENAME CONSTRAINT geometriccrownsolids_pkey TO geometric_crown_solids_pkey;
ALTER TABLE trees.geometric_crown_solids RENAME CONSTRAINT geometriccrownsolids_relative_drag_check TO geometric_crown_solids_relative_drag_check;
ALTER TABLE trees.geometric_crown_solids RENAME CONSTRAINT geometriccrownsolids_relative_lateral_area_check TO geometric_crown_solids_relative_lateral_area_check;
ALTER TABLE trees.geometric_crown_solids RENAME CONSTRAINT geometriccrownsolids_relative_volume_check TO geometric_crown_solids_relative_volume_check;
ALTER TABLE trees.growth_forms RENAME CONSTRAINT growthforms_growth_form_name_key TO growth_forms_growth_form_name_key;
ALTER TABLE trees.growth_forms RENAME CONSTRAINT growthforms_pkey TO growth_forms_pkey;
ALTER TABLE trees.growth_orientations RENAME CONSTRAINT growthorientations_growth_orientation_name_key TO growth_orientations_growth_orientation_name_key;
ALTER TABLE trees.growth_orientations RENAME CONSTRAINT growthorientations_pkey TO growth_orientations_pkey;
ALTER TABLE trees.phanerophyte_height_classes RENAME CONSTRAINT phanerophyteheightclasses_height_class_name_key TO phanerophyte_height_classes_height_class_name_key;
ALTER TABLE trees.phanerophyte_height_classes RENAME CONSTRAINT phanerophyteheightclasses_max_height_m_check TO phanerophyte_height_classes_max_height_m_check;
ALTER TABLE trees.phanerophyte_height_classes RENAME CONSTRAINT phanerophyteheightclasses_min_height_m_check TO phanerophyte_height_classes_min_height_m_check;
ALTER TABLE trees.phanerophyte_height_classes RENAME CONSTRAINT phanerophyteheightclasses_pkey TO phanerophyte_height_classes_pkey;
ALTER TABLE trees.phenology_observations RENAME CONSTRAINT phenologyobservations_intensity_percent_check TO phenology_observations_intensity_percent_check;
ALTER TABLE trees.phenology_observations RENAME CONSTRAINT phenologyobservations_phenophase_status_check TO phenology_observations_phenophase_status_check;
ALTER TABLE trees.phenology_observations RENAME CONSTRAINT phenologyobservations_phenophase_type_check TO phenology_observations_phenophase_type_check;
ALTER TABLE trees.phenology_observations RENAME CONSTRAINT phenologyobservations_pkey TO phenology_observations_pkey;
ALTER TABLE trees.phenology_observations RENAME CONSTRAINT phenologyobservations_tree_id_fkey TO phenology_observations_tree_id_fkey;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_axis_check TO qsm_cylinders_axis_check;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_branch_order_check TO qsm_cylinders_branch_order_check;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_length_m_check TO qsm_cylinders_length_m_check;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_part_type_id_fkey TO qsm_cylinders_part_type_id_fkey;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_pkey TO qsm_cylinders_pkey;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_qsm_id_cylinder_index_key TO qsm_cylinders_qsm_id_cylinder_index_key;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_qsm_id_fkey TO qsm_cylinders_qsm_id_fkey;
ALTER TABLE trees.qsm_cylinders RENAME CONSTRAINT qsmcylinders_radius_m_check TO qsm_cylinders_radius_m_check;
ALTER TABLE trees.root_system_types RENAME CONSTRAINT rootsystemtypes_pkey TO root_system_types_pkey;
ALTER TABLE trees.root_system_types RENAME CONSTRAINT rootsystemtypes_root_system_type_name_key TO root_system_types_root_system_type_name_key;
ALTER TABLE trees.shoot_elongation_types RENAME CONSTRAINT shootelongationtypes_pkey TO shoot_elongation_types_pkey;
ALTER TABLE trees.shoot_elongation_types RENAME CONSTRAINT shootelongationtypes_shoot_elongation_type_name_key TO shoot_elongation_types_shoot_elongation_type_name_key;
ALTER TABLE trees.straightness_types RENAME CONSTRAINT straightnesstypes_deviation_angle_max_check TO straightness_types_deviation_angle_max_check;
ALTER TABLE trees.straightness_types RENAME CONSTRAINT straightnesstypes_deviation_angle_min_check TO straightness_types_deviation_angle_min_check;
ALTER TABLE trees.straightness_types RENAME CONSTRAINT straightnesstypes_pkey TO straightness_types_pkey;
ALTER TABLE trees.straightness_types RENAME CONSTRAINT straightnesstypes_straightness_name_key TO straightness_types_straightness_name_key;
ALTER TABLE trees.taper_types RENAME CONSTRAINT tapertypes_pkey TO taper_types_pkey;
ALTER TABLE trees.taper_types RENAME CONSTRAINT tapertypes_taper_type_name_key TO taper_types_taper_type_name_key;
ALTER TABLE trees.taper_types RENAME CONSTRAINT tapertypes_typical_taper_ratio_max_check TO taper_types_typical_taper_ratio_max_check;
ALTER TABLE trees.taper_types RENAME CONSTRAINT tapertypes_typical_taper_ratio_min_check TO taper_types_typical_taper_ratio_min_check;
ALTER TABLE trees.tree_graph_edges RENAME CONSTRAINT treegraphedges_edge_type_check TO tree_graph_edges_edge_type_check;
ALTER TABLE trees.tree_graph_edges RENAME CONSTRAINT treegraphedges_pkey TO tree_graph_edges_pkey;
ALTER TABLE trees.tree_graph_edges RENAME CONSTRAINT treegraphedges_qsm_from_to_key TO tree_graph_edges_qsm_from_to_key;
ALTER TABLE trees.tree_graph_edges RENAME CONSTRAINT treegraphedges_qsm_id_fkey TO tree_graph_edges_qsm_id_fkey;
ALTER TABLE trees.tree_part_types RENAME CONSTRAINT treeparttypes_part_type_name_key TO tree_part_types_part_type_name_key;
ALTER TABLE trees.tree_part_types RENAME CONSTRAINT treeparttypes_pkey TO tree_part_types_pkey;

-- 5. Column renames landing with the tables that carry them.
--    XRFF-487: shorten the PK rather than lengthen the label. The FK columns in
--    trees.trees are already elongation_habit_id / height_class_id, so after this
--    the FK matches its parent's PK name -- no FK column rename is needed.
ALTER TABLE trees.branch_elongation_habits RENAME COLUMN branch_elongation_habit_id TO elongation_habit_id;
ALTER TABLE trees.phanerophyte_height_classes RENAME COLUMN phanerophyte_height_class_id TO height_class_id;
ALTER TABLE trees.straightness_types RENAME COLUMN straightness_name TO straightness_type_name;

-- XRFF-490 (the free half): angles carry their unit, matching lean_angle_deg.
ALTER TABLE trees.straightness_types RENAME COLUMN deviation_angle_min TO deviation_angle_min_deg;
ALTER TABLE trees.straightness_types RENAME COLUMN deviation_angle_max TO deviation_angle_max_deg;

-- Sequences follow the shortened PK names. This is what buys back the
-- identifier-length headroom: the first of these was 58 bytes and would have
-- been 60 after the table rename alone; it is now 47.
ALTER SEQUENCE trees.phanerophyte_height_classes_phanerophyte_height_class_id_seq
    RENAME TO phanerophyte_height_classes_height_class_id_seq;
ALTER SEQUENCE trees.branch_elongation_habits_branch_elongation_habit_id_seq
    RENAME TO branch_elongation_habits_elongation_habit_id_seq;
CREATE OR REPLACE FUNCTION public.pointclouds_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO pointclouds.point_clouds SELECT NEW.*;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.disturbanceevents_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO shared.disturbance_events (
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
$function$;

CREATE OR REPLACE FUNCTION public.managementevents_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO shared.management_events (
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
$function$;

CREATE OR REPLACE FUNCTION public.phenologyobservations_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO trees.phenology_observations (
        tree_id, observation_date, phenophase_type,
        phenophase_status, intensity_percent, observer, notes, created_by
    ) VALUES (
        NEW.tree_id, NEW.observation_date, NEW.phenophase_type,
        NEW.phenophase_status, NEW.intensity_percent, NEW.observer, NEW.notes, NEW.created_by
    ) RETURNING phenology_observation_id INTO NEW.phenology_observation_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.groundvegetation_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO forest_floor.ground_vegetation (
        location_id, plot_id, species_name, cover_percent,
        height_cm, layer, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.species_name, NEW.cover_percent,
        NEW.height_cm, NEW.layer, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING ground_vegetation_id INTO NEW.ground_vegetation_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION trees.assign_height_class()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.Height_m IS NOT NULL AND NEW.height_class_id IS NULL THEN
        SELECT height_class_id INTO NEW.height_class_id
        FROM trees.phanerophyte_height_classes
        WHERE (min_height_m IS NULL OR NEW.Height_m >= min_height_m)
          AND (max_height_m IS NULL OR NEW.Height_m < max_height_m)
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.refresh_lookup(p_table_name text)
 RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_rows_before INT;
    v_rows_after INT;
    v_csv_path TEXT;
BEGIN
    -- Normalize table name
    p_table_name := lower(trim(p_table_name));
    -- Map table names to CSV files
    v_csv_path := '/var/lib/postgresql/lookups/';
    CASE p_table_name
        WHEN 'species' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.species;
            CREATE TEMP TABLE IF NOT EXISTS _temp_species (
                common_name VARCHAR(200),
                scientific_name VARCHAR(200),
                max_height_m NUMERIC(6, 2),
                max_dbh_cm NUMERIC(6, 2),
                typical_lifespan_years INTEGER,
                growth_rate VARCHAR(20),
                shade_tolerance VARCHAR(20),
                is_deciduous BOOLEAN,
                gbif_key INTEGER,
                gbif_accepted_name VARCHAR(200)
            ) ON COMMIT DROP;
            TRUNCATE _temp_species;
            EXECUTE format('COPY _temp_species FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'species.csv');
            INSERT INTO shared.Species (common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name)
            SELECT common_name, scientific_name, max_height_m, max_dbh_cm, typical_lifespan_years, growth_rate, shade_tolerance, is_deciduous, gbif_key, gbif_accepted_name
            FROM _temp_species
            ON CONFLICT (scientific_name) DO UPDATE SET
                common_name = EXCLUDED.common_name,
                max_height_m = EXCLUDED.max_height_m,
                max_dbh_cm = EXCLUDED.max_dbh_cm,
                typical_lifespan_years = EXCLUDED.typical_lifespan_years,
                growth_rate = EXCLUDED.growth_rate,
                shade_tolerance = EXCLUDED.shade_tolerance,
                is_deciduous = EXCLUDED.is_deciduous,
                gbif_key = EXCLUDED.gbif_key,
                gbif_accepted_name = EXCLUDED.gbif_accepted_name;
            SELECT COUNT(*) INTO v_rows_after FROM shared.species;
        WHEN 'locations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.locations;
            CREATE TEMP TABLE IF NOT EXISTS _temp_locations (
                location_name VARCHAR(200),
                Description TEXT,
                CenterLongitude NUMERIC(10, 6),
                CenterLatitude NUMERIC(10, 6),
                Elevation_m NUMERIC(8, 2),
                Slope_deg NUMERIC(5, 2),
                Aspect VARCHAR(3),
                soil_type_name VARCHAR(100),
                climate_zone_name VARCHAR(10),
                ForestGrowthRegion VARCHAR(16),
                SoilMoistness SMALLINT,
                SoilNutrientSupply SMALLINT,
                CrsEpsg INTEGER
            ) ON COMMIT DROP;
            TRUNCATE _temp_locations;
            EXECUTE format('COPY _temp_locations FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'locations.csv');
            INSERT INTO shared.Locations (location_name, Description, center_point, Elevation_m, Slope_deg, Aspect, soil_type_id, climate_zone_id, forest_growth_region, soil_moistness, soil_nutrient_supply, crs_epsg)
            SELECT 
                t.location_name,
                t.Description,
                CASE WHEN t.CenterLongitude IS NOT NULL AND t.CenterLatitude IS NOT NULL 
                     THEN extensions.ST_SetSRID(extensions.ST_MakePoint(t.CenterLongitude, t.CenterLatitude), 4326)
                     ELSE NULL 
                END,
                t.Elevation_m,
                t.Slope_deg,
                t.Aspect,
                (SELECT soil_type_id FROM shared.SoilTypes WHERE soil_type_name = t.soil_type_name),
                (SELECT climate_zone_id FROM shared.ClimateZones WHERE climate_zone_name = t.climate_zone_name),
                t.ForestGrowthRegion,
                t.SoilMoistness,
                t.SoilNutrientSupply,
                t.CrsEpsg
            FROM _temp_locations t
            -- The eight site-attribute columns keep their value once an
            -- acquisition process has written one, so a refresh cannot revert it
            -- and leave its provenance row claiming a source the column no
            -- longer holds (XRFF-391). Description, center_point and crs_epsg are
            -- always reseeded: the CSV owns all three.
            ON CONFLICT (location_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                center_point = EXCLUDED.center_point,
                crs_epsg = EXCLUDED.crs_epsg,
                Elevation_m = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'elevation_m')
                                   THEN Locations.Elevation_m ELSE EXCLUDED.Elevation_m END,
                Slope_deg = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'slope_deg')
                                 THEN Locations.Slope_deg ELSE EXCLUDED.Slope_deg END,
                Aspect = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'aspect')
                              THEN Locations.Aspect ELSE EXCLUDED.Aspect END,
                soil_type_id = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_type_id')
                                    THEN Locations.soil_type_id ELSE EXCLUDED.soil_type_id END,
                climate_zone_id = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'climate_zone_id')
                                       THEN Locations.climate_zone_id ELSE EXCLUDED.climate_zone_id END,
                forest_growth_region = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'forest_growth_region')
                                            THEN Locations.forest_growth_region ELSE EXCLUDED.forest_growth_region END,
                soil_moistness = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_moistness')
                                      THEN Locations.soil_moistness ELSE EXCLUDED.soil_moistness END,
                soil_nutrient_supply = CASE WHEN shared.attribute_is_acquired(Locations.location_id, 'soil_nutrient_supply')
                                            THEN Locations.soil_nutrient_supply ELSE EXCLUDED.soil_nutrient_supply END;
            SELECT COUNT(*) INTO v_rows_after FROM shared.locations;
        WHEN 'sensor_types', 'sensortypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM sensor.sensortypes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_sensor_types (
                sensor_type_name VARCHAR(100),
                Description TEXT,
                typical_unit VARCHAR(50),
                typical_range_min NUMERIC(12, 4),
                typical_range_max NUMERIC(12, 4)
            ) ON COMMIT DROP;
            TRUNCATE _temp_sensor_types;
            EXECUTE format('COPY _temp_sensor_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'sensor_types.csv');
            INSERT INTO sensor.SensorTypes (sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max)
            SELECT sensor_type_name, Description, typical_unit, typical_range_min, typical_range_max 
            FROM _temp_sensor_types
            ON CONFLICT (sensor_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_unit = EXCLUDED.typical_unit,
                typical_range_min = EXCLUDED.typical_range_min,
                typical_range_max = EXCLUDED.typical_range_max;
            SELECT COUNT(*) INTO v_rows_after FROM sensor.sensortypes;
            p_table_name := 'sensor_types';
        WHEN 'tree_status', 'treestatus' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.treestatus;
            CREATE TEMP TABLE IF NOT EXISTS _temp_tree_status (
                tree_status_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_tree_status;
            EXECUTE format('COPY _temp_tree_status FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'tree_status.csv');
            INSERT INTO trees.TreeStatus (tree_status_name, Description)
            SELECT tree_status_name, Description FROM _temp_tree_status
            ON CONFLICT (tree_status_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.treestatus;
            p_table_name := 'tree_status';
        WHEN 'soil_types', 'soiltypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.soiltypes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_soil_types (
                soil_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_soil_types;
            EXECUTE format('COPY _temp_soil_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'soil_types.csv');
            INSERT INTO shared.SoilTypes (soil_type_name, Description)
            SELECT soil_type_name, Description FROM _temp_soil_types
            ON CONFLICT (soil_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM shared.soiltypes;
            p_table_name := 'soil_types';
        WHEN 'climate_zones', 'climatezones' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.climatezones;
            CREATE TEMP TABLE IF NOT EXISTS _temp_climate_zones (
                climate_zone_name VARCHAR(10),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_climate_zones;
            EXECUTE format('COPY _temp_climate_zones FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'climate_zones.csv');
            INSERT INTO shared.ClimateZones (climate_zone_name, Description)
            SELECT climate_zone_name, Description FROM _temp_climate_zones
            ON CONFLICT (climate_zone_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM shared.climatezones;
            p_table_name := 'climate_zones';
        WHEN 'variant_types', 'varianttypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM shared.varianttypes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_variant_types (
                variant_type_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_variant_types;
            EXECUTE format('COPY _temp_variant_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'variant_types.csv');
            INSERT INTO shared.VariantTypes (variant_type_name, Description)
            SELECT variant_type_name, Description FROM _temp_variant_types
            ON CONFLICT (variant_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM shared.varianttypes;
            p_table_name := 'variant_types';
        WHEN 'scenarios' THEN
            -- Scenarios are location-scoped (Scenarios.location_id NOT NULL,
            -- UNIQUE(location_id, scenario_name)) and are created per site by the
            -- growth-variant seed scripts — not a refreshable global lookup CSV.
            SELECT COUNT(*) INTO v_rows_before FROM shared.scenarios;
            RAISE NOTICE 'scenarios are location-scoped; not refreshed from a global CSV (skipped)';
            v_rows_after := v_rows_before;
        WHEN 'taper_types', 'tapertypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.taper_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_taper_types (
                taper_type_name VARCHAR(100),
                Description TEXT,
                typical_taper_ratio_min NUMERIC(4, 3),
                typical_taper_ratio_max NUMERIC(4, 3)
            ) ON COMMIT DROP;
            TRUNCATE _temp_taper_types;
            EXECUTE format('COPY _temp_taper_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'taper_types.csv');
            INSERT INTO trees.taper_types (taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max)
            SELECT taper_type_name, Description, typical_taper_ratio_min, typical_taper_ratio_max FROM _temp_taper_types
            ON CONFLICT (taper_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_taper_ratio_min = EXCLUDED.typical_taper_ratio_min,
                typical_taper_ratio_max = EXCLUDED.typical_taper_ratio_max;
            SELECT COUNT(*) INTO v_rows_after FROM trees.taper_types;
            p_table_name := 'taper_types';
        WHEN 'straightness_types', 'straightnesstypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.straightness_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_straightness_types (
                straightness_type_name VARCHAR(100),
                Description TEXT,
                deviation_angle_min_deg NUMERIC(5, 2),
                deviation_angle_max_deg NUMERIC(5, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_straightness_types;
            EXECUTE format('COPY _temp_straightness_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'straightness_types.csv');
            INSERT INTO trees.straightness_types (straightness_type_name, Description, deviation_angle_min_deg, deviation_angle_max_deg)
            SELECT straightness_type_name, Description, deviation_angle_min_deg, deviation_angle_max_deg FROM _temp_straightness_types
            ON CONFLICT (straightness_type_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                deviation_angle_min_deg = EXCLUDED.deviation_angle_min_deg,
                deviation_angle_max_deg = EXCLUDED.deviation_angle_max_deg;
            SELECT COUNT(*) INTO v_rows_after FROM trees.straightness_types;
            p_table_name := 'straightness_types';
        WHEN 'branching_patterns', 'branchingpatterns' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branching_patterns;
            CREATE TEMP TABLE IF NOT EXISTS _temp_branching_patterns (
                branching_pattern_name VARCHAR(100),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_branching_patterns;
            EXECUTE format('COPY _temp_branching_patterns FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branching_patterns.csv');
            INSERT INTO trees.branching_patterns (branching_pattern_name, Description)
            SELECT branching_pattern_name, Description FROM _temp_branching_patterns
            ON CONFLICT (branching_pattern_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.branching_patterns;
            p_table_name := 'branching_patterns';
        WHEN 'bark_characteristics', 'barkcharacteristics' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.bark_characteristics;
            CREATE TEMP TABLE IF NOT EXISTS _temp_bark_characteristics (
                bark_characteristic_name VARCHAR(100),
                Description TEXT,
                typical_species TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_bark_characteristics;
            EXECUTE format('COPY _temp_bark_characteristics FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'bark_characteristics.csv');
            INSERT INTO trees.bark_characteristics (bark_characteristic_name, Description, typical_species)
            SELECT bark_characteristic_name, Description, typical_species FROM _temp_bark_characteristics
            ON CONFLICT (bark_characteristic_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_species = EXCLUDED.typical_species;
            SELECT COUNT(*) INTO v_rows_after FROM trees.bark_characteristics;
            p_table_name := 'bark_characteristics';
        WHEN 'datasource_types', 'datasourcetypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.datasourcetypes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_datasource_types (
                data_source_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_datasource_types;
            EXECUTE format('COPY _temp_datasource_types FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'datasource_types.csv');
            INSERT INTO trees.DataSourceTypes (data_source_type_name, Description)
            SELECT data_source_type_name, Description FROM _temp_datasource_types
            ON CONFLICT (data_source_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.datasourcetypes;
            p_table_name := 'datasource_types';
        -- =====================================================================
        -- TREE MORPHOLOGY TABLES (from tree_anatomy.pdf)
        -- =====================================================================
        WHEN 'height_classes', 'phanerophyte_height_classes', 'phanerophyteheightclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.phanerophyte_height_classes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_height_classes (
                height_class_name VARCHAR(50),
                Description TEXT,
                min_height_m NUMERIC(6, 2),
                max_height_m NUMERIC(6, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_height_classes;
            EXECUTE format('COPY _temp_height_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'phanerophyte_height_classes.csv');
            INSERT INTO trees.phanerophyte_height_classes (height_class_name, Description, min_height_m, max_height_m)
            SELECT height_class_name, Description, min_height_m, max_height_m FROM _temp_height_classes
            ON CONFLICT (height_class_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                min_height_m = EXCLUDED.min_height_m,
                max_height_m = EXCLUDED.max_height_m;
            SELECT COUNT(*) INTO v_rows_after FROM trees.phanerophyte_height_classes;
            p_table_name := 'height_classes';
        WHEN 'crown_architectures', 'crownarchitectures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crown_architectures;
            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_arch (
                crown_architecture_name VARCHAR(50),
                Description TEXT,
                typical_examples TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_arch;
            EXECUTE format('COPY _temp_crown_arch FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_architectures.csv');
            INSERT INTO trees.crown_architectures (crown_architecture_name, Description, typical_examples)
            SELECT crown_architecture_name, Description, typical_examples FROM _temp_crown_arch
            ON CONFLICT (crown_architecture_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                typical_examples = EXCLUDED.typical_examples;
            SELECT COUNT(*) INTO v_rows_after FROM trees.crown_architectures;
            p_table_name := 'crown_architectures';
        WHEN 'branch_elongation_habits', 'branchelongationhabits', 'elongation_habits' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.branch_elongation_habits;
            CREATE TEMP TABLE IF NOT EXISTS _temp_elongation (
                elongation_habit_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_elongation;
            EXECUTE format('COPY _temp_elongation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'branch_elongation_habits.csv');
            INSERT INTO trees.branch_elongation_habits (elongation_habit_name, Description)
            SELECT elongation_habit_name, Description FROM _temp_elongation
            ON CONFLICT (elongation_habit_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.branch_elongation_habits;
            p_table_name := 'branch_elongation_habits';
        WHEN 'growth_orientations', 'growthorientations' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growth_orientations;
            CREATE TEMP TABLE IF NOT EXISTS _temp_orientation (
                growth_orientation_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_orientation;
            EXECUTE format('COPY _temp_orientation FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_orientations.csv');
            INSERT INTO trees.growth_orientations (growth_orientation_name, Description)
            SELECT growth_orientation_name, Description FROM _temp_orientation
            ON CONFLICT (growth_orientation_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.growth_orientations;
            p_table_name := 'growth_orientations';
        WHEN 'shoot_elongation_types', 'shootelongationtypes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.shoot_elongation_types;
            CREATE TEMP TABLE IF NOT EXISTS _temp_shoot (
                shoot_elongation_type_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shoot;
            EXECUTE format('COPY _temp_shoot FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'shoot_elongation_types.csv');
            INSERT INTO trees.shoot_elongation_types (shoot_elongation_type_name, Description)
            SELECT shoot_elongation_type_name, Description FROM _temp_shoot
            ON CONFLICT (shoot_elongation_type_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.shoot_elongation_types;
            p_table_name := 'shoot_elongation_types';
        WHEN 'crown_shapes', 'crownshapes' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crown_shapes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_shapes (
                crown_shape_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_shapes;
            EXECUTE format('COPY _temp_shapes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_shapes.csv');
            INSERT INTO trees.crown_shapes (crown_shape_name, Description)
            SELECT crown_shape_name, Description FROM _temp_shapes
            ON CONFLICT (crown_shape_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.crown_shapes;
            p_table_name := 'crown_shapes';
        WHEN 'geometric_crown_solids', 'geometriccrownsolids', 'geometric_solids' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.geometric_crown_solids;
            CREATE TEMP TABLE IF NOT EXISTS _temp_solids (
                geometric_solid_name VARCHAR(50),
                Description TEXT,
                relative_lateral_area NUMERIC(4, 2),
                relative_volume NUMERIC(4, 2),
                relative_drag NUMERIC(4, 2)
            ) ON COMMIT DROP;
            TRUNCATE _temp_solids;
            EXECUTE format('COPY _temp_solids FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'geometric_crown_solids.csv');
            INSERT INTO trees.geometric_crown_solids (geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag)
            SELECT geometric_solid_name, Description, relative_lateral_area, relative_volume, relative_drag FROM _temp_solids
            ON CONFLICT (geometric_solid_name) DO UPDATE SET
                Description = EXCLUDED.Description,
                relative_lateral_area = EXCLUDED.relative_lateral_area,
                relative_volume = EXCLUDED.relative_volume,
                relative_drag = EXCLUDED.relative_drag;
            SELECT COUNT(*) INTO v_rows_after FROM trees.geometric_crown_solids;
            p_table_name := 'geometric_crown_solids';
        WHEN 'axis_structures', 'axisstructures' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.axis_structures;
            CREATE TEMP TABLE IF NOT EXISTS _temp_axis (
                axis_structure_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_axis;
            EXECUTE format('COPY _temp_axis FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'axis_structures.csv');
            INSERT INTO trees.axis_structures (axis_structure_name, Description)
            SELECT axis_structure_name, Description FROM _temp_axis
            ON CONFLICT (axis_structure_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.axis_structures;
            p_table_name := 'axis_structures';
        WHEN 'growth_forms', 'growthforms' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.growth_forms;
            CREATE TEMP TABLE IF NOT EXISTS _temp_forms (
                growth_form_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_forms;
            EXECUTE format('COPY _temp_forms FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'growth_forms.csv');
            INSERT INTO trees.growth_forms (growth_form_name, Description)
            SELECT growth_form_name, Description FROM _temp_forms
            ON CONFLICT (growth_form_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.growth_forms;
            p_table_name := 'growth_forms';
        -- =====================================================================
        -- TREE CONDITION TABLES (FIA/NEON/ICP Forests-aligned)
        -- =====================================================================
        WHEN 'crown_classes', 'crownclasses' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.crown_classes;
            CREATE TEMP TABLE IF NOT EXISTS _temp_crown_classes (
                crown_class_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_crown_classes;
            EXECUTE format('COPY _temp_crown_classes FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'crown_classes.csv');
            INSERT INTO trees.crown_classes (crown_class_name, Description)
            SELECT crown_class_name, Description FROM _temp_crown_classes
            ON CONFLICT (crown_class_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.crown_classes;
            p_table_name := 'crown_classes';
        WHEN 'damage_agents', 'damageagents' THEN
            SELECT COUNT(*) INTO v_rows_before FROM trees.damage_agents;
            CREATE TEMP TABLE IF NOT EXISTS _temp_damage_agents (
                damage_agent_name VARCHAR(50),
                Description TEXT
            ) ON COMMIT DROP;
            TRUNCATE _temp_damage_agents;
            EXECUTE format('COPY _temp_damage_agents FROM %L WITH (FORMAT csv, HEADER true)', v_csv_path || 'damage_agents.csv');
            INSERT INTO trees.damage_agents (damage_agent_name, Description)
            SELECT damage_agent_name, Description FROM _temp_damage_agents
            ON CONFLICT (damage_agent_name) DO UPDATE SET Description = EXCLUDED.Description;
            SELECT COUNT(*) INTO v_rows_after FROM trees.damage_agents;
            p_table_name := 'damage_agents';
        ELSE
            RETURN QUERY SELECT p_table_name, 0, 0, 'ERROR: Unknown table. Use: species, locations, sensor_types, tree_status, soil_types, climate_zones, variant_types, scenarios, taper_types, straightness_types, branching_patterns, bark_characteristics, datasource_types, height_classes, crown_architectures, branch_elongation_habits, growth_orientations, shoot_elongation_types, crown_shapes, geometric_crown_solids, axis_structures, growth_forms, crown_classes, damage_agents';
            RETURN;
    END CASE;
    RETURN QUERY SELECT p_table_name, v_rows_before, v_rows_after, 'OK';
END;
$function$;

CREATE OR REPLACE FUNCTION public.crownfoliageprofiles_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO trees.crown_foliage_profiles (
        tree_id, process_id, distribution_type, vertical_params,
        horizontal_params, total_leaf_area_m2, source, created_by
    ) VALUES (
        NEW.tree_id, NEW.process_id, NEW.distribution_type, NEW.vertical_params,
        NEW.horizontal_params, NEW.total_leaf_area_m2, NEW.source, NEW.created_by
    ) RETURNING profile_id INTO NEW.profile_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.treegraphedges_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO trees.tree_graph_edges (
        qsm_id, from_cylinder_index, to_cylinder_index, edge_type
    ) VALUES (
        NEW.qsm_id, NEW.from_cylinder_index, NEW.to_cylinder_index, NEW.edge_type
    ) RETURNING edge_id INTO NEW.edge_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_location_attributes(p_location_id integer, p_attributes jsonb, p_process_id integer, p_source_uri text DEFAULT NULL::text, p_license character varying DEFAULT NULL::character varying, p_fetched_at timestamp with time zone DEFAULT now())
 RETURNS TABLE(out_written_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
    c_settable CONSTANT text[] := ARRAY[
        'elevation_m', 'slope_deg', 'aspect',
        'soil_type_id', 'climate_zone_id',
        'forest_growth_region', 'soil_moistness', 'soil_nutrient_supply'
    ];
    v_rejected text[];
    v_column   text;
    v_type     text;
    v_count    integer := 0;
BEGIN
    IF p_attributes IS NULL OR jsonb_typeof(p_attributes) <> 'object' THEN
        RAISE EXCEPTION 'p_attributes must be a JSON object, got %',
            COALESCE(jsonb_typeof(p_attributes), 'null');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.locations WHERE location_id = p_location_id) THEN
        RAISE EXCEPTION 'no such location: %', p_location_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'no such process: % -- register the source in shared.Processes first',
            p_process_id;
    END IF;
    SELECT array_agg(k ORDER BY k) INTO v_rejected
      FROM jsonb_object_keys(p_attributes) AS k
     WHERE k <> ALL (c_settable);
    IF v_rejected IS NOT NULL THEN
        RAISE EXCEPTION 'not settable through set_location_attributes: % (settable: %)',
            array_to_string(v_rejected, ', '), array_to_string(c_settable, ', ');
    END IF;
    FOR v_column IN SELECT k FROM jsonb_object_keys(p_attributes) AS k ORDER BY k
    LOOP
        SELECT format_type(a.atttypid, a.atttypmod) INTO v_type
          FROM pg_attribute a
         WHERE a.attrelid = 'shared.locations'::regclass
           AND a.attname  = v_column
           AND a.attnum > 0 AND NOT a.attisdropped;
        -- The cast is to the column's own declared type, so a bad value fails
        -- here rather than being coerced into something plausible.
        EXECUTE format('UPDATE shared.locations SET %I = $1::%s WHERE location_id = $2',
                       v_column, v_type)
          USING p_attributes ->> v_column, p_location_id;
        INSERT INTO shared.attribute_provenance
            (location_id, column_name, process_id, fetched_at, source_uri, license)
        VALUES (p_location_id, v_column, p_process_id, p_fetched_at, p_source_uri, p_license)
        ON CONFLICT (location_id, column_name) DO UPDATE SET
            process_id = EXCLUDED.process_id,
            fetched_at = EXCLUDED.fetched_at,
            source_uri = EXCLUDED.source_uri,
            license    = EXCLUDED.license;
        v_count := v_count + 1;
    END LOOP;
    RETURN QUERY SELECT v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION shared.attribute_is_acquired(p_location_id integer, p_column_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM shared.attribute_provenance
        WHERE location_id = p_location_id
          AND column_name = p_column_name
    );
$function$;
