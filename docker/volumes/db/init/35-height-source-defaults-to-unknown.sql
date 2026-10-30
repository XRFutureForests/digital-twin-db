-- Mirrored from supabase/migrations/20260903150000_height_source_defaults_to_unknown.sql.
-- Fresh builds get the default drop, the comment and the two trigger functions
-- here; existing databases get them from the migration. Keep the two identical.
-- =============================================================================
-- An unstamped write must not claim a field measurement
-- =============================================================================
-- XRFF-400. `trees.Trees.height_source` defaulted to 'measured'. Any writer that
-- omitted the column silently manufactured a field measurement that never
-- happened -- and unlike a NULL, that claim is indistinguishable from a real one
-- once it is in the table.
--
-- The audit behind this migration found the trap is worse than "a writer might
-- forget". Two of the five write paths set the column correctly:
--
--   silva-connector/R/writeback.R          sets 'simulated_silva', with a comment
--                                          explaining that it is working around
--                                          this very default
--   scripts/import/fill_missing_heights.py sets 'allometric_pylometree'
--
-- and three cannot set it at all:
--
--   public.trees_insert()                  height_source absent from the INSERT
--   public.trees_update()                  height_source absent from the SET
--   scripts/import/import_trees.py         height_source absent from the INSERT
--
-- `public.trees` *selects* height_source, so the column is readable over
-- PostgREST but has never been writable through it. Every insert through the
-- view took the default. Dropping the default without fixing the two trigger
-- functions would therefore make the view path strictly worse: it would write
-- NULL forever with no way to correct it. Both halves have to land together,
-- which is why this migration touches the triggers as well as the default.
--
-- No repair is needed. All 11,125 rows in the reference database are already
-- consistent -- 1,198 measured/field, 1,027 allometric_pylometree/estimated,
-- 8,900 simulated_silva/simulated, every one with a process_id. The 'measured'
-- rows came from the default via import_trees.py and happen to be true, because
-- that importer's input was field campaign data. They are correct by luck, not
-- by construction, and that is exactly the property this migration removes.
--
-- height_source stays a column on trees.Trees rather than moving to
-- shared.AttributeProvenance (20260902140000), which is keyed on location_id and
-- does not reach trees without a schema change of its own. Whether per-tree
-- derived values should carry provenance the same way site attributes now do is
-- a real question, but it belongs to the uncertainty-convention decision in
-- XRFF-401, alongside volume, crown, age, biomass and carbon -- not to a
-- one-column default fix.
--
-- No CHECK constraint on the vocabulary: a new writer with a new legitimate
-- source should not need a migration to record it. The comment below is the
-- register.
--
-- Mirrored to init 35-height-source-defaults-to-unknown.sql.
-- =============================================================================

SET search_path TO trees, public;


-- 1. An omitted height_source is now visibly unknown rather than invisibly false.
ALTER TABLE trees.trees ALTER COLUMN height_source DROP DEFAULT;

COMMENT ON COLUMN trees.trees.height_source IS
    'How height_m was arrived at. NULL means unrecorded -- it is not a claim '
    'that the height was measured. Values in use: ''measured'' (field '
    'instrument), ''allometric_pylometree'' (H-D model fill, see '
    'scripts/import/fill_missing_heights.py), ''simulated_silva'' (SILVA '
    'projection, see silva-connector). Pair with data_source_type_id, which '
    'records how the tree record as a whole was produced, and process_id, which '
    'identifies the run.';


-- 2. Make the column writable through public.trees. Both function bodies are the
--    live definitions with height_source added and nothing else changed.
CREATE OR REPLACE FUNCTION public.trees_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO trees.trees (
        tree_entity_id, variant_id, parent_tree_id, point_cloud_id, campaign_id,
        location_id, plot_id, scenario_id, variant_type_id, process_id,
        species_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
        measurement_date, data_source_type_id,
        height_m, height_source, crown_width_m, crown_base_height_m, crown_boundary,
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
        NEW.height_m, NEW.height_source, NEW.crown_width_m, NEW.crown_base_height_m, NEW.crown_boundary,
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
$$;

COMMENT ON FUNCTION public.trees_insert() IS 'INSTEAD OF INSERT trigger function for public.trees view';


CREATE OR REPLACE FUNCTION public.trees_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
        height_source = NEW.height_source,
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
$$;

COMMENT ON FUNCTION public.trees_update() IS 'INSTEAD OF UPDATE trigger function for public.trees view';
