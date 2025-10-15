-- =============================================================================
-- SUPABASE INITIALIZATION
-- =============================================================================
-- This migration creates the necessary roles and users required by Supabase
-- services (auth, storage, realtime, etc.)
--
-- Execution Order: MUST run first (000_*)
-- =============================================================================

-- Create roles required by Supabase
DO $$
BEGIN
    -- anon role - used by PostgREST for public API access with RLS
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;

    -- authenticated role - used for authenticated users
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;

    -- service_role - used for server-side operations (bypasses RLS)
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN BYPASSRLS;
    END IF;

    -- authenticator - PostgREST connection role that can switch to anon/authenticated/service_role
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator LOGIN NOINHERIT;
        GRANT anon, authenticated, service_role TO authenticator;
    END IF;

    -- supabase_admin - administrative role for Supabase internal operations
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin LOGIN BYPASSRLS CREATEDB CREATEROLE REPLICATION;
    END IF;

    -- supabase_auth_admin - used by GoTrue (Auth service)
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') THEN
        CREATE ROLE supabase_auth_admin LOGIN NOINHERIT CREATEROLE;
    END IF;

    -- supabase_storage_admin - used by Storage API
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin LOGIN NOINHERIT CREATEROLE;
    END IF;

    -- supabase_realtime_admin - used by Realtime service
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_realtime_admin') THEN
        CREATE ROLE supabase_realtime_admin LOGIN NOINHERIT CREATEROLE;
    END IF;
END
$$;

-- Set passwords for service accounts
-- In production, these should use strong, unique passwords
-- For local development, we use the POSTGRES_PASSWORD for simplicity
DO $$
DECLARE
    db_password TEXT := current_setting('app.postgres_password', true);
BEGIN
    IF db_password IS NULL OR db_password = '' THEN
        db_password := 'postgres';  -- default for local development
    END IF;

    EXECUTE format('ALTER USER authenticator WITH PASSWORD %L', db_password);
    EXECUTE format('ALTER USER supabase_admin WITH PASSWORD %L', db_password);
    EXECUTE format('ALTER USER supabase_auth_admin WITH PASSWORD %L', db_password);
    EXECUTE format('ALTER USER supabase_storage_admin WITH PASSWORD %L', db_password);
    EXECUTE format('ALTER USER supabase_realtime_admin WITH PASSWORD %L', db_password);
END
$$;

-- Create schemas for Supabase services
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS realtime;

-- Grant schema permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO supabase_admin, supabase_auth_admin, supabase_storage_admin, supabase_realtime_admin;

-- Grant specific schema permissions to service users
GRANT ALL ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON SCHEMA realtime TO supabase_realtime_admin;

-- Allow service users to create objects in their schemas
ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO supabase_storage_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA realtime GRANT ALL ON TABLES TO supabase_realtime_admin;

-- Grant table permissions (for tables created in public schema)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO supabase_admin;

-- Grant sequence permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO supabase_admin;

-- Grant function permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO supabase_admin;

-- Enable necessary extensions
-- Note: uuid-ossp, pgcrypto, and pgjwt should already be available in Supabase postgres image
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
-- CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA public;
-- CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA public;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Supabase roles and users initialized successfully';
END
$$;
