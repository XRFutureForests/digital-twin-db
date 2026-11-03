-- =============================================================================
-- Three species of the Pathfinder superplots: Lawson cypress, holly, wych elm
-- =============================================================================
-- XRFF-641. The five Pathfinder sites imported as new locations hold three
-- species the lookup did not have. GBIF keys from the GBIF backbone (strict
-- match, status ACCEPTED, 2026-11-03). leaf_type as in 63-species-leaf-type:
-- Lawson cypress is a conifer (scale leaves) and counts as needleleaf in the
-- Copernicus Dominant Leaf Type classes.
--
-- The rows are also in data/lookups/species.csv, so a rebuild loads them;
-- this file only adds leaf_type, which the CSV does not carry. Growth rate,
-- shade tolerance and size maxima are left NULL rather than guessed.
--
-- Mirrored to init 82-species-lawson-cypress-holly-wych-elm.sql.
-- =============================================================================

INSERT INTO shared.species (common_name, scientific_name, is_deciduous, gbif_key, gbif_accepted_name, leaf_type)
VALUES ('Lawson Cypress', 'Chamaecyparis lawsoniana', false, 2683866, 'Chamaecyparis lawsoniana', 'needleleaf'),
       ('Holly',          'Ilex aquifolium',          false, 5414222, 'Ilex aquifolium',          'broadleaf'),
       ('Wych Elm',       'Ulmus glabra',             true,  5361866, 'Ulmus glabra',             'broadleaf')
ON CONFLICT (scientific_name) DO UPDATE
   SET leaf_type          = coalesce(shared.species.leaf_type, EXCLUDED.leaf_type),
       gbif_key           = coalesce(shared.species.gbif_key, EXCLUDED.gbif_key),
       gbif_accepted_name = coalesce(shared.species.gbif_accepted_name, EXCLUDED.gbif_accepted_name),
       is_deciduous       = coalesce(shared.species.is_deciduous, EXCLUDED.is_deciduous);
