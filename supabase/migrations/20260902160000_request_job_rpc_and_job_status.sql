-- =============================================================================
-- request_job() and public.job_status -- the trigger surface
-- =============================================================================
-- XRFF-347. Gives the queue table that has existed and stayed empty since the
-- baseline snapshot a way in and a way to watch: one RPC to ask for a run, one
-- view to see what happened. PostgREST exposes both at /rest/v1/, which Kong
-- already fronts with key-auth and acl -- deliberately not an Edge Function
-- (the edge runtime cannot execute any of this work, and its Kong route
-- carries no auth plugins).
--
-- SECURITY DEFINER on request_job() is required, not stylistic. RLS on
-- shared.ProcessingJobs is service_role-all, authenticated-read-only, so an
-- authenticated caller cannot insert a row at all. The function is the only
-- write path, which is what lets it be the place every rule is enforced.
--
-- WHAT IT DOES NOT DO: it does not fill in defaults. `default` in param_schema
-- is advisory -- it tells a caller and Studio what will happen if a key is
-- omitted, and the tool's own default is what actually applies. Materialising
-- defaults here would put every default in two places that drift silently, and
-- would freeze host-adaptive ones (growpy's --workers defaults to
-- min(4, cpu_count), which only the runner host can know). input_data records
-- what was *requested*; what a run actually used is the tool's business, which
-- is why trees.SimulationRuns exists (XRFF-374).
--
-- Idempotent: safe to re-run.
-- =============================================================================


-- =============================================================================
-- PART 1 -- the param_schema validator
-- =============================================================================
-- The draft-07 subset settled in 20260902150000, and nothing wider. Keeping it
-- small is the point: a full JSON Schema implementation in plpgsql would be a
-- liability, and every keyword here earns its place against a real parameter
-- of a real workflow.
--
--   object level:  additionalProperties (false), required, dependentRequired
--   per property:  type, enum, minimum, maximum, multipleOf, pattern
--
-- Raises 22023 (invalid_parameter_value), which PostgREST returns as 400 with
-- the message -- so a caller gets told what was wrong with their request
-- rather than a 500. Constraints not expressible in the subset stay in the
-- tool's own argument parsing; this pre-checks, it does not replace.
--
-- Separate from request_job() so the runner and tests can validate a params
-- blob without submitting anything.
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $$
DECLARE
    key       text;
    dep       text;
    spec      jsonb;
    val       jsonb;
    want_type text;
    num       numeric;
