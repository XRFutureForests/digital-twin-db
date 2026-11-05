-- =============================================================================
-- Drone orthophoto catalog, dead wood polygons, tree quality, convenience views
-- =============================================================================
-- Ports what the Shiny app (twinfrontend) still needed from the simple-postgres
-- prototype (digital-twin-feature-simple-postgres, init files 09, 11, 13, 14)
-- (plus crown geometry and the latest-state view from 04, 10 and 17). Everything
-- here is additive.
--
--   * imagery.orthophotos is a catalog, not image storage. The rasters stay
--     Cloud Optimized GeoTIFFs behind TiTiler; the browser fetches tiles from
--     tile_url directly. A new flight is one INSERT, no code change.
--   * imagery.ortho_analyses and imagery.deadwood_polygons hold segmentation
--     results per orthophoto (e.g. deadtrees.earth). Deleting an analysis
--     removes its polygons, so a re-import replaces cleanly. This is remote
--     sensing output, unlike forest_floor.deadwood, which holds pieces measured
--     on the ground.
--   * trees.trees.quality_rvr is the RVR roundwood grade. A new version of a
--     tree inherits it; the prototype matched on treeid, here the identity is
--     tree_entity_id. The prototype's dummy grades are not ported: the app
--     computes its own fallback (rvr_quality_dummy()) when the value is NULL.
--   * trees.trees.crown_poly is the crown as drawn on the map, a MultiPolygon in
--     EPSG:25832 as delivered by the ULS processing. crown_boundary is a single
--     polygon in WGS84 and cannot hold a crown in several parts. A new version
--     does not inherit it: a crown belongs to the measurement that produced it.
--   * trees.v_trees_latest shows the newest measured row of each tree, whichever
--     variant it is in (decided 2026-11-05), so a partial inventory leaves the
--     trees it did not visit on the map. The price: a tree a full inventory no
--     longer finds stays visible until a row records it. The prototype walked
--     parent links per tree; here the newest row per tree_entity_id does that
--     job. Simulated, model and XR-edited rows are not measurements. A harvested
--     tree drops out because its newest row says so, hence the status filter
--     comes after picking that row.
--   * trees.v_trees_full, trees.v_trees_geojson and shared.v_locations_overview
--     are plain joins over all variants, as in the prototype. Their column
--     names follow this database. tree_count counts trees, not rows: the
--     prototype's count of versions would grow with every variant here.
--
-- Differences from the prototype beyond naming:
--
--   * orthophotos.campaign_id and the policies that go with it. Without them a
--     restricted campaign's flight would be readable by everyone, as
--     imagery.images is not. Analyses and polygons follow their orthophoto.
--   * camera_model and ground_sample_distance_cm replace sensor and gsd_m, to
--     match imagery.images; attrs is source_attributes, as elsewhere.
--
-- Left out on purpose (decided 2026-11-05): tree_role, because planning never
-- changes a tree and crop trees live in management.thinning_trees; glb_url,
-- because nothing displays it at the moment.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS imagery.orthophotos (
    orthophoto_id             serial PRIMARY KEY,
    location_id               integer REFERENCES shared.locations (location_id) ON DELETE SET NULL,
    campaign_id               integer REFERENCES shared.campaigns (campaign_id),
    flight_date               date,
    camera_model              text,
    ground_sample_distance_cm numeric(6, 2),
    tile_url                  text NOT NULL,
    min_zoom                  integer NOT NULL DEFAULT 10,
    max_native_zoom           integer NOT NULL DEFAULT 22,
    attribution               text,
    is_active                 boolean NOT NULL DEFAULT true,
    bbox                      extensions.geometry(Polygon, 4326),
    created_at                timestamptz NOT NULL DEFAULT now(),
    updated_at                timestamptz NOT NULL DEFAULT now(),
    created_by                text,
    updated_by                text
);

COMMENT ON TABLE imagery.orthophotos IS
    'Drone orthophotos selectable as a map layer. Catalog only: the rasters are Cloud Optimized GeoTIFFs served by TiTiler.';
