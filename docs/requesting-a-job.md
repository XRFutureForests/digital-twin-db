# Requesting a job

How to ask the twin to run something — a SILVA growth projection, an Aquarius
sync, a growpy batch — instead of only reading what it already holds.

Three pieces, all in the database:

| | |
|---|---|
| `public.workflows` | the menu: what can be run, and what each one accepts |
| `public.request_job()` | ask for a run; returns a job id |
| `public.job_status` | what happened to it |

A runner on some host picks the job up, runs the tool, and writes the result
back. Nothing in the database says *how* a workflow runs — see
[scripts/runner/README.md](../scripts/runner/README.md).

---

## 1. See what can be run

In Studio → **SQL Editor**:

```sql
select workflow_key, description, category, version
from public.workflows
order by workflow_key;
```

Four workflows today: `silva`, `aquarius-sync`, `aquarius-enrich`, `growpy`.
The `description` is written to answer "should I press this?" — what it
changes, roughly how long it takes, and what it costs to be wrong.

To see what one of them accepts:

```sql
select jsonb_pretty(param_schema)
from public.workflows
where workflow_key = 'silva';
```

That is a [JSON Schema](https://json-schema.org/) fragment. The parts worth
reading are `required`, and for each property its `type`, `default`, `enum` and
range. For `silva` it says, without opening a repository, that `location` is
required, `years` defaults to 20 and must be a multiple of 5, and `competition`
is one of `sf_polygon`, `rect_sum`, `legacy`.

## 2. Ask for a run

```sql
select request_job('silva', '{"location":"ecosense","years":30}'::jsonb);
```

It returns the new job's id. Parameters you leave out are simply not passed:
the tool's own default applies, which is what `default` in the schema is
telling you it will be.

Bad parameters are refused immediately, with a message meant for you:

```
select request_job('silva', '{"location":"ecosense","years":33}'::jsonb);
ERROR:  parameter "years" must be a multiple of 5, got 33
```

**Not twice by accident.** Pass a third argument — any string you choose — and
a repeated request with the same string returns the first job instead of
queueing a second:

```sql
select request_job('silva', '{"location":"ecosense"}'::jsonb, 'my-2026-09-02-run');
```

Leave it out when you *want* a second run. Two identical SILVA runs are a
legitimate thing to want: `trees.GrowthSimulations` accumulates, which is what
makes scenario comparison possible.

## 3. Watch it

```sql
select job_id, workflow_name, status, submitted_at, duration_seconds, error_message
from job_status
order by submitted_at desc
limit 10;
```

| `status` | meaning |
|---|---|
| `pending` | queued; no runner has taken it yet |
| `running` | a runner has it; `duration_seconds` counts up |
| `completed` | finished, exit code 0 |
| `failed` | non-zero exit, timeout, or invalid parameters — see `error_message` |

`output_data` holds the tail of the tool's stdout and stderr, which is usually
where the answer to "why did it fail" is:

```sql
select output_data->>'stderr' from job_status where job_id = 42;
```

You see your own jobs. Curators see everyone's.

---

## What does not work yet, and why

**`request_job()` cannot be called from the Studio SQL Editor.** Verified on
the live stack, 2026-09-02:

```
select request_job('aquarius-enrich');
ERROR:  requesting a job requires the contributor role
```

Two separate reasons, and the second outlives the first:

1. **No user carries an `app_metadata.role` claim.** `shared.is_contributor()`
   has nothing to check, so it rejects everyone. On the local stack `auth.users`
   is empty — there are no accounts at all. This is not missing machinery:
   creating an account and setting its role tier are both documented in
   [data-access-guide.md](data-access-guide.md) (*Assigning a role tier*), and
   XRFF-239, which built that, is closed. It is a manual step nobody has taken.

2. **The Studio SQL Editor has no signed-in identity at all.** It reaches the
   database through the `meta` service as `supabase_admin`
   (`docker-compose.yml`, `PG_META_DB_USER`), so `auth.jwt()` is null and the
   role check fails there *however* privileged the person at the keyboard is.
   Fixing XRFF-239 will not change this.

So Studio works today as the place to **read** the menu and **watch** jobs —
both queries above run fine there, and a superuser sees every job. Actually
*requesting* one has to come from a caller that carries a user token: the REST
endpoint, which is how Unreal will do it (XRFF-352).

```bash
# Sign in once (see data-access-guide.md), then:
curl -X POST "$SUPABASE_URL/rest/v1/rpc/request_job" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{"workflow":"silva","params":{"location":"ecosense","years":30}}'
```

That path is verified working end to end, including the idempotency key and a
`400` with the message on bad parameters. Closing the gap for non-coders means
either handing colleagues that call in a form they will actually use, or giving
Studio a caller that carries a token — a decision for XRFF-375/XRFF-239, not
something to unpick by loosening the role check.

> **Do not insert into `shared.ProcessingJobs` by hand** in the Table Editor to
> get around this. It bypasses `request_job()` entirely — no workflow check, no
> parameter validation, no idempotency — and a runner will happily execute
> whatever a typo produces. The runner re-validates parameters for exactly this
> reason, but a misspelled `workflow_name` simply never runs and never fails.

## Nothing runs until a runner exists somewhere

A job sits at `pending` until a host with a configured runner claims it. As of
2026-09-02 no cron line exists anywhere in this workspace, and
`dt.unr.uni-freiburg.de` has no database, no conda and no Blender — that is
XRFF-238's work. Locally, drain the queue by hand:

```bash
conda activate digital-twin
python scripts/runner/runner.py drain
```
