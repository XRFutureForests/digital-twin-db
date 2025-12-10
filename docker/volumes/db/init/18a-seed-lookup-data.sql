-- XR Future Forests Lab - Essential Lookup/Reference Data
-- This migration provides ONLY essential reference data (species)
-- These are universal lookup values that apply to any installation
-- Note: SoilTypes, ClimateZones, VariantTypes, and Scenarios are already
-- seeded in 11-shared-schema.sql as part of the schema definition

-- =============================================================================
-- SPECIES (Universal reference data)
-- =============================================================================

INSERT INTO shared.Species (CommonName, ScientificName, GrowthCharacteristics) VALUES
    (
        'European Beech',
        'Fagus sylvatica',
        '{"max_height_m": 40, "max_dbh_cm": 150, "typical_lifespan_years": 300, "growth_rate": "moderate", "shade_tolerance": "high"}'::jsonb
    ),
    (
        'Pedunculate Oak',
        'Quercus robur',
        '{"max_height_m": 35, "max_dbh_cm": 200, "typical_lifespan_years": 500, "growth_rate": "slow", "shade_tolerance": "moderate"}'::jsonb
    ),
    (
        'Norway Spruce',
        'Picea abies',
        '{"max_height_m": 50, "max_dbh_cm": 150, "typical_lifespan_years": 200, "growth_rate": "fast", "shade_tolerance": "high"}'::jsonb
    ),
    (
        'Silver Fir',
        'Abies alba',
        '{"max_height_m": 50, "max_dbh_cm": 200, "typical_lifespan_years": 500, "growth_rate": "moderate", "shade_tolerance": "very_high"}'::jsonb
    ),
    (
        'Scots Pine',
        'Pinus sylvestris',
        '{"max_height_m": 35, "max_dbh_cm": 100, "typical_lifespan_years": 300, "growth_rate": "moderate", "shade_tolerance": "low"}'::jsonb
    ),
    (
        'Douglas Fir',
        'Pseudotsuga menziesii',
        '{"max_height_m": 60, "max_dbh_cm": 180, "typical_lifespan_years": 500, "growth_rate": "fast", "shade_tolerance": "moderate"}'::jsonb
    );

-- =============================================================================
-- END OF LOOKUP DATA
-- =============================================================================
