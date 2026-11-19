-- Migration 89 (tree changes, field surveys). Runs against a database with 89
-- applied, inside a transaction it rolls back:
--   docker cp <this file> dftdb-db:/tmp/t89.sql
--   docker exec dftdb-db psql -U supabase_admin -d postgres -f /tmp/t89.sql
-- Expected: every NOTICE says "ok"; the review list holds T3, T4 and T8.
\set ON_ERROR_STOP 1
\pset footer off
BEGIN;
-- Without a JWT nobody may write changes, not even a superuser session
DO $$ BEGIN
  PERFORM trees.record_corrections((SELECT tree_entity_id FROM trees.v_trees_current LIMIT 1),
    '{"quality_rvr":{"old":null,"new":"B"}}'::jsonb);
  RAISE NOTICE 'R0 FEHLER: ohne JWT geschrieben';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'R0 ok: %', SQLERRM;
END $$;
-- Act as a curator, the way the app sets the signed-in user's claims
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated","app_metadata":{"role":"curator"}}', true);
SELECT 'latest' AS t, count(*) FROM trees.v_trees_latest;
SELECT 'current' AS t, count(*), count(*) FILTER (WHERE is_harvested) AS harvested FROM trees.v_trees_current;

CREATE TEMP TABLE tt AS
SELECT row_number() OVER (ORDER BY tree_entity_id) AS n, c.*
  FROM trees.v_trees_current c
 WHERE location_name = 'mathisle' AND NOT is_harvested AND species_id IS NOT NULL
   AND dbh_cm IS NOT NULL AND height_m IS NOT NULL
 ORDER BY tree_entity_id LIMIT 8;
CREATE TEMP TABLE sp2 AS
SELECT (SELECT species_id FROM shared.species WHERE species_id NOT IN (SELECT species_id FROM tt WHERE n IN (1,3)) ORDER BY 1 LIMIT 1) AS b,
       (SELECT species_id FROM shared.species WHERE species_id NOT IN (SELECT species_id FROM tt WHERE n IN (1,3)) ORDER BY 1 OFFSET 1 LIMIT 1) AS c;
SELECT n, tree_entity_id, species_id, dbh_cm, height_m, tree_status_id FROM tt;

INSERT INTO shared.campaigns (campaign_name, campaign_type, start_date, licence, description)
VALUES ('test_inventur_2027', 'field_inventory', DATE '2027-03-01', 'test', 'Test 89');

-- Helper: survey with base = state in tt
CREATE TEMP TABLE camp AS SELECT campaign_id FROM shared.campaigns WHERE campaign_name = 'test_inventur_2027';

-- T1: correction species; field leaves species as seen -> correction stays
SELECT 'T1 corr' AS t, attribute, state FROM trees.record_corrections(
  (SELECT tree_entity_id FROM tt WHERE n=1),
  jsonb_build_object('species_id', jsonb_build_object('old', (SELECT species_id FROM tt WHERE n=1), 'new', (SELECT b FROM sp2))),
  DATE '2026-11-18', 'tester');

-- T1b: stale old value is refused
DO $$ BEGIN
  PERFORM trees.record_corrections((SELECT tree_entity_id FROM tt WHERE n=1),
    jsonb_build_object('species_id', jsonb_build_object('old', (SELECT species_id FROM tt WHERE n=1), 'new', 1)));
  RAISE NOTICE 'T1b FEHLER: veralteter Wert wurde angenommen';
EXCEPTION WHEN serialization_failure THEN RAISE NOTICE 'T1b ok: %', SQLERRM;
END $$;

INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_tree_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by, device)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), tree_id, species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       species_id, dbh_cm + 1.2, height_m + 0.5, tree_status_id, "position", 'trupp', 'tablet1'
  FROM tt WHERE n=1;

-- T2: correction DBH; field measures new DBH -> superseded, field value wins
SELECT 'T2 corr' AS t, attribute, state FROM trees.record_corrections(
  (SELECT tree_entity_id FROM tt WHERE n=2),
  jsonb_build_object('dbh_cm', jsonb_build_object('old', (SELECT dbh_cm FROM tt WHERE n=2), 'new', (SELECT dbh_cm + 5 FROM tt WHERE n=2))),
  DATE '2026-11-18', 'tester');
INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       species_id, dbh_cm + 6, height_m, tree_status_id, "position", 'trupp'
  FROM tt WHERE n=2;

-- T3: correction species A->B; field sets C -> conflict, change stays in force
SELECT 'T3 corr' AS t, attribute, state FROM trees.record_corrections(
  (SELECT tree_entity_id FROM tt WHERE n=3),
  jsonb_build_object('species_id', jsonb_build_object('old', (SELECT species_id FROM tt WHERE n=3), 'new', (SELECT b FROM sp2))),
  DATE '2026-11-18', 'tester');
INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       (SELECT c FROM sp2), dbh_cm, height_m, tree_status_id, "position", 'trupp'
  FROM tt WHERE n=3;

-- T4: harvest via fork, then tree found in the field -> conflict
INSERT INTO management.areas (location_id, geom, description)
SELECT location_id, extensions.st_buffer("position"::extensions.geography, 30)::extensions.geometry, 'Test 89'
  FROM tt WHERE n=4;