COMMENT ON COLUMN imagery.orthophotos.campaign_id IS 'Campaign the flight belongs to; decides who may read it, as on imagery.images';
COMMENT ON COLUMN imagery.orthophotos.flight_date IS 'Date of the flight';
COMMENT ON COLUMN imagery.orthophotos.camera_model IS 'Camera or sensor used';
COMMENT ON COLUMN imagery.orthophotos.ground_sample_distance_cm IS 'Ground sample distance in centimeters per pixel';
COMMENT ON COLUMN imagery.orthophotos.tile_url IS 'XYZ tile template with {z}/{x}/{y}; the browser requests tiles from this address directly';
COMMENT ON COLUMN imagery.orthophotos.min_zoom IS 'Lowest zoom level the layer is shown at';
COMMENT ON COLUMN imagery.orthophotos.max_native_zoom IS 'Highest zoom level the COG resolves; above it tiles are scaled up';
COMMENT ON COLUMN imagery.orthophotos.attribution IS 'Attribution shown on the map';
COMMENT ON COLUMN imagery.orthophotos.is_active IS 'Whether the flight is offered in the app';
COMMENT ON COLUMN imagery.orthophotos.bbox IS 'Extent of the image in WGS84 (EPSG:4326)';

CREATE INDEX IF NOT EXISTS idx_orthophotos_location_date ON imagery.orthophotos (location_id, flight_date DESC);
CREATE INDEX IF NOT EXISTS idx_orthophotos_campaign ON imagery.orthophotos (campaign_id);
CREATE INDEX IF NOT EXISTS idx_orthophotos_bbox ON imagery.orthophotos USING gist (bbox);

CREATE TABLE IF NOT EXISTS imagery.ortho_analyses (
    ortho_analysis_id serial PRIMARY KEY,
    orthophoto_id     integer NOT NULL REFERENCES imagery.orthophotos (orthophoto_id) ON DELETE CASCADE,
    analysis_type     text NOT NULL DEFAULT 'deadwood' CHECK (analysis_type IN ('deadwood')),
    source            text NOT NULL DEFAULT 'deadtrees.earth',
    model             text,
    run_date          date,
    source_file       text,
    source_crs        text,
    n_features        integer,
    area_ha           numeric(12, 4),
    coverage_pct      numeric(5, 2) CHECK (coverage_pct BETWEEN 0 AND 100),
    is_active         boolean NOT NULL DEFAULT true,
    notes             text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    created_by        text,
    updated_by        text
);

COMMENT ON TABLE imagery.ortho_analyses IS 'One analysis run on an orthophoto, e.g. dead wood segmentation from deadtrees.earth';
COMMENT ON COLUMN imagery.ortho_analyses.analysis_type IS 'Kind of analysis';
COMMENT ON COLUMN imagery.ortho_analyses.source IS 'Who produced the result';
COMMENT ON COLUMN imagery.ortho_analyses.model IS 'Model or method used';
COMMENT ON COLUMN imagery.ortho_analyses.run_date IS 'Date of the analysis run';
COMMENT ON COLUMN imagery.ortho_analyses.source_file IS 'File the result was imported from';
COMMENT ON COLUMN imagery.ortho_analyses.source_crs IS 'Coordinate reference system of the imported file';
COMMENT ON COLUMN imagery.ortho_analyses.n_features IS 'Number of polygons imported';
COMMENT ON COLUMN imagery.ortho_analyses.area_ha IS 'Total polygon area in hectares';
COMMENT ON COLUMN imagery.ortho_analyses.coverage_pct IS 'Share of the polygon area inside the orthophoto bbox. Below 100 the file may not belong to this image.';
COMMENT ON COLUMN imagery.ortho_analyses.is_active IS 'Whether the analysis is offered in the app';

CREATE INDEX IF NOT EXISTS idx_ortho_analyses_orthophoto
    ON imagery.ortho_analyses (orthophoto_id, analysis_type, run_date DESC);

CREATE TABLE IF NOT EXISTS imagery.deadwood_polygons (
    deadwood_polygon_id bigserial PRIMARY KEY,
    ortho_analysis_id   integer NOT NULL REFERENCES imagery.ortho_analyses (ortho_analysis_id) ON DELETE CASCADE,
    geom                extensions.geometry(MultiPolygon, 4326) NOT NULL,
    confidence          real,
    area_m2             double precision,
    source_attributes   jsonb
);

COMMENT ON TABLE imagery.deadwood_polygons IS
    'Dead wood segmented from an orthophoto. Remote sensing output; pieces measured on the ground are in forest_floor.deadwood.';
