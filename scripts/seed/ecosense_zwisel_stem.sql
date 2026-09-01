-- XR Future Forests Lab — Ecosense forked-stem (Zwisel) second stem
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after the
-- ecosense tree import:
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres < scripts/seed/ecosense_zwisel_stem.sql
--
-- What this does
-- ==============
-- Tree 4_56 in the ecosense inventory is a Zwisel (forked stem). The field crew
-- recorded it as two rows 0.368 m apart, both commented "Zwisel", with DBH
-- 11.46 cm and 19.10 cm. That is one tree with two stems, not two trees.
--
-- The 2026-09-01 cleaning pass merged the two rows in
-- data/imports/ecosense_trees_import.csv into a single tree positioned at the
-- mean of the two stem fixes, carrying the 19.10 cm stem. import_trees.py only
-- ever writes stem_number = 1, so this script adds the 11.46 cm second stem.
--
-- Idempotent: guarded on (tree_id, stem_number), so re-running is a no-op.

SET search_path TO shared, trees, extensions, public;

INSERT INTO trees.Stems (tree_id, stem_number, dbh_cm)
SELECT t.tree_id, 2, 11.46
FROM trees.Trees t
JOIN shared.Locations l ON l.location_id = t.location_id
WHERE l.location_name = 'ecosense'
  AND t.tree_number = 56
  AND t.field_notes LIKE '%Zwisel%'
  AND NOT EXISTS (
      SELECT 1 FROM trees.Stems s
      WHERE s.tree_id = t.tree_id AND s.stem_number = 2
  );
