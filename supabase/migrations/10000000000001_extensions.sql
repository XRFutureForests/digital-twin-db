-- PostGIS and the grants on the extensions schema. Runs before the platform's
-- own migrations (name order), where the old 10-baseline-schema.sql ran, so the
-- platform's later grants on extension objects reach PostGIS too.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis SCHEMA extensions CASCADE;
CREATE EXTENSION IF NOT EXISTS postgis_topology SCHEMA extensions CASCADE;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA extensions TO anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA extensions TO anon, authenticated, service_role;
ALTER DATABASE postgres SET search_path TO "$user", public, extensions;
