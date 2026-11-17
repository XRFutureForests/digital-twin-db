-- =============================================================================
-- Tree-related microhabitats (XRFF-692)
-- =============================================================================
-- Microhabitats per tree: cavities, bark pockets, fungal fruiting bodies, crown
-- deadwood, epiphytes and the rest, for VR and for biodiversity work.
--
--   trees.microhabitat_types         the 52 types of Bütler et al. 2024 (WSL
--                                    field guide, 2nd ed.), after Larrieu et
--                                    al. 2018: form > group > type, with
--                                    minimum size, frequency and replacement
--   trees.microhabitat_source_codes  codes of other recording schemes, mapped
--                                    to a type: Integrate+ 2016 (Kraus et al.)
--                                    as used by the marteloscopes on GBIF
--   trees.microhabitats              one row per tree x microhabitat, with a
--                                    required provenance tier
--
-- Provenance: 'measured' (own survey), 'reference' (imported from a published
-- dataset), 'predicted' (model output; needs a process and a probability).
-- Predicted rows are decoration for VR and never count as observations.
--
-- Design: knowledge hub 03-DATA-TIER/open-data-microhabitats-soil-biodiversity.
-- Both lookups load from data/lookups/*.csv through shared.lookup_registry.
-- =============================================================================

CREATE TABLE IF NOT EXISTS trees.microhabitat_types (
    microhabitat_type_id    serial PRIMARY KEY,
    type_number             smallint NOT NULL UNIQUE CHECK (type_number BETWEEN 1 AND 99),
    type_name               varchar(100) NOT NULL UNIQUE,
    form                    varchar(60) NOT NULL,
    type_group              varchar(80) NOT NULL,
    minimum_size            text,
    frequency_natural       varchar(40),
    frequency_managed       varchar(40),
    replacement_rate        varchar(40),
    is_difficult_to_monitor boolean NOT NULL DEFAULT false,
    description             text
);

COMMENT ON TABLE trees.microhabitat_types IS 'Tree-related microhabitat types after Bütler, Lachat, Krumm, Kraus & Larrieu (2024), Field Guide to Tree-related Microhabitats, 2nd ed., WSL Birmensdorf, which extends the typology of Larrieu et al. 2018 (Ecol. Indic. 84:194-207) to 52 types in 17 groups and 7 forms. Loaded from data/lookups/microhabitat_types.csv.';
COMMENT ON COLUMN trees.microhabitat_types.type_number IS 'Type number in the field guide (1-52). Natural key of the lookup.';
COMMENT ON COLUMN trees.microhabitat_types.form IS 'One of the 7 forms: Cavities; Tree injuries and exposed wood; Crown deadwood; Excrescences; Fungal fruiting bodies and slime moulds; Epiphytic and epixylic structures; Exudates.';
COMMENT ON COLUMN trees.microhabitat_types.type_group IS 'One of the 17 groups within the form (e.g. Rot-holes, Concavities, Exposed sapwood).';
COMMENT ON COLUMN trees.microhabitat_types.minimum_size IS 'Minimum size for the microhabitat to be recorded, as stated in the field guide; "experts'' threshold" where the guide marks it so.';
COMMENT ON COLUMN trees.microhabitat_types.frequency_natural IS 'Frequency in natural forest as given in the guide (rare, relatively rare, relatively common, common, or a range), from a European database.';
COMMENT ON COLUMN trees.microhabitat_types.frequency_managed IS 'Frequency in managed forest, same scale as frequency_natural.';
COMMENT ON COLUMN trees.microhabitat_types.replacement_rate IS 'How fast the microhabitat forms again in a stand (very slow to rapid), as given in the guide.';
COMMENT ON COLUMN trees.microhabitat_types.is_difficult_to_monitor IS 'True where the guide marks the type DM: hard to monitor routinely because of size, location or sporadic occurrence.';

CREATE TABLE IF NOT EXISTS trees.microhabitat_source_codes (
    source_code_id  serial PRIMARY KEY,
    code            varchar(10) NOT NULL UNIQUE,
    scheme          varchar(40) NOT NULL,
    category        varchar(60),
    code_group      varchar(80),
    label           text NOT NULL,
    type_number     smallint REFERENCES trees.microhabitat_types (type_number) ON UPDATE CASCADE,
    match           varchar(12) NOT NULL CHECK (match IN ('same', 'approximate', 'none')),
    match_note      text,
    CHECK ((match = 'none') = (type_number IS NULL))
);

COMMENT ON TABLE trees.microhabitat_source_codes IS 'Microhabitat codes of other recording schemes and the field-guide type each maps to. scheme integrateplus_2016: Kraus et al. (2016), Catalogue of tree microhabitats - Reference field list, Integrate+ Technical Paper, EFI; the codes of the Integrate+ marteloscopes and of GBIF dataset 10.15468/ocof3v. Loaded from data/lookups/microhabitat_source_codes.csv.';
COMMENT ON COLUMN trees.microhabitat_source_codes.code IS 'Code as recorded in the source (e.g. CV14). Natural key of the lookup.';
COMMENT ON COLUMN trees.microhabitat_source_codes.category IS 'Top level of the source scheme (Integrate+ 2016: Cavities, Injuries and wounds, Bark, Deadwood, Deformation / growth form, Epiphytes, Nests, Other).';
COMMENT ON COLUMN trees.microhabitat_source_codes.type_number IS 'Field-guide type the code maps to; NULL when match = none.';
COMMENT ON COLUMN trees.microhabitat_source_codes.match IS 'same: same concept, the code''s threshold at or above the guide''s; approximate: same concept with a lower threshold or a broader or narrower definition (see match_note); none: no type in the guide.';

CREATE TABLE IF NOT EXISTS trees.microhabitats (
    microhabitat_id       serial PRIMARY KEY,
    tree_id               integer NOT NULL REFERENCES trees.trees (tree_id) ON DELETE CASCADE,
    microhabitat_type_id  integer REFERENCES trees.microhabitat_types (microhabitat_type_id),
    source_code_id        integer REFERENCES trees.microhabitat_source_codes (source_code_id),
    count                 integer NOT NULL DEFAULT 1 CHECK (count >= 1),
    height_m              numeric(5,2) CHECK (height_m >= 0),
    provenance            varchar(12) NOT NULL CHECK (provenance IN ('measured', 'reference', 'predicted')),
    probability           numeric(5,4) CHECK (probability BETWEEN 0 AND 1),
    campaign_id           integer REFERENCES shared.campaigns (campaign_id) ON DELETE SET NULL,
    process_id            integer REFERENCES shared.processes (process_id) ON DELETE SET NULL,
    observation_date      date,
    source_attributes     jsonb,
    created_at            timestamptz DEFAULT now(),
    updated_at            timestamptz DEFAULT now(),
    created_by            varchar(200),
    updated_by            varchar(200),
    CHECK (microhabitat_type_id IS NOT NULL OR source_code_id IS NOT NULL),
    CHECK (provenance <> 'predicted' OR (process_id IS NOT NULL AND probability IS NOT NULL)),
    CONSTRAINT microhabitats_tree_provenance_code_key UNIQUE (tree_id, provenance, source_code_id)
);

CREATE INDEX IF NOT EXISTS idx_microhabitats_tree_id ON trees.microhabitats (tree_id);
CREATE INDEX IF NOT EXISTS idx_microhabitats_type_id ON trees.microhabitats (microhabitat_type_id);
CREATE INDEX IF NOT EXISTS idx_microhabitats_campaign_id ON trees.microhabitats (campaign_id);

COMMENT ON TABLE trees.microhabitats IS 'Tree-related microhabitats, one row per tree x microhabitat. Measured and reference rows carry a campaign; predicted rows carry the process (model) and a probability and are never observations.';
COMMENT ON COLUMN trees.microhabitats.tree_id IS 'The tree record (one tree in one variant) the microhabitat was found on.';
COMMENT ON COLUMN trees.microhabitats.microhabitat_type_id IS 'Field-guide type; for rows imported with a source code, the type the code maps to (NULL when the code has no type).';
COMMENT ON COLUMN trees.microhabitats.source_code_id IS 'Code as recorded by the source scheme, kept so an import stays lossless; NULL for rows recorded directly against a type.';
COMMENT ON COLUMN trees.microhabitats.count IS 'Number of microhabitats of this kind on the tree, as recorded.';
COMMENT ON COLUMN trees.microhabitats.height_m IS 'Height on the stem in metres, where recorded.';
COMMENT ON COLUMN trees.microhabitats.provenance IS 'measured: own survey; reference: imported from a published dataset (see the campaign''s citation and licence); predicted: generated by a model (process_id, probability). Views that count biodiversity filter predicted rows out.';
COMMENT ON COLUMN trees.microhabitats.probability IS 'Model probability of the microhabitat, for predicted rows.';
COMMENT ON COLUMN trees.microhabitats.source_attributes IS 'Source fields kept as delivered (e.g. GBIF occurrence key, raw code and value).';

-- Row-level security: lookups readable by everyone; microhabitats like the
-- other campaign-owned tables (forest_floor.regeneration).
ALTER TABLE trees.microhabitat_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.microhabitat_source_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE trees.microhabitats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tree reference tables are viewable by everyone" ON trees.microhabitat_types;
CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.microhabitat_types FOR SELECT USING (true);
DROP POLICY IF EXISTS "Tree reference tables are viewable by everyone" ON trees.microhabitat_source_codes;
CREATE POLICY "Tree reference tables are viewable by everyone" ON trees.microhabitat_source_codes FOR SELECT USING (true);

DROP POLICY IF EXISTS "Microhabitats are viewable by everyone" ON trees.microhabitats;
CREATE POLICY "Microhabitats are viewable by everyone" ON trees.microhabitats FOR SELECT USING (true);
DROP POLICY IF EXISTS "Contributors can create microhabitat records" ON trees.microhabitats;
CREATE POLICY "Contributors can create microhabitat records" ON trees.microhabitats FOR INSERT TO authenticated WITH CHECK (shared.is_contributor());
DROP POLICY IF EXISTS "Curators can update microhabitat records" ON trees.microhabitats;
CREATE POLICY "Curators can update microhabitat records" ON trees.microhabitats FOR UPDATE TO authenticated USING (shared.is_curator()) WITH CHECK (shared.is_curator());
DROP POLICY IF EXISTS "Curators can delete microhabitat records" ON trees.microhabitats;
CREATE POLICY "Curators can delete microhabitat records" ON trees.microhabitats FOR DELETE TO authenticated USING (shared.is_curator());
DROP POLICY IF EXISTS "Dataset access level" ON trees.microhabitats;
CREATE POLICY "Dataset access level" ON trees.microhabitats AS RESTRICTIVE FOR SELECT
    USING ((campaign_id IS NULL) OR (campaign_id IN (SELECT shared.readable_campaign_ids())));
DROP POLICY IF EXISTS "Dataset owner: insert" ON trees.microhabitats;
CREATE POLICY "Dataset owner: insert" ON trees.microhabitats AS RESTRICTIVE FOR INSERT
    WITH CHECK ((campaign_id IS NULL) OR (campaign_id IN (SELECT shared.writable_campaign_ids())));
DROP POLICY IF EXISTS "Dataset owner: update" ON trees.microhabitats;
CREATE POLICY "Dataset owner: update" ON trees.microhabitats AS RESTRICTIVE FOR UPDATE
    USING ((campaign_id IS NULL) OR (campaign_id IN (SELECT shared.writable_campaign_ids())))
    WITH CHECK ((campaign_id IS NULL) OR (campaign_id IN (SELECT shared.writable_campaign_ids())));
DROP POLICY IF EXISTS "Dataset owner: delete" ON trees.microhabitats;
CREATE POLICY "Dataset owner: delete" ON trees.microhabitats AS RESTRICTIVE FOR DELETE
    USING ((campaign_id IS NULL) OR (campaign_id IN (SELECT shared.writable_campaign_ids())));

DROP TRIGGER IF EXISTS trigger_microhabitats_created_by ON trees.microhabitats;
CREATE TRIGGER trigger_microhabitats_created_by BEFORE INSERT ON trees.microhabitats
    FOR EACH ROW EXECUTE FUNCTION shared.set_created_by();
DROP TRIGGER IF EXISTS trigger_microhabitats_updated_by ON trees.microhabitats;
CREATE TRIGGER trigger_microhabitats_updated_by BEFORE UPDATE ON trees.microhabitats
    FOR EACH ROW EXECUTE FUNCTION shared.set_updated_by();

GRANT SELECT ON TABLE trees.microhabitat_types TO anon, authenticated;
GRANT ALL ON TABLE trees.microhabitat_types TO service_role;
GRANT SELECT ON TABLE trees.microhabitat_source_codes TO anon, authenticated;
GRANT ALL ON TABLE trees.microhabitat_source_codes TO service_role;
GRANT SELECT ON TABLE trees.microhabitats TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE trees.microhabitats TO authenticated;
GRANT ALL ON TABLE trees.microhabitats TO service_role;
GRANT USAGE ON SEQUENCE trees.microhabitats_microhabitat_id_seq TO authenticated, service_role;

-- Lookups: registry rows, and the refresh list (dependency order: types before codes).
INSERT INTO shared.lookup_registry (logical_key, schema_name, table_name, csv_file, csv_columns, natural_key, description)
VALUES
    ('microhabitat_types', 'trees', 'microhabitat_types', 'microhabitat_types.csv',
     ARRAY['type_number', 'type_name', 'form', 'type_group', 'minimum_size', 'frequency_natural',
           'frequency_managed', 'replacement_rate', 'is_difficult_to_monitor', 'description'],
     'type_number', 'Tree-related microhabitat types (Bütler et al. 2024, after Larrieu et al. 2018)'),
    ('microhabitat_source_codes', 'trees', 'microhabitat_source_codes', 'microhabitat_source_codes.csv',
     ARRAY['code', 'scheme', 'category', 'code_group', 'label', 'type_number', 'match', 'match_note'],
     'code', 'Microhabitat codes of other schemes (Integrate+ 2016) mapped to the field-guide types')
ON CONFLICT (logical_key) DO UPDATE SET schema_name = EXCLUDED.schema_name, table_name = EXCLUDED.table_name,
    csv_file = EXCLUDED.csv_file, csv_columns = EXCLUDED.csv_columns, natural_key = EXCLUDED.natural_key,
    description = EXCLUDED.description;

CREATE OR REPLACE FUNCTION shared.refresh_all_lookups() RETURNS TABLE(table_name text, rows_before integer, rows_after integer, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    -- Refresh in dependency order
    RETURN QUERY SELECT * FROM shared.refresh_lookup('soil_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('climate_zones');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('variant_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('scenarios');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('species');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('locations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('sensor_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('tree_status');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('taper_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('straightness_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branching_patterns');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('bark_characteristics');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('datasource_types');
    -- Tree Morphology tables (from tree_anatomy.pdf)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('height_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_architectures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('branch_elongation_habits');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_orientations');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('shoot_elongation_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_shapes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('geometric_crown_solids');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('axis_structures');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('growth_forms');
    -- Tree Condition tables (FIA/NEON/ICP Forests-aligned)
    RETURN QUERY SELECT * FROM shared.refresh_lookup('crown_classes');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('damage_agents');
    -- Tree-related microhabitats (XRFF-692): types before the codes that map to them
    RETURN QUERY SELECT * FROM shared.refresh_lookup('microhabitat_types');
    RETURN QUERY SELECT * FROM shared.refresh_lookup('microhabitat_source_codes');
END;
$$;

-- Public view for Unreal and other clients: one row per tree x microhabitat,
-- with the type's form and group, the source code, and the provenance.
CREATE OR REPLACE VIEW public.tree_microhabitats WITH (security_invoker = on) AS
SELECT m.microhabitat_id,
       m.tree_id,
       t.tree_entity_id,
       t.location_id,
       t.variant_id,
       mt.type_number,
       mt.type_name,
       mt.form,
       mt.type_group,
       sc.scheme      AS source_scheme,
       sc.code        AS source_code,
       sc.label       AS source_label,
       sc.match       AS source_match,
       m.count,
       m.height_m,
       m.provenance,
       m.probability,
       m.observation_date,
       m.campaign_id,
       m.process_id
  FROM trees.microhabitats m
  JOIN trees.trees t ON t.tree_id = m.tree_id
  LEFT JOIN trees.microhabitat_types mt ON mt.microhabitat_type_id = m.microhabitat_type_id
  LEFT JOIN trees.microhabitat_source_codes sc ON sc.source_code_id = m.source_code_id;

COMMENT ON VIEW public.tree_microhabitats IS 'Public API view: tree-related microhabitats per tree with type, form, group, source code and provenance. Filter provenance <> ''predicted'' for anything that counts biodiversity.';

GRANT SELECT ON TABLE public.tree_microhabitats TO anon, authenticated;
GRANT ALL ON TABLE public.tree_microhabitats TO service_role;

NOTIFY pgrst, 'reload schema';
