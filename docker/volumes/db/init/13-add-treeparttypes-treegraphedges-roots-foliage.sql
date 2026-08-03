-- =============================================================================
-- Add trees.TreePartTypes, trees.TreeGraphEdges, trees.RootSystemTypes,
-- trees.Roots, trees.CrownFoliageProfiles (CityGML semantics + topology)
-- =============================================================================
-- XRFF-266. Second schema step of the CityGML/QSM alignment (XRFF-264/265).
-- Design: docs/citygml-qsm-mapping.md §3.1-3.2, Obsidian vault's
-- 03-DATA-TIER/citygml-qsm-alignment.md §4.3-4.4. Additive only.
--
-- -----------------------------------------------------------------------------
-- trees.TreePartTypes
-- -----------------------------------------------------------------------------
-- Read-only lookup mirroring Ambarwari et al.'s CityGML feature classes
-- (root/trunk/branch/twig/leaf/crown). This is the join point to a future
-- CityGML ADE -- without it trees.qsmcylinders is geometry with no meaning
-- attached. Follows the trees.CrownClasses/trees.DamageAgents lookup pattern
-- (plain view, single "viewable by everyone" RLS policy, no base-table grants
-- needed since the view is not security_invoker). Not every value is
-- assignable to a cylinder today: only trunk/branch/twig come from QSM
-- geometry (see the part_type assignment rule below); root/leaf/crown have no
-- per-cylinder representation in the current pipeline (root has no QSM
-- geometry yet, leaf is out of scope for a wood-only QSM skeleton, crown is
-- an aggregate, not a single part) but are listed regardless so the lookup
-- mirrors the full CityGML feature-class set for that future ADE join.
--
-- part_type assignment rule (applied by scripts/import/import_qsm.py, not a
-- stored/computed column -- the rule needs a per-tree twig radius threshold
-- that isn't itself schema, it's an import-time parameter, same as rTwig's
-- own `run_rtwig(twig_radius = ...)`):
--   1. branch_order = 0                                    -> trunk
--   2. branch_order >= 1 AND radius_m <= twig_radius_m      -> twig
--   3. branch_order >= 1 AND radius_m >  twig_radius_m      -> branch
-- twig_radius_m is the species-specific twig radius (rTwig's own `twigs` /
-- `twigs_index` reference database supplies this per scientific_name -- the
-- same value used to correct that QSM's overestimated cylinders in the first
-- place, so reusing it for classification needs no new measurement).
--
-- -----------------------------------------------------------------------------
-- trees.TreeGraphEdges
-- -----------------------------------------------------------------------------
-- Ambarwari et al. model topology as Node/Edge (an Edge relates exactly 2
-- Nodes). A cylinder endpoint already IS a node via trees.qsmcylinders'
-- cylinder_index/parent_cylinder_index chain, so this table materialises
-- only edges that carry information the parent-chain columns cannot: an
-- edge's observed/synthetic provenance. Because every QSM cylinder has
-- exactly one parent (the graph is a rooted tree, not a general graph), the
-- full edge set IS the parent-chain -- so a row here does not add topology,
-- it labels an existing (from,to) pair. A cylinder with no row here is
-- assumed 'observed' (the common case); a row exists only where the type
-- deviates from that default, per the design note's "only where they differ
-- from the cylinder parent chain."
--
-- edge_type values and the third-value decision (acceptance criterion):
--   'observed'  -- the source data provider (e.g. BioDiv-3DTrees / rTwig)
--                  measured this connection directly.
--   'synthetic' -- the source data provider flagged this connection as
--                  inferred, not measured (BioDiv-3DTrees' own network-
--                  analysis cleanup introduces these where the point cloud
--                  doesn't support a structurally valid connection).
--   'derived'   -- WE added or overrode this edge ourselves (e.g. during
--                  import cleanup or a future qsm_to_pve topology fix),
--                  distinct from 'synthetic' because that specifically means
--                  "the original provider inferred this", not us. Losing that
--                  distinction would make a twin's structural-analysis
--                  warranty ("was this junction measured, and by whom")
--                  unrecoverable -- which is the entire reason this column
--                  exists per the design note.
--
-- -----------------------------------------------------------------------------
-- trees.RootSystemTypes / trees.Roots
-- -----------------------------------------------------------------------------
-- Root was originally scoped out for lack of a data source; Guerrero Iñiguez
-- (2017) -- the paper Ambarwari et al. themselves name for root coupling --
-- gives three root system types at LoD-matched detail (block model up to
-- surface-projected), and root system type correlates with species well
-- enough to be a documented default today (source = 'species_default'),
-- geometry columns left NULL until measured. Classifiable now, geometrized
-- later.
--
-- -----------------------------------------------------------------------------
-- trees.CrownFoliageProfiles
-- -----------------------------------------------------------------------------
-- QSM cannot see leaves (wood-only skeleton, Raumonen et al. 2013), but leaf
-- area *density and distribution* within the crown is a separate, storable
-- quantity with real parametric models (Le Port et al. 2000's Beta PDFs;
-- Jeréz et al. 2005's Johnson SB alternative). Feeds growpy/PVE's existing
-- procedural leaf-instancing path with a real distribution instead of an
-- arbitrary default -- once species-specific shape parameters exist. This
-- migration registers both papers as shared.Processes rows (real DOIs) but
-- does NOT seed fabricated Beta/Johnson-SB shape parameters per species --
-- neither paper studied our 11 species (Maritime pine and loblolly pine
-- respectively), and inventing numbers to fill the columns would be
-- indistinguishable from real fitted data to a downstream consumer. The seed
-- script (scripts/seed/root_and_foliage_defaults.sql) instead seeds
-- distribution_type = 'uniform' with NULL params -- an explicit "no species-
-- specific shape known yet" signal, not a placeholder pretending to be one.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. trees.TreePartTypes
-- -----------------------------------------------------------------------------

CREATE TABLE trees.treeparttypes (
    part_type_id smallint NOT NULL,
    part_type_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_part_type_name CHECK (((part_type_name)::text = ANY ((ARRAY['root'::character varying, 'trunk'::character varying, 'branch'::character varying, 'twig'::character varying, 'leaf'::character varying, 'crown'::character varying])::text[])))
);

COMMENT ON TABLE trees.treeparttypes IS 'CityGML tree feature-class lookup (Ambarwari et al. 2024) -- join point for a future CityGML ADE';

CREATE SEQUENCE trees.treeparttypes_part_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.treeparttypes_part_type_id_seq OWNED BY trees.treeparttypes.part_type_id;
ALTER TABLE ONLY trees.treeparttypes ALTER COLUMN part_type_id SET DEFAULT nextval('trees.treeparttypes_part_type_id_seq'::regclass);

ALTER TABLE ONLY trees.treeparttypes
    ADD CONSTRAINT treeparttypes_pkey PRIMARY KEY (part_type_id);

ALTER TABLE ONLY trees.treeparttypes
    ADD CONSTRAINT treeparttypes_part_type_name_key UNIQUE (part_type_name);

CREATE INDEX idx_tree_part_types_name ON trees.treeparttypes USING btree (part_type_name);

ALTER TABLE trees.treeparttypes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.treeparttypes FOR SELECT USING (true);

CREATE VIEW public.treeparttypes AS
 SELECT treeparttypes.part_type_id,
    treeparttypes.part_type_name,
    treeparttypes.description
   FROM trees.treeparttypes;

COMMENT ON VIEW public.treeparttypes IS 'Public API view for tree part types (CityGML feature classes) lookup table';

GRANT ALL ON TABLE public.treeparttypes TO postgres;
GRANT ALL ON TABLE public.treeparttypes TO anon;
GRANT ALL ON TABLE public.treeparttypes TO authenticated;
GRANT ALL ON TABLE public.treeparttypes TO service_role;

-- Now that trees.TreePartTypes exists, add the FK deferred in XRFF-265.
COMMENT ON COLUMN trees.qsmcylinders.part_type_id IS 'CityGML part semantic (trunk/branch/twig) -- see trees.TreePartTypes; assignment rule documented in this migration''s header';

ALTER TABLE ONLY trees.qsmcylinders
    ADD CONSTRAINT qsmcylinders_part_type_id_fkey FOREIGN KEY (part_type_id) REFERENCES trees.treeparttypes(part_type_id);

-- -----------------------------------------------------------------------------
-- 2. trees.TreeGraphEdges
-- -----------------------------------------------------------------------------

CREATE TABLE trees.treegraphedges (
    edge_id bigint NOT NULL,
    qsm_id bigint NOT NULL,
    from_cylinder_index integer NOT NULL,
    to_cylinder_index integer NOT NULL,
    edge_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT treegraphedges_edge_type_check CHECK ((edge_type = ANY (ARRAY['observed'::text, 'synthetic'::text, 'derived'::text])))
);

COMMENT ON TABLE trees.treegraphedges IS 'QSM topology edges whose type deviates from the trees.qsmcylinders parent-chain default (''observed''); see this migration''s header for the observed/synthetic/derived distinction';
COMMENT ON COLUMN trees.treegraphedges.from_cylinder_index IS 'Parent cylinder_index -- the CityGML Edge''s first Node';
COMMENT ON COLUMN trees.treegraphedges.to_cylinder_index IS 'Child cylinder_index -- the CityGML Edge''s second Node';
COMMENT ON COLUMN trees.treegraphedges.edge_type IS 'observed = measured by the source; synthetic = the source itself flagged this as inferred; derived = we added/overrode it ourselves';

CREATE SEQUENCE trees.treegraphedges_edge_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.treegraphedges_edge_id_seq OWNED BY trees.treegraphedges.edge_id;
ALTER TABLE ONLY trees.treegraphedges ALTER COLUMN edge_id SET DEFAULT nextval('trees.treegraphedges_edge_id_seq'::regclass);

ALTER TABLE ONLY trees.treegraphedges
    ADD CONSTRAINT treegraphedges_pkey PRIMARY KEY (edge_id);

ALTER TABLE ONLY trees.treegraphedges
    ADD CONSTRAINT treegraphedges_qsm_from_to_key UNIQUE (qsm_id, from_cylinder_index, to_cylinder_index);

ALTER TABLE ONLY trees.treegraphedges
    ADD CONSTRAINT treegraphedges_qsm_id_fkey FOREIGN KEY (qsm_id) REFERENCES trees.qsms(qsm_id) ON DELETE CASCADE;

CREATE INDEX idx_treegraphedges_qsm ON trees.treegraphedges USING btree (qsm_id);
CREATE INDEX idx_treegraphedges_qsm_type ON trees.treegraphedges USING btree (qsm_id, edge_type);

GRANT SELECT,USAGE ON SEQUENCE trees.treegraphedges_edge_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.treegraphedges_edge_id_seq TO service_role;

GRANT SELECT ON TABLE trees.treegraphedges TO anon;
GRANT SELECT ON TABLE trees.treegraphedges TO authenticated;
GRANT ALL ON TABLE trees.treegraphedges TO service_role;

ALTER TABLE trees.treegraphedges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Contributors can create tree graph edges" ON trees.treegraphedges FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
CREATE POLICY "Curators can update tree graph edges" ON trees.treegraphedges FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
CREATE POLICY "Curators can delete tree graph edges" ON trees.treegraphedges FOR DELETE TO authenticated USING (shared.is_curator());
CREATE POLICY "Tree graph edges are viewable by everyone" ON trees.treegraphedges FOR SELECT USING (true);
CREATE POLICY "Service role can manage all tree graph edges" ON trees.treegraphedges TO service_role USING (true) WITH CHECK (true);

CREATE VIEW public.treegraphedges WITH (security_invoker='on') AS
 SELECT treegraphedges.edge_id,
    treegraphedges.qsm_id,
    treegraphedges.from_cylinder_index,
    treegraphedges.to_cylinder_index,
    treegraphedges.edge_type,
    treegraphedges.created_at
   FROM trees.treegraphedges;

COMMENT ON VIEW public.treegraphedges IS 'Public API view for QSM topology edge overrides (observed/synthetic/derived)';

CREATE FUNCTION public.treegraphedges_insert() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO trees.treegraphedges (
        qsm_id, from_cylinder_index, to_cylinder_index, edge_type
    ) VALUES (
        NEW.qsm_id, NEW.from_cylinder_index, NEW.to_cylinder_index, NEW.edge_type
    ) RETURNING edge_id INTO NEW.edge_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.treegraphedges_insert() IS 'INSTEAD OF INSERT trigger function for public.treegraphedges view';

CREATE TRIGGER treegraphedges_insert_trigger INSTEAD OF INSERT ON public.treegraphedges FOR EACH ROW EXECUTE FUNCTION public.treegraphedges_insert();

GRANT ALL ON FUNCTION public.treegraphedges_insert() TO postgres;
GRANT ALL ON FUNCTION public.treegraphedges_insert() TO anon;
GRANT ALL ON FUNCTION public.treegraphedges_insert() TO authenticated;
GRANT ALL ON FUNCTION public.treegraphedges_insert() TO service_role;

GRANT ALL ON TABLE public.treegraphedges TO postgres;
GRANT ALL ON TABLE public.treegraphedges TO anon;
GRANT ALL ON TABLE public.treegraphedges TO authenticated;
GRANT ALL ON TABLE public.treegraphedges TO service_role;

-- -----------------------------------------------------------------------------
-- 3. trees.RootSystemTypes
-- -----------------------------------------------------------------------------

CREATE TABLE trees.rootsystemtypes (
    root_system_type_id smallint NOT NULL,
    root_system_type_name character varying(50) NOT NULL,
    description text,
    CONSTRAINT chk_root_system_type_name CHECK (((root_system_type_name)::text = ANY ((ARRAY['tap_root'::character varying, 'heart_root'::character varying, 'lateral_root'::character varying])::text[])))
);

COMMENT ON TABLE trees.rootsystemtypes IS 'Root system morphology lookup (Koestler et al. 1968 classification; Guerrero Inigez 2017 LoD-matched geometric models)';

CREATE SEQUENCE trees.rootsystemtypes_root_system_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.rootsystemtypes_root_system_type_id_seq OWNED BY trees.rootsystemtypes.root_system_type_id;
ALTER TABLE ONLY trees.rootsystemtypes ALTER COLUMN root_system_type_id SET DEFAULT nextval('trees.rootsystemtypes_root_system_type_id_seq'::regclass);

ALTER TABLE ONLY trees.rootsystemtypes
    ADD CONSTRAINT rootsystemtypes_pkey PRIMARY KEY (root_system_type_id);

ALTER TABLE ONLY trees.rootsystemtypes
    ADD CONSTRAINT rootsystemtypes_root_system_type_name_key UNIQUE (root_system_type_name);

CREATE INDEX idx_root_system_types_name ON trees.rootsystemtypes USING btree (root_system_type_name);

ALTER TABLE trees.rootsystemtypes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.rootsystemtypes FOR SELECT USING (true);

CREATE VIEW public.rootsystemtypes AS
 SELECT rootsystemtypes.root_system_type_id,
    rootsystemtypes.root_system_type_name,
    rootsystemtypes.description
   FROM trees.rootsystemtypes;

COMMENT ON VIEW public.rootsystemtypes IS 'Public API view for root system types lookup table';

GRANT ALL ON TABLE public.rootsystemtypes TO postgres;
GRANT ALL ON TABLE public.rootsystemtypes TO anon;
GRANT ALL ON TABLE public.rootsystemtypes TO authenticated;
GRANT ALL ON TABLE public.rootsystemtypes TO service_role;

-- -----------------------------------------------------------------------------
-- 4. trees.Roots
-- -----------------------------------------------------------------------------

CREATE TABLE trees.roots (
    root_id bigint NOT NULL,
    tree_entity_id uuid NOT NULL,
    tree_id integer NOT NULL,
    root_system_type_id smallint NOT NULL,
    lod smallint,
    geometry_class text,
    root_depth_m numeric(6,2),
    root_spread_radius_m numeric(6,2),
    process_id integer,
    source text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT roots_lod_check CHECK (((lod >= 0) AND (lod <= 4))),
    CONSTRAINT roots_geometry_class_check CHECK (((geometry_class IS NULL) OR (geometry_class = ANY (ARRAY['implicit'::text, 'explicit'::text])))),
    CONSTRAINT roots_root_depth_m_check CHECK ((root_depth_m >= (0)::numeric)),
    CONSTRAINT roots_root_spread_radius_m_check CHECK ((root_spread_radius_m >= (0)::numeric)),
    CONSTRAINT roots_source_check CHECK ((source = ANY (ARRAY['species_default'::text, 'field_observed'::text, 'measured'::text])))
);

COMMENT ON TABLE trees.roots IS 'Root system classification/geometry (Guerrero Inigez 2017 LoD-matched models) -- classifiable from species now, geometrized later';
COMMENT ON COLUMN trees.roots.tree_entity_id IS 'Stable physical-tree identity (trees.trees.tree_entity_id)';
COMMENT ON COLUMN trees.roots.geometry_class IS 'implicit (block model, LoD1-3) or explicit (surface-projected, LoD4) -- same column/values as trees.TreeAssets.geometry_class (XRFF-267)';
COMMENT ON COLUMN trees.roots.source IS 'species_default = classified from silvics literature, no measurement; field_observed = seen but not measured; measured = geometry actually captured';

CREATE SEQUENCE trees.roots_root_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.roots_root_id_seq OWNED BY trees.roots.root_id;
ALTER TABLE ONLY trees.roots ALTER COLUMN root_id SET DEFAULT nextval('trees.roots_root_id_seq'::regclass);

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_pkey PRIMARY KEY (root_id);

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_root_system_type_id_fkey FOREIGN KEY (root_system_type_id) REFERENCES trees.rootsystemtypes(root_system_type_id);

ALTER TABLE ONLY trees.roots
    ADD CONSTRAINT roots_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;

CREATE INDEX idx_roots_tree ON trees.roots USING btree (tree_id);
CREATE INDEX idx_roots_tree_entity ON trees.roots USING btree (tree_entity_id);
CREATE INDEX idx_roots_root_system_type ON trees.roots USING btree (root_system_type_id);

GRANT SELECT,USAGE ON SEQUENCE trees.roots_root_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.roots_root_id_seq TO service_role;

GRANT SELECT ON TABLE trees.roots TO anon;
GRANT SELECT ON TABLE trees.roots TO authenticated;
GRANT ALL ON TABLE trees.roots TO service_role;

ALTER TABLE trees.roots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Contributors can create roots" ON trees.roots FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
CREATE POLICY "Curators can update roots" ON trees.roots FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
CREATE POLICY "Curators can delete roots" ON trees.roots FOR DELETE TO authenticated USING (shared.is_curator());
CREATE POLICY "Roots are viewable by everyone" ON trees.roots FOR SELECT USING (true);
CREATE POLICY "Service role can manage all roots" ON trees.roots TO service_role USING (true) WITH CHECK (true);

CREATE VIEW public.roots WITH (security_invoker='on') AS
 SELECT roots.root_id,
    roots.tree_entity_id,
    roots.tree_id,
    roots.root_system_type_id,
    roots.lod,
    roots.geometry_class,
    roots.root_depth_m,
    roots.root_spread_radius_m,
    roots.process_id,
    roots.source,
    roots.created_at,
    roots.created_by
   FROM trees.roots;

COMMENT ON VIEW public.roots IS 'Public API view for root system classification/geometry';

CREATE FUNCTION public.roots_insert() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO trees.roots (
        tree_entity_id, tree_id, root_system_type_id, lod, geometry_class,
        root_depth_m, root_spread_radius_m, process_id, source, created_by
    ) VALUES (
        COALESCE(NEW.tree_entity_id, gen_random_uuid()), NEW.tree_id, NEW.root_system_type_id, NEW.lod, NEW.geometry_class,
        NEW.root_depth_m, NEW.root_spread_radius_m, NEW.process_id, NEW.source, NEW.created_by
    ) RETURNING root_id INTO NEW.root_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.roots_insert() IS 'INSTEAD OF INSERT trigger function for public.roots view';

CREATE TRIGGER roots_insert_trigger INSTEAD OF INSERT ON public.roots FOR EACH ROW EXECUTE FUNCTION public.roots_insert();

GRANT ALL ON FUNCTION public.roots_insert() TO postgres;
GRANT ALL ON FUNCTION public.roots_insert() TO anon;
GRANT ALL ON FUNCTION public.roots_insert() TO authenticated;
GRANT ALL ON FUNCTION public.roots_insert() TO service_role;

GRANT ALL ON TABLE public.roots TO postgres;
GRANT ALL ON TABLE public.roots TO anon;
GRANT ALL ON TABLE public.roots TO authenticated;
GRANT ALL ON TABLE public.roots TO service_role;

-- -----------------------------------------------------------------------------
-- 5. trees.CrownFoliageProfiles
-- -----------------------------------------------------------------------------

CREATE TABLE trees.crownfoliageprofiles (
    profile_id bigint NOT NULL,
    tree_id integer NOT NULL,
    process_id integer,
    distribution_type text NOT NULL,
    vertical_params numeric[],
    horizontal_params numeric[],
    total_leaf_area_m2 numeric(10,2),
    source text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    created_by character varying(200),
    CONSTRAINT crownfoliageprofiles_distribution_type_check CHECK ((distribution_type = ANY (ARRAY['beta'::text, 'johnson_sb'::text, 'uniform'::text]))),
    CONSTRAINT crownfoliageprofiles_total_leaf_area_m2_check CHECK ((total_leaf_area_m2 >= (0)::numeric)),
    CONSTRAINT crownfoliageprofiles_source_check CHECK ((source = ANY (ARRAY['species_literature_default'::text, 'fitted'::text, 'measured'::text])))
);

COMMENT ON TABLE trees.crownfoliageprofiles IS 'Crown leaf area density/distribution (not per-leaf geometry -- QSM is wood-only) for growpy/PVE procedural leaf instancing';
COMMENT ON COLUMN trees.crownfoliageprofiles.distribution_type IS 'beta (Le Port et al. 2000) | johnson_sb (Jerez et al. 2005) | uniform (no species-specific shape known yet -- not a placeholder pretending to be fitted data)';
COMMENT ON COLUMN trees.crownfoliageprofiles.vertical_params IS 'Distribution shape parameters (e.g. Beta''s two shape params); NULL when distribution_type = uniform';
COMMENT ON COLUMN trees.crownfoliageprofiles.source IS 'species_literature_default = literature parameters for this species; fitted = fit to our own data; measured = destructive/allometric measurement';

CREATE SEQUENCE trees.crownfoliageprofiles_profile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE trees.crownfoliageprofiles_profile_id_seq OWNED BY trees.crownfoliageprofiles.profile_id;
ALTER TABLE ONLY trees.crownfoliageprofiles ALTER COLUMN profile_id SET DEFAULT nextval('trees.crownfoliageprofiles_profile_id_seq'::regclass);

ALTER TABLE ONLY trees.crownfoliageprofiles
    ADD CONSTRAINT crownfoliageprofiles_pkey PRIMARY KEY (profile_id);

ALTER TABLE ONLY trees.crownfoliageprofiles
    ADD CONSTRAINT crownfoliageprofiles_tree_id_fkey FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE;

ALTER TABLE ONLY trees.crownfoliageprofiles
    ADD CONSTRAINT crownfoliageprofiles_process_id_fkey FOREIGN KEY (process_id) REFERENCES shared.processes(process_id) ON DELETE SET NULL;

CREATE INDEX idx_crownfoliageprofiles_tree ON trees.crownfoliageprofiles USING btree (tree_id);

GRANT SELECT,USAGE ON SEQUENCE trees.crownfoliageprofiles_profile_id_seq TO authenticated;
GRANT SELECT,USAGE ON SEQUENCE trees.crownfoliageprofiles_profile_id_seq TO service_role;

GRANT SELECT ON TABLE trees.crownfoliageprofiles TO anon;
GRANT SELECT ON TABLE trees.crownfoliageprofiles TO authenticated;
GRANT ALL ON TABLE trees.crownfoliageprofiles TO service_role;

ALTER TABLE trees.crownfoliageprofiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Contributors can create crown foliage profiles" ON trees.crownfoliageprofiles FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
CREATE POLICY "Curators can update crown foliage profiles" ON trees.crownfoliageprofiles FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
CREATE POLICY "Curators can delete crown foliage profiles" ON trees.crownfoliageprofiles FOR DELETE TO authenticated USING (shared.is_curator());
CREATE POLICY "Crown foliage profiles are viewable by everyone" ON trees.crownfoliageprofiles FOR SELECT USING (true);
CREATE POLICY "Service role can manage all crown foliage profiles" ON trees.crownfoliageprofiles TO service_role USING (true) WITH CHECK (true);

CREATE VIEW public.crownfoliageprofiles WITH (security_invoker='on') AS
 SELECT crownfoliageprofiles.profile_id,
    crownfoliageprofiles.tree_id,
    crownfoliageprofiles.process_id,
    crownfoliageprofiles.distribution_type,
    crownfoliageprofiles.vertical_params,
    crownfoliageprofiles.horizontal_params,
    crownfoliageprofiles.total_leaf_area_m2,
    crownfoliageprofiles.source,
    crownfoliageprofiles.created_at,
    crownfoliageprofiles.created_by
   FROM trees.crownfoliageprofiles;

COMMENT ON VIEW public.crownfoliageprofiles IS 'Public API view for crown foliage density/distribution profiles';

CREATE FUNCTION public.crownfoliageprofiles_insert() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO trees.crownfoliageprofiles (
        tree_id, process_id, distribution_type, vertical_params,
        horizontal_params, total_leaf_area_m2, source, created_by
    ) VALUES (
        NEW.tree_id, NEW.process_id, NEW.distribution_type, NEW.vertical_params,
        NEW.horizontal_params, NEW.total_leaf_area_m2, NEW.source, NEW.created_by
    ) RETURNING profile_id INTO NEW.profile_id;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.crownfoliageprofiles_insert() IS 'INSTEAD OF INSERT trigger function for public.crownfoliageprofiles view';

CREATE TRIGGER crownfoliageprofiles_insert_trigger INSTEAD OF INSERT ON public.crownfoliageprofiles FOR EACH ROW EXECUTE FUNCTION public.crownfoliageprofiles_insert();

GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO postgres;
GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO anon;
GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO authenticated;
GRANT ALL ON FUNCTION public.crownfoliageprofiles_insert() TO service_role;

GRANT ALL ON TABLE public.crownfoliageprofiles TO postgres;
GRANT ALL ON TABLE public.crownfoliageprofiles TO anon;
GRANT ALL ON TABLE public.crownfoliageprofiles TO authenticated;
GRANT ALL ON TABLE public.crownfoliageprofiles TO service_role;
