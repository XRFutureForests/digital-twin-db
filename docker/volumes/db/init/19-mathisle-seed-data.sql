-- Mathisle Tree Data Seed
-- This script adds the Mathisle location and species data required for tree imports
-- Tree data is imported separately via CSV or direct insert

SET search_path TO shared, trees, public;

-- ============================================================================
-- Add Mathisle location
-- ============================================================================
INSERT INTO shared.locations (locationname, description, centerpoint)
SELECT 'Mathisle', 'Mathisle field research area - University of Freiburg', 
       extensions.ST_SetSRID(extensions.ST_MakePoint(8.088, 47.885), 4326)
WHERE NOT EXISTS (SELECT 1 FROM shared.locations WHERE locationname = 'Mathisle');

-- ============================================================================
-- Add additional tree species found in Mathisle data
-- ============================================================================
INSERT INTO shared.species (commonname, scientificname) 
SELECT * FROM (VALUES 
    ('European Larch', 'Larix decidua'),
    ('Norway Maple', 'Acer platanoides'),
    ('Sycamore Maple', 'Acer pseudoplatanus'),
    ('Wild Cherry', 'Prunus avium'),
    ('Wild Service Tree', 'Sorbus torminalis'),
    ('Birch', 'Betula spp.')
) AS new_species(commonname, scientificname)
WHERE NOT EXISTS (
    SELECT 1 FROM shared.species s WHERE s.commonname = new_species.commonname
);

-- ============================================================================
-- Species code mapping for CSV imports
-- ============================================================================
COMMENT ON TABLE shared.species IS 'Tree species lookup table. CSV codes: BE=European Beech, NS=Norway Spruce, ESF=Silver Fir, ELA=European Larch, NOM=Norway Maple, SY=Sycamore Maple, WCH=Wild Cherry, WST=Wild Service Tree, XBI=Birch';

-- Show what was created
DO $$
DECLARE
    loc_count INTEGER;
    species_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO loc_count FROM shared.locations WHERE locationname = 'Mathisle';
    SELECT COUNT(*) INTO species_count FROM shared.species;
    
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'Mathisle Seed Data Summary';
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'Mathisle location: %', CASE WHEN loc_count > 0 THEN 'Created/Exists' ELSE 'Failed' END;
    RAISE NOTICE 'Total species available: %', species_count;
    RAISE NOTICE '======================================================';
END $$;
