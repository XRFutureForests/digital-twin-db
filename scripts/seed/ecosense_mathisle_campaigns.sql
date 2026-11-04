-- XR Future Forests Lab — campaigns, census extent and first observations for
-- ECOSENSE and Mathislewald
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after the
-- baseline import, the baseline-variant seeds and census_site_plots.sql:
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -1 < scripts/seed/ecosense_mathisle_campaigns.sql
--
-- What this does (XRFF-478, XRFF-465)
-- ===================================
-- 1. Registers four campaigns: the ECOSENSE field inventory (2024), the two
--    ECOSENSE terrestrial laser scans (leaves on and off, 2024) and the
--    Mathislewald inventory (2025). Facts come from the inventory readme and
--    ODK export on the projects share (\\unfnrd02...\projects\ecosense\inventory),
--    the TLS reference in lidar-to-unreal (docs/ecosense-tls-reference) and the
--    import files. Open questions are in the hub; values not known yet stay NULL.
--    Licence of the two inventories: 'all rights reserved' until the data owners
--    choose one (no licence has been granted). Access level stays public, which
--    is what these rows had without a campaign.
-- 2. Stamps the measured baseline trees of each site with its inventory
--    campaign. Projected variants keep campaign_id NULL for now (open decision).
-- 3. ECOSENSE: the inventory extent (inventory_extent_exact.gpkg, 2.911 ha, all
--    1,495 baseline trees inside) becomes the location boundary and the census
--    plot ecosense_site, replacing the convex hull census_site_plots.sql wrote.
--    Run this file after that seed, which would otherwise put the hull back.
--    Mathislewald keeps its convex hull: its 2022 core-area perimeter (1.031 ha)
--    leaves 88 of the 730 trees outside, so it is not the inventory extent.
-- 4. Re-identification: one observation per baseline tree in its inventory
--    campaign, and a first decision 'new' (ECOSENSE: first_campaign, the TLS
--    observations are matched against it; Mathislewald: single_campaign).
--
-- Idempotent: campaigns are upserted by name, the rest skips what exists.

SET search_path TO shared, trees, extensions, public;

-- -----------------------------------------------------------------------------
-- 1. Campaigns
-- -----------------------------------------------------------------------------

INSERT INTO shared.campaigns (campaign_name, campaign_type, location_id, start_date, end_date,
                              description, methodology, equipment, personnel,
                              licence, access_level, citation, doi, created_by)
