-- Mirrored from supabase/migrations/20261104130000_tree_reidentification.sql.
-- =============================================================================
-- Tree re-identification: one row per tree per variant, observations and
-- revisable entity matches
-- =============================================================================
-- XRFF-465 (re-identification module, paper section 5.1.3). Trees could not be
-- linked across campaigns: importers never set tree_entity_id, so a second
-- inventory of the same site would create new trees instead of re-measured
-- ones, and nothing recorded how a link was decided.
--
--   trees.trees              UNIQUE (variant_id, tree_entity_id): one physical
--                            tree appears at most once per forest state.
--                            silva-connector already relies on this (writeback
--                            joins stems on tree_entity_id within a variant);
--                            0 violations on dev, 2026-11-04.
--   trees.observations       new: one tree as detected or measured by one
--                            campaign, before or apart from an entity being
--                            assigned. A field tree's observation points at
--                            its tree row; a LiDAR detection carries its
--                            point cloud and instance id.
--   trees.entity_matches     new: the decision linking an observation to a
--                            physical tree (tree_entity_id): method, score,
--                            decision (matched | new | ambiguous), who decided
--                            and when, the campaign matched against. A
--                            revision is a new row that supersedes the old
--                            one; superseded rows are kept. Per observation
--                            the rows form one chain, so exactly one is
--                            current: public.current_entity_matches.
--
-- The matching itself (gate on position, score on species and plausible
-- growth, one-to-one assignment) runs outside the database; this stores the
-- result. Backfilling ECOSENSE and Mathislewald with decision 'new' needs
-- their campaigns first (XRFF-478) and is not part of this migration.
--
-- Access: both tables get the XRFF-625 policies. Observations are scoped by
-- their campaign; a match is hidden whenever its observation is.
--
-- Additive only. Mirrored to init 85-tree-reidentification.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. One row per physical tree per forest state
-- -----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS trees_variant_entity_key
    ON trees.trees (variant_id, tree_entity_id);

COMMENT ON COLUMN trees.trees.tree_entity_id IS
    'Persistent UUID identifying the physical tree across all variants. Unique within a variant (trees_variant_entity_key). How an entity was assigned across campaigns is recorded in trees.entity_matches.';


-- -----------------------------------------------------------------------------
-- 2. Observations
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS trees.observations (
    observation_id          bigserial PRIMARY KEY,
    location_id             integer NOT NULL REFERENCES shared.locations (location_id) ON DELETE CASCADE,
    campaign_id             integer NOT NULL REFERENCES shared.campaigns (campaign_id) ON DELETE RESTRICT,
    process_id              integer REFERENCES shared.processes (process_id) ON DELETE SET NULL,
    tree_id                 integer REFERENCES trees.trees (tree_id) ON DELETE SET NULL,
    point_cloud_id          integer REFERENCES point_clouds.point_clouds (point_cloud_id) ON DELETE SET NULL,
    instance_id             text,
    observed_on             date,
    "position"              extensions.geometry(Point, 4326),
    position_uncertainty_m  numeric(6,3),
    species_id              integer REFERENCES shared.species (species_id) ON DELETE SET NULL,
    dbh_cm                  numeric(6,2),
    height_m                numeric(6,2),
    source_attributes       jsonb,
    created_at              timestamptz DEFAULT now(),
    created_by              varchar(200),
    CONSTRAINT observations_instance_needs_cloud_check
        CHECK (instance_id IS NULL OR point_cloud_id IS NOT NULL),
    CONSTRAINT observations_locatable_check
        CHECK (tree_id IS NOT NULL OR "position" IS NOT NULL),
    CONSTRAINT observations_position_uncertainty_m_check CHECK (position_uncertainty_m >= 0),
    CONSTRAINT observations_dbh_cm_check CHECK (dbh_cm > 0),
    CONSTRAINT observations_height_m_check CHECK (height_m > 0 AND height_m <= 200),
    CONSTRAINT observations_source_attributes_object_check
        CHECK (source_attributes IS NULL OR jsonb_typeof(source_attributes) = 'object')
);

COMMENT ON TABLE trees.observations IS
    'One tree as detected or measured by one campaign: the input of re-identification. A field-inventory tree points at its tree row (tree_id) and needs no copied attributes; a detection from a point cloud carries its own position and attributes plus point_cloud_id and instance_id. The link to a physical tree is decided in trees.entity_matches, never here.';
COMMENT ON COLUMN trees.observations.campaign_id IS
    'The campaign (dataset) that made the observation; decides who may read it (access levels).';
