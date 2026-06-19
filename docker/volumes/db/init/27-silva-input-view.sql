-- XR Future Forests Lab — SILVA Coupling: Input View
-- XRFF-244: exposes current inventory as SILVA-compatible single-tree input format
-- Dependencies: 13-trees-schema.sql, 24-public-api-views.sql
--
-- ⚠ DRAFT — column names and SILVA species codes are based on the standard
--   SILVA 4.5 specification (Pretzsch et al.). Verify against the Uni Freiburg
--   colleagues' running R/Postgres SILVA implementation before relying on this view.
--   Known unknowns: exact column aliases, site index derivation, coordinate system
--   expectation (UTM 32N assumed here), any custom species codes used in-house.

SET search_path TO trees, shared, public;

-- =============================================================================
-- SILVA SPECIES CODE MAPPING
-- =============================================================================
-- Standard German NFI / SILVA Baumart (ba) codes
-- Source: Pretzsch et al. (2002) SILVA 2.2 manual + BWI3 species list
-- Note: Acer platanoides (Norway Maple) reuses code 24 — verify with colleagues
--
-- ba | Species
-- ---+-----------------------------------------------
--  1 | Picea abies          (Norway Spruce / Fichte)
--  2 | Abies alba           (Silver Fir / Weißtanne)
--  3 | Pinus sylvestris     (Scots Pine / Kiefer)
--  4 | Pseudotsuga menziesii(Douglas Fir / Douglasie)
--  5 | Larix decidua        (European Larch / Lärche)
-- 11 | Fagus sylvatica      (European Beech / Buche)
-- 15 | Quercus robur        (European Oak / Stieleiche)
-- 16 | Quercus petraea      (Sessile Oak / Traubeneiche)
-- 20 | Betula pendula       (Silver Birch / Birke)
-- 22 | Fraxinus excelsior   (Common Ash / Esche)
-- 24 | Acer pseudoplatanus  (Sycamore Maple / Bergahorn)
-- 25 | Tilia cordata        (Small-leaved Linden / Winterlinde)
-- 30 | Prunus avium         (Wild Cherry / Vogelkirsche)
-- 33 | Torminalis glaberrima(Wild Service Tree / Elsbeere)

