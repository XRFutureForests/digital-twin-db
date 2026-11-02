-- XR Future Forests Lab — one census plot per fully mapped site (XRFF-626)
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after the
-- baseline import and after migration 20261102130000_sampling_designs:
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -1 < scripts/seed/census_site_plots.sql
--
-- What this does
-- ==============
-- Ecosense and Mathisle are fully mapped: every tree of the site is in the
-- inventory, so the site is one census and its plots are only labels. For each
-- location with a measured baseline (a root variant of type 'original') this
--
-- 1. creates the sampling design 'full_census' (strategy census, no inclusion
--    rules) once;
-- 2. creates the plot '<location>_site' in that design. Its boundary and area
--    are the convex hull of the baseline's stem positions, computed in the
--    site's projected CRS (shared.locations.crs_epsg) -- the same outline
--    silva-connector uses for stand area (R/stand.R) -- with
--    area_source = 'convex_hull';
-- 3. hangs every other plot that holds baseline trees under it
--    (parent_plot_id) and puts it in the same design. Those plots carry no area,
--    so shared.expansion_factor_ha() walks up to the site plot's area: every
--    baseline tree stands for 10000 / site area trees per hectare.
--
-- Plots without baseline trees (sensor monitoring areas) are left alone.
-- Trees with no plot_id get no expansion factor; the script reports them.
--
-- The hull is taken from the baseline only. Simulated variants keep the same
-- area, so per-hectare values of a scenario stay comparable over time.
--
-- Idempotent: the design and site plots are created once; re-running updates
-- the site plot's hull and re-attaches the plots.

SET search_path TO shared, trees, extensions, public;

INSERT INTO shared.sampling_designs (design_name, strategy, description)
VALUES ('full_census', 'census',
        'Fully mapped site: every tree of the site area is recorded. The site-wide plot carries the area; plots inside it are labels.')
ON CONFLICT (design_name) DO NOTHING;

WITH baseline AS (
    SELECT v.location_id, v.variant_id
      FROM shared.variants v
      JOIN shared.variant_types vt ON vt.variant_type_id = v.variant_type_id
     WHERE v.parent_variant_id IS NULL
       AND vt.variant_type_name = 'original'
),
hull AS (
    SELECT b.location_id,
           l.location_name,
           ST_ConvexHull(ST_Collect(ST_Transform(t.position, l.crs_epsg))) AS geom_local,
           count(*) AS n_trees
      FROM baseline b
      JOIN shared.locations l ON l.location_id = b.location_id
      JOIN trees.trees t      ON t.variant_id = b.variant_id AND t.position IS NOT NULL
     WHERE l.crs_epsg IS NOT NULL
     GROUP BY b.location_id, l.location_name
    HAVING count(*) >= 3
)
INSERT INTO shared.plots (location_id, plot_name, area_m2, boundary, center_point,
                          sampling_design_id, area_source, description)
SELECT h.location_id,
       h.location_name || '_site',
       round(ST_Area(h.geom_local)::numeric, 2),
       ST_Transform(h.geom_local, 4326),
       ST_Transform(ST_Centroid(h.geom_local), 4326),
       (SELECT sampling_design_id FROM shared.sampling_designs WHERE design_name = 'full_census'),
       'convex_hull',
       format('Whole mapped site (census). Area = convex hull of the %s baseline stem positions.', h.n_trees)
  FROM hull h
 WHERE ST_GeometryType(h.geom_local) = 'ST_Polygon'
ON CONFLICT (location_id, plot_name) DO UPDATE
   SET area_m2            = EXCLUDED.area_m2,
       boundary           = EXCLUDED.boundary,
       center_point       = EXCLUDED.center_point,
       sampling_design_id = EXCLUDED.sampling_design_id,
       area_source        = EXCLUDED.area_source,
       description        = EXCLUDED.description;

-- Attach the plots that hold baseline trees.
UPDATE shared.plots p
   SET parent_plot_id     = site.plot_id,
       sampling_design_id = site.sampling_design_id
  FROM shared.plots site
 WHERE site.location_id = p.location_id
   AND site.plot_name = (SELECT l.location_name || '_site' FROM shared.locations l WHERE l.location_id = p.location_id)
   AND p.plot_id <> site.plot_id
   AND EXISTS (
        SELECT 1
          FROM trees.trees t
          JOIN shared.variants v       ON v.variant_id = t.variant_id
          JOIN shared.variant_types vt ON vt.variant_type_id = v.variant_type_id
         WHERE t.plot_id = p.plot_id
           AND v.parent_variant_id IS NULL
           AND vt.variant_type_name = 'original');

-- Report.
SELECT l.location_name,
       site.plot_name,
       round(site.area_m2 / 10000, 3)                                        AS site_area_ha,
       (SELECT count(*) FROM shared.plots c WHERE c.parent_plot_id = site.plot_id) AS plots_attached
  FROM shared.plots site
  JOIN shared.locations l ON l.location_id = site.location_id
 WHERE site.plot_name = l.location_name || '_site'
 ORDER BY 1;

SELECT l.location_name,
       count(*) FILTER (WHERE t.plot_id IS NULL) AS baseline_trees_without_plot
  FROM trees.trees t
  JOIN shared.variants v       ON v.variant_id = t.variant_id
  JOIN shared.variant_types vt ON vt.variant_type_id = v.variant_type_id
  JOIN shared.locations l      ON l.location_id = t.location_id
 WHERE v.parent_variant_id IS NULL AND vt.variant_type_name = 'original'
 GROUP BY 1
 ORDER BY 1;
