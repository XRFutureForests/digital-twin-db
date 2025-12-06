-- XR Future Forests Lab - Essential Reference Data Only
-- This migration provides ONLY essential reference data (species, soil types, climate zones)
-- All other data (locations, trees, sensors) must be loaded manually using the CSV importer tool
-- Locations, pointclouds, trees, and sensor data are NOT included here

-- Note: Locations are seeded because they are referenced by the Aquarius integration
-- and ecosense sensor mappings
-- =============================================================================
-- LOCATIONS (Required for Ecosense integration and sensor linking)
-- =============================================================================

INSERT INTO shared.Locations (LocationName, Boundary, CenterPoint, Description, Elevation_m, Slope_deg, Aspect, SoilTypeID, ClimateZoneID) VALUES
    (
        'University Forest Plot A',
        ST_GeomFromText('POLYGON((7.85 47.99, 7.86 47.99, 7.86 48.00, 7.85 48.00, 7.85 47.99))', 4326),
        ST_GeomFromText('POINT(7.855 47.995)', 4326),
        'Primary research plot in mature mixed forest near Freiburg, Germany',
        450.0,
        12.5,
        'NW',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Alfisol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Cfb')
    ),
    (
        'University Forest Plot B',
        ST_GeomFromText('POLYGON((7.87 47.98, 7.88 47.98, 7.88 47.99, 7.87 47.99, 7.87 47.98))', 4326),
        ST_GeomFromText('POINT(7.875 47.985)', 4326),
        'Secondary research plot in regenerating forest',
        425.0,
        8.3,
        'N',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Alfisol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Cfb')
    ),
    (
        'Black Forest Test Site',
        ST_GeomFromText('POLYGON((8.10 48.50, 8.12 48.50, 8.12 48.52, 8.10 48.52, 8.10 48.50))', 4326),
        ST_GeomFromText('POINT(8.11 48.51)', 4326),
        'High-elevation Black Forest monitoring site',
        950.0,
        22.0,
        'SW',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Spodosol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Dfb')
    );

-- =============================================================================
-- SAMPLE SPECIES
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
    );

-- =============================================================================
-- END OF ESSENTIAL REFERENCE DATA
-- =============================================================================
-- All other data (point clouds, trees, sensors, readings) must be loaded manually
-- via the CSV importer tool (scripts/import-data/csv_importer.py)
-- or via Edge Functions (for ecosense sensor sync)
-- =============================================================================

