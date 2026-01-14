-- =============================================================================
-- 07: SEED LOCATIONS
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- Sample locations for the forest research plots
-- =============================================================================

SET search_path TO shared, public, extensions;

-- =============================================================================
-- SAMPLE LOCATIONS
-- =============================================================================

-- EcoSense Mixed Plot (for ecosense_250911.csv data)
-- UTM Zone 32N coordinates roughly around Freiburg
INSERT INTO shared.Locations (LocationName, Boundary, CenterPoint, Description, Elevation_m, Slope_deg, Aspect, SoilTypeID, ClimateZoneID) VALUES
    (
        'EcoSense Mixed Plot',
        ST_GeomFromText('POLYGON((8.085 47.883, 8.092 47.883, 8.092 47.888, 8.085 47.888, 8.085 47.883))', 4326),
        ST_GeomFromText('POINT(8.088 47.885)', 4326),
        'EcoSense mixed forest plot with Douglas Fir and Beech near Freiburg, Germany. Contains sensor-monitored trees.',
        520.0,
        8.0,
        'NE',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Alfisol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Cfb')
    );

-- Mathisleweiher Plot (for mathisle_250904.csv data)
INSERT INTO shared.Locations (LocationName, Boundary, CenterPoint, Description, Elevation_m, Slope_deg, Aspect, SoilTypeID, ClimateZoneID) VALUES
    (
        'Mathisleweiher Plot',
        ST_GeomFromText('POLYGON((8.086 47.883, 8.091 47.883, 8.091 47.886, 8.086 47.886, 8.086 47.883))', 4326),
        ST_GeomFromText('POINT(8.088 47.885)', 4326),
        'Mathisleweiher forest research plot, predominantly European Beech stand.',
        1050.0,
        12.0,
        'NW',
        (SELECT SoilTypeID FROM shared.SoilTypes WHERE SoilTypeName = 'Spodosol'),
        (SELECT ClimateZoneID FROM shared.ClimateZones WHERE ClimateZoneName = 'Dfb')
    );

DO $$
BEGIN
    RAISE NOTICE '✅ Sample locations seeded';
END
$$;