BEGIN
    IF params IS NULL OR jsonb_typeof(params) <> 'object' THEN
        RAISE EXCEPTION 'params must be a JSON object, got %',
            coalesce(jsonb_typeof(params), 'null')
            USING ERRCODE = '22023';
    END IF;

    IF NOT coalesce((schema->>'additionalProperties')::boolean, false) THEN
        FOR key IN SELECT jsonb_object_keys(params) LOOP
            IF NOT (coalesce(schema->'properties', '{}'::jsonb) ? key) THEN
                RAISE EXCEPTION 'unknown parameter "%"; accepted: %', key,
                    coalesce((SELECT string_agg(k, ', ' ORDER BY k)
                                FROM jsonb_object_keys(coalesce(schema->'properties',
                                                                '{}'::jsonb)) k),
                             '(none)')
                    USING ERRCODE = '22023';
            END IF;
        END LOOP;
    END IF;

    FOR key IN SELECT jsonb_array_elements_text(coalesce(schema->'required', '[]'::jsonb)) LOOP
        IF NOT (params ? key) THEN
            RAISE EXCEPTION 'missing required parameter "%"', key USING ERRCODE = '22023';
        END IF;
    END LOOP;

    FOR key IN SELECT jsonb_object_keys(coalesce(schema->'dependentRequired', '{}'::jsonb)) LOOP
        IF params ? key THEN
            FOR dep IN SELECT jsonb_array_elements_text(schema->'dependentRequired'->key) LOOP
                IF NOT (params ? dep) THEN
                    RAISE EXCEPTION 'parameter "%" must be given together with "%"', key, dep
                        USING ERRCODE = '22023';
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    FOR key, val IN SELECT * FROM jsonb_each(params) LOOP
        spec := coalesce(schema->'properties', '{}'::jsonb) -> key;
        CONTINUE WHEN spec IS NULL;

        want_type := spec->>'type';
        IF want_type = 'integer' THEN
            IF jsonb_typeof(val) <> 'number' OR (val#>>'{}') !~ '^-?[0-9]+$' THEN
                RAISE EXCEPTION 'parameter "%" must be an integer, got %', key, val
                    USING ERRCODE = '22023';
            END IF;
        ELSIF want_type IN ('number', 'boolean', 'string') THEN
            IF jsonb_typeof(val) <> want_type THEN
                RAISE EXCEPTION 'parameter "%" must be %, got %', key, want_type, jsonb_typeof(val)
                    USING ERRCODE = '22023';
            END IF;
        END IF;

        IF spec ? 'enum' AND NOT (spec->'enum' @> jsonb_build_array(val)) THEN
            RAISE EXCEPTION 'parameter "%" must be one of %, got %',
                key, spec->>'enum', val USING ERRCODE = '22023';
        END IF;

        IF jsonb_typeof(val) = 'number' THEN
            num := (val#>>'{}')::numeric;
            IF spec ? 'minimum' AND num < (spec->>'minimum')::numeric THEN
                RAISE EXCEPTION 'parameter "%" must be at least %, got %',
                    key, spec->>'minimum', num USING ERRCODE = '22023';
            END IF;
            IF spec ? 'maximum' AND num > (spec->>'maximum')::numeric THEN
                RAISE EXCEPTION 'parameter "%" must be at most %, got %',
                    key, spec->>'maximum', num USING ERRCODE = '22023';
            END IF;
            IF spec ? 'multipleOf' AND num % (spec->>'multipleOf')::numeric <> 0 THEN
                RAISE EXCEPTION 'parameter "%" must be a multiple of %, got %',
                    key, spec->>'multipleOf', num USING ERRCODE = '22023';
            END IF;
        END IF;

        IF spec ? 'pattern' AND jsonb_typeof(val) = 'string'
           AND (val#>>'{}') !~ (spec->>'pattern') THEN
            RAISE EXCEPTION 'parameter "%" does not match %', key, spec->>'pattern'
                USING ERRCODE = '22023';
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION shared.validate_against_param_schema(jsonb, jsonb) IS
    'Check a params object against a shared.Processes.param_schema. Implements '
    'the JSON Schema draft-07 subset that column documents -- '
    'additionalProperties, required, dependentRequired, type, enum, minimum, '
    'maximum, multipleOf, pattern -- and nothing wider. Returns silently or '
    'raises 22023 with a message meant for the person who sent the request.';


-- =============================================================================
-- PART 2 -- request_job()
-- =============================================================================
-- IDEMPOTENCY. external_job_id is the key, supplied by the caller rather than
-- derived from the request: two identical SILVA requests are a legitimate act
-- (trees.GrowthSimulations accumulates by design, which is what makes scenario
-- comparison possible), so hashing the parameters would forbid something the
-- system is built to allow. A Blueprint sends the same GUID for one button
-- press and gets one job however many times the click registers; a deliberate
-- re-run sends a new key, or none.
--
-- The pre-check and the ON CONFLICT are both needed: the first returns the
-- existing id without burning a sequence value, the second closes the race
-- between two concurrent first requests.
--
-- workflow_version is copied from the process row at request time so a job
-- records which declared version it was asked against, even if the row is
-- later bumped.
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
                  HINT = 'No user carries an app_metadata.role claim yet (XRFF-239), '
                         'so this rejects everyone today.';
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

COMMENT ON FUNCTION public.request_job(text, jsonb, text) IS
    'Ask for a workflow run. Validates the workflow against public.workflows '
    'and the params against its param_schema, then queues a pending job and '
    'returns its id. Pass external_job_id to make the request idempotent -- a '
    'repeat with the same key returns the first job instead of queueing a '
    'second. SECURITY DEFINER because RLS makes shared.ProcessingJobs '
    'read-only to authenticated callers; this function is its only write path. '
    'Nothing here says how a workflow runs: the runner resolves workflow_key '
    'against its own private config and refuses anything absent from it.';

REVOKE ALL ON FUNCTION public.request_job(text, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_job(text, jsonb, text)
    TO authenticated, service_role;


-- =============================================================================
-- PART 3 -- who may see which jobs
-- =============================================================================
-- The baseline policy let every authenticated user read every job (USING
-- true). Narrowed here to submitter-or-curator, which is what XRFF-347 asks
-- for and is free to do now: the table has never held a row.
--
-- auth.uid() is wrapped in a scalar sub-select so it is evaluated once per
-- query rather than once per row.
-- =============================================================================

DROP POLICY IF EXISTS "Enable read for authenticated users" ON shared.ProcessingJobs;
DROP POLICY IF EXISTS "Submitters read own jobs, curators read all" ON shared.ProcessingJobs;
CREATE POLICY "Submitters read own jobs, curators read all"
    ON shared.ProcessingJobs
    FOR SELECT
    TO authenticated
    USING (submitted_by = (SELECT auth.uid())::text OR shared.is_curator());


-- =============================================================================
-- PART 4 -- public.job_status
-- =============================================================================
-- One row per job, for Studio's table view and for a Blueprint polling a run
-- it started. security_invoker='on', so PART 3's policy is what decides
-- visibility -- the view adds no reach of its own.
--
-- WHAT IS ON IT, AND WHAT IS RUNNER-INTERNAL. Part A added five queue columns;
-- three belong to whoever submitted the job and two do not:
--
--   started_at            on  -- "has it actually begun, or is it still queued"
--   attempts/max_attempts on  -- the difference between "gave up" and "will
--                               try again" is the submitter's business
--   claimed_by            off -- a runner hostname; operational, and an
--                               operator can read the base table
--   next_attempt_at       off -- meaningless while max_attempts defaults to 1
--
-- duration_seconds is derived rather than left to the reader: it is the
-- question actually being asked of a 75-minute growpy run, and computing it in
-- Blueprint from two timestamps is exactly the kind of join-in-SQL-not-in-UE
-- the data-fetcher guide asks for.
--
-- ANON SEES AN EMPTY LIST, NOT AN ERROR -- and that is RLS doing it, not a
-- grant. Supabase's default privileges already give anon SELECT on this view
-- and on shared.ProcessingJobs, so the explicit GRANT below adds nothing for
-- anon and revoking it would buy nothing either: the gate is PART 3's policy,
-- which names only `authenticated`, so anon matches no rows. Verified live:
-- GET /rest/v1/job_status as anon returns 200 [].
--
-- That still means Unreal cannot poll job status today. It reads the twin as
-- anon (XRFF-352), and per-submitter visibility has no meaning without a real
-- session -- XRFF-239's dependency, not something to unpick by widening the
-- view.
-- =============================================================================

DROP VIEW IF EXISTS public.job_status;
CREATE VIEW public.job_status
    WITH (security_invoker = 'on') AS
SELECT
    j.processing_job_id                                            AS job_id,
    j.external_job_id,
    j.workflow_name,
    j.workflow_version,
    j.status,
    j.submitted_by,
    j.submitted_at,
    j.started_at,
    j.completed_at,
    CASE
        WHEN j.started_at IS NULL THEN NULL
        ELSE EXTRACT(epoch FROM coalesce(j.completed_at, now()) - j.started_at)::integer
    END                                                            AS duration_seconds,
    j.attempts,
    j.max_attempts,
    j.error_message,
    j.input_data,
    j.output_data
FROM shared.ProcessingJobs j;

COMMENT ON VIEW public.job_status IS
    'Every job the caller is allowed to see -- their own, or all of them for a '
    'curator. Omits claimed_by and next_attempt_at, which are the runner''s '
    'bookkeeping rather than the submitter''s answer. An anon caller matches no '
    'policy and so reads an empty list.';

GRANT SELECT ON public.job_status TO authenticated, service_role;
