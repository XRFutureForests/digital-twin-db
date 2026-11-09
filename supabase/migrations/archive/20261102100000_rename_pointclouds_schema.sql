-- Rename the schema `pointclouds` to `point_clouds`.
--
-- The schema was the one name in the database not in snake_case: its own table is
-- `point_clouds`, and the other multi-word schema is `forest_floor`. The result,
-- `point_clouds.point_clouds`, follows the same pattern as `trees.trees` and
-- `environments.environments`.
--
-- What moves with the rename and needs nothing here: tables, sequences, indexes,
-- RLS policies, grants, default privileges and every view (views and column
-- defaults hold object ids, not names). What does not move: function bodies,
-- which are stored as text. Of those, only public.point_clouds_insert() names
-- the schema; it is rewritten below. The 'PointClouds' labels in the audit
-- functions are audit-table keys, not schema references.
--
-- Outside the database: PGRST_DB_SCHEMAS in docker/.env must list
-- `point_clouds` instead of `pointclouds`, and PostgREST must be restarted, or
-- it fails to load its schema cache.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'pointclouds')
       AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'point_clouds') THEN
        ALTER SCHEMA pointclouds RENAME TO point_clouds;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.point_clouds_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO point_clouds.point_clouds SELECT NEW.*;
    RETURN NEW;
END;
$function$;
