-- =============================================================================
-- request_job: name the renamed idempotency constraint
-- =============================================================================
-- 20260923110000_rename_base_tables_coupled renamed
-- processingjobs_external_job_id_key to processing_jobs_external_job_id_key,
-- but request_job()'s ON CONFLICT ON CONSTRAINT still named the old one. A
-- plpgsql body is not checked at CREATE time, so the rename applied cleanly and
-- every call since has failed with
--   42704 constraint "processingjobs_external_job_id_key" ... does not exist
-- -- the /jobs/ page and every scripted request alike. Found 2026-10-29 while
-- verifying a new contributor account on dt.unr.
--
-- Body otherwise unchanged (pg_get_functiondef of the live function, identical
-- on dev and dt.unr). CREATE OR REPLACE keeps grants and the comment.
--
-- Mirrored to init 66-request-job-renamed-constraint.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.request_job(workflow text, params jsonb DEFAULT '{}'::jsonb, external_job_id text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          FROM shared.processing_jobs j
         WHERE j.external_job_id = request_job.external_job_id;
        IF FOUND THEN
            RETURN job_id;
        END IF;
    END IF;
    INSERT INTO shared.processing_jobs
        (external_job_id, workflow_name, workflow_version, status, input_data, submitted_by)
    VALUES (request_job.external_job_id, proc.workflow_key, proc.version, 'pending',
            coalesce(request_job.params, '{}'::jsonb), auth.uid()::text)
    ON CONFLICT ON CONSTRAINT processing_jobs_external_job_id_key DO NOTHING
    RETURNING processing_job_id INTO job_id;
    IF job_id IS NULL THEN
        SELECT j.processing_job_id INTO job_id
          FROM shared.processing_jobs j
         WHERE j.external_job_id = request_job.external_job_id;
    END IF;
    RETURN job_id;
END;
$function$;
