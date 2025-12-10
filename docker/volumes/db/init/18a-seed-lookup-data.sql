-- XR Future Forests Lab - Essential Lookup/Reference Data
-- This migration provides ONLY essential reference data (species)
-- These are universal lookup values that apply to any installation
-- Note: SoilTypes, ClimateZones, VariantTypes, and Scenarios are already
-- seeded in 11-shared-schema.sql as part of the schema definition

-- =============================================================================
-- SPECIES (Universal reference data)
-- =============================================================================

INSERT INTO shared.Species (CommonName, ScientificName, MaxHeight_m, MaxDBH_cm, TypicalLifespan_years, GrowthRate, ShadeTolerance) VALUES
    ('European Beech', 'Fagus sylvatica', 40, 150, 300, 'moderate', 'high'),
    ('Pedunculate Oak', 'Quercus robur', 35, 200, 500, 'slow', 'moderate'),
    ('Norway Spruce', 'Picea abies', 50, 150, 200, 'fast', 'high'),
    ('Silver Fir', 'Abies alba', 50, 200, 500, 'moderate', 'very_high'),
    ('Scots Pine', 'Pinus sylvestris', 35, 100, 300, 'moderate', 'low'),
    ('Douglas Fir', 'Pseudotsuga menziesii', 60, 180, 500, 'fast', 'moderate');

-- =============================================================================
-- END OF LOOKUP DATA
-- =============================================================================
