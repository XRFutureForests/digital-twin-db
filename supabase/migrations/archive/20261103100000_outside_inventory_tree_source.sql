-- =============================================================================
-- Outside inventories: the producer's tree id and protocol codes on trees;
-- ground-based laser scans as a campaign type
-- =============================================================================
-- XRFF-639. The first outside inventories (Pathfinder superplots, later the
-- 3Dtrees.earth platform) bring two things trees.trees cannot hold:
--
--   source_tree_id     the producer's own tree identifier. Pathfinder's is
--                      text, so tree_number (integer) cannot carry it. Unique
--                      per campaign and variant, so a re-import or a push of
--                      the same inventory updates instead of duplicating.
--   source_attributes  protocol codes that have no column of their own, keyed
--                      by the source's column names: Pathfinder canopy_layer
--                      and rs_visibility, NSW crown condition codes, the raw
--                      species name as delivered. A code is promoted to a
--                      column once a second source shares it.
--
-- campaign_type gains laser_scan for ground-based terrestrial and mobile
-- scans (TLS, MLS); lidar_flight and drone_survey keep their meaning.
--
-- Additive only. Plan: knowledge hub 03-DATA-TIER/3dtrees-db-adjustment-plan.
-- Mirrored to init 80-outside-inventory-tree-source.sql.
-- =============================================================================

ALTER TABLE trees.trees
    ADD COLUMN IF NOT EXISTS source_tree_id text,
    ADD COLUMN IF NOT EXISTS source_attributes jsonb;

COMMENT ON COLUMN trees.trees.source_tree_id IS
    'The producer''s own identifier of this tree (e.g. Pathfinder tree_id, a 3Dtrees.earth instance id). Unique per campaign and variant, so re-importing or re-pushing the same inventory is idempotent. Requires campaign_id.';
COMMENT ON COLUMN trees.trees.source_attributes IS
    'Protocol-specific codes without a column of their own, as a JSON object keyed by the source''s column names (e.g. {"canopy_layer": "1", "rs_visibility": "2", "species_raw": "Larix_europaea"}). The protocol is the plot''s sampling design. A code becomes a column once a second source shares it.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'trees.trees'::regclass
                      AND conname = 'trees_source_tree_id_needs_campaign_check') THEN
        ALTER TABLE trees.trees ADD CONSTRAINT trees_source_tree_id_needs_campaign_check
            CHECK (source_tree_id IS NULL OR campaign_id IS NOT NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'trees.trees'::regclass
                      AND conname = 'trees_source_attributes_object_check') THEN
        ALTER TABLE trees.trees ADD CONSTRAINT trees_source_attributes_object_check
            CHECK (source_attributes IS NULL OR jsonb_typeof(source_attributes) = 'object');
    END IF;
END;
$$;

-- NULLS NOT DISTINCT: a tree imported before its baseline variant is assigned
-- (variant_id NULL) must still collide with a second import of the same id.
CREATE UNIQUE INDEX IF NOT EXISTS trees_campaign_variant_source_tree_id_key
    ON trees.trees (campaign_id, variant_id, source_tree_id) NULLS NOT DISTINCT
    WHERE source_tree_id IS NOT NULL;


-- Ground-based laser scans as a campaign type.
ALTER TABLE shared.campaigns DROP CONSTRAINT IF EXISTS campaigns_campaign_type_check;
ALTER TABLE shared.campaigns ADD CONSTRAINT campaigns_campaign_type_check
    CHECK (campaign_type::text = ANY (ARRAY['lidar_flight', 'field_inventory', 'sensor_deployment',
                                            'drone_survey', 'manual_update', 'laser_scan']));

COMMENT ON COLUMN shared.campaigns.campaign_type IS
    'Type of data collection campaign: field_inventory, lidar_flight (airborne laser scanning), drone_survey (UAV, incl. ULS), laser_scan (ground-based TLS or MLS), sensor_deployment, manual_update.';


-- The public view gains both columns, appended so existing column positions hold.
CREATE OR REPLACE VIEW public.trees WITH (security_invoker = on) AS
SELECT tree_id, tree_entity_id, variant_id, parent_tree_id, point_cloud_id, campaign_id,
       location_id, plot_id, scenario_id, variant_type_id, process_id, species_id,
       tree_status_id, branching_pattern_id, bark_characteristic_id, measurement_date,
       data_source_type_id, height_m, height_source, crown_width_m, crown_base_height_m,
       crown_boundary, crown_offset_x_m, crown_offset_y_m, volume_m3, "position",
       position_original, source_crs, lean_angle_deg, lean_direction_azimuth, time_delta_yrs,
       age_years, health_score, biomass_kg, carbon_content_kg, species_confidence,
       position_confidence, height_confidence, status_change_date, tree_number, field_notes,
       created_at, updated_at, created_by, updated_by, height_class_id, crown_architecture_id,
       elongation_habit_id, growth_orientation_id, shoot_elongation_type_id, crown_shape_id,
       geometric_crown_solid_id, axis_structure_id, growth_form_id, live_crown_ratio,
       crown_class_id, damage_agent_id, defoliation_percent, discolouration_percent,
       crown_transparency_percent,
       source_tree_id, source_attributes
  FROM trees.trees;

NOTIFY pgrst, 'reload schema';
