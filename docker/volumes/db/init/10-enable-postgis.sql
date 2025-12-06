-- =============================================================================
-- ENABLE POSTGIS EXTENSION
-- =============================================================================
-- This must run before forest schema migrations that depend on PostGIS types
-- =============================================================================

-- Create extensions schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS extensions;

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions CASCADE;
CREATE EXTENSION IF NOT EXISTS postgis_topology SCHEMA extensions CASCADE;

-- Grant permissions to Supabase roles
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA extensions TO anon, authenticated, service_role;

-- Add extensions to search path
ALTER DATABASE postgres SET search_path TO "$user", public, extensions;

-- Log success
DO $$
BEGIN
    RAISE NOTICE '✅ PostGIS extension enabled in extensions schema';
END
$$;