SELECT v.campaign_name, v.campaign_type, l.location_id, v.start_date, v.end_date,
       v.description, v.methodology, v.equipment, v.personnel,
       v.licence, 'public', v.citation, NULL, 'scripts/seed/ecosense_mathisle_campaigns.sql'
  FROM (VALUES
    ('ecosense_inventory_2024', 'field_inventory', 'ecosense', DATE '2024-10-14', DATE '2024-11-26',
     'Full tree inventory of the ECOSENSE research forest (Ettenheim): every tree tagged with a QR code (https://dt.unr.uni-freiburg.de/ecosense/<group>_<tree>) and recorded with position, circumference and species.',
     'Census of the inventory extent (2.911 ha). Tablet teams with an ODK Collect form (version 20241011140844) on 14, 15 and 18 October 2024; the last 89 trees on 26 November 2024. Circumference at breast height with a measuring tape; DBH = circumference / pi. GNSS position taken 1 m south of the stem and shifted to the stem, then matched to stems of the leaves-on TLS scan of 15 October 2024 (3DFin segmentation; within 2 m and a DBH difference below 5 cm) and edited by hand where no automatic match was found, so most positions are TLS stem positions. Species named on site, corrected on 15 January 2025. Groups 1-18 (plot_id) are tagging groups, not sample plots. Trees with DBH below 5 cm were removed on import to this database (2026-09-01). Heights are not from this campaign: they come from the TLS scans or are modelled (height_source).',
     'Tablets with ODK Collect; Emlid Reach RS2, RS2+ and RS3 GNSS (base and rovers); measuring tapes; QR code tags and nails; compasses.',
     'Responsible: Teja Kattenborn, Maximilian Fabi, Julian Frey (readme_inventory.txt). Field teams recorded by initials in the ODK forms.',
     'all rights reserved', NULL),
    ('ecosense_tls_2024_leaf_on', 'laser_scan', 'ecosense', DATE '2024-10-15', DATE '2024-10-15',
     'Terrestrial laser scan of the ECOSENSE research forest with leaves on: 3Dtrees.earth dataset 195 "ECOSENSE Research Forest with Flux Tower" (ECOSENSE_TLS_195.laz, about 972 million points, 324 x 407 m) with instance and semantic segmentation.',
     'Per stem: circle fit at 1.3 m above the stem ground; height = highest kept point of the instance above the stem ground. Stems matched to inventory trees as mutual nearest partners within 1.0 m, TLS/field DBH ratio 0.7-1.4, no competitor within 0.5 m (lidar-to-unreal ecosense_tls_reference, XRFF-574): 1,057 matched, 78 ambiguous, 28 DBH mismatch, 1,638 unmatched (mostly outside the inventory extent). The inventory took its positions and DBH from this scan, so DBH is not an independent check.',
     'RIEGL VZ-400i terrestrial laser scanner.',
     'Julian Frey (scan).',
     'CC-BY-4.0',
     'Frey, J. (2024). ECOSENSE Research Forest with Flux Tower, terrestrial laser scan, leaves on. 3Dtrees.earth dataset 195.'),
    ('ecosense_tls_2024_leaf_off', 'laser_scan', 'ecosense', DATE '2024-03-22', DATE '2024-03-22',
     'Terrestrial laser scan of the ECOSENSE research forest with leaves off: 3Dtrees.earth dataset 226 "ECOSENSE Research Forest with Flux Tower Leaves off" (about 451 million points, 900 x 985 m, same registration as dataset 195).',
     'Segmented twice (ForestMamba, SegmentAnyTree) with DetailView species labels. Not loaded as observations yet.',
     'RIEGL VZ-400i terrestrial laser scanner.',
     'Julian Frey (scan).',
     'CC-BY-4.0',
     'Frey, J. (2024). ECOSENSE Research Forest with Flux Tower, terrestrial laser scan, leaves off. 3Dtrees.earth dataset 226.'),
    ('mathisle_inventory_2025', 'field_inventory', 'mathisle', DATE '2025-02-06', DATE '2025-04-13',
     'Full tree inventory of the Mathislewald research area: 730 trees with species, DBH and position, tagged with QR codes (https://dt.unr.uni-freiburg.de/mathisle/<tree>).',
     'Census on one plot, field days between 6 February and 13 April 2025. One GPS fix per tree from the field app, taken under canopy. DBH measured; heights not measured (modelled in this database). 88 trees lie outside the 2022 core-area perimeter, so the inventory extent is larger than the core area.',
     NULL, NULL,
     'all rights reserved', NULL)
  ) AS v(campaign_name, campaign_type, location_name, start_date, end_date, description, methodology,
         equipment, personnel, licence, citation)
  JOIN shared.locations l ON l.location_name = v.location_name
ON CONFLICT (campaign_name) DO UPDATE
   SET campaign_type = EXCLUDED.campaign_type, location_id = EXCLUDED.location_id,
       start_date = EXCLUDED.start_date, end_date = EXCLUDED.end_date,
       description = EXCLUDED.description, methodology = EXCLUDED.methodology,
       equipment = coalesce(EXCLUDED.equipment, shared.campaigns.equipment),
       personnel = coalesce(EXCLUDED.personnel, shared.campaigns.personnel),
       citation = coalesce(EXCLUDED.citation, shared.campaigns.citation),
       updated_at = now();

-- -----------------------------------------------------------------------------
-- 2. Baseline trees carry their inventory campaign
-- -----------------------------------------------------------------------------

UPDATE trees.trees t
   SET campaign_id = c.campaign_id
  FROM shared.variants v
  JOIN shared.variant_types vt ON vt.variant_type_id = v.variant_type_id
  JOIN shared.locations l ON l.location_id = v.location_id
  JOIN shared.campaigns c ON c.campaign_name = CASE l.location_name WHEN 'ecosense' THEN 'ecosense_inventory_2024'
                                                                     WHEN 'mathisle' THEN 'mathisle_inventory_2025' END
 WHERE t.variant_id = v.variant_id
   AND v.parent_variant_id IS NULL
   AND vt.variant_type_name = 'original'
   AND t.campaign_id IS DISTINCT FROM c.campaign_id;