-- =============================================================================
-- PUBLIC VIEW: silva_input
-- =============================================================================
-- One row per tree variant row in trees.Trees (field or LiDAR measurements only).
-- Position is converted from WGS84 to local Cartesian metres (UTM 32N, EPSG:32632)
-- relative to the plot centre — the coordinate system SILVA expects.
--
-- Typical R call:
--   silva_trees <- dbGetQuery(con,
--     "SELECT * FROM silva_input
--      WHERE scenario_name = 'Current_Conditions'
--      AND location_name   = 'Ecosense_MixedPlot'")

CREATE OR REPLACE VIEW public.silva_input AS
SELECT
    -- -------------------------------------------------------
    -- Stand / plot identifiers (SILVA: bid, bid2, nr)
    -- -------------------------------------------------------
    t.LocationID                                            AS bid,
    COALESCE(t.PlotID, t.LocationID)                       AS bid2,
    COALESCE(t.TreeNumber, t.VariantID)                    AS nr,

    -- -------------------------------------------------------
    -- SILVA Baumart code  (SILVA: ba)
    -- -------------------------------------------------------
    CASE sp.ScientificName
        WHEN 'Picea abies'             THEN 1
        WHEN 'Abies alba'              THEN 2
        WHEN 'Pinus sylvestris'        THEN 3
        WHEN 'Pseudotsuga menziesii'   THEN 4
        WHEN 'Larix decidua'           THEN 5
        WHEN 'Fagus sylvatica'         THEN 11
        WHEN 'Quercus robur'           THEN 15
        WHEN 'Quercus petraea'         THEN 16
        WHEN 'Betula pendula'          THEN 20
        WHEN 'Betula pubescens'        THEN 21
        WHEN 'Fraxinus excelsior'      THEN 22
        WHEN 'Acer pseudoplatanus'     THEN 24
        WHEN 'Acer platanoides'        THEN 24
        WHEN 'Tilia cordata'           THEN 25
        WHEN 'Prunus avium'            THEN 30
        WHEN 'Torminalis glaberrima'   THEN 33
        ELSE NULL   -- unknown species: SILVA will reject; check species audit
    END                                                     AS ba,

    -- -------------------------------------------------------
    -- Position: local Cartesian (m from plot centre, UTM 32N)
    -- SILVA expects x/y in metres relative to stand centre.
    -- We project WGS84 → UTM 32N (EPSG:32632) and subtract
    -- the location centre point.  Assumes location CenterPoint
    -- is set (non-NULL) — rows with NULL centre are excluded.
    -- -------------------------------------------------------
    ROUND(CAST(
        extensions.ST_X(extensions.ST_Transform(t.Position, 32632))
        - extensions.ST_X(extensions.ST_Transform(l.CenterPoint, 32632))
    AS NUMERIC), 2)                                         AS x,

    ROUND(CAST(
        extensions.ST_Y(extensions.ST_Transform(t.Position, 32632))
        - extensions.ST_Y(extensions.ST_Transform(l.CenterPoint, 32632))
    AS NUMERIC), 2)                                         AS y,

    -- -------------------------------------------------------
    -- Tree dimensions  (SILVA: h, d, hkb, kb)
    -- -------------------------------------------------------
    t.Height_m                                              AS h,       -- total height (m)
    st.DBH_cm                                               AS d,       -- DBH at 1.3 m (cm)
    t.CrownBaseHeight_m                                     AS hkb,     -- Kronenbasis (m)
    t.CrownWidth_m                                          AS kb,      -- Kronenbreite (m)
    t.Age_years                                             AS age,

    -- -------------------------------------------------------
    -- Simulation base year
    -- -------------------------------------------------------
    EXTRACT(YEAR FROM t.MeasurementDate)::INTEGER           AS base_year,

    -- -------------------------------------------------------
    -- Site context (optional SILVA inputs; verify with colleagues)
    -- -------------------------------------------------------
    l.Elevation_m                                           AS elevation_m,
    l.Slope_deg                                             AS slope_deg,
    l.Aspect                                                AS aspect,

    -- -------------------------------------------------------
    -- Non-SILVA columns — keep for write-back join
    -- The R script should carry these through to the output
    -- so silva_writeback.py can match rows back to DB entities.
    -- -------------------------------------------------------
    t.TreeEntityID                                          AS tree_entity_id,
    t.VariantID                                             AS base_variant_id,
    t.ScenarioID                                            AS scenario_id,
    sc.ScenarioName                                         AS scenario_name,
    t.LocationID                                            AS location_id,
    t.PlotID                                                AS plot_id,
    t.SpeciesID                                             AS species_id,
    sp.CommonName                                           AS species_common,
    sp.ScientificName                                       AS species_sci,
    t.HealthScore                                           AS health_score

FROM trees.Trees       t
LEFT JOIN shared.Locations   l  ON t.LocationID  = l.LocationID
LEFT JOIN shared.Species     sp ON t.SpeciesID   = sp.SpeciesID
LEFT JOIN shared.Scenarios   sc ON t.ScenarioID  = sc.ScenarioID
-- Join to main stem only (StemNumber = 1) for DBH
LEFT JOIN trees.Stems        st ON st.TreeVariantID = t.VariantID
                                AND st.StemNumber    = 1
WHERE
    -- Only field/LiDAR measurements — not simulated or estimated rows
    t.DataSourceType IN ('field', 'lidar', 'photogrammetry')
    -- Must have height (mandatory SILVA input)
    AND t.Height_m IS NOT NULL
    -- Must have a known location centre for coordinate conversion
    AND l.CenterPoint IS NOT NULL
    -- Exclude rows that are themselves simulator output
    AND t.VariantTypeID NOT IN (
        SELECT VariantTypeID FROM shared.VariantTypes
        WHERE VariantTypeName IN ('simulated_growth', 'model_output', 'sensor_derived')
    );

COMMENT ON VIEW public.silva_input IS
    'DRAFT: SILVA 4.5 single-tree input view. '
    'Filter by scenario_name + location_name before passing to R. '
    'Positions are in metres relative to location CenterPoint (UTM 32N). '
    'Verify ba codes and column names against the Freiburg R implementation (XRFF-244).';

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT SELECT ON public.silva_input TO anon, authenticated, service_role;
