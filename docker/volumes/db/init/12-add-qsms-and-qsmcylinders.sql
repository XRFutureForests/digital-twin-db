-- =============================================================================
-- Add trees.QSMs and trees.QSMCylinders (Real Twig cylinder format)
-- =============================================================================
-- XRFF-265. Stores QSM (Quantitative Structure Model) reconstructions and their
-- cylinder geometry -- the first schema step of the CityGML/QSM alignment
-- (XRFF-264). Design: docs/citygml-qsm-mapping.md §3 (Trunk/Branch/Twig
-- mapping), §6 (cylinders/cones); full design note in the Obsidian vault's
-- 03-DATA-TIER/citygml-qsm-alignment.md §4.1-4.2. Additive only -- no existing
-- column changes.
--
-- trees.QSMs is variant-like: the same physical tree can have several QSM
-- reconstructions from different scans, tools or parameter sets, tied together
-- by tree_entity_id. QSM volumes are kept separate from the allometric
-- trees.Trees.volume_m3 -- different estimates, and conflating them would
-- destroy the ability to compare methods.
--
-- trees.QSMCylinders adopts the Real Twig / rTwig standardised cylinder column
-- set directly (https://aidanmorales.github.io/rTwig, "Dictionary" vignette,
-- package v1.4.0) rather than inventing our own, so ingesting a published
-- rTwig CSV is a copy, not a transform. Confirmed against that vignette (this
-- issue's acceptance criterion): the full standardised dictionary has 22
-- columns -- id, parent, start (x/y/z), axis (x/y/z), end (x/y/z), radius,
-- raw_radius, modified, length, branch, branch_position, branch_order,
-- reverse_order, branch_alt, segment, parent_segment, total_children,
-- growth_length, base_distance, twig_distance, vessel_volume, pipe_area,
-- pipe_radius. Only the source geometry/topology columns are stored here
-- (start, axis, length, radius, parent, branch identity/order/position); the
-- rest are derived tree/segment metrics (growth length, distances, pipe-model
-- outputs, segment ids, alternate branch index) recomputable from the stored
-- geometry via rTwig itself -- storing them now would be speculative. Add them
-- if/when a concrete consumer needs them.
--
-- part_type_id has no FK yet: trees.TreePartTypes is created in XRFF-266. The
-- column is nullable and unconstrained until that migration adds the FK.
--
-- Decision (acceptance criterion): trees.QSMCylinders is NOT exposed through a
-- public.* view in this migration. Every other public.* view in this repo is
-- one-row-per-entity (trees, stems, phenology observations); QSMCylinders is
-- ~10^3-10^4 rows per tree, and unlike sensor.sensorreadings (which has a
-- known, filtered query shape -- see docs/sensorreadings-scaling-evaluation.md)
-- there is no client query pattern yet: XRFF-269 (qsm_to_pve spike) is what
-- will define how a UE client or import script actually needs to read
-- cylinders. The table remains reachable today via the `trees` schema, already
-- listed in PGRST_DB_SCHEMAS, gated by the same RLS policies a public view
-- would enforce -- this decision only defers committing to a public-facing
-- shape before a consumer exists. Add the view once XRFF-269 defines the real
-- access pattern.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. trees.QSMs -- one row per reconstruction
-- -----------------------------------------------------------------------------

CREATE TABLE trees.qsms (
    qsm_id bigint NOT NULL,
    tree_entity_id uuid NOT NULL,
    tree_id integer NOT NULL,
    point_cloud_id integer,
    process_id integer,
    lod smallint,
    local_crs text,
    origin_position extensions.geometry(PointZ,4326),
    cylinder_count integer,
    total_volume_m3 numeric(10,3),
    trunk_volume_m3 numeric(10,3),
    branch_volume_m3 numeric(10,3),
    dbh_qsm_cm numeric(6,2),
    height_qsm_m numeric(6,2),
    crown_area_qsm_m2 numeric(10,2),
    is_corrected boolean NOT NULL DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT qsms_lod_check CHECK (((lod >= 0) AND (lod <= 4))),
    CONSTRAINT qsms_cylinder_count_check CHECK ((cylinder_count >= 0)),
    CONSTRAINT qsms_total_volume_m3_check CHECK ((total_volume_m3 >= (0)::numeric)),
    CONSTRAINT qsms_trunk_volume_m3_check CHECK ((trunk_volume_m3 >= (0)::numeric)),
    CONSTRAINT qsms_branch_volume_m3_check CHECK ((branch_volume_m3 >= (0)::numeric)),
    CONSTRAINT qsms_dbh_qsm_cm_check CHECK (((dbh_qsm_cm > (0)::numeric) AND (dbh_qsm_cm <= (1000)::numeric))),
    CONSTRAINT qsms_height_qsm_m_check CHECK (((height_qsm_m > (0)::numeric) AND (height_qsm_m <= (200)::numeric))),
    CONSTRAINT qsms_crown_area_qsm_m2_check CHECK ((crown_area_qsm_m2 >= (0)::numeric))
);

COMMENT ON TABLE trees.qsms IS 'QSM (Quantitative Structure Model) reconstructions -- one row per reconstruction, several per physical tree possible';
COMMENT ON COLUMN trees.qsms.tree_entity_id IS 'Stable physical-tree identity (trees.trees.tree_entity_id) -- groups QSMs of the same tree across scans/tools/parameter sets';
COMMENT ON COLUMN trees.qsms.local_crs IS 'CRS of the cylinder coordinates in trees.qsmcylinders, or the literal value ''local'' if none';
COMMENT ON COLUMN trees.qsms.origin_position IS 'Georeferences the local cylinder coordinate frame';
COMMENT ON COLUMN trees.qsms.is_corrected IS 'Raw TreeQSM (false) vs Real Twig radius-corrected (true)';
COMMENT ON COLUMN trees.qsms.dbh_qsm_cm IS 'DBH as derived from the QSM -- kept separate from trees.stems.dbh_cm to allow validating one against the other';
COMMENT ON COLUMN trees.qsms.total_volume_m3 IS 'QSM-derived total volume -- kept separate from the allometric trees.trees.volume_m3';

CREATE SEQUENCE trees.qsms_qsm_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.qsms_qsm_id_seq OWNED BY trees.qsms.qsm_id;
ALTER TABLE ONLY trees.qsms ALTER COLUMN qsm_id SET DEFAULT nextval('trees.qsms_qsm_id_seq'::regclass);

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_pkey PRIMARY KEY (qsm_id);

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_point_cloud_id_fkey FOREIGN KEY (point_cloud_id) REFERENCES pointclouds.pointclouds(point_cloud_id) ON DELETE SET NULL;

ALTER TABLE ONLY trees.qsms
    ADD CONSTRAINT qsms_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;

CREATE INDEX idx_qsms_tree ON trees.qsms USING btree (tree_id);
CREATE INDEX idx_qsms_tree_entity ON trees.qsms USING btree (tree_entity_id);
CREATE INDEX idx_qsms_point_cloud ON trees.qsms USING btree (point_cloud_id);

GRANT SELECT,USAGE ON SEQUENCE trees.qsms_qsm_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.qsms_qsm_id_seq TO service_role;

GRANT SELECT ON TABLE trees.qsms TO anon;
GRANT SELECT ON TABLE trees.qsms TO authenticated;
GRANT ALL ON TABLE trees.qsms TO service_role;

ALTER TABLE trees.qsms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Contributors can create QSMs" ON trees.qsms FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
CREATE POLICY "Curators can update QSMs" ON trees.qsms FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
CREATE POLICY "Curators can delete QSMs" ON trees.qsms FOR DELETE TO authenticated USING (shared.is_curator());
CREATE POLICY "QSMs are viewable by everyone" ON trees.qsms FOR SELECT USING (true);
CREATE POLICY "Service role can manage all QSMs" ON trees.qsms TO service_role USING (true) WITH CHECK (true);

-- public.qsms -- one row per reconstruction, cheap to expose like every other
-- reference table (see decision note above re: trees.qsmcylinders).

CREATE VIEW public.qsms WITH (security_invoker='on') AS
 SELECT qsms.qsm_id,
    qsms.tree_entity_id,
    qsms.tree_id,
    qsms.point_cloud_id,
    qsms.process_id,
    qsms.lod,
    qsms.local_crs,
    qsms.origin_position,
    qsms.cylinder_count,
    qsms.total_volume_m3,
    qsms.trunk_volume_m3,
    qsms.branch_volume_m3,
    qsms.dbh_qsm_cm,
    qsms.height_qsm_m,
    qsms.crown_area_qsm_m2,
    qsms.is_corrected,
    qsms.created_at,
    qsms.created_by
   FROM trees.qsms;

COMMENT ON VIEW public.qsms IS 'Public API view for QSM reconstructions';

CREATE FUNCTION public.qsms_insert() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO trees.qsms (
        tree_entity_id, tree_id, point_cloud_id, process_id,
        lod, local_crs, origin_position, cylinder_count,
        total_volume_m3, trunk_volume_m3, branch_volume_m3,
        dbh_qsm_cm, height_qsm_m, crown_area_qsm_m2,
        is_corrected, created_by
    ) VALUES (
        COALESCE(NEW.tree_entity_id, gen_random_uuid()), NEW.tree_id, NEW.point_cloud_id, NEW.process_id,
        NEW.lod, NEW.local_crs, NEW.origin_position, NEW.cylinder_count,
        NEW.total_volume_m3, NEW.trunk_volume_m3, NEW.branch_volume_m3,
        NEW.dbh_qsm_cm, NEW.height_qsm_m, NEW.crown_area_qsm_m2,
        COALESCE(NEW.is_corrected, false), NEW.created_by
    ) RETURNING qsm_id INTO NEW.qsm_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.qsms_insert() IS 'INSTEAD OF INSERT trigger function for public.qsms view';

CREATE TRIGGER qsms_insert_trigger INSTEAD OF INSERT ON public.qsms FOR EACH ROW EXECUTE FUNCTION public.qsms_insert();

GRANT ALL ON FUNCTION public.qsms_insert() TO postgres;
GRANT ALL ON FUNCTION public.qsms_insert() TO anon;
GRANT ALL ON FUNCTION public.qsms_insert() TO authenticated;
GRANT ALL ON FUNCTION public.qsms_insert() TO service_role;

GRANT ALL ON TABLE public.qsms TO postgres;
GRANT ALL ON TABLE public.qsms TO anon;
GRANT ALL ON TABLE public.qsms TO authenticated;
GRANT ALL ON TABLE public.qsms TO service_role;

-- -----------------------------------------------------------------------------
-- 2. trees.QSMCylinders -- the geometry
-- -----------------------------------------------------------------------------

CREATE TABLE trees.qsmcylinders (
    cylinder_id bigint NOT NULL,
    qsm_id bigint NOT NULL,
    cylinder_index integer NOT NULL,
    parent_cylinder_index integer,
    start_point extensions.geometry(PointZ),
    axis double precision[],
    length_m numeric(8,4) NOT NULL,
    radius_m numeric(8,5) NOT NULL,
    branch_index integer,
    branch_order integer,
    branch_position integer,
    part_type_id smallint,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT qsmcylinders_length_m_check CHECK ((length_m > (0)::numeric)),
    CONSTRAINT qsmcylinders_radius_m_check CHECK ((radius_m >= (0)::numeric)),
    CONSTRAINT qsmcylinders_branch_order_check CHECK ((branch_order >= 0)),
    CONSTRAINT qsmcylinders_axis_check CHECK (((axis IS NULL) OR (array_length(axis, 1) = 3)))
);

COMMENT ON TABLE trees.qsmcylinders IS 'QSM cylinder geometry, Real Twig / rTwig standardised column set -- ~10^3-10^4 rows per tree';
COMMENT ON COLUMN trees.qsmcylinders.cylinder_index IS 'Cylinder id within the QSM, as published (rTwig ''id'')';
COMMENT ON COLUMN trees.qsmcylinders.parent_cylinder_index IS 'Parent cylinder_index, self-referenced by index (not FK) to match the source files -- 0 for the base cylinder, per rTwig convention';
COMMENT ON COLUMN trees.qsmcylinders.start_point IS 'Cylinder base coordinate in the QSM''s local frame (trees.qsms.local_crs / origin_position)';
COMMENT ON COLUMN trees.qsmcylinders.axis IS 'Unit vector [x,y,z] from cylinder base to top';
COMMENT ON COLUMN trees.qsmcylinders.branch_order IS 'Branch order; 0 = trunk (rTwig ''branch_order'')';
COMMENT ON COLUMN trees.qsmcylinders.part_type_id IS 'CityGML part semantic (trunk/branch/twig) -- FK to trees.treeparttypes added in XRFF-266, unconstrained until then';

CREATE SEQUENCE trees.qsmcylinders_cylinder_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.qsmcylinders_cylinder_id_seq OWNED BY trees.qsmcylinders.cylinder_id;
ALTER TABLE ONLY trees.qsmcylinders ALTER COLUMN cylinder_id SET DEFAULT nextval('trees.qsmcylinders_cylinder_id_seq'::regclass);

ALTER TABLE ONLY trees.qsmcylinders
    ADD CONSTRAINT qsmcylinders_pkey PRIMARY KEY (cylinder_id);

ALTER TABLE ONLY trees.qsmcylinders
    ADD CONSTRAINT qsmcylinders_qsm_id_cylinder_index_key UNIQUE (qsm_id, cylinder_index);

ALTER TABLE ONLY trees.qsmcylinders
    ADD CONSTRAINT qsmcylinders_qsm_id_fkey FOREIGN KEY (qsm_id) REFERENCES trees.qsms(qsm_id) ON DELETE CASCADE;

CREATE INDEX idx_qsmcylinders_qsm_branch_order ON trees.qsmcylinders USING btree (qsm_id, branch_order);
CREATE INDEX idx_qsmcylinders_qsm_parent ON trees.qsmcylinders USING btree (qsm_id, parent_cylinder_index);

GRANT SELECT,USAGE ON SEQUENCE trees.qsmcylinders_cylinder_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.qsmcylinders_cylinder_id_seq TO service_role;

GRANT SELECT ON TABLE trees.qsmcylinders TO anon;
GRANT SELECT ON TABLE trees.qsmcylinders TO authenticated;
GRANT ALL ON TABLE trees.qsmcylinders TO service_role;

ALTER TABLE trees.qsmcylinders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Contributors can create QSM cylinders" ON trees.qsmcylinders FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
CREATE POLICY "Curators can update QSM cylinders" ON trees.qsmcylinders FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
CREATE POLICY "Curators can delete QSM cylinders" ON trees.qsmcylinders FOR DELETE TO authenticated USING (shared.is_curator());
CREATE POLICY "QSM cylinders are viewable by everyone" ON trees.qsmcylinders FOR SELECT USING (true);
CREATE POLICY "Service role can manage all QSM cylinders" ON trees.qsmcylinders TO service_role USING (true) WITH CHECK (true);
