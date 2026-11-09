-- =============================================================================
-- trees.fill_from_variant(): no EXECUTE for PUBLIC (XRFF-661)
-- =============================================================================
-- dt.unr ran 20261109100000 in its corrected form, whose global default
-- privilege closes new functions to PUBLIC before the function is created.
-- Dev and the 2026-11-09 snapshot were built from the first form, where the
-- per-schema statement was a no-op, so the trigger function kept PUBLIC's
-- default EXECUTE there. A trigger function needs no EXECUTE to fire; this
-- only makes every database agree.
-- =============================================================================

REVOKE ALL ON FUNCTION trees.fill_from_variant() FROM PUBLIC;
