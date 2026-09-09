-- =============================================================================
-- request_job(): tell a rejected caller something true
-- =============================================================================
-- XRFF-422. The HINT written in 20260902160000 said "No user carries an
-- app_metadata.role claim yet (XRFF-239), so this rejects everyone today."
-- That was accurate while auth.users was empty. It stopped being accurate on
-- 2026-09-09, when the first accounts were created and a contributor queued
-- the queue's first two jobs -- and a hint that blames a closed issue sends
-- the next person who genuinely lacks a role tier looking in the wrong place.
--
-- The replacement says what to do about it, and names the one case that no
-- role tier fixes: Studio's SQL Editor reaches the database as supabase_admin
-- through the meta service, so auth.jwt() is null and is_contributor() is
-- false there regardless of who is logged in.
--
-- Body otherwise byte-identical to 20260902160000; only the HINT changes.
-- Idempotent: safe to re-run.
-- =============================================================================


CREATE OR REPLACE FUNCTION public.request_job(
    workflow        text,
    params          jsonb DEFAULT '{}'::jsonb,
    external_job_id text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    proc   record;
    job_id integer;
BEGIN
    IF NOT shared.is_contributor() THEN
        RAISE EXCEPTION 'requesting a job requires the contributor role'
            USING ERRCODE = '42501',
                  HINT = 'The caller needs an app_metadata.role of contributor, '
                         'curator or admin -- see data-access-guide.md, '
                         '"Assigning a role tier". Note that the Studio SQL '
                         'Editor connects as supabase_admin with no JWT, so it '
                         'can never satisfy this check however privileged the '
                         'person at the keyboard is.';
    END IF;

    SELECT p.workflow_key, p.version, p.param_schema
      INTO proc
      FROM shared.Processes p
     WHERE p.workflow_key = request_job.workflow;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown workflow "%"', request_job.workflow
            USING ERRCODE = '22023',
                  HINT = 'select workflow_key, description from public.workflows;';
    END IF;

    PERFORM shared.validate_against_param_schema(
        proc.param_schema, coalesce(request_job.params, '{}'::jsonb));

    IF request_job.external_job_id IS NOT NULL THEN
        SELECT j.processing_job_id INTO job_id
          FROM shared.ProcessingJobs j
         WHERE j.external_job_id = request_job.external_job_id;
        IF FOUND THEN
            RETURN job_id;
        END IF;
    END IF;

    INSERT INTO shared.ProcessingJobs
        (external_job_id, workflow_name, workflow_version, status, input_data, submitted_by)
    VALUES (request_job.external_job_id, proc.workflow_key, proc.version, 'pending',
            coalesce(request_job.params, '{}'::jsonb), auth.uid()::text)
    ON CONFLICT ON CONSTRAINT processingjobs_external_job_id_key DO NOTHING
    RETURNING processing_job_id INTO job_id;

    IF job_id IS NULL THEN
        SELECT j.processing_job_id INTO job_id
          FROM shared.ProcessingJobs j
         WHERE j.external_job_id = request_job.external_job_id;
    END IF;

    RETURN job_id;
END;
$$;