COMMENT ON COLUMN imagery.deadwood_polygons.geom IS 'Polygon in WGS84 (EPSG:4326)';
COMMENT ON COLUMN imagery.deadwood_polygons.confidence IS 'Confidence reported by the model';
COMMENT ON COLUMN imagery.deadwood_polygons.area_m2 IS 'Area in square meters, computed on import';
COMMENT ON COLUMN imagery.deadwood_polygons.source_attributes IS 'Remaining attributes of the imported file';

CREATE INDEX IF NOT EXISTS idx_deadwood_polygons_geom ON imagery.deadwood_polygons USING gist (geom);
CREATE INDEX IF NOT EXISTS idx_deadwood_polygons_analysis ON imagery.deadwood_polygons (ortho_analysis_id);


-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trigger_orthophotos_created_by ON imagery.orthophotos;
CREATE TRIGGER trigger_orthophotos_created_by BEFORE INSERT ON imagery.orthophotos
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();
DROP TRIGGER IF EXISTS trigger_orthophotos_updated_at ON imagery.orthophotos;
CREATE TRIGGER trigger_orthophotos_updated_at BEFORE UPDATE ON imagery.orthophotos
    FOR EACH ROW EXECUTE FUNCTION imagery.update_updated_at_column();
DROP TRIGGER IF EXISTS trigger_orthophotos_updated_by ON imagery.orthophotos;
CREATE TRIGGER trigger_orthophotos_updated_by BEFORE UPDATE ON imagery.orthophotos
    FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();

DROP TRIGGER IF EXISTS trigger_ortho_analyses_created_by ON imagery.ortho_analyses;
CREATE TRIGGER trigger_ortho_analyses_created_by BEFORE INSERT ON imagery.ortho_analyses
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();
DROP TRIGGER IF EXISTS trigger_ortho_analyses_updated_at ON imagery.ortho_analyses;
CREATE TRIGGER trigger_ortho_analyses_updated_at BEFORE UPDATE ON imagery.ortho_analyses
    FOR EACH ROW EXECUTE FUNCTION imagery.update_updated_at_column();
DROP TRIGGER IF EXISTS trigger_ortho_analyses_updated_by ON imagery.ortho_analyses;
CREATE TRIGGER trigger_ortho_analyses_updated_by BEFORE UPDATE ON imagery.ortho_analyses
    FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();


-- -----------------------------------------------------------------------------
-- RLS and grants: the same rules as imagery.images
-- -----------------------------------------------------------------------------

ALTER TABLE imagery.orthophotos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE imagery.ortho_analyses    ENABLE ROW LEVEL SECURITY;
ALTER TABLE imagery.deadwood_polygons ENABLE ROW LEVEL SECURITY;

DO $do$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['orthophotos', 'ortho_analyses', 'deadwood_polygons']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Everyone can read" ON imagery.%I', t);
        EXECUTE format('CREATE POLICY "Everyone can read" ON imagery.%I FOR SELECT USING (true)', t);
        EXECUTE format('DROP POLICY IF EXISTS "Contributors can create" ON imagery.%I', t);
        EXECUTE format('CREATE POLICY "Contributors can create" ON imagery.%I FOR INSERT TO authenticated '
                       'WITH CHECK (shared.is_contributor())', t);
        EXECUTE format('DROP POLICY IF EXISTS "Curators can update" ON imagery.%I', t);
        EXECUTE format('CREATE POLICY "Curators can update" ON imagery.%I FOR UPDATE TO authenticated '
                       'USING (shared.is_curator()) WITH CHECK (shared.is_curator())', t);
        EXECUTE format('DROP POLICY IF EXISTS "Curators can delete" ON imagery.%I', t);
        EXECUTE format('CREATE POLICY "Curators can delete" ON imagery.%I FOR DELETE TO authenticated '
                       'USING (shared.is_curator())', t);
        EXECUTE format('DROP POLICY IF EXISTS "Service role can manage all" ON imagery.%I', t);
        EXECUTE format('CREATE POLICY "Service role can manage all" ON imagery.%I TO service_role '
                       'USING (true) WITH CHECK (true)', t);
    END LOOP;
END
$do$;

-- Dataset access levels: the four restrictive policies imagery.images has.
DROP POLICY IF EXISTS "Dataset access level" ON imagery.orthophotos;
CREATE POLICY "Dataset access level" ON imagery.orthophotos AS RESTRICTIVE FOR SELECT
    USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.readable_campaign_ids()));
