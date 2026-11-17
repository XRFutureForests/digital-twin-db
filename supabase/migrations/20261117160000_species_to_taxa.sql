-- =============================================================================
-- shared.species -> shared.taxa, species_id -> taxon_id (XRFF-690)
-- =============================================================================
-- The species table becomes a taxa table: a row may be a species, a genus, a
-- family or a morphospecies, for biodiversity data beyond trees. Rank and
-- higher taxonomy (GBIF backbone) are added; the tree trait columns stay and
-- are NULL for non-trees. forest_floor.ground_vegetation gets a taxon link
-- beside its free-text name.
--
-- Base tables, foreign keys, constraints, indexes, the sequence and the
-- policies are renamed. The public API views keep their output column names
-- (species_id, species_name): Postgres follows a renamed base column inside a
-- view without renaming the view's column, so Unreal and the other API
-- clients see no change. Their rename follows with the Unreal fetchers
-- (follow-up issue). The insert/update functions behind the writable views
-- write to the renamed base columns.
--
-- Lookup: data/lookups/species.csv is now taxa.csv, with seven new columns;
-- registry key 'species' becomes 'taxa'.
-- =============================================================================

ALTER TABLE shared.species RENAME TO taxa;
ALTER TABLE shared.taxa RENAME COLUMN species_id TO taxon_id;
ALTER SEQUENCE shared.species_species_id_seq RENAME TO taxa_taxon_id_seq;
ALTER TABLE shared.taxa RENAME CONSTRAINT species_pkey TO taxa_pkey;
ALTER TABLE shared.taxa RENAME CONSTRAINT species_scientific_name_key TO taxa_scientific_name_key;
ALTER TABLE shared.taxa RENAME CONSTRAINT species_growth_rate_check TO taxa_growth_rate_check;
ALTER TABLE shared.taxa RENAME CONSTRAINT species_leaf_type_check TO taxa_leaf_type_check;
ALTER TABLE shared.taxa RENAME CONSTRAINT species_shade_tolerance_check TO taxa_shade_tolerance_check;
ALTER INDEX shared.idx_species_common_name RENAME TO idx_taxa_common_name;
ALTER INDEX shared.idx_species_growth_rate RENAME TO idx_taxa_growth_rate;
ALTER INDEX shared.idx_species_scientific_name RENAME TO idx_taxa_scientific_name;
ALTER INDEX shared.idx_species_shade_tolerance RENAME TO idx_taxa_shade_tolerance;
ALTER POLICY "Species are viewable by everyone" ON shared.taxa RENAME TO "Taxa are viewable by everyone";
ALTER POLICY "Contributors can manage species" ON shared.taxa RENAME TO "Contributors can manage taxa";

ALTER TABLE shared.taxa
    ADD COLUMN taxon_rank  varchar(20),
    ADD COLUMN kingdom     varchar(60),
    ADD COLUMN phylum      varchar(60),
    ADD COLUMN class_name  varchar(60),
    ADD COLUMN order_name  varchar(60),
    ADD COLUMN family      varchar(60),
    ADD COLUMN genus       varchar(60);

COMMENT ON TABLE shared.taxa IS 'Taxa: tree species and any other organism the twin records (species, genus, family or morphospecies), linked to the GBIF backbone. The tree trait columns (max height, max DBH, lifespan, growth rate, shade tolerance, deciduousness, leaf type) apply to trees and are NULL otherwise. Loaded from data/lookups/taxa.csv.';
COMMENT ON COLUMN shared.taxa.taxon_rank IS 'Rank of the taxon as in the GBIF backbone (species, genus, family, ...).';
COMMENT ON COLUMN shared.taxa.kingdom IS 'Kingdom (GBIF backbone).';
COMMENT ON COLUMN shared.taxa.phylum IS 'Phylum (GBIF backbone).';
COMMENT ON COLUMN shared.taxa.class_name IS 'Class (GBIF backbone); named class_name because class is an SQL keyword in many clients.';
COMMENT ON COLUMN shared.taxa.order_name IS 'Order (GBIF backbone); named order_name because order is an SQL keyword.';
COMMENT ON COLUMN shared.taxa.family IS 'Family (GBIF backbone).';
COMMENT ON COLUMN shared.taxa.genus IS 'Genus (GBIF backbone).';