COMMENT ON COLUMN trees.observations.process_id IS
    'The detection or measurement process (e.g. a segmentation pipeline and version).';
COMMENT ON COLUMN trees.observations.tree_id IS
    'The tree row that carries this observation in its campaign''s variant, when there is one: the field tree itself, or the tree created for a detection decided as new. At most one observation per tree row.';
COMMENT ON COLUMN trees.observations.point_cloud_id IS
    'The point cloud the tree was detected in.';
COMMENT ON COLUMN trees.observations.instance_id IS
    'The tree''s label within that point cloud (e.g. TreeID). Unique per point cloud; requires point_cloud_id.';
COMMENT ON COLUMN trees.observations."position" IS
    'Stem position as observed, WGS84. NULL when the observation is a tree row, which holds the position.';
COMMENT ON COLUMN trees.observations.position_uncertainty_m IS
    'Planimetric position uncertainty in metres, as the source states it.';
COMMENT ON COLUMN trees.observations.dbh_cm IS 'DBH as observed, centimetres. NULL when the observation is a tree row.';
COMMENT ON COLUMN trees.observations.height_m IS 'Height as observed, metres. NULL when the observation is a tree row.';
COMMENT ON COLUMN trees.observations.source_attributes IS
    'Source fields without a column of their own, as a JSON object keyed by the source''s names.';

CREATE UNIQUE INDEX IF NOT EXISTS observations_tree_id_key
    ON trees.observations (tree_id) WHERE tree_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS observations_point_cloud_instance_key
    ON trees.observations (point_cloud_id, instance_id) WHERE instance_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS observations_location_id_idx ON trees.observations (location_id);
CREATE INDEX IF NOT EXISTS observations_campaign_id_idx ON trees.observations (campaign_id);
CREATE INDEX IF NOT EXISTS observations_position_idx ON trees.observations USING gist ("position");

DROP TRIGGER IF EXISTS trigger_observations_created_by ON trees.observations;
CREATE TRIGGER trigger_observations_created_by BEFORE INSERT ON trees.observations
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


-- -----------------------------------------------------------------------------
-- 3. Entity matches
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS trees.entity_matches (
    entity_match_id        bigserial PRIMARY KEY,
    observation_id         bigint NOT NULL REFERENCES trees.observations (observation_id) ON DELETE CASCADE,
    tree_entity_id         uuid,
    decision               varchar(20) NOT NULL,
    method                 varchar(100) NOT NULL,
    score                  numeric(4,3),
    reference_campaign_id  integer REFERENCES shared.campaigns (campaign_id) ON DELETE SET NULL,
    process_id             integer REFERENCES shared.processes (process_id) ON DELETE SET NULL,
    decided_by             varchar(200) NOT NULL,
    decided_at             timestamptz NOT NULL DEFAULT now(),
    supersedes_entity_match_id    bigint,
    notes                  text,
    created_at             timestamptz DEFAULT now(),
    created_by             varchar(200),
    CONSTRAINT entity_matches_decision_check CHECK (decision IN ('matched', 'new', 'ambiguous')),
    CONSTRAINT entity_matches_entity_unless_ambiguous_check
        CHECK (decision = 'ambiguous' OR tree_entity_id IS NOT NULL),
    CONSTRAINT entity_matches_score_check CHECK (score BETWEEN 0 AND 1),
    CONSTRAINT entity_matches_not_self_check CHECK (supersedes_entity_match_id <> entity_match_id),
    -- Lets the supersedes key below demand the same observation.
    CONSTRAINT entity_matches_id_observation_key UNIQUE (entity_match_id, observation_id),
    CONSTRAINT entity_matches_supersedes_same_observation_fkey
        FOREIGN KEY (supersedes_entity_match_id, observation_id)
        REFERENCES trees.entity_matches (entity_match_id, observation_id) ON DELETE RESTRICT
);

COMMENT ON TABLE trees.entity_matches IS
    'Re-identification decisions: which physical tree (tree_entity_id) an observation belongs to, how that was decided and by whom. Revisable: a new decision supersedes the previous one, which is kept. Per observation the decisions form one chain, so exactly one is current (public.current_entity_matches).';
COMMENT ON COLUMN trees.entity_matches.tree_entity_id IS
    'The physical tree the observation is assigned to: an existing entity for matched, a new UUID for new. NULL only for ambiguous. No foreign key: an entity is a UUID shared by tree rows, not a row of its own.';
