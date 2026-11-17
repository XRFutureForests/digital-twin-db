-- =============================================================================
-- Biodiversity, first table: site checklists (XRFF-696)
-- =============================================================================
-- Which taxa are recorded at or near a site, aggregated from an external
-- source: GBIF occurrences within a radius, or the species of a Natura 2000
-- standard data form. One row per site x radius x source x taxon, with record
-- count, first and last year and the licences of the underlying records.
--
-- Raw occurrences stay at the source (scope rule, hub note
-- 03-DATA-TIER/database-scope-and-extensions); the query and the process are
-- stored so the list can be rebuilt and cited. Taxonomy is carried on the row
-- from the source; taxon_id links to shared.taxa where the taxon is there.
--
-- Written only through public.replace_site_checklist() by the service role
-- (open-data-connector `open-data checklist`); read through
-- public.site_checklists.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS biodiversity;
COMMENT ON SCHEMA biodiversity IS 'Biodiversity data beyond single trees: site checklists now; Darwin Core events and occurrences when survey data arrive.';
GRANT USAGE ON SCHEMA biodiversity TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS biodiversity.site_checklists (
    site_checklist_id  serial PRIMARY KEY,
    location_id        integer NOT NULL REFERENCES shared.locations (location_id) ON DELETE CASCADE,
    radius_m           integer NOT NULL CHECK (radius_m > 0),
    source             varchar(20) NOT NULL CHECK (source IN ('gbif', 'natura2000')),
    source_taxon_key   bigint,
    taxon_id           integer REFERENCES shared.taxa (taxon_id) ON DELETE SET NULL,
    scientific_name    text NOT NULL,
    taxon_rank         varchar(20),
    kingdom            varchar(60),
    phylum             varchar(60),
    class_name         varchar(60),
    order_name         varchar(60),
    family             varchar(60),
    genus              varchar(60),
    record_count       integer CHECK (record_count >= 0),
    first_year         smallint,
    last_year          smallint,
    licences           text[],
    process_id         integer NOT NULL REFERENCES shared.processes (process_id),
    source_query       text,
    fetched_at         date NOT NULL DEFAULT current_date,
    CONSTRAINT site_checklists_entry_key UNIQUE (location_id, radius_m, source, scientific_name),
    CHECK (first_year IS NULL OR last_year IS NULL OR first_year <= last_year)
);

CREATE INDEX IF NOT EXISTS idx_site_checklists_location ON biodiversity.site_checklists (location_id, source, radius_m);
CREATE INDEX IF NOT EXISTS idx_site_checklists_class ON biodiversity.site_checklists (class_name);

COMMENT ON TABLE biodiversity.site_checklists IS 'Taxa recorded at or near a site, aggregated from an external source (GBIF occurrences within radius_m, or a Natura 2000 standard data form). Raw records stay at the source; source_query and process_id say how to rebuild and cite the list.';
COMMENT ON COLUMN biodiversity.site_checklists.radius_m IS 'Search radius around the location''s center_point in metres. For natura2000 rows: distance to the Natura 2000 site the list comes from.';
COMMENT ON COLUMN biodiversity.site_checklists.source_taxon_key IS 'Taxon key in the source: the GBIF backbone usageKey for gbif rows.';
COMMENT ON COLUMN biodiversity.site_checklists.taxon_id IS 'shared.taxa row of the taxon where one exists (matched on GBIF key, then scientific name); NULL otherwise.';
COMMENT ON COLUMN biodiversity.site_checklists.class_name IS 'Class (GBIF backbone), e.g. Aves, Insecta, Magnoliopsida.';
COMMENT ON COLUMN biodiversity.site_checklists.record_count IS 'Number of source records behind the entry (gbif: occurrences that passed the query''s filters).';
COMMENT ON COLUMN biodiversity.site_checklists.licences IS 'Distinct licences of the underlying records (CC0-1.0, CC-BY-4.0, CC-BY-NC-4.0). A list that mixes in CC-BY-NC is not free for commercial reuse.';
COMMENT ON COLUMN biodiversity.site_checklists.source_query IS 'The query that produced the list (e.g. the GBIF occurrence search URL with its filters), as run on fetched_at.';

