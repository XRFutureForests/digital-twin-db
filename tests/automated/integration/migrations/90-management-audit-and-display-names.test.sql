-- Migration 90 (management audit, display names). Runs against a database
-- with 89 and 90 applied, inside a transaction it rolls back:
--   docker cp <this file> dftdb-db:/tmp/t90.sql
--   docker exec dftdb-db psql -U supabase_admin -d postgres -f /tmp/t90.sql
-- Expected: every NOTICE says "ok".
\set ON_ERROR_STOP 1
\pset footer off
BEGIN;

-- A contributor: an existing account, so a display name resolves
CREATE TEMP TABLE me AS SELECT id::text AS uid FROM auth.users WHERE deleted_at IS NULL ORDER BY created_at LIMIT 1;
GRANT SELECT ON me TO authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', uid, 'role', 'authenticated', 'app_metadata', json_build_object('role', 'contributor'))::text, true)
  FROM me;
SET LOCAL ROLE authenticated;

SELECT set_config('app.change_reason', 'Test 90: Fork gespeichert', true);
INSERT INTO management.areas (location_id, geom, description)
SELECT location_id, extensions.st_buffer(extensions.st_setsrid(extensions.st_makepoint(longitude, latitude), 4326)::extensions.geography, 20)::extensions.geometry, 'Test 90'
  FROM trees.v_trees_latest WHERE location_name = 'mathisle' LIMIT 1;
INSERT INTO management.forks (area_id, base_variant_id, description)
SELECT max(area_id), (SELECT max(variant_id) FROM trees.v_trees_latest WHERE location_name = 'mathisle'), 'Test 90'
  FROM management.areas;
UPDATE management.forks SET description = 'Test 90 geändert' WHERE fork_id = (SELECT max(fork_id) FROM management.forks);
-- No-op update: not recorded
UPDATE management.forks SET description = description WHERE fork_id = (SELECT max(fork_id) FROM management.forks);
DELETE FROM management.forks WHERE fork_id = (SELECT max(fork_id) FROM management.forks);

SELECT 'A1 created_by = uid' AS t, created_by = (SELECT uid FROM me) AS ok FROM management.areas WHERE description = 'Test 90';
SELECT 'A2 trail' AS t, l.table_name, a.change_type, a.change_reason, a.user_id = (SELECT uid FROM me) AS own,
       (a.new_value::jsonb ->> 'description') AS new_descr
  FROM shared.audit_log_management l JOIN shared.audit_log a USING (audit_log_id)
 WHERE a.change_reason = 'Test 90: Fork gespeichert' ORDER BY a.audit_log_id;
SELECT 'A3 display name' AS t, shared.user_display_name(created_by) IS NOT NULL AND shared.user_display_name(created_by) <> created_by AS ok
  FROM management.areas WHERE description = 'Test 90';
SELECT 'A4 legacy text' AS t, shared.user_display_name('Lokaler Test') = 'Lokaler Test' AS ok;
RESET ROLE;

-- Anonymous callers learn no names
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
DO $$ BEGIN
  PERFORM shared.user_display_name('00000000-0000-0000-0000-000000000000');
  RAISE NOTICE 'A5 FEHLER: anon darf die Funktion aufrufen';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'A5 ok: %', SQLERRM;
END $$;
RESET ROLE;

ROLLBACK;
