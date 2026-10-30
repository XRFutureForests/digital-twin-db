-- =============================================================================
-- INSTEAD OF UPDATE/DELETE triggers on public views: report rows RLS skipped
-- =============================================================================
-- public.trees, public.sensors and public.campaigns are written through
-- INSTEAD OF triggers. Each UPDATE / DELETE trigger runs its statement against
-- the base table as the caller (SECURITY INVOKER), so RLS applies -- and when
-- RLS filters the row out, the statement touches nothing, but the trigger
-- still returns NEW / OLD. PostgREST then reports the row as updated or
-- deleted.
--
-- Measured on dev 2026-10-30: a contributor PATCHing public.trees (trees may
-- only be updated by curators) got 200 with the row in the body; nothing was
-- written. The same PATCH on public.stems -- an auto-updatable view, no
-- trigger -- correctly returned []. Found while building the portal's data
-- page, which would otherwise tell a contributor their correction was saved.
--
-- Fix: after the base-table statement, `IF NOT FOUND THEN RETURN NULL`. A NULL
-- from an INSTEAD OF row trigger means "this row was not processed", so the
-- caller sees 0 rows -- exactly what an auto-updatable view says. No error
-- semantics change, nothing changes for callers that were allowed.
--
-- Applied by rewriting each body's single RETURN statement, with a check that
-- there is exactly one, rather than restating the 45-column trees_update body
-- here: the check fails loudly if a later migration reshapes a body, where a
-- restated copy would silently revert it.
--
-- Mirrored to init 69-view-triggers-report-rls-skips.sql.
-- =============================================================================

DO $$
DECLARE
    f      record;
    v_src  text;
    v_ret  text;
    v_hits int;
BEGIN
    FOR f IN
        SELECT * FROM (VALUES
            ('trees_update',     'NEW'), ('trees_delete',     'OLD'),
            ('sensors_update',   'NEW'), ('sensors_delete',   'OLD'),
            ('campaigns_update', 'NEW'), ('campaigns_delete', 'OLD')
        ) AS v(fname, rec)
    LOOP
        SELECT p.prosrc INTO v_src
          FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.fname;

        IF v_src IS NULL THEN
            RAISE EXCEPTION 'public.%() not found', f.fname;
        END IF;

        -- Already applied on a re-run.
        CONTINUE WHEN v_src LIKE '%IF NOT FOUND THEN RETURN NULL; END IF;%';

        v_ret  := 'RETURN ' || f.rec || ';';
        v_hits := (length(v_src) - length(replace(v_src, v_ret, ''))) / length(v_ret);
        IF v_hits <> 1 THEN
            RAISE EXCEPTION 'public.%() has % "%" statements, expected exactly 1 -- body changed, patch by hand',
                f.fname, v_hits, v_ret;
        END IF;

        v_src := replace(v_src, v_ret, 'IF NOT FOUND THEN RETURN NULL; END IF;' || chr(10) || '    ' || v_ret);

        EXECUTE format('CREATE OR REPLACE FUNCTION public.%I() RETURNS trigger LANGUAGE plpgsql AS %L',
                       f.fname, v_src);
    END LOOP;
END;
$$;