INSERT INTO management.forks (area_id, base_variant_id, description)
SELECT (SELECT max(area_id) FROM management.areas), variant_id, 'Test 89' FROM tt WHERE n=4;
INSERT INTO management.thinning_trees (fork_id, tree_entity_id, role)
SELECT (SELECT max(fork_id) FROM management.forks), tree_entity_id, 'removal' FROM tt WHERE n=4;
SELECT 'T4 apply' AS t, * FROM management.apply_fork((SELECT max(fork_id) FROM management.forks), DATE '2026-11-20', 'tester');
SELECT 'T4 in latest?' AS t, count(*) FROM trees.v_trees_latest WHERE tree_entity_id = (SELECT tree_entity_id FROM tt WHERE n=4);
SELECT 'T4 field view' AS t, is_harvested, tree_status_name FROM field.v_trees_current WHERE tree_entity_id = (SELECT tree_entity_id FROM tt WHERE n=4);
DO $$ BEGIN
  PERFORM management.apply_fork((SELECT max(fork_id) FROM management.forks));
  RAISE NOTICE 'T4b FEHLER: zweimal angewandt';
EXCEPTION WHEN raise_exception THEN RAISE NOTICE 'T4b ok: %', SQLERRM;
END $$;
INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       species_id, dbh_cm + 1, height_m, tree_status_id, "position", 'trupp'
  FROM tt WHERE n=4;

-- T5: invalid value -> fehler, sync not aborted
INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_dbh_cm, dbh_cm)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), dbh_cm, 0 FROM tt WHERE n=5;

-- T6: field change, DB unchanged -> field value taken; second survey same campaign replaces first
INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       species_id, dbh_cm + 2, height_m, tree_status_id, "position", 'trupp'
  FROM tt WHERE n=6;
