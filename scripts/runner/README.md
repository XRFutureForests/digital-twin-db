# Job runner

Drains `shared.ProcessingJobs`: claims pending work, runs the connectors'
existing CLIs as subprocesses, and records what happened. Jobs get there
through `public.request_job()`, which is what Studio and Unreal call.

A cron one-shot, not a daemon. Each invocation claims at most `max_jobs`, runs
them and exits — nothing to supervise, nothing to survive a reboot, and
`Linger=no` on the deployment host stops mattering.

```bash
conda activate digital-twin

python scripts/runner/runner.py list     # what this host may claim
python scripts/runner/runner.py drain    # claim and run
python scripts/runner/runner.py reap     # fail jobs whose process is gone
```

## A workflow is declared in two places

| Half | Where | Says |
|---|---|---|
| Name and parameters | `shared.Processes.workflow_key` + `param_schema` | *that* a workflow exists and what it accepts |
| Command | `config/workflows.toml`, per host, gitignored | *what* that name runs |

The runner claims a job only when its workflow appears in **both**. Nothing a
caller sends can name a command, because commands exist only on the host,
outside the database — which is what makes command injection structurally
impossible rather than merely unlikely. Parameters reach the subprocess as an
argv list passed straight to `execve`; a value containing `; rm -rf /` is one
argument and nothing more.

Copy `config/workflows.example.toml` to `config/workflows.toml` and edit it for
the host; the example carries the full annotated reference.

## Several hosts, one queue

growpy needs Blender, silva needs Docker on the database network, aquarius
needs to reach the Aquarius API. Those may never be one machine. Give each host
a `workflows.toml` listing only what it can run, and each claims only its own
work — `FOR UPDATE SKIP LOCKED` means two runners never take the same job, and
no connector learns that a queue exists.

Verified locally: two simultaneous `drain` invocations split six jobs three and
three, each claimed exactly once.

### This is also the lane mechanism — settled under XRFF-380

XRFF-346 left concurrency as *"one job at a time is simplest, per-workflow lanes
only if needed"*, and XRFF-380 asked whether the nightly `open-data-weather`
refresh needs a lane of its own: it takes minutes, but a growpy run ahead of it
in the queue could hold the host for an hour and cost a day's weather.

**It does not, because the split above already prevents it.** growpy needs
Blender and so belongs on a different host from the connectors; a host's
`workflows.toml` lists only what that host can run, so a runner draining
`open-data-weather` never sees a growpy job to queue behind. The contention the
question describes only exists on a host configured to run both.

If one ever is, reach for `max_jobs` and cron frequency before adding lanes —
a `priority` column no runner consults would be worse than none, which is the
same reasoning that kept one out of `shared.ProcessingJobs` to begin with.

## Arguments are derived, not listed

A parameter `foo_bar` becomes `--foo-bar <value>`; a boolean becomes the bare
flag when true and nothing when false; a key named in the workflow's
`positional` list becomes a bare value. So `param_schema` in the database is
the single description of what a workflow accepts, and the host configuration
does not repeat it.

```
{"location": "ecosense", "years": 30, "mortality": true, "dry_run": false}
  -> --location ecosense --mortality --years 30
```

## Status transitions

| From | To | When |
|---|---|---|
| `pending` | `running` | claimed; sets `started_at`, `claimed_by`, `attempts += 1` |
| `running` | `completed` | exit code 0 |
| `running` | `failed` | non-zero exit, timeout, missing command, or invalid parameters, with no attempts left |
| `running` | `pending` | same, but `attempts < max_attempts`; `next_attempt_at` set, `started_at`/`claimed_by` cleared |

`max_attempts` defaults to 1, so by default nothing is retried.

A job is never claimed when `attempts >= max_attempts` or `next_attempt_at` is
in the future.

`reap` only touches rows this runner claimed — matched on `claimed_by`. A host
cannot tell whether another host's process is alive, and guessing would kill
live work. The case it covers is a `drain` killed mid-job, whose next cron
wake-up finds the row still `running` past its timeout.

`drain` exits non-zero if any job failed, per the repo's exit-code rule: an
unattended run's exit code is the only signal cron mail carries.

## Scheduling it — for when there is something to schedule

Not installed anywhere. There is no cron line in this workspace. As of
2026-09-02 `dt.unr.uni-freiburg.de` does run the database (XRFF-238), but it
still has no conda, no Blender and no `aquarius-connector` checkout, so a runner
there could claim jobs it cannot execute. Develop and test against the WSL
Docker stack until those are in place.

When the host is ready, this is the shape — a **user** crontab, not a systemd
unit. That host has `Linger=no`, so a `--user` timer would stop at logout, and
there is no passwordless sudo for a system one. Its user crontab is already in
use (certbot), so this appends rather than replaces.

```cron
# Drain the job queue every minute; reap abandoned jobs hourly.
# Cron's PATH is not a login shell's -- use absolute paths here and in
# workflows.toml, and let the conda env's interpreter be the entry point
# rather than sourcing an activate script.
RUNNER=/home/max/dev/digital-twin-db/scripts/runner/runner.py
PYTHON=/home/max/miniconda3/envs/digital-twin/bin/python

# The subprocess inherits this environment and nothing else. silva's compose
# file refuses to start without PGPASSWORD, and cron supplies almost nothing.
# Read it from a mode-600 file rather than writing it in the crontab.
PGPASSWORD=...

* * * * *  $PYTHON $RUNNER drain >> /home/max/log/runner-drain.log 2>&1
7 * * * *  $PYTHON $RUNNER reap  >> /home/max/log/runner-reap.log  2>&1
```

Overlapping invocations are safe — that is what `FOR UPDATE SKIP LOCKED` is
for — so a drain that outlives its minute does not need a lock file. Keep
`max_jobs` low on a host that runs growpy: one job can hold it for an hour.

Redirecting to a log rather than letting cron mail is deliberate on a host
where `drain` runs every minute; drop the redirect if you want the non-zero
exit of a failed job to reach you by mail.

On Windows the equivalent is a Task Scheduler entry running the same two
commands; nothing in the runner assumes a POSIX host except the paths in
`workflows.toml`.

## Draining by hand

```bash
conda activate digital-twin
python scripts/runner/runner.py drain
```
