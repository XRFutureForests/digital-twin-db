-- =============================================================================
-- public.growth_simulations: stop renaming stand_biomass_tha to standbio_tha
-- =============================================================================
-- XRFF-485 (partial). Found by the naming-convention audit (XRFF-484).
--
-- The view aliased `gs.stand_biomass_tha AS standbio_tha` while passing its
-- three siblings through unrenamed:
--
--   stand_basal_area_m2ha   stand_volume_m3ha   stand_stem_count_ha
--
-- so one of the four stand aggregates arrived at clients under an abbreviated
-- name that exists nowhere else in the database. The alias carried no meaning --
-- the base column is `trees.growthsimulations.stand_biomass_tha` and is well
-- within the 63-character identifier limit.
--
-- Consumer grep (AGENTS.md): `standbio_tha` appears nowhere outside this repo's
-- own DDL -- not in digital-twin-dashboard, silva-connector, open-data-connector
-- or any of the four Unreal projects. silva-connector writes the base column and
-- never reads this view.
--
-- This migration deliberately fixes only this one column. The other five view
-- columns in XRFF-485 (linked_tree_scientificname, sensor_label, sensor_type,
-- management_regime, climate_pathway) are cached verbatim into UE DataTable JSON
-- and cannot be renamed without a matching change to the row structs, which the
-- external UE developer owns.
--
-- Mirrored to init 47-growth-simulations-stand-biomass-name.sql.
-- =============================================================================

SET search_path TO public;


-- CREATE OR REPLACE VIEW cannot rename an output column, so the view is dropped
-- and recreated. Grants and comment are restored to what it carried before.
DROP VIEW IF EXISTS public.growth_simulations;

CREATE VIEW public.growth_simulations AS
 SELECT gs.growth_simulation_id,
    gs.run_id,
    gs.tree_entity_id,
    gs.base_tree_id,
    gs.location_id,
    gs.plot_id,
    gs.scenario_id,
    s.scenario_name,
    sp.common_name AS species_name,
    sp.scientific_name,
    gs.simulator_name,
    gs.simulator_version,
    gs.projection_year,
    gs.time_delta_yrs,
    gs.height_m,
    gs.dbh_cm,
    gs.basal_area_m2,
    gs.crown_width_m,
    gs.crown_base_height_m,
    gs.volume_m3,
    gs.biomass_kg,
    gs.carbon_content_kg,
    gs.health_score,
    gs.mortality,
    gs.stand_basal_area_m2ha,
    gs.stand_volume_m3ha,
    gs.stand_biomass_tha,
    gs.stand_stem_count_ha,
    gs.created_at,
    gs.created_by
   FROM trees.growthsimulations gs
     LEFT JOIN shared.scenarios s ON gs.scenario_id = s.scenario_id
     LEFT JOIN shared.species sp ON gs.species_id = sp.species_id;

-- Recreating a view resets its owner to whoever runs the migration; every other
-- public view is owned by supabase_admin, so pin it rather than inherit it.
ALTER VIEW public.growth_simulations OWNER TO supabase_admin;

COMMENT ON VIEW public.growth_simulations IS
    'Flat view of growth simulation projections with scenario and species names '
    'resolved. Filter by scenario_name + projection_year to get a full forest '
    'state for UE Time Machine.';

-- GRANT ALL to the same four roles the baseline grants to. `postgres` is not
-- redundant here: the view is owned by supabase_admin, so postgres holds no
-- implicit privilege on it, and every other public view grants it explicitly.
GRANT ALL ON TABLE public.growth_simulations TO postgres, anon, authenticated, service_role;
