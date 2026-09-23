-- =============================================================================
-- public view columns still advertising the pre-XRFF-487 primary key names
-- =============================================================================
-- A regression from 20260923120000_rename_pk_stems_and_view_names.sql, which
-- shortened two lookup PKs but left the views that expose them aliasing the old
-- long name:
--
--   public.branch_elongation_habits.branch_elongation_habit_id
--   public.phanerophyte_height_classes.phanerophyte_height_class_id
--
-- This is the column-rename gotcha that bit this push twice already. Renaming a
-- base COLUMN rewrites a dependent view's stored definition -- so the view kept
-- working -- but does NOT rename the view's OUTPUT column, because that name was
-- pinned by an explicit AS in the original DDL. A TABLE rename updates both,
-- which is why only these two slipped through.
--
-- The result was an API advertising two `_id` columns that exist nowhere in the
-- base schemas, each sitting beside a `_name` column with a different stem --
-- the exact pairing XRFF-487 set out to remove. It reached only the published
-- views, never a consumer: grepping the dashboard, the three connectors and this
-- repo finds no reference outside the frozen baseline snapshot.
--
-- ALTER VIEW ... RENAME COLUMN renames in place, so security_invoker, owner,
-- grants and comments all survive. DROP+CREATE silently loses every one of them.
--
-- check_naming.py rule 13 now asserts that every `_id` column a public view
-- publishes exists on some base table, so this class cannot return unseen.
--
-- Mirrored to init 56-view-pk-alias-drift.sql.
-- =============================================================================

ALTER VIEW public.branch_elongation_habits
    RENAME COLUMN branch_elongation_habit_id TO elongation_habit_id;

ALTER VIEW public.phanerophyte_height_classes
    RENAME COLUMN phanerophyte_height_class_id TO height_class_id;
