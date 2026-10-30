-- =============================================================================
-- Declare each site's internal projected CRS
-- =============================================================================
-- The Digital Forest Twin Schema profile (publications/full/digital-forest-twin-
-- standard) requires a conforming deployment to declare ONE internal projected
-- CRS per site and to record it in the site definition. shared.Locations had no
-- such column: geometry is stored in EPSG:4326 (PostGIS/Supabase convention),
-- trees.trees.position_original carries the ingested frame with its own
-- source_crs, and nothing stated which projected frame per-site planimetric
-- work (engine placement, terrain, distances) is done in.
--
-- crs_epsg is that declaration. Both research sites use EPSG:32632
-- (WGS 84 / UTM zone 32N): it is the frame the surveyed tree positions arrive in
-- and the one the engine client places from. Storage stays geographic; the
-- declared CRS says which projection a consumer must transform into before
-- treating coordinates as metres.
--
-- Seeded from data/lookups/locations.csv (column CrsEpsg): a declared site
-- identity like center_point, so the CSV owns it and every reseed rewrites it
-- (XRFF-388 rule: a data fix needs both the migration and the CSV). It is not
-- an acquired attribute and has no AttributeProvenance guard.
--
-- Init ordering: the lookup loaders 30-/31- read the column, so this file must
-- run before them; 11-29 are taken, hence the letter suffix (same device as
-- 98a-realtime.sql / 99a-jwt.sql in Dockerfile.db).
-- =============================================================================

ALTER TABLE shared.Locations
    ADD COLUMN IF NOT EXISTS crs_epsg INTEGER;

-- Idempotent constraint (re)creation: ADD CONSTRAINT has no IF NOT EXISTS.
ALTER TABLE shared.Locations DROP CONSTRAINT IF EXISTS locations_crs_epsg_check;
ALTER TABLE shared.Locations
    ADD CONSTRAINT locations_crs_epsg_check
    CHECK (crs_epsg IS NULL OR (crs_epsg BETWEEN 1024 AND 32767));

COMMENT ON COLUMN shared.Locations.crs_epsg IS
    'Declared internal projected CRS of the site as an EPSG code (e.g. 32632 = '
    'WGS 84 / UTM zone 32N). The one frame in which per-site planimetric work '
    '(engine placement, terrain, distances) is done; every input in another '
    'frame is transformed on ingestion and its source frame retained on the '
    'record (trees.trees.source_crs / position_original). Geometry columns '
    'stay EPSG:4326. Seeded from data/lookups/locations.csv.';

-- public.locations is the PostgREST surface for the site definition; append the
-- column (CREATE OR REPLACE keeps grants and comment, as in 19-fix-public-
-- locations-view.sql).
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
    locations.soil_nutrient_supply,
    locations.crs_epsg
   FROM shared.locations;

COMMENT ON VIEW public.locations IS 'Public API view for locations reference table';
