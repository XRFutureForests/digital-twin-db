-- =============================================================================
-- ue_trees: projected coordinates for every variant, not only the measured one
-- =============================================================================
-- The SILVA variants (silva_2030 ... silva_2075) are written with `position`
-- (WGS84) but without `position_original` / `source_crs`, so ue_trees returned
-- NULL original_x / original_y / source_crs for 10 of the 11 ECOSENSE variants.
-- Unreal places trees from original_x / original_y (BP_ApiTreeDataTable runs
-- them through ProjectedToEngine), so every simulated tree landed at UTM (0,0)
-- and the year picker had nothing to show.
--
-- Fix in the view, not in Unreal: fall back to `position` transformed into the
-- location's CRS, and report that CRS as source_crs. For the SILVA rows this
-- reproduces the baseline UTM position of the same tree_entity_id to < 1e-8 m
-- (checked on dev 2026-10-08, 14,950 rows). Rows that have position_original
-- are unchanged.
--
-- Same columns, names, types and order: no Unreal struct change. Consumers
-- re-fetch: TreeDataCache.json, then DT_Trees (Play -> SaveTwinData).
--
-- Mirror of supabase/migrations/20261008100000_ue_trees_silva_positions.sql.
-- =============================================================================

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
       ts.tree_status_name
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