ALTER TABLE biodiversity.site_checklists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Site checklists are viewable by everyone" ON biodiversity.site_checklists;
CREATE POLICY "Site checklists are viewable by everyone" ON biodiversity.site_checklists FOR SELECT USING (true);

GRANT SELECT ON TABLE biodiversity.site_checklists TO anon, authenticated;
GRANT ALL ON TABLE biodiversity.site_checklists TO service_role;
GRANT USAGE ON SEQUENCE biodiversity.site_checklists_site_checklist_id_seq TO service_role;

-- Write path: replace one site x radius x source list in a single call.
CREATE OR REPLACE FUNCTION public.replace_site_checklist(
    p_location_id integer, p_radius_m integer, p_source text, p_process_id integer,
    p_source_query text, p_entries jsonb)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
    n integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM shared.locations WHERE location_id = p_location_id) THEN
        RAISE EXCEPTION 'replace_site_checklist: unknown location_id %', p_location_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'replace_site_checklist: unknown process_id %', p_process_id;
    END IF;
    IF jsonb_typeof(p_entries) <> 'array' THEN
        RAISE EXCEPTION 'replace_site_checklist: p_entries must be a JSON array';
    END IF;

    DELETE FROM biodiversity.site_checklists
     WHERE location_id = p_location_id AND radius_m = p_radius_m AND source = p_source;

    INSERT INTO biodiversity.site_checklists (
        location_id, radius_m, source, source_taxon_key, taxon_id, scientific_name, taxon_rank,
        kingdom, phylum, class_name, order_name, family, genus, record_count, first_year, last_year,
        licences, process_id, source_query)
    SELECT p_location_id, p_radius_m, p_source, (e->>'source_taxon_key')::bigint,
           (SELECT t.taxon_id FROM shared.taxa t
             WHERE t.gbif_key = (e->>'source_taxon_key')::bigint OR t.scientific_name = e->>'scientific_name'
             ORDER BY (t.gbif_key = (e->>'source_taxon_key')::bigint) DESC NULLS LAST LIMIT 1),
           e->>'scientific_name', e->>'taxon_rank', e->>'kingdom', e->>'phylum', e->>'class_name',
           e->>'order_name', e->>'family', e->>'genus', (e->>'record_count')::integer,
           (e->>'first_year')::smallint, (e->>'last_year')::smallint,
           ARRAY(SELECT jsonb_array_elements_text(coalesce(e->'licences', '[]'::jsonb))),
           p_process_id, p_source_query
      FROM jsonb_array_elements(p_entries) e;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END;
$$;

COMMENT ON FUNCTION public.replace_site_checklist(integer, integer, text, integer, text, jsonb) IS 'Replace the checklist of one location x radius x source with p_entries (JSON array of {scientific_name, source_taxon_key, taxon_rank, kingdom, phylum, class_name, order_name, family, genus, record_count, first_year, last_year, licences[]}). Returns the number of rows written. Service role only.';
REVOKE ALL ON FUNCTION public.replace_site_checklist(integer, integer, text, integer, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.replace_site_checklist(integer, integer, text, integer, text, jsonb) TO service_role;

-- Read path
CREATE OR REPLACE VIEW public.site_checklists WITH (security_invoker = on) AS
SELECT c.site_checklist_id, c.location_id, l.location_name, c.radius_m, c.source, c.source_taxon_key,
       c.taxon_id, c.scientific_name, c.taxon_rank, c.kingdom, c.phylum, c.class_name, c.order_name,
       c.family, c.genus, c.record_count, c.first_year, c.last_year, c.licences, c.process_id,
       c.fetched_at
  FROM biodiversity.site_checklists c
  JOIN shared.locations l ON l.location_id = c.location_id;

COMMENT ON VIEW public.site_checklists IS 'Public API view: taxa recorded at or near each site, per source and radius (biodiversity.site_checklists).';
GRANT SELECT ON TABLE public.site_checklists TO anon, authenticated;
GRANT ALL ON TABLE public.site_checklists TO service_role;

NOTIFY pgrst, 'reload schema';