-- Foreign keys: species_id -> taxon_id
ALTER TABLE trees.trees RENAME COLUMN species_id TO taxon_id;
ALTER TABLE trees.trees RENAME CONSTRAINT trees_species_id_fkey TO trees_taxon_id_fkey;
ALTER INDEX trees.idx_trees_species RENAME TO idx_trees_taxon;
ALTER TABLE trees.observations RENAME COLUMN species_id TO taxon_id;
ALTER TABLE trees.observations RENAME CONSTRAINT observations_species_id_fkey TO observations_taxon_id_fkey;
ALTER TABLE trees.growth_simulations RENAME COLUMN species_id TO taxon_id;
ALTER TABLE trees.growth_simulations RENAME CONSTRAINT growth_simulations_species_id_fkey TO growth_simulations_taxon_id_fkey;
ALTER TABLE forest_floor.deadwood RENAME COLUMN species_id TO taxon_id;
ALTER TABLE forest_floor.deadwood RENAME CONSTRAINT deadwood_species_id_fkey TO deadwood_taxon_id_fkey;
ALTER INDEX forest_floor.idx_deadwood_species RENAME TO idx_deadwood_taxon;
ALTER TABLE forest_floor.regeneration RENAME COLUMN species_id TO taxon_id;
ALTER TABLE forest_floor.regeneration RENAME CONSTRAINT regeneration_species_id_fkey TO regeneration_taxon_id_fkey;

-- Ground vegetation: a taxon link beside the name as recorded.
ALTER TABLE forest_floor.ground_vegetation
    ADD COLUMN taxon_id integer REFERENCES shared.taxa (taxon_id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_ground_vegetation_taxon ON forest_floor.ground_vegetation (taxon_id);
UPDATE forest_floor.ground_vegetation g SET taxon_id = t.taxon_id
  FROM shared.taxa t WHERE t.scientific_name = g.species_name AND g.taxon_id IS NULL;
COMMENT ON COLUMN forest_floor.ground_vegetation.taxon_id IS 'Taxon of the record, resolved from species_name on insert; NULL when the name is not in shared.taxa.';
COMMENT ON COLUMN forest_floor.ground_vegetation.species_name IS 'Name as recorded. taxon_id holds the resolved taxon.';

-- Writable API views: their functions write to the renamed base columns.
CREATE OR REPLACE FUNCTION public.deadwood_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO forest_floor.deadwood (
        location_id, plot_id, tree_id, taxon_id,
        wood_type, length_m, diameter_cm, decay_class,
        volume_m3, position, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.tree_id, NEW.species_id,
        NEW.wood_type, NEW.length_m, NEW.diameter_cm, NEW.decay_class,
        NEW.volume_m3, NEW.position, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING deadwood_id INTO NEW.deadwood_id;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trees_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO trees.trees (
        tree_entity_id, variant_id, parent_tree_id, point_cloud_id, campaign_id,
        location_id, plot_id, scenario_id, variant_type_id, process_id,
        taxon_id, tree_status_id, branching_pattern_id, bark_characteristic_id,
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
$function$;

CREATE OR REPLACE FUNCTION public.trees_update()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
        taxon_id = NEW.species_id,
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
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ground_vegetation_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO forest_floor.ground_vegetation (
        location_id, plot_id, species_name, taxon_id, cover_percent,
        height_cm, layer, measurement_date, notes, created_by
    ) VALUES (
        NEW.location_id, NEW.plot_id, NEW.species_name,
        (SELECT t.taxon_id FROM shared.taxa t WHERE t.scientific_name = NEW.species_name),
        NEW.cover_percent, NEW.height_cm, NEW.layer, NEW.measurement_date, NEW.notes, NEW.created_by
    ) RETURNING ground_vegetation_id INTO NEW.ground_vegetation_id;
    RETURN NEW;
END;
$function$;

-- Lookup registry and refresh list: key 'species' -> 'taxa', seven new CSV columns.
UPDATE shared.lookup_registry
   SET logical_key = 'taxa', table_name = 'taxa', csv_file = 'taxa.csv',
       csv_columns = ARRAY['common_name', 'scientific_name', 'max_height_m', 'max_dbh_cm', 'typical_lifespan_years',
                           'growth_rate', 'shade_tolerance', 'is_deciduous', 'gbif_key', 'gbif_accepted_name', 'leaf_type',
                           'taxon_rank', 'kingdom', 'phylum', 'class_name', 'order_name', 'family', 'genus'],
       description = 'Taxa with GBIF backbone rank and higher taxonomy; tree traits for trees'
 WHERE logical_key = 'species';

CREATE OR REPLACE FUNCTION shared.refresh_all_lookups() RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Refresh in dependency order
    RETURN QUERY SELECT * FROM shared.refresh_lookup('soil_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('climate_zones');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('variant_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('scenarios');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('taxa');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('locations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('sensor_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('tree_status');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('taper_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('straightness_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branching_patterns');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('bark_characteristics');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('datasource_types');
    -- Tree Morphology tables (from tree_anatomy.pdf)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('height_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_architectures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branch_elongation_habits');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_orientations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('shoot_elongation_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_shapes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('geometric_crown_solids');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('axis_structures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_forms');
    -- Tree Condition tables (FIA/NEON/ICP Forests-aligned)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('damage_agents');
    -- Tree-related microhabitats (XRFF-692): types before the codes that map to them
    RETURN QUERY SELECT * FROM shared.refresh_lookup('microhabitat_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('microhabitat_source_codes');
END;
$$;

NOTIFY pgrst, 'reload schema';
