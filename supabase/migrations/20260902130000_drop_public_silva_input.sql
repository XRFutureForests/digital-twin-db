-- =============================================================================
-- Drop public.silva_input
-- =============================================================================
-- XRFF-351 / XRFF-244. The view was built for a CSV round-trip that was never
-- implemented: export silva_input to CSV, run SILVA in R by hand, feed the CSV
-- back through a Python script. The live coupling is silva-connector, which
-- reads trees.Trees / shared.Species directly and writes back over libpq in one
-- transaction. Nothing has ever read this view.
--
-- It is not merely unused, it is wrong in three ways -- all three re-verified
-- against the running database on 2026-09-02:
--
-- 1. `ba` emits legacy SILVA 4.5 species codes (4 = Douglasie, 5 = Laerche,
--    11 = Buche). silvaR works in ForestElementsR's `tum_wwk_short`, where
--    4 = Larix, 5 = Fagus, 6 = Quercus. The two codings collide on 4, 5 and 6,
--    so feeding `ba` to the model silently turns Douglas fir into larch and
--    larch into beech. It fails no check and raises no error; the stand simply
--    grows as the wrong species. silva-connector/R/species.R:10-13 documents
--    exactly this and maps from scientific_name instead.
--
-- 2. The data-source filter (`field | lidar | photogrammetry`) returns 1,198 of
--    the 2,225 measured trees and *zero* mathisle trees -- every mathisle tree
--    is typed `estimated`, as are 297 ecosense trees.
--
-- 3. There is no way to select a base variant, so it can only ever describe the
--    measured baseline, never a projected state to continue from.
--
-- Rewriting it around scientific_name and absolute coordinates was considered
-- and rejected: there would still be no reader. silva-connector deliberately
-- queries the base tables (see digital-twin-db/AGENTS.md), and a corrected view
-- with no consumer is another thing to keep in step with the schema. A wrong
-- view in the public schema is worse than no view, because the next person to
-- find it will reasonably assume it works.
--
-- Recovering it, should a future export surface want one, means writing a new
-- view against scientific_name -- not restoring this definition. The old body
-- is in supabase/migrations/20260717093000_baseline_snapshot.sql.
--
-- Idempotent.
-- =============================================================================

DROP VIEW IF EXISTS public.silva_input;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'silva_input') THEN
        RAISE EXCEPTION 'public.silva_input still exists';
    END IF;
    RAISE NOTICE 'public.silva_input dropped (XRFF-351)';
END $$;
