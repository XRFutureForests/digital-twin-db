-- =============================================================================
-- ecosense center_point was 30.7 km from its own trees
-- =============================================================================
-- XRFF-388. shared.Locations.center_point for ecosense held 47.9921, 7.8732 --
-- a point in the Rhine plain north-west of Freiburg. Every one of the site's
-- 1,504 surveyed trees sits in a 158 x 255 m box around 48.2681, 7.8780, some
-- 30.7 km to the north. mathisle's centre is correct (45 m from its own tree
-- centroid) and is left alone.
--
-- The corrected value is the centroid of the 1,504 tree positions in
-- data/ecosense_250911.csv (columns x_32632 / y_32632, EPSG:32632, transformed
-- to EPSG:4326), not a value read off a map:
--
--     UTM32 E 416742.1  N 5346711.1  ->  lat 48.268132  lon 7.878040
--
-- This is not cosmetic. center_point is the sampling point for every open-data
-- source in XRFF-370, and sampling 30 km away produces plausible-looking wrong
-- values rather than an obvious failure:
--
--                        elevation   slope   aspect   Wuchsbezirk
--   old center_point       294.0 m    2.2      SW     99.73.11
--   true tree centroid     477.1 m    3.9      NW     99.73.04
--   what this table holds  445.0 m   10.0      NW     99.73.04
--
-- The row's own aspect and forest_growth_region already agree with the trees,
-- not with the old centre -- so the coordinate was the wrong value, and the
-- attributes derived from the real site were right. The Thuenen layer returns
-- 99.73.11 for the old point and 99.73.04 for the true one, which is how the
-- error was found.
--
-- data/lookups/locations.csv is corrected in the same commit. That file is the
-- seed of record -- 30-load-lookup-tables.sql rebuilds center_point from it
-- with an ON CONFLICT UPDATE -- so without that change a rebuild would
-- reintroduce the wrong point.
--
-- DELIBERATELY NOT CHANGED HERE: Elevation_m (445.0) and Slope_deg (10.0).
-- Three independent sources now put the site nearer 471-477 m: the EU-DTM
-- reads 477.1 m at the corrected centre, and the survey's own `elevation`
-- column (mean 520.6 m) is ellipsoidal height -- EGM2008 puts the geoid
-- undulation there at +49.3 m, giving 471.3 m orthometric, which agrees with
-- the DEM to within 6 m. So 445.0 is probably ~30 m low. It is left in place
-- because writing a corrected elevation is XRFF-370's job and must arrive with
-- a shared.AttributeProvenance row naming the DEM, its resolution and its
-- licence. Replacing one unattributed number with another is what this epic
-- exists to stop.
--
-- Idempotent: safe to re-run.
-- =============================================================================

UPDATE shared.Locations
   SET center_point = extensions.ST_SetSRID(
                          extensions.ST_MakePoint(7.878040, 48.268132), 4326),
       updated_at   = NOW()
 WHERE location_name = 'ecosense'
   AND (center_point IS NULL
        OR extensions.ST_DistanceSphere(
               center_point,
               extensions.ST_SetSRID(
                   extensions.ST_MakePoint(7.878040, 48.268132), 4326)) > 1.0);


-- =============================================================================
-- Report: how far is each location's centre from its own trees?
-- =============================================================================
-- The check that would have caught this, and the one XRFF-388 asks for. Uses
-- the measured variant only -- trees.Trees also holds SILVA projections, which
-- repeat each tree's position and would weight the centroid.
-- =============================================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT l.location_name,
               extensions.ST_DistanceSphere(
                   l.center_point,
                   extensions.ST_Centroid(extensions.ST_Collect(t.position))) AS metres,
               count(*) AS n_trees
          FROM shared.Locations l
          JOIN trees.Trees t ON t.location_id = l.location_id
         WHERE t.position IS NOT NULL
           AND NOT extensions.ST_IsEmpty(t.position)
           AND t.variant_type_id = 1          -- original / measured
         GROUP BY l.location_name, l.center_point
         ORDER BY l.location_name
    LOOP
        IF r.metres > 500 THEN
            RAISE WARNING 'XRFF-388: % centre is % m from its own % trees',
                r.location_name, round(r.metres::numeric, 0), r.n_trees;
        ELSE
            RAISE NOTICE 'XRFF-388: % centre is % m from its own % trees -- ok',
                r.location_name, round(r.metres::numeric, 0), r.n_trees;
        END IF;
    END LOOP;
END $$;
