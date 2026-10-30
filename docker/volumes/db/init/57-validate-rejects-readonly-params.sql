-- =============================================================================
-- request_job() must reject a readOnly parameter, not silently accept it
-- =============================================================================
-- Follow-up to 20260923170000, which declared silva's three resolved parameters
-- (management_regime, climate_pathway, climate_periods) as "readOnly": true so
-- that emit_ro_crate could record them.
--
-- That declaration had a side effect. shared.validate_against_param_schema()
-- accepts any key present in `properties` and knew nothing about readOnly, so
-- the moment those three were declared, request_job() began ACCEPTING them as
-- input -- and doing nothing with them, since silva-connector derives them from
-- `regime` and `climate` during the run. The caller would get a job id back and
-- a silently ignored parameter, which is worse than the error it replaced.
--
-- Filtering them out of web/jobs/ was not enough: that page is one client, and
-- the RPC is the contract. readOnly in JSON Schema means exactly this -- present
-- in responses, not to be sent in a request -- so the validator now enforces it,
-- and the "accepted:" list in the unknown-parameter error stops advertising
-- parameters nobody is allowed to pass.
--
-- The body below is pg_get_functiondef output with only that block inserted.
-- Retyping it by hand dropped `SET search_path TO ''`, enum, minimum, maximum,
-- multipleOf and pattern validation, which is why it is generated instead.
--
-- Mirrored to init 57-validate-rejects-readonly-params.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.validate_against_param_schema(schema jsonb, params jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
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

    -- A readOnly property is recorded BY the run, not offered to the caller.
    -- Checked ahead of the unknown-parameter branch below, because the key is
    -- in `properties` and would otherwise be accepted silently: declaring
    -- silva's three resolved parameters (20260923170000) so the RO-Crate could
    -- record them had the side effect of making request_job() take them as
    -- input and ignore them.
    FOR key IN SELECT jsonb_object_keys(params) LOOP
        IF coalesce((schema->'properties'->key->>'readOnly')::boolean, false) THEN
            RAISE EXCEPTION
                'parameter "%" is readOnly: it is recorded by the run, not set by the caller',
                key USING ERRCODE = '22023';
        END IF;
    END LOOP;

    IF NOT coalesce((schema->>'additionalProperties')::boolean, false) THEN
        FOR key IN SELECT jsonb_object_keys(params) LOOP
            IF NOT (coalesce(schema->'properties', '{}'::jsonb) ? key) THEN
                RAISE EXCEPTION 'unknown parameter "%"; accepted: %', key,
                    coalesce((SELECT string_agg(k, ', ' ORDER BY k)
                                FROM jsonb_object_keys(coalesce(schema->'properties',
                                                                '{}'::jsonb)) k
                               WHERE NOT coalesce(
                                   (schema->'properties'->k->>'readOnly')::boolean, false)),
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
$function$;
