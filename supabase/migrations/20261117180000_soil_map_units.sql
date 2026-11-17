-- =============================================================================
-- Soil map units per site (XRFF-695)
-- =============================================================================
-- The soil map unit a site lies in, with the unit's described properties.
-- First source: LGRB BK50 (Baden-Wuerttemberg soil map 1:50,000, dl-de/by-2-0,
-- "Datenquelle: Regierungspraesidium Freiburg - LGRB"): the WFS
-- services.lgrb-bw.de/ms/lgrb_geola_bod gives the unit at a point, the unit's
-- sheet (media.lgrb-bw.de/link/bod3200/<unit>.pdf) its characteristic values.
--
-- A unit is described once; locations point to it. Values are ranges as the
-- map gives them (a map unit is a mix of soils, not one profile). Text fields
-- keep the source's German wording; numeric ranges are parsed from it.
-- Written only through public.set_soil_map_unit() by the service role
-- (open-data-connector `open-data soil-unit`).
-- =============================================================================

CREATE TABLE IF NOT EXISTS shared.soil_map_units (
    soil_map_unit_id            serial PRIMARY KEY,
    source                      varchar(20) NOT NULL CHECK (source IN ('lgrb_bk50')),
    unit_code                   varchar(20) NOT NULL,
    legend_text                 text NOT NULL,
    sheet_url                   text,
    sheet_date                  date,
    soil_types                  text,
    parent_material             text,
    rooting_depth               text,
    forest_humus_form           text,
    soil_reaction_forest        text,
    field_capacity_text         text,
    field_capacity_min_mm       numeric(6,1),
    field_capacity_max_mm       numeric(6,1),
    available_water_text        text,
    available_water_min_mm      numeric(6,1),
    available_water_max_mm      numeric(6,1),
    air_capacity_text           text,
    permeability_text           text,
    sorption_capacity_text      text,
    sorption_capacity_min       numeric(7,1),
    sorption_capacity_max       numeric(7,1),
    process_id                  integer NOT NULL REFERENCES shared.processes (process_id),
    fetched_at                  date NOT NULL DEFAULT current_date,
    CONSTRAINT soil_map_units_source_code_key UNIQUE (source, unit_code),
    CHECK (field_capacity_min_mm IS NULL OR field_capacity_max_mm IS NULL OR field_capacity_min_mm <= field_capacity_max_mm),
    CHECK (available_water_min_mm IS NULL OR available_water_max_mm IS NULL OR available_water_min_mm <= available_water_max_mm),
    CHECK (sorption_capacity_min IS NULL OR sorption_capacity_max IS NULL OR sorption_capacity_min <= sorption_capacity_max)
);

COMMENT ON TABLE shared.soil_map_units IS 'Soil map units with their described properties, one row per source x unit; shared.locations.soil_map_unit_id points here. lgrb_bk50: BK50 Baden-Wuerttemberg (LGRB), dl-de/by-2-0, attribution "Datenquelle: Regierungspraesidium Freiburg - LGRB, https://www.lgrb-bw.de". Ranges, because a map unit is a mix of soils.';
COMMENT ON COLUMN shared.soil_map_units.unit_code IS 'Map unit code in the source (BK50 Kartiereinheit, e.g. b132).';
COMMENT ON COLUMN shared.soil_map_units.legend_text IS 'Legend text of the unit, as in the source (German).';
COMMENT ON COLUMN shared.soil_map_units.sheet_url IS 'Unit description sheet the values were read from.';
COMMENT ON COLUMN shared.soil_map_units.sheet_date IS 'Date printed on the sheet.';
COMMENT ON COLUMN shared.soil_map_units.rooting_depth IS 'Gruendigkeit: soil depth and rootability, as in the source.';
COMMENT ON COLUMN shared.soil_map_units.forest_humus_form IS 'Waldhumusform (forest humus form), as in the source.';
COMMENT ON COLUMN shared.soil_map_units.soil_reaction_forest IS 'Bodenreaktion under forest (soil acidity class), as in the source.';
COMMENT ON COLUMN shared.soil_map_units.available_water_min_mm IS 'Nutzbare Feldkapazitaet (plant-available water capacity) to 10 dm, lower bound in mm.';
COMMENT ON COLUMN shared.soil_map_units.available_water_max_mm IS 'Nutzbare Feldkapazitaet to 10 dm, upper bound in mm.';
COMMENT ON COLUMN shared.soil_map_units.field_capacity_min_mm IS 'Feldkapazitaet (field capacity) to 10 dm, lower bound in mm.';
COMMENT ON COLUMN shared.soil_map_units.sorption_capacity_min IS 'Sorptionskapazitaet (potential cation exchange capacity) to 10 dm, lower bound in mol/z per m2.';

ALTER TABLE shared.locations
    ADD COLUMN IF NOT EXISTS soil_map_unit_id integer REFERENCES shared.soil_map_units (soil_map_unit_id) ON DELETE SET NULL;
COMMENT ON COLUMN shared.locations.soil_map_unit_id IS 'Soil map unit at the location''s center_point (shared.soil_map_units), set by open-data-connector `open-data soil-unit`.';