DROP POLICY IF EXISTS "Dataset owner: insert" ON imagery.orthophotos;
CREATE POLICY "Dataset owner: insert" ON imagery.orthophotos AS RESTRICTIVE FOR INSERT
    WITH CHECK (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()));
DROP POLICY IF EXISTS "Dataset owner: update" ON imagery.orthophotos;
CREATE POLICY "Dataset owner: update" ON imagery.orthophotos AS RESTRICTIVE FOR UPDATE
    USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))
    WITH CHECK (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()));
DROP POLICY IF EXISTS "Dataset owner: delete" ON imagery.orthophotos;
CREATE POLICY "Dataset owner: delete" ON imagery.orthophotos AS RESTRICTIVE FOR DELETE
    USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()));

-- Analyses and polygons have no campaign of their own: they are readable
-- exactly when their orthophoto is. The subqueries run under the caller's RLS.
DROP POLICY IF EXISTS "Dataset access level" ON imagery.ortho_analyses;
CREATE POLICY "Dataset access level" ON imagery.ortho_analyses AS RESTRICTIVE FOR SELECT
    USING (orthophoto_id IN (SELECT o.orthophoto_id FROM imagery.orthophotos o));
DROP POLICY IF EXISTS "Dataset access level" ON imagery.deadwood_polygons;
CREATE POLICY "Dataset access level" ON imagery.deadwood_polygons AS RESTRICTIVE FOR SELECT
    USING (ortho_analysis_id IN (SELECT a.ortho_analysis_id FROM imagery.ortho_analyses a));

GRANT SELECT ON TABLE imagery.orthophotos, imagery.ortho_analyses, imagery.deadwood_polygons TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE imagery.orthophotos, imagery.ortho_analyses, imagery.deadwood_polygons TO authenticated;
GRANT ALL ON TABLE imagery.orthophotos, imagery.ortho_analyses, imagery.deadwood_polygons TO service_role;
GRANT USAGE ON SEQUENCE imagery.orthophotos_orthophoto_id_seq,
                        imagery.ortho_analyses_ortho_analysis_id_seq,
                        imagery.deadwood_polygons_deadwood_polygon_id_seq TO authenticated, service_role;


-- -----------------------------------------------------------------------------
-- Tree quality
-- -----------------------------------------------------------------------------

ALTER TABLE trees.trees
    ADD COLUMN IF NOT EXISTS quality_rvr character(1);

ALTER TABLE trees.trees DROP CONSTRAINT IF EXISTS trees_quality_rvr_check;
ALTER TABLE trees.trees
    ADD CONSTRAINT trees_quality_rvr_check CHECK (quality_rvr IN ('A', 'B', 'C', 'D'));

COMMENT ON COLUMN trees.trees.quality_rvr IS
    'Roundwood grade after the RVR sorting (A, B, C, D). A new version of a tree inherits it when left empty.';

CREATE OR REPLACE FUNCTION trees.inherit_quality_rvr()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
    IF NEW.quality_rvr IS NULL AND NEW.tree_entity_id IS NOT NULL THEN
        SELECT t.quality_rvr INTO NEW.quality_rvr
          FROM trees.trees t
         WHERE t.tree_entity_id = NEW.tree_entity_id
           AND t.quality_rvr IS NOT NULL
         ORDER BY t.measurement_date DESC NULLS LAST, t.tree_id DESC
         LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION trees.inherit_quality_rvr() IS
    'Fills quality_rvr of a new tree row from the most recent version of the same tree_entity_id.';

DROP TRIGGER IF EXISTS trg_inherit_quality_rvr ON trees.trees;
CREATE TRIGGER trg_inherit_quality_rvr BEFORE INSERT ON trees.trees
    FOR EACH ROW EXECUTE FUNCTION trees.inherit_quality_rvr();


-- -----------------------------------------------------------------------------
-- Crown geometry
-- -----------------------------------------------------------------------------

ALTER TABLE trees.trees
    ADD COLUMN IF NOT EXISTS crown_poly extensions.geometry(MultiPolygon, 25832);

COMMENT ON COLUMN trees.trees.crown_poly IS
    'Crown outline for the map, possibly in several parts, in EPSG:25832. crown_boundary is the single polygon in WGS84.';


