-- =============================================================================
-- Mirrored to docker/volumes/db/init/89-tree-changes-and-field-surveys.sql.
-- Tests: tests/automated/integration/migrations/89-tree-changes-and-field-surveys.test.sql
-- Not yet reviewed by the repo owner (twinfrontend, 2026-11-19).
-- =============================================================================
-- Changes to a tree between two inventories, and field surveys from QField
-- merged against them (three-way merge)
-- =============================================================================
-- 87-management-schema.sql left open how a change between two inventories
-- reaches the tree ("NOT HERE: applying a fork"). trees_variant_entity_key
-- allows one row per tree per variant, and v_trees_latest ranked rows by
-- measurement_date only, so an edit and a later inventory would silently
-- override each other.
--
-- Decided 2026-11-18 (twinfrontend):
--
--   * A measured row is never changed. Changes from the app are separate rows
--     in trees.tree_changes, one per tree and attribute, laid over the newest
--     measurement by trees.v_trees_current.
--   * The app writes two kinds: 'harvest' (applying a fork, tree_status_id ->
--     harvested, with shared.management_events) and 'correction' (species,
--     DBH, height, quality, position). No new trees.
--   * A change records the value its author saw (old_value). It is refused
--     when the tree no longer shows that value (optimistic check, the same
--     idea as the fork fingerprint in twinfrontend).
--   * QField takes the state it saw into the field (base_* in
--     field.tree_surveys). Import is a three-way merge per attribute of
--     base (seen in the field), current (DB before the import) and field value:
--
--       field = base                 -> keep current, an open change stays
--       field <> base, DB = base     -> take the field value
--       field <> base, DB <> base:
--           field = DB               -> take it, the change is 'confirmed'
--           DBH / height             -> take the field value (new measurement),
--                                       the change is 'superseded'
--           species, status, quality,
--           position                 -> 'conflict': the change stays in force
--                                       until a curator decides
--       tree found, but harvested    -> 'conflict'
--
--   * Conflicts are resolved by curators and admins
--     (trees.resolve_change_conflict). Contributors write changes.
--   * Harvested trees stay in field.v_trees_current, marked, so the crew
--     sees them and a find becomes a review case.
--   * New measurements come only from QField and from importers (e.g. laser
--     scans as a new variant), never from the app. Measured rows written by
--     an importer are settled against the changes by a deferred trigger
--     (section 6b), comparing with the value each change's author saw.
--
-- Port of field.tree_survey from the simple-postgres prototype
-- (qfield-forest-twin, sql/18-qfield-field.sql): insert-only, conflicts and
-- errors are recorded in the row instead of aborting the device sync.
-- Difference: the prototype compared a whole-row version and called any
-- change since packing a conflict; here the device sends the seen values and
-- the merge works per attribute.
--
-- NOT HERE: new trees from the field (re-identification, 85), linking a
-- survey to trees.observations / entity_matches, QField sign-in via Supabase,
-- SILVA baselines using corrected values.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS field;
GRANT USAGE ON SCHEMA field TO anon, authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 1. Changes
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS trees.tree_changes (
    change_id            bigserial PRIMARY KEY,
    tree_entity_id       uuid NOT NULL,
    location_id          integer NOT NULL
                         REFERENCES shared.locations (location_id) ON DELETE CASCADE,
    -- the measured row that was current when the change was made
    base_tree_id         integer REFERENCES trees.trees (tree_id) ON DELETE SET NULL,
    attribute            text NOT NULL CHECK (attribute IN
                         ('species_id', 'dbh_cm', 'height_m', 'tree_status_id',
                          'quality_rvr', 'position')),
    old_value            jsonb,
    new_value            jsonb NOT NULL CHECK (new_value <> 'null'::jsonb),
    kind                 text NOT NULL CHECK (kind IN ('correction', 'harvest')),
    source               text NOT NULL DEFAULT 'app' CHECK (source IN ('app', 'qfield')),
    event_date           date NOT NULL,
    fork_id              integer REFERENCES management.forks (fork_id) ON DELETE SET NULL,
    management_event_id  integer REFERENCES shared.management_events (management_event_id)
                         ON DELETE SET NULL,
    -- active     in force
    -- conflict   in force, contested by a field survey, waits for a curator
    -- confirmed  a field survey measured the same value
    -- superseded a field survey measured a new value (DBH, height)
    -- replaced   a later change of the same attribute
    -- rejected   a curator decided for the field survey
    state                text NOT NULL DEFAULT 'active' CHECK (state IN
                         ('active', 'conflict', 'confirmed', 'superseded', 'replaced', 'rejected')),
    state_note           text,
    survey_uuid          uuid,
    created_at           timestamptz NOT NULL DEFAULT now(),
    created_by           varchar(200),
    resolved_at          timestamptz,
    resolved_by          varchar(200),
    CONSTRAINT tree_changes_harvest_is_status
        CHECK (kind <> 'harvest' OR attribute = 'tree_status_id')
);

-- At most one change in force per tree and attribute
CREATE UNIQUE INDEX IF NOT EXISTS tree_changes_one_open
    ON trees.tree_changes (tree_entity_id, attribute)
    WHERE state IN ('active', 'conflict');
CREATE INDEX IF NOT EXISTS idx_tree_changes_state ON trees.tree_changes (state);
CREATE INDEX IF NOT EXISTS idx_tree_changes_fork  ON trees.tree_changes (fork_id);

COMMENT ON TABLE trees.tree_changes IS
    'Changes to a tree between two inventories (harvest, corrections), one row per tree and attribute. Measured rows stay untouched; trees.v_trees_current lays the changes in force (active, conflict) over the newest measurement.';
COMMENT ON COLUMN trees.tree_changes.old_value IS
    'The value the author saw. Written only if the tree still showed it (optimistic check).';