COMMENT ON COLUMN trees.entity_matches.decision IS
    'matched (an existing tree) | new (no counterpart; a new entity) | ambiguous (no safe decision; held for review).';
COMMENT ON COLUMN trees.entity_matches.method IS
    'How the decision was reached. Deliberately unconstrained so a new method needs no migration; values in use: single_campaign (the only campaign at its site: every observation is new), tag_number (field tag or tree number), spatial (position gate plus attribute score), manual (a person''s review).';
COMMENT ON COLUMN trees.entity_matches.score IS
    'Match confidence from 0 to 1, when the method gives one.';
COMMENT ON COLUMN trees.entity_matches.reference_campaign_id IS
    'The campaign matched against (the other half of the campaign pair). NULL when there was none, e.g. a single-campaign site.';
COMMENT ON COLUMN trees.entity_matches.process_id IS
    'The matching process and version, when a process decided.';
COMMENT ON COLUMN trees.entity_matches.decided_by IS
    'Who decided: a person''s e-mail or a process name.';
COMMENT ON COLUMN trees.entity_matches.supersedes_entity_match_id IS
    'The earlier decision on the same observation that this one replaces. Superseded decisions are kept, never deleted.';

-- One chain per observation: a single first decision, and each decision
-- superseded at most once. So exactly one decision per observation is current.
CREATE UNIQUE INDEX IF NOT EXISTS entity_matches_first_decision_key
    ON trees.entity_matches (observation_id) WHERE supersedes_entity_match_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS entity_matches_supersedes_key
    ON trees.entity_matches (supersedes_entity_match_id) WHERE supersedes_entity_match_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS entity_matches_tree_entity_id_idx ON trees.entity_matches (tree_entity_id);

DROP TRIGGER IF EXISTS trigger_entity_matches_created_by ON trees.entity_matches;
CREATE TRIGGER trigger_entity_matches_created_by BEFORE INSERT ON trees.entity_matches
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();


-- -----------------------------------------------------------------------------
-- 4. Grants and policies
-- -----------------------------------------------------------------------------

GRANT SELECT ON TABLE trees.observations, trees.entity_matches TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE trees.observations, trees.entity_matches TO authenticated;
GRANT ALL ON TABLE trees.observations, trees.entity_matches TO service_role;
GRANT USAGE ON SEQUENCE trees.observations_observation_id_seq, trees.entity_matches_entity_match_id_seq
    TO authenticated, service_role;

ALTER TABLE trees.observations   ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.entity_matches ENABLE ROW LEVEL SECURITY;

-- Permissive: the same tiers as the other tree tables.
DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['trees.observations', 'trees.entity_matches']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Viewable by everyone" ON %s', t);
        EXECUTE format('CREATE POLICY "Viewable by everyone" ON %s FOR SELECT USING (true)', t);
        EXECUTE format('DROP POLICY IF EXISTS "Contributors can create" ON %s', t);
        EXECUTE format('CREATE POLICY "Contributors can create" ON %s FOR INSERT TO authenticated '
                       'WITH CHECK (shared.is_contributor())', t);
        EXECUTE format('DROP POLICY IF EXISTS "Curators can update" ON %s', t);
        EXECUTE format('CREATE POLICY "Curators can update" ON %s FOR UPDATE TO authenticated '
                       'USING (shared.is_curator()) WITH CHECK (shared.is_curator())', t);
        EXECUTE format('DROP POLICY IF EXISTS "Curators can delete" ON %s', t);
        EXECUTE format('CREATE POLICY "Curators can delete" ON %s FOR DELETE TO authenticated '
                       'USING (shared.is_curator())', t);
        EXECUTE format('DROP POLICY IF EXISTS "Service role can manage all" ON %s', t);
        EXECUTE format('CREATE POLICY "Service role can manage all" ON %s TO service_role '
                       'USING (true) WITH CHECK (true)', t);
    END LOOP;
END;
$$;

-- Restrictive (XRFF-625): observations by their campaign.
DROP POLICY IF EXISTS "Dataset access level" ON trees.observations;
CREATE POLICY "Dataset access level" ON trees.observations AS RESTRICTIVE FOR SELECT
    USING (campaign_id IN (SELECT shared.readable_campaign_ids()));
DROP POLICY IF EXISTS "Dataset owner: insert" ON trees.observations;
CREATE POLICY "Dataset owner: insert" ON trees.observations AS RESTRICTIVE FOR INSERT
    WITH CHECK (campaign_id IN (SELECT shared.writable_campaign_ids()));
