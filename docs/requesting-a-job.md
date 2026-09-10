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

## The short version: use the page

**<https://dt.unr.uni-freiburg.de/jobs/>** — sign in, pick a workflow, fill in
the form, watch it run. That is the whole thing, and it is what to hand a
colleague. The rest of this document is what the page does underneath, which
matters when you are scripting it or when something fails.

The form is not written by hand for each workflow: it is generated from that
workflow's own `param_schema`, so it always agrees with what the server will
accept, and a new connector gets a form the moment it lands a `workflow_key`.
Source is [web/jobs/](../web/jobs/); it is one static file, served by the
dashboard's nginx, calling the same REST API as everything else.

---

## 1. See what can be run

In Studio → **SQL Editor**:

```sql
select workflow_key, description, category, version
from public.workflows
order by workflow_key;
```

Nine workflows today: `silva`, `aquarius-sync`, `aquarius-enrich`, `growpy`,
and five `open-data-*` acquisitions.
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

## Why there is a page at all, and not just Studio

**`request_job()` cannot be called from the Studio SQL Editor**, and this is
not a configuration problem. Verified on the live stack 2026-09-02, 2026-09-09
and again 2026-09-10:

```
select request_job('aquarius-enrich');
ERROR:  requesting a job requires the contributor role
```

Studio reaches the database through the `meta` service as `supabase_admin`
(`docker-compose.yml`, `PG_META_DB_USER`), so `auth.jwt()` is **null** there and
the role check fails *however* privileged the person at the keyboard is.
Creating accounts did not change this and never could. So Studio is the place to
**read** the menu and **watch** jobs — both queries above run fine there, and a
superuser sees every job — but requesting one has to come from a caller that
carries a **user token**.

There are three such callers, and they are the same REST call underneath:

| Caller | For |
|---|---|
| [the page](https://dt.unr.uni-freiburg.de/jobs/) | people |
| `curl` (below) | scripts |
| Unreal Blueprint | the headsets (XRFF-352) |

```bash
# Sign in once (see data-access-guide.md), then:
curl -X POST "$SUPABASE_URL/rest/v1/rpc/request_job"   -H "apikey: $ANON_KEY"   -H "Authorization: Bearer $USER_JWT"   -H "Content-Type: application/json"   -d '{"workflow":"silva","params":{"location":"ecosense","years":30}}'
```

Verified end to end against a real signed-in account on 2026-09-09: a
contributor got job ids `19` and `20`, the same `external_job_id` returned the
first id rather than queueing a second job, a bad parameter came back `400` with
the message, and `anon` was refused. `job_status` showed the contributor only
its own row while the curator saw both, and `anon` read `[]` with a `200`.

**Accounts exist on both stacks now.** They are created through the GoTrue admin
endpoint, which sets the role in the same call rather than the
create-then-`UPDATE` pair [data-access-guide.md](data-access-guide.md)
describes. Studio's *Invite user* is not the route: `SMTP_HOST` is the
`dftdb-mail` container, an inbucket catch-all that forwards nothing, so the
invitation is generated and never delivered.

```bash
curl -X POST "$SUPABASE_URL/auth/v1/admin/users"   -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY"   -H "Content-Type: application/json"   -d '{"email":"someone@example.com","password":"…","email_confirm":true,
       "app_metadata":{"role":"contributor"}}'
```

`shared.is_contributor()` accepts `admin`, `curator` and `contributor`; anything
else — or no role at all — reads the menu and its own job history but cannot
request a run.

> **Do not insert into `shared.ProcessingJobs` by hand** in the Table Editor to
> get around this. It bypasses `request_job()` entirely — no workflow check, no
> parameter validation, no idempotency — and a runner will happily execute
> whatever a typo produces. The runner re-validates parameters for exactly this
> reason, but a misspelled `workflow_name` simply never runs and never fails.

## Nothing runs until a runner exists somewhere

A job sits at `pending` until a host with a configured runner claims it, and a
runner only claims the workflow keys its own private `config/workflows.toml`
lists. That is the routing mechanism: a key absent from a host is a job that
host will never touch, however long it waits.

**`dt.unr.uni-freiburg.de` runs one** as of 2026-09-10 — a `systemd` timer
draining the queue every minute, so a request there becomes a running job within
about a minute unattended. It carries the `silva` key only. It has no Blender
and no PDAL, so `growpy` and the point-cloud workflows would queue there and
never run; request those where a runner for them exists.

Locally, drain the queue by hand:

```bash
conda activate digital-twin
python scripts/runner/runner.py drain
```