-- -----------------------------------------------------------------------------
-- 2. Current state
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW trees.v_trees_current WITH (security_invoker = on) AS
WITH newest AS (
    SELECT DISTINCT ON (COALESCE(t.tree_entity_id::text, t.tree_id::text))
           t.tree_id
      FROM trees.trees t
      JOIN shared.variant_types vt ON vt.variant_type_id = t.variant_type_id
      LEFT JOIN shared.variants v ON v.variant_id = t.variant_id
     WHERE vt.variant_type_name NOT IN ('simulated_growth', 'model_output', 'user_input')
     ORDER BY COALESCE(t.tree_entity_id::text, t.tree_id::text),
              t.measurement_date DESC NULLS LAST,
              v.sort_order DESC NULLS LAST,
              t.tree_id DESC
), open_changes AS (
    SELECT c.tree_entity_id,
           max(c.new_value #>> '{}') FILTER (WHERE c.attribute = 'species_id')     AS species_id,
           max(c.new_value #>> '{}') FILTER (WHERE c.attribute = 'dbh_cm')         AS dbh_cm,
           max(c.new_value #>> '{}') FILTER (WHERE c.attribute = 'height_m')       AS height_m,
           max(c.new_value #>> '{}') FILTER (WHERE c.attribute = 'tree_status_id') AS tree_status_id,
           max(c.new_value #>> '{}') FILTER (WHERE c.attribute = 'quality_rvr')    AS quality_rvr,
           max(c.new_value::text)    FILTER (WHERE c.attribute = 'position')       AS position_geojson,
           bool_or(c.state = 'conflict')                                           AS has_conflict,
           array_agg(c.attribute ORDER BY c.attribute)                             AS changed
      FROM trees.tree_changes c
     WHERE c.state IN ('active', 'conflict')
     GROUP BY c.tree_entity_id
), cur AS (
    SELECT t.tree_id,
           t.tree_entity_id,
           t.variant_id,
           t.measurement_date,
           COALESCE(oc.species_id::integer, t.species_id)                AS species_id,
           COALESCE(oc.dbh_cm::numeric, s.dbh_cm)::numeric(6,2)          AS dbh_cm,
           COALESCE(extensions.st_setsrid(extensions.st_geomfromgeojson(oc.position_geojson), 4326),
                    t."position")                                        AS "position",
           t.location_id,
           COALESCE(oc.height_m::numeric, t.height_m)::numeric(6,2)      AS height_m,
           COALESCE(oc.tree_status_id::integer, t.tree_status_id)        AS tree_status_id,
           COALESCE(oc.quality_rvr, t.quality_rvr::text)::character(1)   AS quality_rvr,
           COALESCE(oc.has_conflict, false)                              AS has_open_conflict,
           COALESCE(oc.changed, '{}'::text[])                            AS changed_attributes
      FROM newest n
      JOIN trees.trees t ON t.tree_id = n.tree_id
      LEFT JOIN trees.stems s ON s.tree_id = t.tree_id AND s.stem_number = 1
      LEFT JOIN open_changes oc ON oc.tree_entity_id = t.tree_entity_id
)
SELECT c.tree_id,
       c.tree_entity_id,
       c.variant_id,
       c.measurement_date,
       sp.scientific_name,
       c.species_id,
       c.dbh_cm,
       extensions.st_x(c."position") AS longitude,
       extensions.st_y(c."position") AS latitude,
       c.location_id,
       l.location_name,
       c.height_m,
       c.tree_status_id,
       c.quality_rvr,
       c."position",
       ts.tree_status_name,
       (ts.tree_status_name = 'harvested') IS TRUE AS is_harvested,
       c.has_open_conflict,
       c.changed_attributes
  FROM cur c
  LEFT JOIN shared.species sp ON sp.species_id = c.species_id
  LEFT JOIN shared.locations l ON l.location_id = c.location_id
  LEFT JOIN trees.tree_status ts ON ts.tree_status_id = c.tree_status_id;

COMMENT ON VIEW trees.v_trees_current IS
    'Current state of every tree, harvested ones included: the newest measured row, with the changes in force from trees.tree_changes laid over it per attribute. tree_id is the measured row the changes rest on.';

-- Same columns as before (88), now on top of v_trees_current
CREATE OR REPLACE VIEW trees.v_trees_latest WITH (security_invoker = on) AS
SELECT tree_id, tree_entity_id, variant_id, measurement_date, scientific_name,
       species_id, dbh_cm, longitude, latitude, location_id, location_name,
       height_m, tree_status_id, quality_rvr
  FROM trees.v_trees_current
 WHERE NOT is_harvested;

COMMENT ON VIEW trees.v_trees_latest IS
    'Current state without harvested trees: trees.v_trees_current minus harvested. Simulated, model and XR-edited rows do not count as measured; changes in trees.tree_changes do.';


-- -----------------------------------------------------------------------------
-- 3. Helpers
-- -----------------------------------------------------------------------------

-- An attribute of the current state as jsonb, the form old_value/new_value use
CREATE OR REPLACE FUNCTION trees.tree_attr(c trees.v_trees_current, p_attr text)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_attr
        WHEN 'species_id'     THEN to_jsonb(c.species_id)
        WHEN 'dbh_cm'         THEN to_jsonb(c.dbh_cm)
        WHEN 'height_m'       THEN to_jsonb(c.height_m)
        WHEN 'tree_status_id' THEN to_jsonb(c.tree_status_id)
        WHEN 'quality_rvr'    THEN to_jsonb(c.quality_rvr::text)
        WHEN 'position'       THEN extensions.st_asgeojson(c."position")::jsonb
    END;
$$;

-- Position tolerance of the merge: closer than this counts as the same place
CREATE OR REPLACE FUNCTION trees.position_tolerance_m() RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$ SELECT 0.5 $$;

-- Same value? Numbers compare as numbers (30 = 30.0), positions within tolerance
CREATE OR REPLACE FUNCTION trees.tree_attr_equal(p_attr text, a jsonb, b jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN a IS NULL OR a = 'null'::jsonb OR b IS NULL OR b = 'null'::jsonb
            THEN COALESCE(a, 'null'::jsonb) = COALESCE(b, 'null'::jsonb)
        WHEN p_attr = 'position'
            THEN extensions.st_distancesphere(
                     extensions.st_setsrid(extensions.st_geomfromgeojson(a::text), 4326),
                     extensions.st_setsrid(extensions.st_geomfromgeojson(b::text), 4326))
                 <= trees.position_tolerance_m()
        ELSE a = b
    END;
$$;

-- Who may write is decided by the JWT alone. twinfrontend connects as
-- authenticator and sets the signed-in user's claims, like PostgREST; a direct
-- session without claims (postgres, supabase_admin) may not write changes.
-- Importers do not need to: their measured rows are settled by the trigger in
-- section 6b.

-- May the caller write changes? Contributors and the service role.
CREATE OR REPLACE FUNCTION trees.may_write_tree_changes() RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT shared.is_contributor()
        OR COALESCE(auth.role() = 'service_role', false);
$$;

-- May the caller resolve conflicts? Curators, admins and the service role.
CREATE OR REPLACE FUNCTION trees.may_resolve_tree_changes() RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT shared.is_curator()
        OR COALESCE(auth.role() = 'service_role', false);
$$;


-- -----------------------------------------------------------------------------
-- 4. Corrections from the app
-- -----------------------------------------------------------------------------
-- p_changes: {"species_id": {"old": 12, "new": 7}, "dbh_cm": {"old": 30.5, "new": 35}}
-- "old" is what the user saw. Positions as GeoJSON.

CREATE OR REPLACE FUNCTION trees.record_corrections(
    p_tree_entity_id uuid,
    p_changes        jsonb,
    p_event_date     date DEFAULT current_date,
    p_entered_by     text DEFAULT NULL)
RETURNS SETOF trees.tree_changes
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, extensions AS $$
DECLARE
    cur trees.v_trees_current;
    who text := COALESCE(auth.uid()::text, p_entered_by, 'system');
    k   text;
    v   jsonb;
    oc  trees.tree_changes;
BEGIN
    IF NOT trees.may_write_tree_changes() THEN
        RAISE EXCEPTION 'Keine Berechtigung, Bäume zu ändern.' USING ERRCODE = '42501';
    END IF;
    -- One writer per tree at a time
    PERFORM pg_advisory_xact_lock(hashtextextended(p_tree_entity_id::text, 89));

    SELECT * INTO cur FROM trees.v_trees_current WHERE tree_entity_id = p_tree_entity_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Baum % ist unbekannt.', p_tree_entity_id;
    END IF;

    FOR k, v IN SELECT key, value FROM jsonb_each(p_changes) LOOP
        IF k NOT IN ('species_id', 'dbh_cm', 'height_m', 'quality_rvr', 'position') THEN
            RAISE EXCEPTION 'Attribut % lässt sich nicht korrigieren.', k;
        END IF;
        IF NOT trees.tree_attr_equal(k, trees.tree_attr(cur, k), v -> 'old') THEN
            RAISE EXCEPTION 'Baum % wurde inzwischen geändert (%): angezeigt %, aktuell %.',
                  p_tree_entity_id, k, v -> 'old', trees.tree_attr(cur, k)
                  USING ERRCODE = '40001';
        END IF;
        IF trees.tree_attr_equal(k, v -> 'old', v -> 'new') THEN
            CONTINUE;
        END IF;

        SELECT * INTO oc FROM trees.tree_changes
         WHERE tree_entity_id = p_tree_entity_id AND attribute = k
           AND state IN ('active', 'conflict');
        IF FOUND THEN
            IF oc.state = 'conflict' AND NOT trees.may_resolve_tree_changes() THEN
                RAISE EXCEPTION 'Zu % von Baum % ist ein Konflikt offen; den löst ein Curator.',
                      k, p_tree_entity_id USING ERRCODE = '42501';
            END IF;
            UPDATE trees.tree_changes
               SET state = 'replaced', resolved_at = now(), resolved_by = who
             WHERE change_id = oc.change_id;
        END IF;

        RETURN QUERY
        INSERT INTO trees.tree_changes
               (tree_entity_id, location_id, base_tree_id, attribute, old_value, new_value,
                kind, source, event_date, created_by)
        VALUES (p_tree_entity_id, cur.location_id, cur.tree_id, k, v -> 'old', v -> 'new',
                'correction', 'app', p_event_date, who)
        RETURNING *;
    END LOOP;
END;
$$;


-- -----------------------------------------------------------------------------
-- 5. Applying a fork: the harvest
-- -----------------------------------------------------------------------------
-- Same selection as the prototype (archive/simple-db-writes/apply_fork.R):
-- removals of the thinning first, then skid roads (half the road width),
-- windthrow and biotic areas; crop trees are never taken. Per tree one
-- shared.management_events_trees row and one 'harvest' change.

CREATE OR REPLACE FUNCTION management.apply_fork(
    p_fork_id    integer,
    p_event_date date DEFAULT current_date,
    p_entered_by text DEFAULT NULL)
RETURNS TABLE (harvest_cause text, n_trees integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, extensions AS $$
DECLARE
    f        record;
    who      text := COALESCE(auth.uid()::text, p_entered_by, 'system');
    ev_id    integer;
    harv_id  integer;
BEGIN
    SELECT fk.fork_id, fk.is_committed, fk.description, a.location_id
      INTO f
      FROM management.forks fk JOIN management.areas a ON a.area_id = fk.area_id
     WHERE fk.fork_id = p_fork_id
       FOR UPDATE OF fk;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fork #% existiert nicht.', p_fork_id;
    END IF;
    IF NOT (management.can_edit_fork(p_fork_id) OR trees.may_resolve_tree_changes()) THEN
        RAISE EXCEPTION 'Keine Berechtigung, Fork #% anzuwenden.', p_fork_id USING ERRCODE = '42501';
    END IF;
    IF f.is_committed THEN
        RAISE EXCEPTION 'Fork #% wurde bereits angewandt.', p_fork_id;
    END IF;

    SELECT tree_status_id INTO harv_id FROM trees.tree_status WHERE tree_status_name = 'harvested';

    INSERT INTO shared.management_events
           (location_id, event_type, event_date, description, performed_by, created_by)
    VALUES (f.location_id, 'harvesting', p_event_date,
            'Fork #' || p_fork_id || COALESCE(': ' || f.description, ''), who, who)
    RETURNING management_event_id INTO ev_id;

    DROP TABLE IF EXISTS _harvest;
    CREATE TEMP TABLE _harvest ON COMMIT DROP AS
    WITH cand AS (
        SELECT tt.tree_entity_id, 'planned'::text AS cause, 1 AS prio
          FROM management.thinning_trees tt
         WHERE tt.fork_id = p_fork_id AND tt.role = 'removal'
        UNION ALL
        SELECT c.tree_entity_id,
               CASE ft.feature_type_id WHEN 1 THEN 'skid_road' WHEN 2 THEN 'windthrow' ELSE 'biotic' END,
               1 + ft.feature_type_id
          FROM management.features ft
          JOIN trees.v_trees_current c
            ON c.location_id = f.location_id
           AND CASE WHEN ft.feature_type_id = 1
                    THEN st_dwithin(c."position"::geography, ft.geom::geography,
                                    COALESCE(ft.skid_width_m, 0) / 2.0)
                    ELSE st_within(c."position", ft.geom) END
         WHERE ft.fork_id = p_fork_id AND ft.feature_type_id IN (1, 2, 3)
    ), pick AS (
        SELECT DISTINCT ON (cand.tree_entity_id) cand.tree_entity_id, cand.cause
          FROM cand
         WHERE cand.tree_entity_id NOT IN (
                   SELECT z.tree_entity_id FROM management.thinning_trees z
                    WHERE z.fork_id = p_fork_id AND z.role = 'z')
         ORDER BY cand.tree_entity_id, cand.prio
    )
    SELECT p.tree_entity_id, p.cause, c.tree_id, c.tree_status_id, c.location_id
      FROM pick p
      JOIN trees.v_trees_current c ON c.tree_entity_id = p.tree_entity_id
     WHERE NOT c.is_harvested
       AND NOT EXISTS (SELECT 1 FROM trees.tree_changes oc
                        WHERE oc.tree_entity_id = p.tree_entity_id
                          AND oc.attribute = 'tree_status_id'
                          AND oc.state IN ('active', 'conflict'));

    INSERT INTO shared.management_events_trees (management_event_id, tree_id, harvest_cause, fork_id)
    SELECT ev_id, h.tree_id, h.cause, p_fork_id FROM _harvest h;

    INSERT INTO trees.tree_changes
           (tree_entity_id, location_id, base_tree_id, attribute, old_value, new_value,
            kind, source, event_date, fork_id, management_event_id, created_by)
    SELECT h.tree_entity_id, h.location_id, h.tree_id, 'tree_status_id',
           to_jsonb(h.tree_status_id), to_jsonb(harv_id),
           'harvest', 'app', p_event_date, p_fork_id, ev_id, who
      FROM _harvest h;

    UPDATE management.forks SET is_committed = true WHERE fork_id = p_fork_id;

    RETURN QUERY SELECT h.cause, count(*)::integer FROM _harvest h GROUP BY h.cause ORDER BY 1;
END;
$$;


-- -----------------------------------------------------------------------------
-- 6. Field surveys (QField)
-- -----------------------------------------------------------------------------
-- Insert-only on the device. No CHECK constraints on the values: a refused
-- row would block the device sync. The trigger validates and records
-- problems in state/message.

CREATE TABLE IF NOT EXISTS field.tree_surveys (
    survey_uuid          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- 'erhebung' = new measurement, 'korrektur' = fixes the seen state
    mode                 text NOT NULL DEFAULT 'erhebung',
    tree_entity_id       uuid,
    campaign_id          integer,
    -- state the device saw (from field.v_trees_current at packing time)
    base_tree_id         integer,
    base_species_id      integer,
    base_dbh_cm          numeric(6,2),
    base_height_m        numeric(6,2),
    base_tree_status_id  integer,
    base_quality_rvr     character(1),
    base_position        extensions.geometry(Point, 4326),
    -- surveyed values; NULL = not surveyed
    species_id           integer,
    dbh_cm               numeric(6,2),
    height_m             numeric(6,2),
    tree_status_id       integer,
    quality_rvr          character(1),
    "position"           extensions.geometry(Point, 4326),
    field_notes          text,
    surveyed_at          timestamptz NOT NULL DEFAULT now(),
    surveyed_by          varchar(200),
    device               text,
    -- set by the trigger only: 'uebernommen' | 'konflikt' | 'fehler'
    state                text,
    message              text,
    result_tree_id       integer,
    processed_at         timestamptz
);

CREATE INDEX IF NOT EXISTS idx_tree_surveys_entity ON field.tree_surveys (tree_entity_id);
CREATE INDEX IF NOT EXISTS idx_tree_surveys_state  ON field.tree_surveys (state);

COMMENT ON TABLE field.tree_surveys IS
    'Tree surveys from QField, insert-only. A trigger merges each row three-way (seen base_*, current DB state, surveyed value) and records the outcome in state/message/result_tree_id.';


-- Surveyed value as jsonb; NULL (not surveyed) means "as seen"
CREATE OR REPLACE FUNCTION field.survey_attr(s field.tree_surveys, p_attr text, p_base boolean)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_base THEN
        CASE p_attr
            WHEN 'species_id'     THEN to_jsonb(s.base_species_id)
            WHEN 'dbh_cm'         THEN to_jsonb(s.base_dbh_cm)
            WHEN 'height_m'       THEN to_jsonb(s.base_height_m)
            WHEN 'tree_status_id' THEN to_jsonb(s.base_tree_status_id)
            WHEN 'quality_rvr'    THEN to_jsonb(s.base_quality_rvr::text)
            WHEN 'position'       THEN extensions.st_asgeojson(s.base_position)::jsonb
        END
    ELSE
        CASE p_attr
            WHEN 'species_id'     THEN COALESCE(to_jsonb(s.species_id),           to_jsonb(s.base_species_id))
            WHEN 'dbh_cm'         THEN COALESCE(to_jsonb(s.dbh_cm),               to_jsonb(s.base_dbh_cm))
            WHEN 'height_m'       THEN COALESCE(to_jsonb(s.height_m),             to_jsonb(s.base_height_m))
            WHEN 'tree_status_id' THEN COALESCE(to_jsonb(s.tree_status_id),       to_jsonb(s.base_tree_status_id))
            WHEN 'quality_rvr'    THEN COALESCE(to_jsonb(s.quality_rvr::text),    to_jsonb(s.base_quality_rvr::text))
            WHEN 'position'       THEN COALESCE(extensions.st_asgeojson(s."position")::jsonb,
                                                extensions.st_asgeojson(s.base_position)::jsonb)
        END
    END;
$$;


CREATE OR REPLACE FUNCTION field.apply_tree_survey() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, extensions AS $$
DECLARE
    attrs     text[] := ARRAY['species_id', 'dbh_cm', 'height_m', 'tree_status_id', 'quality_rvr', 'position'];
    a         text;
    cur       trees.v_trees_current;
    m         trees.trees;
    m_dbh     numeric;
    oc        trees.tree_changes;
    base_j    jsonb;
    field_j   jsonb;
    cur_j     jsonb;
    meas_j    jsonb;
    out_vals  jsonb := '{}'::jsonb;
    conflicts text[] := '{}';
    notes     text[] := '{}';
    who       text;
    camp      shared.campaigns;
    var_id    integer;
    scen_id   integer;
    row_id    integer;
    f_status  text;
BEGIN
    NEW.state := NULL; NEW.message := NULL; NEW.result_tree_id := NULL;
    NEW.processed_at := now();
    who := COALESCE(auth.uid()::text, NEW.surveyed_by, 'system');
    NEW.surveyed_by := who;

    BEGIN
        IF NEW.mode NOT IN ('erhebung', 'korrektur') THEN
            RAISE EXCEPTION 'Unbekannter Modus %.', NEW.mode;
        END IF;
        IF NEW.dbh_cm IS NOT NULL AND NEW.dbh_cm <= 0 THEN
            RAISE EXCEPTION 'BHD % ist unzulässig.', NEW.dbh_cm;
        END IF;
        IF NEW.height_m IS NOT NULL AND (NEW.height_m <= 0 OR NEW.height_m > 200) THEN
            RAISE EXCEPTION 'Höhe % ist unzulässig.', NEW.height_m;
        END IF;

        PERFORM pg_advisory_xact_lock(hashtextextended(NEW.tree_entity_id::text, 89));
        SELECT * INTO cur FROM trees.v_trees_current WHERE tree_entity_id = NEW.tree_entity_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Baum % ist unbekannt (neue Bäume laufen über die Zuordnung).', NEW.tree_entity_id;
        END IF;
        SELECT * INTO m FROM trees.trees WHERE tree_id = cur.tree_id;
        SELECT s.dbh_cm INTO m_dbh FROM trees.stems s WHERE s.tree_id = m.tree_id AND s.stem_number = 1;

        FOREACH a IN ARRAY attrs LOOP
            base_j  := field.survey_attr(NEW, a, true);
            field_j := field.survey_attr(NEW, a, false);
            cur_j   := trees.tree_attr(cur, a);
            meas_j  := CASE a
                WHEN 'species_id'     THEN to_jsonb(m.species_id)
                WHEN 'dbh_cm'         THEN to_jsonb(m_dbh)
                WHEN 'height_m'       THEN to_jsonb(m.height_m)
                WHEN 'tree_status_id' THEN to_jsonb(m.tree_status_id)
                WHEN 'quality_rvr'    THEN to_jsonb(m.quality_rvr::text)
                WHEN 'position'       THEN st_asgeojson(m."position")::jsonb
            END;
            SELECT * INTO oc FROM trees.tree_changes
             WHERE tree_entity_id = NEW.tree_entity_id AND attribute = a
               AND state IN ('active', 'conflict');

            IF NEW.mode = 'korrektur' THEN
                -- Field fixes the seen state: becomes a change like one from the app
                IF NOT trees.tree_attr_equal(a, field_j, base_j) THEN
                    IF NOT trees.tree_attr_equal(a, cur_j, base_j)
                       AND NOT trees.tree_attr_equal(a, field_j, cur_j) THEN
                        conflicts := conflicts || a;
                        IF oc.change_id IS NOT NULL THEN
                            UPDATE trees.tree_changes SET state = 'conflict', survey_uuid = NEW.survey_uuid
                             WHERE change_id = oc.change_id;
                        END IF;
                    ELSIF NOT trees.tree_attr_equal(a, field_j, cur_j) THEN
                        IF oc.change_id IS NOT NULL THEN
                            UPDATE trees.tree_changes
                               SET state = 'replaced', resolved_at = now(), resolved_by = who
                             WHERE change_id = oc.change_id;
                        END IF;
                        INSERT INTO trees.tree_changes
                               (tree_entity_id, location_id, base_tree_id, attribute, old_value, new_value,
                                kind, source, event_date, survey_uuid, created_by)
                        VALUES (NEW.tree_entity_id, cur.location_id, cur.tree_id, a, base_j, field_j,
                                'correction', 'qfield', NEW.surveyed_at::date, NEW.survey_uuid, who);
                    END IF;
                END IF;
                CONTINUE;
            END IF;

            -- mode 'erhebung': three-way merge, out_vals = value of the new measured row
            IF a = 'tree_status_id' AND oc.kind = 'harvest' THEN
                -- The tree was found. Only "harvested" or "missing" fits the harvest.
                SELECT tree_status_name INTO f_status FROM trees.tree_status
                 WHERE tree_status_id = (field_j #>> '{}')::integer;
                IF f_status IN ('harvested', 'missing') THEN
                    UPDATE trees.tree_changes SET state = 'confirmed', survey_uuid = NEW.survey_uuid,
                           resolved_at = now(), resolved_by = who
                     WHERE change_id = oc.change_id;
                ELSE
                    UPDATE trees.tree_changes SET state = 'conflict', survey_uuid = NEW.survey_uuid,
                           state_note = 'Als geerntet geführt, im Feld aufgenommen'
                     WHERE change_id = oc.change_id;
                    conflicts := conflicts || a;
                END IF;
                out_vals := out_vals || jsonb_build_object(a, field_j);
            ELSIF trees.tree_attr_equal(a, field_j, base_j) THEN
                out_vals := out_vals || jsonb_build_object(a, meas_j);
            ELSIF trees.tree_attr_equal(a, cur_j, base_j) THEN
                out_vals := out_vals || jsonb_build_object(a, field_j);
            ELSIF trees.tree_attr_equal(a, field_j, cur_j) THEN
                out_vals := out_vals || jsonb_build_object(a, field_j);
                IF oc.change_id IS NOT NULL THEN
                    UPDATE trees.tree_changes SET state = 'confirmed', survey_uuid = NEW.survey_uuid,
                           resolved_at = now(), resolved_by = who
                     WHERE change_id = oc.change_id;
                END IF;
            ELSIF a IN ('dbh_cm', 'height_m') THEN
                out_vals := out_vals || jsonb_build_object(a, field_j);
                IF oc.change_id IS NOT NULL THEN
                    UPDATE trees.tree_changes SET state = 'superseded', survey_uuid = NEW.survey_uuid,
                           resolved_at = now(), resolved_by = who
                     WHERE change_id = oc.change_id;
                    notes := notes || a;
                END IF;
            ELSE
                out_vals := out_vals || jsonb_build_object(a, field_j);
                conflicts := conflicts || a;
                IF oc.change_id IS NOT NULL THEN
                    UPDATE trees.tree_changes SET state = 'conflict', survey_uuid = NEW.survey_uuid
                     WHERE change_id = oc.change_id;
                END IF;
            END IF;
        END LOOP;

        IF NEW.mode = 'erhebung' THEN
            IF NEW.campaign_id IS NULL THEN
                RAISE EXCEPTION 'Erhebung ohne Kampagne.';
            END IF;
            SELECT * INTO camp FROM shared.campaigns WHERE campaign_id = NEW.campaign_id;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Kampagne % existiert nicht.', NEW.campaign_id;
            END IF;

            -- One variant per campaign and site, created on the first survey
            scen_id := COALESCE(m.scenario_id,
                                (SELECT v.scenario_id FROM shared.variants v WHERE v.variant_id = m.variant_id));
            SELECT v.variant_id INTO var_id FROM shared.variants v
             WHERE v.location_id = m.location_id AND v.scenario_id = scen_id
               AND v.variant_name = camp.campaign_name;
            IF var_id IS NULL THEN
                INSERT INTO shared.variants
                       (location_id, scenario_id, variant_type_id, variant_name, simulation_year,
                        sort_order, parent_variant_id, description)
                SELECT m.location_id, scen_id, vt.variant_type_id, camp.campaign_name,
                       extract(year FROM NEW.surveyed_at)::integer,
                       COALESCE((SELECT max(v.sort_order) + 1 FROM shared.variants v
                                  WHERE v.location_id = m.location_id AND v.scenario_id = scen_id), 0),
                       m.variant_id,
                       'Feldaufnahme (QField), Kampagne ' || camp.campaign_name
                  FROM shared.variant_types vt WHERE vt.variant_type_name = 'repeat_measurement'
                RETURNING variant_id INTO var_id;
            END IF;

            SELECT t.tree_id INTO row_id FROM trees.trees t
             WHERE t.variant_id = var_id AND t.tree_entity_id = NEW.tree_entity_id;

            IF row_id IS NULL THEN
                INSERT INTO trees.trees
                       (tree_entity_id, variant_id, parent_tree_id, campaign_id, location_id, plot_id,
                        scenario_id, variant_type_id, species_id, tree_status_id, measurement_date,
                        data_source_type_id, height_m, crown_width_m, crown_base_height_m, "position",
                        tree_number, source_tree_id, field_notes, quality_rvr, source_attributes, created_by)
                SELECT NEW.tree_entity_id, var_id, m.tree_id, NEW.campaign_id, m.location_id, m.plot_id,
                       scen_id, v.variant_type_id,
                       (out_vals ->> 'species_id')::integer,
                       (out_vals ->> 'tree_status_id')::integer,
                       NEW.surveyed_at::date,
                       (SELECT d.data_source_type_id FROM trees.data_source_types d
                         WHERE d.data_source_type_name = 'field'),
                       (out_vals ->> 'height_m')::numeric,
                       m.crown_width_m, m.crown_base_height_m,
                       st_setsrid(st_geomfromgeojson(out_vals ->> 'position'), 4326),
                       m.tree_number, m.source_tree_id, NEW.field_notes,
                       (out_vals ->> 'quality_rvr')::character(1),
                       jsonb_build_object('survey_uuid', NEW.survey_uuid, 'device', NEW.device),
                       who
                  FROM shared.variants v WHERE v.variant_id = var_id
                RETURNING tree_id INTO row_id;
                INSERT INTO trees.stems (tree_id, stem_number, dbh_cm)
                VALUES (row_id, 1, (out_vals ->> 'dbh_cm')::numeric);
            ELSE
                -- Second survey of the tree in the same campaign: replaces the first
                UPDATE trees.trees
                   SET species_id      = (out_vals ->> 'species_id')::integer,
                       tree_status_id  = (out_vals ->> 'tree_status_id')::integer,
                       height_m        = (out_vals ->> 'height_m')::numeric,
                       "position"      = st_setsrid(st_geomfromgeojson(out_vals ->> 'position'), 4326),
                       quality_rvr     = (out_vals ->> 'quality_rvr')::character(1),
                       measurement_date = NEW.surveyed_at::date,
                       field_notes     = NEW.field_notes,
                       source_attributes = jsonb_build_object('survey_uuid', NEW.survey_uuid, 'device', NEW.device)
                 WHERE tree_id = row_id;
                UPDATE trees.stems SET dbh_cm = (out_vals ->> 'dbh_cm')::numeric
                 WHERE tree_id = row_id AND stem_number = 1;
                notes := notes || 'zweite Erhebung im selben Durchgang'::text;
            END IF;
            NEW.result_tree_id := row_id;
        END IF;

        IF cardinality(conflicts) > 0 THEN
            NEW.state := 'konflikt';
            NEW.message := 'Prüfen: ' || array_to_string(conflicts, ', ')
                || ' weicht von einer Änderung seit dem Packen ab.';
        ELSE
            NEW.state := 'uebernommen';
            NEW.message := CASE WHEN cardinality(notes) > 0
                                THEN 'Abgelöst bzw. Hinweis: ' || array_to_string(notes, ', ') END;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NEW.state := 'fehler';
        NEW.message := SQLERRM;
        NEW.result_tree_id := NULL;
    END;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_tree_surveys_apply ON field.tree_surveys;
CREATE TRIGGER trigger_tree_surveys_apply BEFORE INSERT ON field.tree_surveys
    FOR EACH ROW EXECUTE FUNCTION field.apply_tree_survey();


-- What QField packs: current state incl. harvested trees, marked. The plugin
-- copies the attribute columns into base_* of a new survey.
CREATE OR REPLACE VIEW field.v_trees_current WITH (security_invoker = on) AS
SELECT c.tree_entity_id,
       COALESCE(t.source_tree_id, t.tree_number::text, c.tree_entity_id::text) AS tree_label,
       c.tree_id AS base_tree_id,
       c.species_id, c.scientific_name, c.dbh_cm, c.height_m,
       c.tree_status_id, c.tree_status_name, c.quality_rvr, c."position",
       c.is_harvested, c.has_open_conflict, c.location_id, c.location_name
  FROM trees.v_trees_current c
  JOIN trees.trees t ON t.tree_id = c.tree_id;

COMMENT ON VIEW field.v_trees_current IS
    'Trees for QField, harvested ones included and marked (is_harvested). The attribute columns are the base_* values of a survey.';


-- -----------------------------------------------------------------------------
-- 6b. New measurements from imports (laser scans, CSV, other tools)
-- -----------------------------------------------------------------------------
-- A new inventory arrives as new measured rows in a new variant. Changes hang
-- on the tree (tree_entity_id), not on a variant, so they would stay laid
-- over the new measurement. This trigger settles them for every importer,
-- without the importer knowing about tree_changes.
--
-- A scanner has seen no base, but every change carries the value its author
-- saw (old_value). That is the base of the three-way comparison:
--
--   new value missing (not measured)      -> change stays
--   new value = change value              -> 'confirmed'
--   new value = old_value (not touched,
--     e.g. species copied from a template) -> change stays
--   DBH / height, otherwise               -> 'superseded' (new measurement)
--   species, quality, position, otherwise -> 'conflict'
--   harvest, tree measured again          -> 'conflict', unless the row says
--                                            harvested or missing ('confirmed')
--
-- Only when the new row is now the newest measurement of the tree: a backfill
-- of an older inventory leaves the changes alone. QField surveys are skipped;
-- field.apply_tree_survey already merged them against the base the device saw.
-- Deferred to commit, so the stems (DBH) written after the tree row count.
-- NOT HERE: in-place corrections of measured rows (UPDATE, as in
-- scripts/import/import_tls_heights.py).

CREATE OR REPLACE FUNCTION trees.reconcile_changes_on_measurement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, extensions AS $$
DECLARE
    r        trees.trees;
    vt       text;
    cur_tid  integer;
    dbh      numeric;
    oc       trees.tree_changes;
    inc_j    jsonb;
    f_status text;
    verdict  text;
BEGIN
    SELECT * INTO r FROM trees.trees WHERE tree_id = NEW.tree_id;
    IF NOT FOUND OR r.tree_entity_id IS NULL
       OR COALESCE(r.source_attributes ? 'survey_uuid', false) THEN
        RETURN NULL;
    END IF;
    SELECT x.variant_type_name INTO vt FROM shared.variant_types x
     WHERE x.variant_type_id = r.variant_type_id;
    IF vt IN ('simulated_growth', 'model_output', 'user_input') THEN
        RETURN NULL;
    END IF;
    SELECT c.tree_id INTO cur_tid FROM trees.v_trees_current c
     WHERE c.tree_entity_id = r.tree_entity_id;
    IF cur_tid IS DISTINCT FROM r.tree_id THEN
        RETURN NULL;
    END IF;
    SELECT s.dbh_cm INTO dbh FROM trees.stems s WHERE s.tree_id = r.tree_id AND s.stem_number = 1;

    FOR oc IN SELECT * FROM trees.tree_changes c
               WHERE c.tree_entity_id = r.tree_entity_id
                 AND c.state IN ('active', 'conflict')
                 AND c.base_tree_id IS DISTINCT FROM r.tree_id
    LOOP
        verdict := NULL;
        IF oc.kind = 'harvest' THEN
            -- A new measured row means the tree was found
            SELECT tree_status_name INTO f_status FROM trees.tree_status
             WHERE tree_status_id = r.tree_status_id;
            verdict := CASE WHEN f_status IN ('harvested', 'missing') THEN 'confirmed' ELSE 'conflict' END;
        ELSE
            inc_j := CASE oc.attribute
                WHEN 'species_id'  THEN to_jsonb(r.species_id)
                WHEN 'dbh_cm'      THEN to_jsonb(dbh)
                WHEN 'height_m'    THEN to_jsonb(r.height_m)
                WHEN 'quality_rvr' THEN to_jsonb(r.quality_rvr::text)
                WHEN 'position'    THEN st_asgeojson(r."position")::jsonb
            END;
            IF inc_j IS NULL OR inc_j = 'null'::jsonb THEN
                verdict := NULL;
            ELSIF trees.tree_attr_equal(oc.attribute, inc_j, oc.new_value) THEN
                verdict := 'confirmed';
            ELSIF trees.tree_attr_equal(oc.attribute, inc_j, oc.old_value) THEN
                verdict := NULL;
            ELSIF oc.attribute IN ('dbh_cm', 'height_m') THEN
                verdict := 'superseded';
            ELSE
                verdict := 'conflict';
            END IF;
        END IF;

        IF verdict = 'conflict' THEN
            UPDATE trees.tree_changes
               SET state = 'conflict',
                   state_note = 'Neue Messung (Baum ' || r.tree_id || ', Variante ' || r.variant_id
                                || ') weicht ab'
             WHERE change_id = oc.change_id;
        ELSIF verdict IN ('confirmed', 'superseded') THEN
            UPDATE trees.tree_changes
               SET state = verdict, resolved_at = now(), resolved_by = 'system',
                   state_note = 'Neue Messung (Baum ' || r.tree_id || ', Variante ' || r.variant_id || ')'
             WHERE change_id = oc.change_id;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trigger_trees_reconcile_changes ON trees.trees;
CREATE CONSTRAINT TRIGGER trigger_trees_reconcile_changes
    AFTER INSERT ON trees.trees
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION trees.reconcile_changes_on_measurement();


-- -----------------------------------------------------------------------------
-- 7. Review list and resolving
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW trees.v_tree_change_conflicts WITH (security_invoker = on) AS
SELECT c.change_id, c.tree_entity_id, c.location_id, c.attribute, c.kind,
       c.old_value AS seen_by_change, c.new_value AS change_value,
       c.created_by AS changed_by, c.event_date, c.fork_id, c.state_note,
       s.survey_uuid, s.surveyed_at, s.surveyed_by,
       field.survey_attr(s, c.attribute, true)  AS seen_in_field,
       field.survey_attr(s, c.attribute, false) AS field_value
  FROM trees.tree_changes c
  LEFT JOIN field.tree_surveys s ON s.survey_uuid = c.survey_uuid
 WHERE c.state = 'conflict'
UNION ALL
-- Field survey contradicting another measurement (no change involved)
SELECT NULL, s.tree_entity_id, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, s.message,
       s.survey_uuid, s.surveyed_at, s.surveyed_by, NULL, NULL
  FROM field.tree_surveys s
 WHERE s.state = 'konflikt'
   AND NOT EXISTS (SELECT 1 FROM trees.tree_changes c
                    WHERE c.survey_uuid = s.survey_uuid AND c.state = 'conflict');

COMMENT ON VIEW trees.v_tree_change_conflicts IS
    'Review list: changes contested by a field survey, and surveys that contradict a newer measurement.';

-- Curator decides: keep the change (back to active) or follow the survey
CREATE OR REPLACE FUNCTION trees.resolve_change_conflict(
    p_change_id   bigint,
    p_keep_change boolean,
    p_note        text DEFAULT NULL,
    p_entered_by  text DEFAULT NULL)
RETURNS trees.tree_changes
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, extensions AS $$
DECLARE
    r trees.tree_changes;
BEGIN
    IF NOT trees.may_resolve_tree_changes() THEN
        RAISE EXCEPTION 'Konflikte lösen Curator und Admin.' USING ERRCODE = '42501';
    END IF;
    UPDATE trees.tree_changes
       SET state = CASE WHEN p_keep_change THEN 'active' ELSE 'rejected' END,
           state_note = COALESCE(p_note, state_note),
           resolved_at = now(),
           resolved_by = COALESCE(auth.uid()::text, p_entered_by, 'system')
     WHERE change_id = p_change_id AND state = 'conflict'
    RETURNING * INTO r;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Änderung % ist kein offener Konflikt.', p_change_id;
    END IF;
    RETURN r;
END;
$$;


-- -----------------------------------------------------------------------------
-- 8. Rights
-- -----------------------------------------------------------------------------
-- tree_changes: everyone reads, writes only through the functions above.
-- tree_surveys: contributors insert; nobody updates or deletes (insert-only).

ALTER TABLE trees.tree_changes  ENABLE ROW LEVEL SECURITY;
ALTER TABLE field.tree_surveys  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tree changes are viewable by everyone" ON trees.tree_changes;
CREATE POLICY "Tree changes are viewable by everyone" ON trees.tree_changes FOR SELECT USING (true);
DROP POLICY IF EXISTS "Dataset access level" ON trees.tree_changes;
CREATE POLICY "Dataset access level" ON trees.tree_changes AS RESTRICTIVE FOR SELECT
    USING ((SELECT NOT shared.has_restricted_campaigns())
           OR tree_entity_id NOT IN (SELECT shared.hidden_tree_entity_ids()));
DROP POLICY IF EXISTS "Service role can manage all tree changes" ON trees.tree_changes;
CREATE POLICY "Service role can manage all tree changes" ON trees.tree_changes
    TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Tree surveys are viewable by everyone" ON field.tree_surveys;
CREATE POLICY "Tree surveys are viewable by everyone" ON field.tree_surveys FOR SELECT USING (true);
DROP POLICY IF EXISTS "Contributors can create tree surveys" ON field.tree_surveys;
CREATE POLICY "Contributors can create tree surveys" ON field.tree_surveys
    FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
DROP POLICY IF EXISTS "Service role can manage all tree surveys" ON field.tree_surveys;
CREATE POLICY "Service role can manage all tree surveys" ON field.tree_surveys
    TO service_role USING (true) WITH CHECK (true);

GRANT SELECT ON trees.tree_changes, trees.v_trees_current, trees.v_tree_change_conflicts
    TO anon, authenticated;
GRANT ALL ON trees.tree_changes TO service_role;
GRANT SELECT, INSERT ON field.tree_surveys TO authenticated;
GRANT SELECT ON field.tree_surveys, field.v_trees_current TO anon, authenticated;
GRANT ALL ON field.tree_surveys TO service_role;

REVOKE ALL ON FUNCTION trees.record_corrections(uuid, jsonb, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION management.apply_fork(integer, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION trees.resolve_change_conflict(bigint, boolean, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trees.record_corrections(uuid, jsonb, date, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION management.apply_fork(integer, date, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION trees.resolve_change_conflict(bigint, boolean, text, text) TO authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 9. PostgREST
-- -----------------------------------------------------------------------------
-- PostgREST serves public only. The QField plugin signs in to Supabase and
-- uploads its surveys here with the user's token instead of through a
-- database connection; it reads the trees it packs from public.field_trees.
-- security_invoker, so the RLS above applies to the caller. An INSERT on the
-- single-table view reaches field.tree_surveys and fires its trigger.

CREATE OR REPLACE VIEW public.tree_surveys WITH (security_invoker = on) AS
    SELECT * FROM field.tree_surveys;
CREATE OR REPLACE VIEW public.field_trees WITH (security_invoker = on) AS
    SELECT * FROM field.v_trees_current;
CREATE OR REPLACE VIEW public.tree_changes WITH (security_invoker = on) AS
    SELECT * FROM trees.tree_changes;
CREATE OR REPLACE VIEW public.tree_change_conflicts WITH (security_invoker = on) AS
    SELECT * FROM trees.v_tree_change_conflicts;

GRANT SELECT ON public.tree_surveys, public.field_trees, public.tree_changes,
                public.tree_change_conflicts TO anon, authenticated;
GRANT INSERT ON public.tree_surveys TO authenticated;
GRANT ALL ON public.tree_surveys TO service_role;
