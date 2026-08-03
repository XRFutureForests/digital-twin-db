-- XR Future Forests Lab — Species-default Roots + CrownFoliageProfiles (XRFF-266)
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after the
-- baseline import and the XRFF-266 schema migration:
--
--   docker exec -i dftdb-db psql -U postgres -d postgres < scripts/seed/root_and_foliage_defaults.sql
--
-- What this does
-- ==============
-- 1. Registers Le Port et al. (2000) and Jeréz et al. (2005) as shared.Processes
--    rows -- the two crown-foliage-distribution methods trees.CrownFoliageProfiles
--    is designed around. Registered now so the citation exists in the
--    Processes registry whenever a real fitted distribution is added later;
--    neither paper studied any of our 11 species, so no CrownFoliageProfiles
--    row below references either process_id.
-- 2. Seeds one trees.Roots row (source = 'species_default') for every tree
--    whose species is in our canonical 11-species catalog (growpy's
--    config/tree_asset_lookup.csv, Dataset = 'yes' -- see
--    memory/publication-canonical-numbers.md), classified by root system
--    type per Koestler, Brueckner & Bibelriether (1968), "Die Wurzeln der
--    Waldbaeume" -- the standard European-forestry root-morphology
--    classification (tap root / heart root / lateral root) that Guerrero
--    Iniguez (2017) itself builds on.
-- 3. Seeds one trees.CrownFoliageProfiles row (distribution_type = 'uniform',
--    source = 'species_literature_default') for the same trees. 'uniform'
--    here is an explicit "no species-specific shape parameters known yet"
--    signal -- NOT a stand-in for real Beta/Johnson-SB parameters, which
--    would need a paper that actually studied that species (neither Le Port
--    2000 [Maritime pine] nor Jeréz 2005 [loblolly pine] did).
--
-- Root system type classification (Koestler et al. 1968; see
-- data/lookups/root_system_types.csv for the type definitions):
--   Fagus sylvatica       -> heart_root   (textbook Herzwurzel example)
--   Quercus robur         -> tap_root     (classic taproot former)
--   Picea abies           -> lateral_root (shallow plate-root, high windthrow risk)
--   Abies alba            -> tap_root     (taproot in deep soils, more so than spruce)
--   Pinus sylvestris      -> tap_root     (classic taproot on well-drained sites)
--   Pseudotsuga menziesii -> tap_root     (deep-rooting where site allows)
--   Acer pseudoplatanus   -> heart_root
--   Prunus avium          -> lateral_root (shallow, spreading)
--   Betula pendula        -> lateral_root (pioneer, shallow widespread roots)
--   Fraxinus excelsior    -> heart_root
--   Tilia cordata         -> heart_root
--
-- Idempotent: guarded by ON CONFLICT / NOT EXISTS so re-running is a no-op.

SET search_path TO shared, trees, extensions, public;

-- ============================================================
-- STEP 1: Register Le Port (2000) and Jeréz (2005) as processes
-- ============================================================

INSERT INTO shared.Processes (process_name, algorithm_name, version, description, author, publication_date, citation, category)
VALUES (
    'Crown Foliage Area Distribution',
    'Beta PDF (vertical/horizontal)',
    '2000',
    'Fits Beta probability density functions to the vertical and horizontal foliage-area distribution within the crown, parameterised by tree/stand age.',
    'Le Port, Bosc, Champion & Loustau',
    '2000-01-01',
    'Le Port, A.S., Bosc, A., Champion, I. & Loustau, D. (2000). Estimating the foliage area of Maritime pine (Pinus pinaster Ait.) branches and crowns with application to modelling the foliage area distribution in the crown. Annals of Forest Science, 57, 11-22. doi:10.1051/forest:2000110',
    'analysis'
)
ON CONFLICT (process_name, version) DO NOTHING;

