-- =============================================================================
-- 01: ENABLE POSTGIS EXTENSION
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- This must run before forest schema migrations that depend on PostGIS types
-- =============================================================================

-- Create extensions schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS extensions;

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions CASCADE;
CREATE EXTENSION IF NOT EXISTS postgis_topology SCHEMA extensions CASCADE;

-- Add extensions to search path for all sessions
ALTER DATABASE forest_twin SET search_path TO "$user", public, extensions;

-- Also set for current session
SET search_path TO "$user", public, extensions;

-- Log success
DO $$
BEGIN
    RAISE NOTICE '✅ PostGIS extension enabled in extensions schema';
END
$$;
