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

## Scheduling it

**Installed and running on `dt.unr.uni-freiburg.de` since 2026-09-10**, as
systemd *system* units rather than the crontab this section used to describe.
The unit files live next to this README and are deployed by copying them:

```bash
sudo cp ~/dev/digital-twin-db/scripts/runner/dt-job-runner.{service,timer} /etc/systemd/system/
sudo cp ~/dev/digital-twin-db/scripts/runner/dt-job-runner-reap.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dt-job-runner.timer dt-job-runner-reap.timer
```

| Unit | Cadence | Does |
|---|---|---|
| `dt-job-runner.timer` | every minute | `drain` — claim and run |
| `dt-job-runner-reap.timer` | hourly at :07 | `reap` — recover jobs this runner abandoned |

Measured end to end on that host: a job requested at 10:07:16 was claimed at
10:07:29 and finished at 10:07:41. **25 seconds from request to done**, which is
the number that decides whether a queued job feels like a button press.

### Three things this section used to say that were wrong

1. *"a **user** crontab, not a systemd unit … there is no passwordless sudo for
   a system one"* — correct about sudo, wrong about the conclusion. Someone with
   sudo installs it once; the units are static files in the repo.
2. *"That host has `Linger=no`, so a `--user` timer would stop at logout"* — the
   premise is true but not binding: **`loginctl enable-linger max` succeeds
   unprivileged there**, so user timers were always an option if sudo had been
   unavailable. Verified 2026-09-10, then reverted, because the system units
   made it moot.
3. *"`PGPASSWORD=…`"* in the crontab — **not needed.** `silva`'s compose file
   reads `silva-connector/docker/.env` on its own, because `-f
   docker/docker-compose.yml` makes `docker/` the compose project directory. The
   secret stays in one mode-600 file and the runner's environment stays empty.
   `config/workflows.example.toml` still gives the crontab advice; it is not
   wrong, just avoidable.

Also note the interpreter: on that host it is `envs/runner/bin/python`, a
minimal env of python + psycopg2 + python-dotenv — **not** `envs/digital-twin`,
which pulls `r-base`, `jupyter` and `devtools` that the runner never uses onto a
28 GB root disk.

Overlapping invocations are safe — that is what `FOR UPDATE SKIP LOCKED` is
for — so a drain that outlives its minute does not need a lock file. Keep
`max_jobs` low on a host that runs growpy: one job can hold it for an hour.

`drain` exits non-zero when a job failed, which is why the unit sets
`SuccessExitStatus=0 1`: the failure is already recorded on the job row, and a
unit flapping into `failed` for it would hide a genuinely broken runner.

On Windows the equivalent is a Task Scheduler entry running the same two
commands; nothing in the runner assumes a POSIX host except the paths in
`workflows.toml`.

## Draining by hand

```bash
conda activate digital-twin
python scripts/runner/runner.py drain
```
