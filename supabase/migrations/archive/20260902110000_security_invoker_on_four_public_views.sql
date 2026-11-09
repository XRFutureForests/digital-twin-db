-- =============================================================================
-- security_invoker on four public views
-- =============================================================================
-- XRFF-378. public.scenarios and public.variants were created without
-- security_invoker in the baseline snapshot; public.treeparttypes and
-- public.rootsystemtypes (added 2026-07-30 by 20260730140000) continued the
-- drift. Without it the views run as their owner (supabase_admin), which
-- bypasses row-level security on the base tables -- so anon can write through
-- them today.
--
-- Deliberately scoped to these four. ue_trees, growth_simulations,
-- simulation_runs and silva_input are the anon-facing Unreal endpoints;
-- XRFF-239 has not yet given any user a role claim, so flipping those could
-- make them return nothing. They get a separate, deliberate pass.
--
-- The grants below are not incidental: with security_invoker the caller needs
-- privileges on the base table, and 20260730140000 granted none on
-- trees.TreePartTypes / trees.RootSystemTypes at all. Without them the flip
-- would make both views return "permission denied" for every REST role. The
-- privileges granted are exactly the pattern every other trees.* table
-- already follows (SELECT to anon/authenticated, ALL to service_role,
-- sequence USAGE to authenticated/service_role), and both tables already
-- carry a "Tree reference tables are viewable by everyone" SELECT policy that
-- these grants let take effect.
-- =============================================================================

ALTER VIEW public.scenarios       SET (security_invoker = on);
ALTER VIEW public.variants        SET (security_invoker = on);
ALTER VIEW public.treeparttypes   SET (security_invoker = on);
ALTER VIEW public.rootsystemtypes SET (security_invoker = on);

GRANT SELECT ON TABLE trees.TreePartTypes   TO anon, authenticated;
GRANT SELECT ON TABLE trees.RootSystemTypes TO anon, authenticated;
GRANT ALL    ON TABLE trees.TreePartTypes   TO service_role;
GRANT ALL    ON TABLE trees.RootSystemTypes TO service_role;

GRANT USAGE ON SEQUENCE trees.treeparttypes_part_type_id_seq          TO authenticated, service_role;
GRANT USAGE ON SEQUENCE trees.rootsystemtypes_root_system_type_id_seq TO authenticated, service_role;
