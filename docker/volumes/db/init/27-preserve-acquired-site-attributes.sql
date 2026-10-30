-- =============================================================================
-- A lookup refresh must not revert an acquired site attribute
-- =============================================================================
-- XRFF-391. shared.Locations carries eight settable site-attribute columns, and
-- two separate paths reseed all eight from data/lookups/locations.csv with
-- ON CONFLICT (location_name) DO UPDATE SET:
--
--   30-load-lookup-tables.sql        on a fresh build
--   shared.refresh_lookup('locations')  on a live database, via
--                                    scripts/admin/refresh_lookups.py
--
-- Since 20260902140000 those columns can also be written by
-- public.set_location_attributes, which records where each value came from in
-- shared.AttributeProvenance. Neither loader knew about that table, so a refresh
-- reverted the acquired value **and left its provenance row behind** -- the
-- database would then assert, through public.attributeprovenance, that
-- elevation_m came from EDTM30 v1.1 at 30 m under CC-BY-4.0, for a column
-- holding the number that was there before.
--
-- That is worse than an unattributed value, and it is exactly what the open-data
-- connector (XRFF-368) exists to prevent. It is also the XRFF-388 lesson
-- generalised: a value written only to shared.Locations is not durable, because
-- the CSV is still its owner.
--
-- The rule this file establishes: **the CSV seeds, acquisition owns thereafter.**
-- A column with an AttributeProvenance row keeps its value through any number of
-- refreshes; a column without one is still reseeded from the CSV exactly as
-- before. No new state was needed -- AttributeProvenance already *is* the record
-- of "this value is owned by acquisition". A fresh build is unaffected, because
-- the table is empty at that point and every column reseeds.
--
-- center_point is deliberately NOT covered. XRFF-388 established that the CSV is
-- its right home -- a DB-only fix there was undone by the next rebuild, which is
-- why that fix changed both. It is a surveyed identity, not an acquired
-- attribute, and nothing writes it through set_location_attributes.
--
-- This file only creates the helper, because 30- and 31- (which use it) are
-- loaded after it on a fresh build and already carry the guarded upserts. The
-- matching migration 20260902180000 additionally replaces shared.refresh_lookup,
-- which an existing database still holds in its unguarded form.
-- =============================================================================

SET search_path TO shared, public;

CREATE OR REPLACE FUNCTION shared.attribute_is_acquired(
    p_location_id INTEGER,
    p_column_name TEXT
)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1
        FROM shared.AttributeProvenance
        WHERE location_id = p_location_id
          AND column_name = p_column_name
    );
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION shared.attribute_is_acquired IS
    'True when a shared.Locations column was written by an acquisition process and '
    'therefore must not be reseeded from data/lookups/locations.csv (XRFF-391).';

GRANT EXECUTE ON FUNCTION shared.attribute_is_acquired(INTEGER, TEXT) TO postgres, service_role;
