-- =============================================================================
-- public.locations: expose the SILVA site-condition columns
-- =============================================================================
-- XRFF-373. The view was created in the 2026-07-17 baseline snapshot and lists
-- 14 columns. Migration 20260831120000 added forest_growth_region,
-- soil_moistness and soil_nutrient_supply to shared.Locations but did not
-- refresh the view, so those three columns are not reachable over PostgREST at
-- all -- neither readable nor writable by any REST client.
--
-- CREATE OR REPLACE VIEW is used rather than DROP + CREATE: appending columns
-- to the end of the select list is permitted, and it preserves the existing
-- grants to anon/authenticated/service_role and the view comment.
-- =============================================================================

CREATE OR REPLACE VIEW public.locations WITH (security_invoker='on') AS
 SELECT locations.location_id,
    locations.location_name,
    locations.boundary,
    locations.center_point,
    locations.description,
    locations.elevation_m,
    locations.slope_deg,
    locations.aspect,
    locations.soil_type_id,
    locations.climate_zone_id,
    locations.created_at,
    locations.updated_at,
    locations.created_by,
    locations.updated_by,
    locations.forest_growth_region,
    locations.soil_moistness,
    locations.soil_nutrient_supply
   FROM shared.locations;

COMMENT ON VIEW public.locations IS 'Public API view for locations reference table';
