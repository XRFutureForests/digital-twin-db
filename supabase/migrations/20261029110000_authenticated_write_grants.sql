-- =============================================================================
-- Let the write policies take effect: table grants for authenticated
-- =============================================================================
-- Every table below has RLS enabled and a write policy for authenticated --
-- contributors insert field data (shared.is_contributor()), curators update and
-- delete it (shared.is_curator()), and the metadata tables (species, locations,
-- campaigns, plots, scenarios, processes, sensors, scanners, events) are open to
-- any signed-in account. That is the model docs/data-access-guide.md describes.
--
-- It never took effect. Since the 2026-07-17 baseline authenticated holds only
-- SELECT on these tables (sensor_readings had INSERT), and a missing grant fails
-- before RLS is consulted: a contributor's INSERT into trees.trees, directly or
-- through the public.trees INSTEAD OF trigger, got "permission denied for table
-- trees". Found 2026-10-29 while onboarding an app developer on dt.unr.
--
-- The same gap exists for reads: the RLS-enabled tables in the first block
-- below carry a SELECT policy for authenticated (or public) but no SELECT grant.
-- Writes trip over it -- trees.assign_height_class(), a BEFORE INSERT trigger on
-- trees.trees, reads trees.phanerophyte_height_classes as the caller, so a
-- contributor's insert with a height failed on that lookup instead.
--
-- So the grant follows the policy, never wider: SELECT where a SELECT policy
-- exists, INSERT/UPDATE/DELETE only where an authenticated policy for that
-- command exists (ALL = all three), and USAGE on the sequences those tables own
-- so an INSERT can draw an id. RLS still decides who may do what. Untouched on
-- purpose:
--   * tables without RLS (shared.variants, sensor.units, sensor.sensor_tree_links,
--     shared.lookup_registry, trees.data_source_types, trees.growth_simulations,
--     shared.audit_log_phenology_observations) -- a grant there would bypass
--     every role check;
--   * writes to tables whose only authenticated policy is SELECT (lookups,
--     audit_log, shared.processing_jobs -- jobs go through request_job()).
-- The audit and created_by/updated_by triggers are SECURITY DEFINER, so they
-- keep working for user-token writes.
--
-- Both lists were generated from pg_class.relrowsecurity + pg_policies on dev
-- and were identical on dt.unr.
--
-- Mirrored to init 67-authenticated-write-grants.sql.
-- =============================================================================

GRANT SELECT ON TABLE shared.audit_log_environments TO authenticated;
GRANT SELECT ON TABLE shared.audit_log_point_clouds TO authenticated;
GRANT SELECT ON TABLE shared.audit_log_stems TO authenticated;
GRANT SELECT ON TABLE shared.audit_log_trees TO authenticated;
GRANT SELECT ON TABLE shared.disturbance_events_trees TO authenticated;
GRANT SELECT ON TABLE shared.process_parameters_environments TO authenticated;
GRANT SELECT ON TABLE shared.process_parameters_point_clouds TO authenticated;
GRANT SELECT ON TABLE shared.process_parameters_stems TO authenticated;
GRANT SELECT ON TABLE shared.process_parameters_trees TO authenticated;
GRANT SELECT ON TABLE trees.axis_structures TO authenticated;
GRANT SELECT ON TABLE trees.branch_elongation_habits TO authenticated;
GRANT SELECT ON TABLE trees.crown_architectures TO authenticated;
GRANT SELECT ON TABLE trees.crown_classes TO authenticated;
GRANT SELECT ON TABLE trees.crown_shapes TO authenticated;
GRANT SELECT ON TABLE trees.damage_agents TO authenticated;
GRANT SELECT ON TABLE trees.geometric_crown_solids TO authenticated;
GRANT SELECT ON TABLE trees.growth_forms TO authenticated;
GRANT SELECT ON TABLE trees.growth_orientations TO authenticated;
GRANT SELECT ON TABLE trees.phanerophyte_height_classes TO authenticated;
GRANT SELECT ON TABLE trees.shoot_elongation_types TO authenticated;

GRANT INSERT, UPDATE, DELETE ON TABLE environments.environments TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE forest_floor.deadwood TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE forest_floor.ground_vegetation TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE imagery.images TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE pointclouds.point_clouds TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE pointclouds.scanners TO authenticated;
GRANT INSERT ON TABLE sensor.sensor_readings TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE sensor.sensors TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.attribute_provenance TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.campaigns TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.climate_pathways TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.disturbance_events TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.disturbance_events_trees TO authenticated;
GRANT INSERT, UPDATE ON TABLE shared.locations TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.management_events TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.management_regimes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.plots TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.process_metrics TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.process_parameters TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.process_parameters_environments TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.process_parameters_point_clouds TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.process_parameters_stems TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.process_parameters_trees TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.processes TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.scenarios TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE shared.species TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.crown_foliage_profiles TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.phenology_observations TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.qsm_cylinders TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.qsms TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.roots TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.simulation_runs TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.stems TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.tree_graph_edges TO authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE trees.trees TO authenticated;

GRANT USAGE ON SEQUENCE environments.environments_environment_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE forest_floor.deadwood_deadwood_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE forest_floor.ground_vegetation_ground_vegetation_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE imagery.images_image_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE pointclouds.point_clouds_point_cloud_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE pointclouds.scanners_scanner_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE sensor.sensor_readings_sensor_reading_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE sensor.sensors_sensor_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.attribute_provenance_attribute_provenance_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.campaigns_campaign_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.disturbance_events_disturbance_event_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.locations_location_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.management_events_management_event_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.plots_plot_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.process_metrics_process_metric_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.process_parameters_process_parameter_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.processes_process_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.scenarios_scenario_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE shared.species_species_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.crown_foliage_profiles_crown_foliage_profile_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.phenology_observations_phenology_observation_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.qsm_cylinders_qsm_cylinder_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.qsms_qsm_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.roots_root_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.stems_stem_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.tree_graph_edges_tree_graph_edge_id_seq TO authenticated;
GRANT USAGE ON SEQUENCE trees.trees_tree_id_seq TO authenticated;
