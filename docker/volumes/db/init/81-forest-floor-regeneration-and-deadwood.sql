-- =============================================================================
-- Forest floor for outside inventories: regeneration, richer deadwood, and
-- campaign scoping of deadwood and ground vegetation
-- =============================================================================
-- XRFF-640. Pathfinder and NSW record regeneration as counts per species on
-- subplots, and deadwood as pieces drawn as lines with a base and a top
-- diameter (NSW adds the hollow core). The schema held neither. And access
-- levels (XRFF-625) hid a deadwood row only through its tree, so the free-lying
-- deadwood of a restricted dataset stayed public.
--
--   forest_floor.regeneration  new: counts per species and size class on a
--                              (sub)plot whose own area_m2 gives the per-hectare
--                              value; public.regeneration and
--                              public.regeneration_per_ha
--   forest_floor.deadwood      + campaign_id, geom (the piece as any geometry;
--                              position stays the representative point),
--                              diameter_top_cm, void_diameter_cm,
--                              source_deadwood_id, source_attributes
--   forest_floor.ground_vegetation + campaign_id
--
-- All three get the restrictive campaign policies of XRFF-625 ("Dataset
-- access level" and "Dataset owner: insert/update/delete"). On deadwood the
-- campaign check is a second restrictive policy beside the existing
-- tree-based one; restrictive policies combine with AND.
--
-- Additive only; both existing tables are empty on dev and dt.unr.
-- Plan: knowledge hub 03-DATA-TIER/3dtrees-db-adjustment-plan.
-- Mirrored to init 81-forest-floor-regeneration-and-deadwood.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Deadwood
-- -----------------------------------------------------------------------------

ALTER TABLE forest_floor.deadwood
    ADD COLUMN IF NOT EXISTS campaign_id integer REFERENCES shared.campaigns (campaign_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS geom extensions.geometry(Geometry, 4326),
    ADD COLUMN IF NOT EXISTS diameter_top_cm numeric(6,2),
    ADD COLUMN IF NOT EXISTS void_diameter_cm numeric(6,2),
    ADD COLUMN IF NOT EXISTS source_deadwood_id text,
    ADD COLUMN IF NOT EXISTS source_attributes jsonb;

COMMENT ON COLUMN forest_floor.deadwood.campaign_id IS
    'Data collection campaign (dataset) this record belongs to; decides who may read it (access levels).';
COMMENT ON COLUMN forest_floor.deadwood.geom IS
    'The piece as measured, any geometry in WGS84: a line for a lying piece, a point for a stump. position stays the representative point.';
COMMENT ON COLUMN forest_floor.deadwood.diameter_cm IS
    'Diameter in centimetres: at the base (thick end) for lying pieces and stumps, at breast height for standing dead trees.';
COMMENT ON COLUMN forest_floor.deadwood.diameter_top_cm IS
    'Diameter at the thin end of a lying piece, in centimetres.';
COMMENT ON COLUMN forest_floor.deadwood.void_diameter_cm IS
    'Diameter of the hollow core, in centimetres (NSW coarseWoodyDebrisVoidSpace). 0 = solid.';
COMMENT ON COLUMN forest_floor.deadwood.source_deadwood_id IS
    'The producer''s own identifier of this piece. Unique per campaign; requires campaign_id.';
COMMENT ON COLUMN forest_floor.deadwood.source_attributes IS
    'Protocol codes without a column of their own, as a JSON object keyed by the source''s column names (e.g. the raw typology).';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'forest_floor.deadwood'::regclass
                      AND conname = 'deadwood_diameter_top_cm_check') THEN
        ALTER TABLE forest_floor.deadwood ADD CONSTRAINT deadwood_diameter_top_cm_check
            CHECK (diameter_top_cm > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'forest_floor.deadwood'::regclass
                      AND conname = 'deadwood_void_diameter_cm_check') THEN
        ALTER TABLE forest_floor.deadwood ADD CONSTRAINT deadwood_void_diameter_cm_check
            CHECK (void_diameter_cm >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'forest_floor.deadwood'::regclass
                      AND conname = 'deadwood_source_id_needs_campaign_check') THEN
        ALTER TABLE forest_floor.deadwood ADD CONSTRAINT deadwood_source_id_needs_campaign_check
            CHECK (source_deadwood_id IS NULL OR campaign_id IS NOT NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'forest_floor.deadwood'::regclass
                      AND conname = 'deadwood_source_attributes_object_check') THEN
        ALTER TABLE forest_floor.deadwood ADD CONSTRAINT deadwood_source_attributes_object_check
            CHECK (source_attributes IS NULL OR jsonb_typeof(source_attributes) = 'object');
    END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS deadwood_campaign_source_id_key
    ON forest_floor.deadwood (campaign_id, source_deadwood_id) WHERE source_deadwood_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS deadwood_campaign_id_idx ON forest_floor.deadwood (campaign_id);
CREATE INDEX IF NOT EXISTS deadwood_geom_idx ON forest_floor.deadwood USING gist (geom);


-- -----------------------------------------------------------------------------
-- 2. Ground vegetation
-- -----------------------------------------------------------------------------

ALTER TABLE forest_floor.ground_vegetation
    ADD COLUMN IF NOT EXISTS campaign_id integer REFERENCES shared.campaigns (campaign_id) ON DELETE SET NULL;

COMMENT ON COLUMN forest_floor.ground_vegetation.campaign_id IS
    'Data collection campaign (dataset) this record belongs to; decides who may read it (access levels).';

CREATE INDEX IF NOT EXISTS ground_vegetation_campaign_id_idx ON forest_floor.ground_vegetation (campaign_id);


-- -----------------------------------------------------------------------------
-- 3. Regeneration
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS forest_floor.regeneration (
    regeneration_id   serial PRIMARY KEY,
    location_id       integer NOT NULL REFERENCES shared.locations (location_id) ON DELETE CASCADE,
    plot_id           integer REFERENCES shared.plots (plot_id) ON DELETE SET NULL,
    campaign_id       integer REFERENCES shared.campaigns (campaign_id) ON DELETE SET NULL,
    species_id        integer REFERENCES shared.species (species_id) ON DELETE SET NULL,
    size_class        varchar(20) NOT NULL,
    live_count        integer NOT NULL DEFAULT 0,
    dead_count        integer NOT NULL DEFAULT 0,
    mean_height_m     numeric(5,2),
    "position"        extensions.geometry(Point, 4326),
    measurement_date  date,
    source_regeneration_id text,
    source_attributes jsonb,
    notes             text,
    created_at        timestamptz DEFAULT now(),
    updated_at        timestamptz DEFAULT now(),
    created_by        varchar(200),
    updated_by        varchar(200),
    CONSTRAINT regeneration_size_class_check CHECK (size_class IN ('seedling', 'sapling')),
    CONSTRAINT regeneration_live_count_check CHECK (live_count >= 0),
    CONSTRAINT regeneration_dead_count_check CHECK (dead_count >= 0),
    CONSTRAINT regeneration_mean_height_m_check CHECK (mean_height_m >= 0),
    CONSTRAINT regeneration_source_id_needs_campaign_check
        CHECK (source_regeneration_id IS NULL OR campaign_id IS NOT NULL),
    CONSTRAINT regeneration_source_attributes_object_check
        CHECK (source_attributes IS NULL OR jsonb_typeof(source_attributes) = 'object')
);

COMMENT ON TABLE forest_floor.regeneration IS
    'Regeneration tallies: live and dead counts per species and size class on a plot or subplot. The subplot is a shared.plots row (usually a child of the main plot through parent_plot_id) whose own area_m2 turns counts into per-hectare values; see public.regeneration_per_ha. Size classes follow the protocol of the plot''s sampling design.';
COMMENT ON COLUMN forest_floor.regeneration.plot_id IS
    'The (sub)plot the tally was made on. Its area_m2, or the nearest enclosing plot''s, is the survey area.';
COMMENT ON COLUMN forest_floor.regeneration.size_class IS
    'seedling | sapling, as the protocol defines them (e.g. Pathfinder: seedlings on 12 x 12 m, saplings on 0.01 ha).';
COMMENT ON COLUMN forest_floor.regeneration.live_count IS 'Live individuals counted.';
COMMENT ON COLUMN forest_floor.regeneration.dead_count IS 'Dead individuals counted.';
COMMENT ON COLUMN forest_floor.regeneration.mean_height_m IS 'Mean height of the counted individuals, when recorded.';
COMMENT ON COLUMN forest_floor.regeneration."position" IS 'Where the tally was made, when recorded (subplot centre or measured point).';
COMMENT ON COLUMN forest_floor.regeneration.source_regeneration_id IS
    'The producer''s own identifier of this tally. Unique per campaign; requires campaign_id.';
COMMENT ON COLUMN forest_floor.regeneration.source_attributes IS
    'Protocol codes without a column of their own, as a JSON object keyed by the source''s column names (e.g. the raw species name).';

CREATE UNIQUE INDEX IF NOT EXISTS regeneration_campaign_source_id_key
    ON forest_floor.regeneration (campaign_id, source_regeneration_id) WHERE source_regeneration_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS regeneration_location_id_idx ON forest_floor.regeneration (location_id);
CREATE INDEX IF NOT EXISTS regeneration_plot_id_idx ON forest_floor.regeneration (plot_id);
CREATE INDEX IF NOT EXISTS regeneration_campaign_id_idx ON forest_floor.regeneration (campaign_id);

DROP TRIGGER IF EXISTS trigger_regeneration_created_by ON forest_floor.regeneration;
CREATE TRIGGER trigger_regeneration_created_by BEFORE INSERT ON forest_floor.regeneration
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();
DROP TRIGGER IF EXISTS trigger_regeneration_updated_by ON forest_floor.regeneration;
CREATE TRIGGER trigger_regeneration_updated_by BEFORE UPDATE ON forest_floor.regeneration
    FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();

GRANT SELECT ON TABLE forest_floor.regeneration TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE forest_floor.regeneration TO authenticated;
GRANT ALL ON TABLE forest_floor.regeneration TO service_role;
GRANT USAGE ON SEQUENCE forest_floor.regeneration_regeneration_id_seq TO authenticated, service_role;

ALTER TABLE forest_floor.regeneration ENABLE ROW LEVEL SECURITY;

-- The same permissive policies as the other forest-floor tables.
DROP POLICY IF EXISTS "Regeneration records are viewable by everyone" ON forest_floor.regeneration;
CREATE POLICY "Regeneration records are viewable by everyone" ON forest_floor.regeneration
    FOR SELECT USING (true);
DROP POLICY IF EXISTS "Contributors can create regeneration records" ON forest_floor.regeneration;
CREATE POLICY "Contributors can create regeneration records" ON forest_floor.regeneration
    FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
DROP POLICY IF EXISTS "Curators can update regeneration records" ON forest_floor.regeneration;
CREATE POLICY "Curators can update regeneration records" ON forest_floor.regeneration
    FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
DROP POLICY IF EXISTS "Curators can delete regeneration records" ON forest_floor.regeneration;
CREATE POLICY "Curators can delete regeneration records" ON forest_floor.regeneration
    FOR DELETE TO authenticated USING (shared.is_curator());
DROP POLICY IF EXISTS "Service role can manage all regeneration records" ON forest_floor.regeneration;
CREATE POLICY "Service role can manage all regeneration records" ON forest_floor.regeneration
    TO service_role USING (true) WITH CHECK (true);


-- -----------------------------------------------------------------------------
-- 4. Restrictive campaign policies (XRFF-625)
-- -----------------------------------------------------------------------------

DO $$
DECLARE
    r record;
BEGIN
    -- Deadwood keeps its tree-based "Dataset access level"; the campaign check
    -- is a second restrictive policy under its own name.
    FOR r IN SELECT * FROM (VALUES
        ('forest_floor.regeneration',      'Dataset access level'),
        ('forest_floor.ground_vegetation', 'Dataset access level'),
        ('forest_floor.deadwood',          'Dataset access level: campaign')
    ) AS v(tbl, read_policy)
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %s', r.read_policy, r.tbl);
        EXECUTE format('CREATE POLICY %I ON %s AS RESTRICTIVE FOR SELECT '
                       'USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.readable_campaign_ids()))',
                       r.read_policy, r.tbl);
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: insert" ON %s', r.tbl);
        EXECUTE format('CREATE POLICY "Dataset owner: insert" ON %s AS RESTRICTIVE FOR INSERT '
                       'WITH CHECK (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))', r.tbl);
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: update" ON %s', r.tbl);
        EXECUTE format('CREATE POLICY "Dataset owner: update" ON %s AS RESTRICTIVE FOR UPDATE '
                       'USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids())) '
                       'WITH CHECK (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))', r.tbl);
        EXECUTE format('DROP POLICY IF EXISTS "Dataset owner: delete" ON %s', r.tbl);
        EXECUTE format('CREATE POLICY "Dataset owner: delete" ON %s AS RESTRICTIVE FOR DELETE '
                       'USING (campaign_id IS NULL OR campaign_id IN (SELECT shared.writable_campaign_ids()))', r.tbl);
    END LOOP;
END;
$$;


-- -----------------------------------------------------------------------------
-- 5. Public views
-- -----------------------------------------------------------------------------

-- New columns appended so existing column positions hold.
CREATE OR REPLACE VIEW public.deadwood WITH (security_invoker = on) AS
SELECT deadwood_id, location_id, plot_id, tree_id, species_id, wood_type, length_m, diameter_cm,
       decay_class, volume_m3, "position", measurement_date, notes, created_at, created_by,
       campaign_id, geom, diameter_top_cm, void_diameter_cm, source_deadwood_id, source_attributes
  FROM forest_floor.deadwood;

CREATE OR REPLACE VIEW public.ground_vegetation WITH (security_invoker = on) AS
SELECT ground_vegetation_id, location_id, plot_id, species_name, cover_percent, height_cm, layer,
       measurement_date, notes, created_at, created_by,
       campaign_id
  FROM forest_floor.ground_vegetation;

CREATE OR REPLACE VIEW public.regeneration WITH (security_invoker = on) AS
SELECT regeneration_id, location_id, plot_id, campaign_id, species_id, size_class, live_count,
       dead_count, mean_height_m, "position", measurement_date, source_regeneration_id,
       source_attributes, notes, created_at, updated_at, created_by, updated_by
  FROM forest_floor.regeneration;

COMMENT ON VIEW public.regeneration IS
    'Regeneration tallies: live and dead counts per species and size class on a plot or subplot. Writable by contributors.';

-- Per hectare through the plot's resolved survey area (its own, else the
-- nearest enclosing plot's), the same resolution trees use.
CREATE OR REPLACE VIEW public.regeneration_per_ha WITH (security_invoker = on) AS
SELECT r.regeneration_id, r.location_id, r.plot_id, r.campaign_id, r.species_id,
       sp.scientific_name, r.size_class, r.live_count, r.dead_count, r.mean_height_m,
       pi.area_m2 AS survey_area_m2,
       round(r.live_count * 10000.0 / pi.area_m2, 2) AS live_per_ha,
       round(r.dead_count * 10000.0 / pi.area_m2, 2) AS dead_per_ha,
       r.measurement_date
  FROM forest_floor.regeneration r
  LEFT JOIN shared.species sp ON sp.species_id = r.species_id
  LEFT JOIN shared.plot_inclusion pi ON pi.plot_id = r.plot_id;

COMMENT ON VIEW public.regeneration_per_ha IS
    'Regeneration per hectare: each tally''s counts divided by the survey area of its plot (the plot''s own area_m2, else the nearest enclosing plot''s). NULL per-hectare values where no area is known.';

GRANT SELECT ON public.regeneration, public.regeneration_per_ha TO anon, authenticated, service_role;
GRANT INSERT, UPDATE, DELETE ON public.regeneration TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
