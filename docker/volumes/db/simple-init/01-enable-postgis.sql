-- =============================================================================
-- 01: ENABLE POSTGIS EXTENSION
-- =============================================================================
-- Digital Forest Twin - Simplified PostgreSQL Setup
-- This must run before forest schema migrations that depend on PostGIS types
-- =============================================================================

-- Create extensions schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS extensions;

-- Enable PostGIS extension in public schema (simpler, avoids search path issues)
CREATE EXTENSION IF NOT EXISTS postgis CASCADE;

-- Add extensions to search path for all sessions (use current database name)
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path TO "$user", public, extensions', current_database());
END
$$;

-- Also set for current session
SET search_path TO "$user", public, extensions;

-- Log success
DO $$
BEGIN
    RAISE NOTICE '✅ PostGIS extension enabled in extensions schema';
END
$$;
