-- =============================================================================
-- Site conditions required by the SILVA growth model
-- =============================================================================
-- Consumer: silva-connector. silvaR's site_conditions_coarse() needs eight
-- inputs per stand. Five were already derivable from shared.Locations
-- (latitude from center_point, elevation_m, slope_deg, aspect) or from the run
-- itself (calendar year). The three added here had no home in the schema, so
-- the connector would otherwise have to carry them in its own config — which
-- would make site conditions invisible to every other consumer of the twin.
--
-- Deliberately on Locations rather than Plots: these vary at landscape scale,
-- and shared.Plots currently carries no geometry at all, so a per-plot value
-- would have nothing to attach to.
-- =============================================================================

ALTER TABLE shared.Locations
    ADD COLUMN IF NOT EXISTS forest_growth_region VARCHAR(16),
    ADD COLUMN IF NOT EXISTS soil_moistness       SMALLINT,
    ADD COLUMN IF NOT EXISTS soil_nutrient_supply SMALLINT;

-- Idempotent constraint (re)creation: ADD CONSTRAINT has no IF NOT EXISTS.
ALTER TABLE shared.Locations DROP CONSTRAINT IF EXISTS locations_soil_moistness_check;
ALTER TABLE shared.Locations
    ADD CONSTRAINT locations_soil_moistness_check
    CHECK (soil_moistness IS NULL OR (soil_moistness BETWEEN 1 AND 9));

ALTER TABLE shared.Locations DROP CONSTRAINT IF EXISTS locations_soil_nutrient_supply_check;
ALTER TABLE shared.Locations
    ADD CONSTRAINT locations_soil_nutrient_supply_check
    CHECK (soil_nutrient_supply IS NULL OR (soil_nutrient_supply BETWEEN 1 AND 5));

COMMENT ON COLUMN shared.Locations.forest_growth_region IS
    'German forest growth region code (Wuchsgebiet.Wuchsbezirk), e.g. ''99.73.11''. '
    'Keys SILVA/silvaR''s internal climate table, which supplies temperature, '
    'precipitation and vegetation-period length for the site. Derived once by '
    'point-in-polygon against the Thuenen Wuchsbezirke 2020 layer; see '
    'silva-connector/docs/site-conditions.md for provenance.';

COMMENT ON COLUMN shared.Locations.soil_moistness IS
    'SILVA soil moisture class, 1-9 (1 = very dry, 5 = fresh, 9 = very wet). '
    'Not derivable from soil_type_id: shared.SoilTypes holds USDA soil orders '
    '(Alfisol, Spodosol, ...), which describe pedogenesis rather than water '
    'supply. Requires a site survey value.';

COMMENT ON COLUMN shared.Locations.soil_nutrient_supply IS
    'SILVA soil nutrient supply class, 1-5 (1 = very low, 5 = very high). '
    'Like soil_moistness, independent of the USDA order in soil_type_id and '
    'requires a site survey value.';