INSERT INTO field.tree_surveys (tree_entity_id, campaign_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       species_id, dbh_cm + 2.5, height_m, tree_status_id, "position", 'trupp'
  FROM tt WHERE n=6;

-- T7-T9: import of a new inventory (e.g. laser scan) as a new variant
SELECT 'T7 corr' AS t, attribute, state FROM trees.record_corrections(
  (SELECT tree_entity_id FROM tt WHERE n=7),
  jsonb_build_object('species_id', jsonb_build_object('old', (SELECT species_id FROM tt WHERE n=7), 'new', (SELECT b FROM sp2)),
                     'dbh_cm',     jsonb_build_object('old', (SELECT dbh_cm FROM tt WHERE n=7), 'new', (SELECT dbh_cm + 5 FROM tt WHERE n=7))),
  DATE '2026-11-18', 'tester');
INSERT INTO management.areas (location_id, geom, description)
SELECT location_id, extensions.st_buffer("position"::extensions.geography, 1)::extensions.geometry, 'Test 89 T8' FROM tt WHERE n=8;
INSERT INTO management.forks (area_id, base_variant_id, description)
SELECT (SELECT max(area_id) FROM management.areas), variant_id, 'Test 89 T8' FROM tt WHERE n=8;
INSERT INTO management.thinning_trees (fork_id, tree_entity_id, role)
SELECT (SELECT max(fork_id) FROM management.forks), tree_entity_id, 'removal' FROM tt WHERE n=8;
SELECT 'T8 apply' AS t, * FROM management.apply_fork((SELECT max(fork_id) FROM management.forks), DATE '2026-11-20', 'tester');

-- Scan inventory 2027: new variant, species copied, DBH and height measured, status unknown
INSERT INTO shared.variants (location_id, scenario_id, variant_type_id, variant_name, sort_order, description)
SELECT t.location_id, v.scenario_id, (SELECT variant_type_id FROM shared.variant_types WHERE variant_type_name = 'repeat_measurement'),
       'test_tls_2027', 99, 'Test 89 Scan'
  FROM tt t JOIN shared.variants v ON v.variant_id = t.variant_id WHERE t.n = 7;
WITH ins AS (
  INSERT INTO trees.trees (tree_entity_id, variant_id, location_id, scenario_id, variant_type_id, species_id,
                           tree_status_id, measurement_date, "position", height_m)
  SELECT t.tree_entity_id, sv.variant_id, t.location_id, sv.scenario_id, sv.variant_type_id,
         t.species_id, NULL, DATE '2027-06-01', t."position", t.height_m + 0.4
    FROM tt t, shared.variants sv
   WHERE t.n IN (7, 8) AND sv.variant_name = 'test_tls_2027'
  RETURNING tree_id, tree_entity_id)
INSERT INTO trees.stems (tree_id, stem_number, dbh_cm)
SELECT ins.tree_id, 1, t.dbh_cm + 3 FROM ins JOIN tt t USING (tree_entity_id);
-- T9: backfill of an older inventory for tree 7 with another species: must not touch the changes
INSERT INTO shared.variants (location_id, scenario_id, variant_type_id, variant_name, sort_order, description)
SELECT location_id, scenario_id, variant_type_id, 'test_old_2001', -1, 'Test 89 Altbestand'
  FROM shared.variants WHERE variant_name = 'test_tls_2027';
INSERT INTO trees.trees (tree_entity_id, variant_id, location_id, scenario_id, variant_type_id, species_id,
                         measurement_date, "position")
SELECT t.tree_entity_id, sv.variant_id, t.location_id, sv.scenario_id, sv.variant_type_id,
       (SELECT c FROM sp2), DATE '2001-01-01', t."position"
  FROM tt t, shared.variants sv
 WHERE t.n = 7 AND sv.variant_name = 'test_old_2001';
SET CONSTRAINTS trees.trigger_trees_reconcile_changes IMMEDIATE;
SET CONSTRAINTS trees.trigger_trees_reconcile_changes DEFERRED;
\echo '--- T7/T8 nach Scan-Import'
SELECT t.n, c.attribute, c.kind, c.state, c.state_note
  FROM trees.tree_changes c JOIN tt t USING (tree_entity_id) WHERE t.n IN (7, 8) ORDER BY t.n, c.change_id;
SELECT t.n, t.species_id AS sp_vorher, c.species_id AS sp_jetzt, t.dbh_cm AS bhd_vorher, c.dbh_cm AS bhd_jetzt,
       c.is_harvested, c.has_open_conflict
  FROM tt t JOIN trees.v_trees_current c USING (tree_entity_id) WHERE t.n IN (7, 8) ORDER BY t.n;

\echo '--- Surveys'
SELECT t.n, s.state, s.message, s.result_tree_id IS NOT NULL AS has_row
  FROM field.tree_surveys s JOIN tt t USING (tree_entity_id) ORDER BY s.processed_at, t.n;
\echo '--- Changes'
SELECT t.n, c.attribute, c.kind, c.state, c.old_value, c.new_value
  FROM trees.tree_changes c JOIN tt t USING (tree_entity_id) ORDER BY t.n, c.change_id;
\echo '--- Current vs. before'
SELECT t.n, t.species_id AS sp_vorher, c.species_id AS sp_jetzt, t.dbh_cm AS bhd_vorher, c.dbh_cm AS bhd_jetzt,
       c.variant_id <> t.variant_id AS neue_messung, c.is_harvested, c.has_open_conflict, c.changed_attributes
  FROM tt t JOIN trees.v_trees_current c USING (tree_entity_id) ORDER BY t.n;
\echo '--- Review list'
SELECT change_id IS NOT NULL AS ist_change, attribute, kind, change_value, field_value, state_note FROM trees.v_tree_change_conflicts;

-- T3 resolved for the survey -> field value shows
SELECT 'T3 resolve' AS t, state FROM trees.resolve_change_conflict(
  (SELECT change_id FROM trees.tree_changes WHERE state = 'conflict' AND attribute = 'species_id'), false, 'Feld hat recht', 'kurator');
SELECT 'T3 danach' AS t, species_id = (SELECT c FROM sp2) AS feldwert FROM trees.v_trees_current WHERE tree_entity_id = (SELECT tree_entity_id FROM tt WHERE n=3);

-- Rights: a contributor JWT may correct, may not resolve
GRANT SELECT ON tt, camp TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"role":"contributor"}}', true);
SELECT 'R1 contributor corr' AS t, state, created_by FROM trees.record_corrections(
  (SELECT tree_entity_id FROM tt WHERE n=5),
  jsonb_build_object('height_m', jsonb_build_object('old', (SELECT height_m FROM tt WHERE n=5), 'new', 12.3)));
DO $$ BEGIN
  PERFORM trees.resolve_change_conflict((SELECT change_id FROM trees.tree_changes WHERE state='conflict' LIMIT 1), true);
  RAISE NOTICE 'R2 FEHLER: contributor durfte entscheiden';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'R2 ok: %', SQLERRM;
END $$;
DO $$ BEGIN
  INSERT INTO trees.tree_changes (tree_entity_id, location_id, attribute, new_value, kind, event_date)
  VALUES (gen_random_uuid(), 1, 'dbh_cm', '1', 'correction', current_date);
  RAISE NOTICE 'R3 FEHLER: direkter Insert erlaubt';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'R3 ok: %', SQLERRM;
END $$;
-- R4: a survey through the PostgREST view, as the QField plugin sends it
INSERT INTO public.tree_surveys (tree_entity_id, campaign_id, base_species_id, base_dbh_cm, base_height_m,
       base_tree_status_id, base_quality_rvr, base_position, species_id, dbh_cm, height_m, tree_status_id, "position", surveyed_by)
SELECT tree_entity_id, (SELECT campaign_id FROM camp), species_id, dbh_cm, height_m, tree_status_id, quality_rvr, "position",
       species_id, dbh_cm + 0.7, height_m, tree_status_id, "position", 'wird ersetzt'
  FROM tt WHERE n=8;
SELECT 'R4 survey via public' AS t, state, surveyed_by FROM field.tree_surveys
 WHERE tree_entity_id = (SELECT tree_entity_id FROM tt WHERE n=8);
RESET ROLE;

ROLLBACK;