-- -----------------------------------------------------------------------------
-- Views for the app
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW imagery.v_orthophotos WITH (security_invoker = on) AS
SELECT o.orthophoto_id,
       o.location_id,
       l.location_name,
       o.flight_date,
       o.camera_model,
       o.ground_sample_distance_cm,
       o.tile_url,
       o.min_zoom,
       o.max_native_zoom,
       o.attribution,
       extensions.st_xmin(o.bbox) AS west,
       extensions.st_ymin(o.bbox) AS south,
       extensions.st_xmax(o.bbox) AS east,
       extensions.st_ymax(o.bbox) AS north
  FROM imagery.orthophotos o
  LEFT JOIN shared.locations l ON l.location_id = o.location_id
 WHERE o.is_active
 ORDER BY o.flight_date DESC NULLS LAST;

COMMENT ON VIEW imagery.v_orthophotos IS
    'Active orthophotos for the map, newest first, with the site name and the bbox as four numbers.';

CREATE OR REPLACE VIEW imagery.v_ortho_analyses WITH (security_invoker = on) AS
SELECT a.ortho_analysis_id,
       a.orthophoto_id,
       o.flight_date,
       o.location_id,
       l.location_name,
       a.analysis_type,
       a.source,
       a.model,
       a.run_date,
       a.n_features,
       a.area_ha,
       a.coverage_pct,
       a.created_at
  FROM imagery.ortho_analyses a
  JOIN imagery.orthophotos o ON o.orthophoto_id = a.orthophoto_id
  LEFT JOIN shared.locations l ON l.location_id = o.location_id
 WHERE a.is_active
 ORDER BY o.flight_date DESC NULLS LAST, a.run_date DESC NULLS LAST;

COMMENT ON VIEW imagery.v_ortho_analyses IS 'Active analyses per orthophoto, newest first.';

CREATE OR REPLACE VIEW imagery.v_deadwood WITH (security_invoker = on) AS
SELECT d.deadwood_polygon_id,
       d.ortho_analysis_id,
       a.orthophoto_id,
       o.flight_date,
       d.geom,
       d.confidence,
       d.area_m2
  FROM imagery.deadwood_polygons d
  JOIN imagery.ortho_analyses a ON a.ortho_analysis_id = d.ortho_analysis_id
  JOIN imagery.orthophotos o ON o.orthophoto_id = a.orthophoto_id
 WHERE a.is_active;

COMMENT ON VIEW imagery.v_deadwood IS 'Dead wood polygons of active analyses, with their orthophoto.';

CREATE OR REPLACE VIEW trees.v_trees_full WITH (security_invoker = on) AS
SELECT t.tree_id,
       t.tree_entity_id,
       t.variant_id,
       sp.common_name,
       sp.scientific_name,
       ts.tree_status_name,
       t.height_m,
       s.dbh_cm,
       t."position",
       extensions.st_x(t."position") AS longitude,
       extensions.st_y(t."position") AS latitude,
       l.location_name,
       t.field_notes,
       t.created_by,
       t.created_at
  FROM trees.trees t
  LEFT JOIN shared.species sp ON sp.species_id = t.species_id
  LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
  LEFT JOIN shared.locations l ON l.location_id = t.location_id
  LEFT JOIN trees.stems s ON s.tree_id = t.tree_id AND s.stem_number = 1;

COMMENT ON VIEW trees.v_trees_full IS
    'Every tree row of every variant with species, status, site and main stem.';

CREATE OR REPLACE VIEW trees.v_trees_geojson WITH (security_invoker = on) AS
SELECT t.tree_id,
       t.tree_entity_id,
       t.variant_id,
       sp.common_name,
       t.height_m,
       s.dbh_cm,
       ts.tree_status_name,
       l.location_name,
       extensions.st_asgeojson(t."position")::jsonb AS geometry
  FROM trees.trees t
  LEFT JOIN shared.species sp ON sp.species_id = t.species_id
  LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
  LEFT JOIN shared.locations l ON l.location_id = t.location_id
  LEFT JOIN trees.stems s ON s.tree_id = t.tree_id AND s.stem_number = 1;

COMMENT ON VIEW trees.v_trees_geojson IS
    'Every tree row of every variant, position as GeoJSON, for export.';

