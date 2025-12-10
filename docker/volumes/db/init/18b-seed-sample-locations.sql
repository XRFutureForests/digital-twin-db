-- XR Future Forests Lab - Sample Location Data
-- This migration provides sample locations for development and testing
-- These locations are required for the Aquarius/Ecosense integration to work
-- 
-- For production deployments, you may want to replace these with your actual locations
-- or import locations using the CSV importer tool (scripts/import-data/csv_importer.py)

-- =============================================================================
-- SAMPLE LOCATIONS (Required for Ecosense integration and sensor linking)
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
-- END OF SAMPLE LOCATION DATA
-- =============================================================================