DROP POLICY IF EXISTS "Dataset owner: update" ON trees.observations;
CREATE POLICY "Dataset owner: update" ON trees.observations AS RESTRICTIVE FOR UPDATE
    USING (campaign_id IN (SELECT shared.writable_campaign_ids()))
    WITH CHECK (campaign_id IN (SELECT shared.writable_campaign_ids()));
DROP POLICY IF EXISTS "Dataset owner: delete" ON trees.observations;
CREATE POLICY "Dataset owner: delete" ON trees.observations AS RESTRICTIVE FOR DELETE
    USING (campaign_id IN (SELECT shared.writable_campaign_ids()));

-- Matches follow their observation, as the other child tables follow theirs.
CREATE OR REPLACE FUNCTION shared.hidden_observation_ids()
RETURNS SETOF bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $f$
    SELECT o.observation_id FROM trees.observations o
     WHERE o.campaign_id NOT IN (SELECT shared.readable_campaign_ids());
$f$;

CREATE OR REPLACE FUNCTION shared.writable_observation_ids()
RETURNS SETOF bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $f$
    SELECT o.observation_id FROM trees.observations o
     WHERE o.campaign_id IN (SELECT shared.writable_campaign_ids());
$f$;

GRANT EXECUTE ON FUNCTION shared.hidden_observation_ids(), shared.writable_observation_ids()
    TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "Dataset access level" ON trees.entity_matches;
CREATE POLICY "Dataset access level" ON trees.entity_matches AS RESTRICTIVE FOR SELECT
    USING ((SELECT NOT shared.has_restricted_campaigns())
           OR observation_id NOT IN (SELECT shared.hidden_observation_ids()));
DROP POLICY IF EXISTS "Dataset owner: insert" ON trees.entity_matches;
CREATE POLICY "Dataset owner: insert" ON trees.entity_matches AS RESTRICTIVE FOR INSERT
    WITH CHECK (observation_id IN (SELECT shared.writable_observation_ids()));
DROP POLICY IF EXISTS "Dataset owner: update" ON trees.entity_matches;
CREATE POLICY "Dataset owner: update" ON trees.entity_matches AS RESTRICTIVE FOR UPDATE
    USING (observation_id IN (SELECT shared.writable_observation_ids()))
    WITH CHECK (observation_id IN (SELECT shared.writable_observation_ids()));
DROP POLICY IF EXISTS "Dataset owner: delete" ON trees.entity_matches;
CREATE POLICY "Dataset owner: delete" ON trees.entity_matches AS RESTRICTIVE FOR DELETE
    USING (observation_id IN (SELECT shared.writable_observation_ids()));


-- -----------------------------------------------------------------------------
-- 5. Public views
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.observations WITH (security_invoker = on) AS
SELECT observation_id, location_id, campaign_id, process_id, tree_id, point_cloud_id, instance_id,
       observed_on, "position", position_uncertainty_m, species_id, dbh_cm, height_m,
       source_attributes, created_at, created_by
  FROM trees.observations;

COMMENT ON VIEW public.observations IS
    'Trees as detected or measured by one campaign, the input of re-identification. Writable by contributors.';

CREATE OR REPLACE VIEW public.entity_matches WITH (security_invoker = on) AS
SELECT entity_match_id, observation_id, tree_entity_id, decision, method, score,
       reference_campaign_id, process_id, decided_by, decided_at, supersedes_entity_match_id, notes,
       created_at, created_by
  FROM trees.entity_matches;

COMMENT ON VIEW public.entity_matches IS
    'Every re-identification decision, superseded ones included. Writable by contributors; revise by inserting a decision that supersedes the current one.';

CREATE OR REPLACE VIEW public.current_entity_matches WITH (security_invoker = on) AS
SELECT m.entity_match_id, m.observation_id, o.location_id, o.campaign_id, o.tree_id,
       m.tree_entity_id, m.decision, m.method, m.score, m.reference_campaign_id,
       m.decided_by, m.decided_at
  FROM trees.entity_matches m
  JOIN trees.observations o ON o.observation_id = m.observation_id
 WHERE NOT EXISTS (SELECT 1 FROM trees.entity_matches s
                    WHERE s.supersedes_entity_match_id = m.entity_match_id);

COMMENT ON VIEW public.current_entity_matches IS
    'The one current decision per observation, with the observation''s location, campaign and tree row.';

GRANT SELECT ON public.observations, public.entity_matches, public.current_entity_matches
    TO anon, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.observations, public.entity_matches TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