-- -----------------------------------------------------------------------------
-- 3. ECOSENSE inventory extent: location boundary and census plot
-- -----------------------------------------------------------------------------

WITH ext AS (
    SELECT ST_GeomFromText('POLYGON((7.8787198 48.2669981,7.8787174 48.266996,7.8787143 48.2669944,7.8787106 48.2669935,7.8787067 48.2669934,7.878624 48.2669981,7.8786226 48.2669982,7.8777633 48.2671084,7.8777623 48.2671086,7.8775284 48.2671508,7.8775272 48.267151,7.8770047 48.2672804,7.8770007 48.2672819,7.8769978 48.2672843,7.8769962 48.2672872,7.8769961 48.2672903,7.8775029 48.2693005,7.8775041 48.269303,7.8775063 48.2693051,7.8775093 48.2693067,7.8775129 48.2693077,7.8775168 48.269308,7.877519 48.2693079,7.8775198 48.2693079,7.87817 48.2692634,7.8781707 48.2692634,7.8782476 48.2692555,7.8782514 48.2692547,7.8783028 48.269238,7.878306 48.2692365,7.8783084 48.2692346,7.8783099 48.2692322,7.8784244 48.2689469,7.8788365 48.2689596,7.8788407 48.2689593,7.8788445 48.2689582,7.8791172 48.2688402,7.8791201 48.2688386,7.8791222 48.2688364,7.8791232 48.268834,7.8791232 48.2688314,7.8791009 48.2687273,7.8791009 48.2687272,7.8787324 48.2670399,7.8787323 48.2670395,7.8787211 48.2670006,7.8787198 48.2669981))', 4326) AS g
), loc AS (
    UPDATE shared.locations l SET boundary = ext.g
      FROM ext
     WHERE l.location_name = 'ecosense' AND l.boundary IS DISTINCT FROM ext.g
    RETURNING l.location_id
)
UPDATE shared.plots p
   SET boundary     = ext.g,
       center_point = ST_Centroid(ext.g),
       area_m2      = round(ST_Area(ST_Transform(ext.g, l.crs_epsg))::numeric, 2),
       area_source  = 'surveyed',
       description  = 'Whole mapped site (census). Area = the ECOSENSE inventory extent (inventory_extent_exact.gpkg on the projects share); every baseline tree lies inside it.',
       updated_at   = now()
  FROM ext, shared.locations l
 WHERE l.location_name = 'ecosense'
   AND p.location_id = l.location_id
   AND p.plot_name = 'ecosense_site'
   AND p.area_source IS DISTINCT FROM 'surveyed';

-- -----------------------------------------------------------------------------
-- 4. First observations and decisions
-- -----------------------------------------------------------------------------

INSERT INTO trees.observations (location_id, campaign_id, tree_id, observed_on)
SELECT t.location_id, t.campaign_id, t.tree_id, t.measurement_date
  FROM trees.trees t
  JOIN shared.campaigns c ON c.campaign_id = t.campaign_id
 WHERE c.campaign_name IN ('ecosense_inventory_2024', 'mathisle_inventory_2025')
ON CONFLICT (tree_id) WHERE tree_id IS NOT NULL DO NOTHING;

INSERT INTO trees.entity_matches (observation_id, tree_entity_id, decision, method, decided_by, notes)
SELECT o.observation_id, t.tree_entity_id, 'new',
       CASE c.campaign_name WHEN 'ecosense_inventory_2024' THEN 'first_campaign' ELSE 'single_campaign' END,
       'scripts/seed/ecosense_mathisle_campaigns.sql',
       'First campaign at the site: the observation creates the entity.'
  FROM trees.observations o
  JOIN trees.trees t ON t.tree_id = o.tree_id
  JOIN shared.campaigns c ON c.campaign_id = o.campaign_id
 WHERE c.campaign_name IN ('ecosense_inventory_2024', 'mathisle_inventory_2025')
   AND NOT EXISTS (SELECT 1 FROM trees.entity_matches m WHERE m.observation_id = o.observation_id);