INSERT INTO shared.Processes (process_name, algorithm_name, version, description, author, publication_date, citation, category)
VALUES (
    'Crown Foliage Area Distribution',
    'Johnson SB function',
    '2005',
    'Alternative parametric (Johnson SB) distribution for leaf area distribution within the crown.',
    'Jerez, Dean, Cao & Roberts',
    '2005-01-01',
    'Jerez, M., Dean, T.J., Cao, Q.V. & Roberts, S.D. (2005). Describing Leaf Area Distribution in Loblolly Pine Trees with Johnson''s SB Function. Forest Science, 51(2), 93. doi:10.1093/forestscience/51.2.93',
    'analysis'
)
ON CONFLICT (process_name, version) DO NOTHING;

-- ============================================================
-- STEP 2: Species -> root system type mapping (11-species catalog)
-- ============================================================

CREATE TEMP TABLE temp_species_root_defaults (
    scientific_name VARCHAR(200),
    root_system_type_name VARCHAR(50)
);

INSERT INTO temp_species_root_defaults (scientific_name, root_system_type_name) VALUES
    ('Fagus sylvatica', 'heart_root'),
    ('Quercus robur', 'tap_root'),
    ('Picea abies', 'lateral_root'),
    ('Abies alba', 'tap_root'),
    ('Pinus sylvestris', 'tap_root'),
    ('Pseudotsuga menziesii', 'tap_root'),
    ('Acer pseudoplatanus', 'heart_root'),
    ('Prunus avium', 'lateral_root'),
    ('Betula pendula', 'lateral_root'),
    ('Fraxinus excelsior', 'heart_root'),
    ('Tilia cordata', 'heart_root');

-- ============================================================
-- STEP 3: Seed trees.Roots (one row per matching tree, source = 'species_default')
-- ============================================================

INSERT INTO trees.Roots (tree_entity_id, tree_id, root_system_type_id, lod, geometry_class, source, created_by)
SELECT
    t.tree_entity_id,
    t.tree_id,
    rst.root_system_type_id,
    1,              -- LoD1: block model, no measured geometry
    'implicit',
    'species_default',
    'seed_root_and_foliage_defaults'
FROM trees.Trees t
JOIN shared.Species sp ON sp.species_id = t.species_id
JOIN temp_species_root_defaults d ON d.scientific_name = sp.scientific_name
JOIN trees.RootSystemTypes rst ON rst.root_system_type_name = d.root_system_type_name
WHERE NOT EXISTS (
    SELECT 1 FROM trees.Roots r
    WHERE r.tree_id = t.tree_id AND r.source = 'species_default'
);

-- ============================================================
-- STEP 4: Seed trees.CrownFoliageProfiles (same trees, distribution_type = 'uniform')
-- ============================================================

INSERT INTO trees.CrownFoliageProfiles (tree_id, process_id, distribution_type, vertical_params, horizontal_params, total_leaf_area_m2, source, created_by)
SELECT
    t.tree_id,
    NULL,           -- no species-specific fit exists yet; not attributed to Le Port/Jerez
    'uniform',
    NULL,
    NULL,
    NULL,
    'species_literature_default',
    'seed_root_and_foliage_defaults'
FROM trees.Trees t
JOIN shared.Species sp ON sp.species_id = t.species_id
JOIN temp_species_root_defaults d ON d.scientific_name = sp.scientific_name
WHERE NOT EXISTS (
    SELECT 1 FROM trees.CrownFoliageProfiles p
    WHERE p.tree_id = t.tree_id AND p.source = 'species_literature_default'
);

DROP TABLE temp_species_root_defaults;

-- ============================================================
-- SUMMARY
-- ============================================================
DO $$
DECLARE
    roots_count INTEGER;
    profiles_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO roots_count FROM trees.Roots WHERE source = 'species_default';
    SELECT COUNT(*) INTO profiles_count FROM trees.CrownFoliageProfiles WHERE source = 'species_literature_default';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Species-default Roots + CrownFoliageProfiles seeded';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE '  trees.Roots (species_default):               % rows', roots_count;
    RAISE NOTICE '  trees.CrownFoliageProfiles (literature_def.): % rows', profiles_count;
    RAISE NOTICE '=======================================================';
END $$;