ALTER TABLE shared.soil_map_units ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Soil map units are viewable by everyone" ON shared.soil_map_units;
CREATE POLICY "Soil map units are viewable by everyone" ON shared.soil_map_units FOR SELECT USING (true);
GRANT SELECT ON TABLE shared.soil_map_units TO anon, authenticated;
GRANT ALL ON TABLE shared.soil_map_units TO service_role;
GRANT USAGE ON SEQUENCE shared.soil_map_units_soil_map_unit_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.set_soil_map_unit(p_location_id integer, p_process_id integer, p_unit jsonb)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
    allowed text[] := ARRAY['source', 'unit_code', 'legend_text', 'sheet_url', 'sheet_date', 'soil_types',
        'parent_material', 'rooting_depth', 'forest_humus_form', 'soil_reaction_forest', 'field_capacity_text',
        'field_capacity_min_mm', 'field_capacity_max_mm', 'available_water_text', 'available_water_min_mm',
        'available_water_max_mm', 'air_capacity_text', 'permeability_text', 'sorption_capacity_text',
        'sorption_capacity_min', 'sorption_capacity_max'];
    unknown text;
    v_id integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM shared.locations WHERE location_id = p_location_id) THEN
        RAISE EXCEPTION 'set_soil_map_unit: unknown location_id %', p_location_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM shared.processes WHERE process_id = p_process_id) THEN
        RAISE EXCEPTION 'set_soil_map_unit: unknown process_id %', p_process_id;
    END IF;
    -- an unknown key is a typo in the connector, not something to skip
    SELECT string_agg(k, ', ') INTO unknown FROM jsonb_object_keys(p_unit) k WHERE k <> ALL (allowed);
    IF unknown IS NOT NULL THEN
        RAISE EXCEPTION 'set_soil_map_unit: unknown key(s) %', unknown;
    END IF;

    INSERT INTO shared.soil_map_units AS u (
        source, unit_code, legend_text, sheet_url, sheet_date, soil_types, parent_material, rooting_depth,
        forest_humus_form, soil_reaction_forest, field_capacity_text, field_capacity_min_mm, field_capacity_max_mm,
        available_water_text, available_water_min_mm, available_water_max_mm, air_capacity_text, permeability_text,
        sorption_capacity_text, sorption_capacity_min, sorption_capacity_max, process_id, fetched_at)
    VALUES (
        p_unit->>'source', p_unit->>'unit_code', p_unit->>'legend_text', p_unit->>'sheet_url',
        (p_unit->>'sheet_date')::date, p_unit->>'soil_types', p_unit->>'parent_material', p_unit->>'rooting_depth',
        p_unit->>'forest_humus_form', p_unit->>'soil_reaction_forest', p_unit->>'field_capacity_text',
        (p_unit->>'field_capacity_min_mm')::numeric, (p_unit->>'field_capacity_max_mm')::numeric,
        p_unit->>'available_water_text', (p_unit->>'available_water_min_mm')::numeric,
        (p_unit->>'available_water_max_mm')::numeric, p_unit->>'air_capacity_text', p_unit->>'permeability_text',
        p_unit->>'sorption_capacity_text', (p_unit->>'sorption_capacity_min')::numeric,
        (p_unit->>'sorption_capacity_max')::numeric, p_process_id, current_date)
    ON CONFLICT (source, unit_code) DO UPDATE SET
        legend_text = EXCLUDED.legend_text, sheet_url = EXCLUDED.sheet_url, sheet_date = EXCLUDED.sheet_date,
        soil_types = EXCLUDED.soil_types, parent_material = EXCLUDED.parent_material,
        rooting_depth = EXCLUDED.rooting_depth, forest_humus_form = EXCLUDED.forest_humus_form,
        soil_reaction_forest = EXCLUDED.soil_reaction_forest, field_capacity_text = EXCLUDED.field_capacity_text,
        field_capacity_min_mm = EXCLUDED.field_capacity_min_mm, field_capacity_max_mm = EXCLUDED.field_capacity_max_mm,
        available_water_text = EXCLUDED.available_water_text,
        available_water_min_mm = EXCLUDED.available_water_min_mm,
        available_water_max_mm = EXCLUDED.available_water_max_mm, air_capacity_text = EXCLUDED.air_capacity_text,
        permeability_text = EXCLUDED.permeability_text, sorption_capacity_text = EXCLUDED.sorption_capacity_text,
        sorption_capacity_min = EXCLUDED.sorption_capacity_min, sorption_capacity_max = EXCLUDED.sorption_capacity_max,
        process_id = EXCLUDED.process_id, fetched_at = EXCLUDED.fetched_at
    RETURNING u.soil_map_unit_id INTO v_id;

    UPDATE shared.locations SET soil_map_unit_id = v_id WHERE location_id = p_location_id;
    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.set_soil_map_unit(integer, integer, jsonb) IS 'Upsert a soil map unit (by source and unit_code) and point the location to it. Raises on an unknown key. Service role only.';
REVOKE ALL ON FUNCTION public.set_soil_map_unit(integer, integer, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_soil_map_unit(integer, integer, jsonb) TO service_role;

CREATE OR REPLACE VIEW public.location_soil WITH (security_invoker = on) AS
SELECT l.location_id, l.location_name, u.source, u.unit_code, u.legend_text, u.soil_types, u.parent_material,
       u.rooting_depth, u.forest_humus_form, u.soil_reaction_forest, u.field_capacity_min_mm,
       u.field_capacity_max_mm, u.available_water_min_mm, u.available_water_max_mm, u.air_capacity_text,
       u.permeability_text, u.sorption_capacity_min, u.sorption_capacity_max, u.sheet_url, u.sheet_date,
       u.process_id
  FROM shared.locations l
  JOIN shared.soil_map_units u ON u.soil_map_unit_id = l.soil_map_unit_id;

COMMENT ON VIEW public.location_soil IS 'Public API view: the soil map unit of each location with its described properties (shared.soil_map_units).';
GRANT SELECT ON TABLE public.location_soil TO anon, authenticated;
GRANT ALL ON TABLE public.location_soil TO service_role;

NOTIFY pgrst, 'reload schema';
