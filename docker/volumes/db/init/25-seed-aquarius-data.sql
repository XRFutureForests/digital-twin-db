-- Aquarius Seed Data Migration
-- This script creates the Ecosense_MixedPlot location for Aquarius sensor data
-- Sensors and readings will be fetched dynamically by the ecosense-ingest edge function
-- 
-- To populate sensor data after startup, run:
--   ./scripts/sync-aquarius.sh
-- Or call the edge function directly:
--   curl -X POST "http://localhost:8000/functions/v1/ecosense-ingest?days_back=30" \
--     -H "Authorization: Bearer $SERVICE_ROLE_KEY"

SET search_path TO sensor, shared, public;

-- =============================================================================
-- CREATE ECOSENSE LOCATION
-- The ecosense-ingest function will auto-create locations, but we pre-create
-- the main plot location with proper metadata
-- =============================================================================

INSERT INTO shared.Locations (LocationName, Description)
VALUES (
    'Ecosense_MixedPlot', 
    'Ecosense sensor network - Mixed species plot at University of Freiburg forest research site'
)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- SUMMARY
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Aquarius/Ecosense Integration Ready';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Location "Ecosense_MixedPlot" created for sensor data';
    RAISE NOTICE '';
    RAISE NOTICE 'To fetch sensor data from Aquarius API:';
    RAISE NOTICE '  ./scripts/sync-aquarius.sh';
    RAISE NOTICE '';
    RAISE NOTICE 'Or call the edge function:';
    RAISE NOTICE '  curl -X POST "http://localhost:8000/functions/v1/ecosense-ingest?days_back=30" \';
    RAISE NOTICE '    -H "Authorization: Bearer $SERVICE_ROLE_KEY"';
    RAISE NOTICE '';
    RAISE NOTICE 'Note: Requires university VPN connection for Aquarius access';
    RAISE NOTICE '=======================================================';
END $$;
