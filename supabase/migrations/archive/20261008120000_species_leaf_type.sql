-- =============================================================================
-- shared.species.leaf_type, exposed in ue_trees
-- =============================================================================
-- The Unreal surround forest (PCG_Forest) gives every forest point the mesh of
-- a random measured tree of the same leaf type, where the leaf type comes from
-- the Copernicus Dominant Leaf Type map (coniferous / broadleaved). Until now
-- the "which species are conifers" list lived as a graph parameter in Unreal.
--
-- is_deciduous cannot stand in for it: European Larch (Larix decidua) is a
-- deciduous conifer, is_deciduous = true, and the leaf-type map counts it as
-- coniferous. leaf_type is the needle / broad leaf habit, independent of
-- leaf fall.
--
-- Values are set here by scientific name, not in data/lookups/species.csv:
-- the species loaders (30-load-lookup-tables.sql, shared.refresh_lookup) upsert
-- a fixed column list that does not include leaf_type, so a reload keeps it.
-- A species added later through the CSV arrives with leaf_type NULL.
--
-- ue_trees gains leaf_type as its LAST column (CREATE OR REPLACE VIEW can only
-- append); the view body is otherwise 20261008100000_ue_trees_silva_positions.
-- Unreal: add a leaf_type String field to ST_Tree, then re-fetch
-- TreeDataCache.json and DT_Trees (Play -> SaveTwinData).
--
-- Mirrored to init 63-species-leaf-type.sql.
-- =============================================================================

ALTER TABLE shared.species
    ADD COLUMN IF NOT EXISTS leaf_type VARCHAR(20)
        CONSTRAINT species_leaf_type_check CHECK (leaf_type IN ('needleleaf', 'broadleaf'));

COMMENT ON COLUMN shared.species.leaf_type IS
    'Leaf habit: needleleaf (conifers, larch included) or broadleaf. Independent of is_deciduous. Matches the Copernicus Dominant Leaf Type classes.';

UPDATE shared.species sp
SET leaf_type = v.leaf_type
FROM (VALUES
    ('Picea abies',           'needleleaf'),
    ('Abies alba',            'needleleaf'),
    ('Pinus sylvestris',      'needleleaf'),
    ('Pseudotsuga menziesii', 'needleleaf'),
    ('Larix decidua',         'needleleaf'),
    ('Fagus sylvatica',       'broadleaf'),
    ('Quercus robur',         'broadleaf'),
    ('Acer platanoides',      'broadleaf'),
    ('Acer pseudoplatanus',   'broadleaf'),
    ('Prunus avium',          'broadleaf'),
    ('Torminalis glaberrima', 'broadleaf'),
    ('Betula pendula',        'broadleaf'),
    ('Fraxinus excelsior',    'broadleaf'),
    ('Tilia cordata',         'broadleaf')
) AS v(scientific_name, leaf_type)
WHERE sp.scientific_name = v.scientific_name;

CREATE OR REPLACE VIEW public.ue_trees AS
SELECT t.tree_id,
       t.tree_entity_id,
       t.location_id,
       l.location_name,
       s.scenario_id,
       s.scenario_name,
       t.variant_id,
       v.variant_name,
       v.simulation_year,
       vt.variant_type_name,
       sp.common_name AS species_name,
       sp.scientific_name,
       t.height_m,
       t.crown_width_m,
       t.crown_base_height_m,
       st.dbh_cm,
       t.age_years,
       t.health_score,
       COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0::numeric)) > 0.6, false) AS has_competition,
       t.sensor_ref,
       (EXISTS (SELECT 1 FROM sensor.sensor_tree_links stl WHERE stl.tree_id = t.tree_id)) AS has_sensors,
       extensions.st_x(COALESCE(t.position_original, extensions.st_transform(t."position", l.crs_epsg))) AS original_x,
       extensions.st_y(COALESCE(t.position_original, extensions.st_transform(t."position", l.crs_epsg))) AS original_y,
       COALESCE(t.source_crs, CASE WHEN t.position_original IS NULL AND t."position" IS NOT NULL THEN l.crs_epsg END) AS source_crs,
       extensions.st_y(t."position") AS latitude,
       extensions.st_x(t."position") AS longitude,
       v.sort_order,
       v.time_delta_yrs,
       v.variant_type_id,
       s.scenario_code,
       s.management_regime_id,
       mr.management_regime_name,
       s.climate_pathway_id,
       cp.climate_pathway_name,
       t.tree_status_id,
       ts.tree_status_name,
       sp.leaf_type
FROM trees.trees t
    LEFT JOIN shared.locations          l  ON t.location_id = l.location_id
    LEFT JOIN shared.variants           v  ON t.variant_id = v.variant_id
    LEFT JOIN shared.scenarios          s  ON v.scenario_id = s.scenario_id
    LEFT JOIN shared.variant_types      vt ON v.variant_type_id = vt.variant_type_id
    LEFT JOIN shared.species            sp ON t.species_id = sp.species_id
    LEFT JOIN trees.stems               st ON st.tree_id = t.tree_id AND st.stem_number = 1
    LEFT JOIN shared.management_regimes mr ON mr.management_regime_id = s.management_regime_id
    LEFT JOIN shared.climate_pathways   cp ON cp.climate_pathway_id = s.climate_pathway_id
    LEFT JOIN trees.tree_status         ts ON ts.tree_status_id = t.tree_status_id;