CREATE OR REPLACE VIEW trees.v_trees_latest WITH (security_invoker = on) AS
WITH newest AS (
    SELECT DISTINCT ON (COALESCE(t.tree_entity_id::text, t.tree_id::text))
           t.tree_id
      FROM trees.trees t
      JOIN shared.variant_types vt ON vt.variant_type_id = t.variant_type_id
      LEFT JOIN shared.variants v ON v.variant_id = t.variant_id
     WHERE vt.variant_type_name NOT IN ('simulated_growth', 'model_output', 'user_input')
     ORDER BY COALESCE(t.tree_entity_id::text, t.tree_id::text),
              t.measurement_date DESC NULLS LAST,
              v.sort_order DESC NULLS LAST,
              t.tree_id DESC
)
SELECT t.tree_id,
       t.tree_entity_id,
       t.variant_id,
       t.measurement_date,
       sp.scientific_name,
       t.species_id,
       s.dbh_cm,
       extensions.st_x(t."position") AS longitude,
       extensions.st_y(t."position") AS latitude,
       t.location_id,
       l.location_name,
       t.height_m,
       t.tree_status_id,
       t.quality_rvr
  FROM newest n
  JOIN trees.trees t ON t.tree_id = n.tree_id
  LEFT JOIN shared.species sp ON sp.species_id = t.species_id
  LEFT JOIN shared.locations l ON l.location_id = t.location_id
  LEFT JOIN trees.stems s ON s.tree_id = t.tree_id AND s.stem_number = 1
  LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
 WHERE ts.tree_status_name IS DISTINCT FROM 'harvested';

COMMENT ON VIEW trees.v_trees_latest IS
    'Current state: the newest measured row of each tree across all variants, without harvested trees. Simulated, model and XR-edited rows do not count as measured.';

CREATE OR REPLACE VIEW shared.v_locations_overview WITH (security_invoker = on) AS
SELECT l.location_id,
       l.location_name,
       l.description,
       l.elevation_m,
       st.soil_type_name,
       cz.climate_zone_name,
       (SELECT count(DISTINCT t.tree_entity_id) + count(*) FILTER (WHERE t.tree_entity_id IS NULL)
          FROM trees.trees t
         WHERE t.location_id = l.location_id) AS tree_count,
       (SELECT count(*)
          FROM sensor.sensors s
         WHERE s.location_id = l.location_id) AS sensor_count,
       extensions.st_asgeojson(l.center_point)::jsonb AS center_geojson
  FROM shared.locations l
  LEFT JOIN shared.soil_types st ON st.soil_type_id = l.soil_type_id
  LEFT JOIN shared.climate_zones cz ON cz.climate_zone_id = l.climate_zone_id;

COMMENT ON VIEW shared.v_locations_overview IS
    'Sites with soil, climate and counts. tree_count counts trees (tree_entity_id), not their versions; a row without an entity counts as one tree.';

GRANT SELECT ON imagery.v_orthophotos, imagery.v_ortho_analyses, imagery.v_deadwood,
                trees.v_trees_full, trees.v_trees_geojson, trees.v_trees_latest,
                shared.v_locations_overview
    TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- PostgREST surface. Single-table views are auto-updatable; RLS on the base
-- table decides.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.orthophotos WITH (security_invoker = on) AS
SELECT orthophoto_id, location_id, campaign_id, flight_date, camera_model,
       ground_sample_distance_cm, tile_url, min_zoom, max_native_zoom, attribution,
       is_active, bbox, created_at, updated_at, created_by, updated_by
  FROM imagery.orthophotos;

CREATE OR REPLACE VIEW public.ortho_analyses WITH (security_invoker = on) AS
SELECT ortho_analysis_id, orthophoto_id, analysis_type, source, model, run_date,
       source_file, source_crs, n_features, area_ha, coverage_pct, is_active, notes,
       created_at, updated_at, created_by, updated_by
  FROM imagery.ortho_analyses;

CREATE OR REPLACE VIEW public.deadwood_polygons WITH (security_invoker = on) AS
SELECT deadwood_polygon_id, ortho_analysis_id, geom, confidence, area_m2, source_attributes
  FROM imagery.deadwood_polygons;

COMMENT ON VIEW public.orthophotos IS 'Drone orthophoto catalog (imagery.orthophotos).';
COMMENT ON VIEW public.ortho_analyses IS 'Analysis runs on orthophotos (imagery.ortho_analyses).';
COMMENT ON VIEW public.deadwood_polygons IS 'Dead wood segmented from orthophotos (imagery.deadwood_polygons).';
