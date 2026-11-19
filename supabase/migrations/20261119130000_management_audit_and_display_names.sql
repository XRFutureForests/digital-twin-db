-- =============================================================================
-- Mirrored to docker/volumes/db/init/90-management-audit-and-display-names.sql.
-- Tests: tests/automated/integration/migrations/90-management-audit-and-display-names.test.sql
-- Not yet reviewed by the repo owner (twinfrontend, 2026-11-19).
-- =============================================================================
-- History for the planning data in management.* and the harvest events, and
-- display names for the user ids that created_by now holds
-- =============================================================================
-- shared.audit_log records UPDATEs of selected columns, one row per field.
-- Planning data is mostly INSERTed and DELETEd (a fork's features are
-- replaced on save) and carries geometries, so a field-wise trail would be
-- both incomplete and huge. Here one audit_log row per changed ROW:
--
--   field_name   '*'
--   old_value    to_jsonb(OLD) as text (NULL on INSERT)
--   new_value    to_jsonb(NEW) as text (NULL on DELETE)
--   change_type  'insert' | 'field_update' | 'delete' (the values the
--                CHECK on audit_log allows; field '*' = the whole row)
--   user_id      auth.uid(), change_reason app.change_reason, as before
--
-- linked through shared.audit_log_management (table, key, fork, area), like
-- the existing audit_log_<table> link tables. An UPDATE that changes nothing
-- but updated_at / heartbeat columns is not recorded. management.fork_locks is
-- left out on purpose: a lock is a heartbeat, not a planning decision.
--
-- created_by in management.* is auth.uid() since 87 (shared.set_created_by).
-- shared.user_display_name() turns such an id into the name the app shows,
-- without granting anyone read access to auth.users.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Display names
-- -----------------------------------------------------------------------------
-- user_metadata.display_name, else the part of the e-mail before the @. A
-- value that is not a known user id (older rows, 'system') comes back as is.
CREATE OR REPLACE FUNCTION shared.user_display_name(p_user_id text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_name text;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN NULL;
    END IF;
    IF p_user_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN p_user_id;
    END IF;
    -- Only signed-in users learn names
    IF auth.uid() IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
        RETURN NULL;
    END IF;
    SELECT COALESCE(NULLIF(u.raw_user_meta_data ->> 'display_name', ''),
                    split_part(u.email::text, '@', 1))
      INTO v_name
      FROM auth.users u
     WHERE u.id = p_user_id::uuid;
    RETURN COALESCE(v_name, 'unbekannt');
END;
$$;

COMMENT ON FUNCTION shared.user_display_name(text) IS
    'Display name for a user id as stored in created_by / locked_by / resolved_by (user_metadata.display_name, else the e-mail local part). Non-uuid values are returned unchanged. NULL for anonymous callers.';

REVOKE ALL ON FUNCTION shared.user_display_name(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION shared.user_display_name(text) TO authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 2. Row-level audit
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS shared.audit_log_management (
    audit_log_id  bigint PRIMARY KEY
                  REFERENCES shared.audit_log (audit_log_id) ON DELETE CASCADE,
    table_name    text NOT NULL,
    record_key    text NOT NULL,
    fork_id       integer,
    area_id       integer
);
CREATE INDEX IF NOT EXISTS idx_audit_log_management_fork ON shared.audit_log_management (fork_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_management_area ON shared.audit_log_management (area_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_management_key  ON shared.audit_log_management (table_name, record_key);

COMMENT ON TABLE shared.audit_log_management IS
    'Links shared.audit_log rows written by shared.audit_row_trigger() to the planning row they describe. record_key holds the primary key column(s) named in the trigger arguments, joined by "/".';

-- Trigger arguments: the primary key column(s) of the table.
CREATE OR REPLACE FUNCTION shared.audit_row_trigger() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    v_old   jsonb := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END;
    v_new   jsonb := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END;
    v_row   jsonb := COALESCE(v_new, v_old);
    v_key   text;
    v_id    bigint;
    v_noise text[] := ARRAY['updated_at', 'updated_by'];
BEGIN
    IF TG_OP = 'UPDATE' AND (v_old - v_noise) = (v_new - v_noise) THEN
        RETURN NULL;
    END IF;

    SELECT string_agg(v_row ->> k, '/' ORDER BY ord)
      INTO v_key
      FROM unnest(TG_ARGV) WITH ORDINALITY AS a(k, ord);

    INSERT INTO shared.audit_log (field_name, old_value, new_value, change_reason,
                                  user_id, change_type, ip_address)
    VALUES ('*', v_old::text, v_new::text,
            NULLIF(current_setting('app.change_reason', true), ''),
            auth.uid()::text,
            CASE TG_OP WHEN 'UPDATE' THEN 'field_update' ELSE lower(TG_OP) END,
            inet_client_addr())
    RETURNING audit_log_id INTO v_id;

    INSERT INTO shared.audit_log_management (audit_log_id, table_name, record_key, fork_id, area_id)
    VALUES (v_id, TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, COALESCE(v_key, ''),
            (v_row ->> 'fork_id')::integer, (v_row ->> 'area_id')::integer);
    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION shared.audit_row_trigger() IS
    'AFTER INSERT/UPDATE/DELETE row trigger: one shared.audit_log row per changed row with the old and new row as JSON, linked in shared.audit_log_management. Arguments: primary key column(s).';

DO $$
DECLARE
    t record;
BEGIN
    FOR t IN SELECT * FROM (VALUES
        ('management', 'areas',                   'area_id'),
        ('management', 'forks',                   'fork_id'),
        ('management', 'features',                'feature_id'),
        ('management', 'thinning_trees',          'fork_id, tree_entity_id'),
        ('management', 'thinning_runs',           'fork_id'),
        ('shared',     'management_events',       'management_event_id'),
        ('shared',     'management_events_trees', 'management_event_id, tree_id')
    ) AS v(sch, tbl, pk) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trigger_%s_audit_row ON %I.%I', t.tbl, t.sch, t.tbl);
        EXECUTE format(
            'CREATE TRIGGER trigger_%s_audit_row AFTER INSERT OR UPDATE OR DELETE ON %I.%I '
            'FOR EACH ROW EXECUTE FUNCTION shared.audit_row_trigger(%s)',
            t.tbl, t.sch, t.tbl,
            (SELECT string_agg(quote_literal(trim(c)), ', ') FROM unnest(string_to_array(t.pk, ',')) c));
    END LOOP;
END $$;


-- -----------------------------------------------------------------------------
-- 3. Rights
-- -----------------------------------------------------------------------------
-- Same reach as shared.audit_log: own entries, curators all of them (planning
-- history is a team matter), service role everything.

ALTER TABLE shared.audit_log_management ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own management audit" ON shared.audit_log_management;
CREATE POLICY "Users can view their own management audit" ON shared.audit_log_management
    FOR SELECT TO authenticated
    USING (shared.is_curator() OR EXISTS (
        SELECT 1 FROM shared.audit_log a
         WHERE a.audit_log_id = audit_log_management.audit_log_id
           AND a.user_id = auth.uid()::text));
DROP POLICY IF EXISTS "Service role can manage management audit" ON shared.audit_log_management;
CREATE POLICY "Service role can manage management audit" ON shared.audit_log_management
    TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Curators can view management audit logs" ON shared.audit_log;
CREATE POLICY "Curators can view management audit logs" ON shared.audit_log
    FOR SELECT TO authenticated
    USING (shared.is_curator() AND field_name = '*');

GRANT SELECT ON shared.audit_log_management TO authenticated;
GRANT ALL ON shared.audit_log_management TO service_role;
