#!/usr/bin/env python3
"""Drain the job queue: claim pending work, run it, record what happened.

    python scripts/runner/runner.py list      # what this host may claim
    python scripts/runner/runner.py drain     # claim and run
    python scripts/runner/runner.py reap      # fail jobs whose process is gone

A cron one-shot, not a daemon. Each invocation claims at most `max_jobs`,
runs them, and exits -- so nothing has to survive a reboot, there is no
supervisor to install, and `Linger=no` on the deployment host stops mattering.

WHY A GENERIC RUNNER AND NOT A POLLING CONNECTOR. The expensive part of a queue
is not the polling loop, it is the claim protocol: atomic claim, visibility
timeout, reap, status transitions, output capture. Having each connector poll
would mean implementing that three times -- Python for aquarius, R for silva,
again for growpy -- and kept consistent by hand. Worse, it would give growpy,
which today has no database code at all and is separately citable because of
it, a Postgres dependency and knowledge of a site-specific queue table. Here it
is written once and no connector learns that a queue exists.

Distribution across hosts comes from configuration, not from code: a second
runner with its own workflows.toml claims only what its machine can run.

The runner connects to the database directly, as trusted infrastructure rather
than as an API client -- it is the one component on the write side of
request_job(), which exists precisely so that everyone else does not need such
access.
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import psycopg2
from psycopg2.extras import Json

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection  # noqa: E402

sys.path.insert(0, str(Path(__file__).parent))
from config import ConfigError, RunnerConfig, Workflow, build_argv, load_config  # noqa: E402

# Job output is stored to be read by a human in Studio, not archived. A growpy
# run can emit megabytes; the last few thousand characters carry the failure.
OUTPUT_TAIL_CHARS = 8000


def log(message: str) -> None:
    print(f"[{datetime.now():%H:%M:%S}] {message}", flush=True)


def tail(text: str) -> str:
    text = (text or "").strip()
    if len(text) <= OUTPUT_TAIL_CHARS:
        return text
    return "...(truncated)...\n" + text[-OUTPUT_TAIL_CHARS:]


# =============================================================================
# The two halves of a declaration
# =============================================================================


def claimable_workflows(conn, cfg: RunnerConfig) -> dict[str, Workflow]:
    """Workflows declared in the database AND configured on this host.

    The intersection is the refusal rule. A workflow the database does not
    declare cannot be run here even if configured -- that is a stale entry, and
    it is reported rather than silently ignored. A workflow this host has no
    configuration for is not an error at all: another host runs it.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT workflow_key FROM shared.Processes WHERE workflow_key IS NOT NULL"
        )
        declared = {row[0] for row in cur.fetchall()}

    for key in sorted(set(cfg.workflows) - declared):
        log(
            f"WARNING: workflow '{key}' is configured on this host but not declared in "
            f"shared.Processes -- it will not be claimed. Remove it, or seed the row."
        )

    return {key: wf for key, wf in cfg.workflows.items() if key in declared}


def validation_error(conn, workflow: str, params: dict[str, Any]) -> str | None:
    """Re-check a claimed job's parameters, returning a message or None.

    request_job() already validated these, but a job can also reach the queue
    through service_role, which bypasses that function entirely. Re-checking
    costs one query and reuses the same validator, so there is no second
    implementation to keep in step.
    """
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT shared.validate_against_param_schema(p.param_schema, %s::jsonb) "
                "FROM shared.Processes p WHERE p.workflow_key = %s",
                (Json(params), workflow),
            )
        conn.commit()
        return None
    except psycopg2.Error as exc:
        conn.rollback()
        return str(exc).strip().splitlines()[0]


# =============================================================================
# Claim, finish, reap
# =============================================================================


def claim_one(conn, cfg: RunnerConfig, claimable: dict[str, Workflow]):
    """Claim the oldest runnable job, or return None.

    FOR UPDATE SKIP LOCKED is what lets several runners -- or two invocations
    of this one, if cron overlaps -- select from the same queue without either
    blocking on the other or handing the same job to both.

    The claim commits before the job runs. Holding the row lock for a 75-minute
    growpy run would block every other runner on the table.
    """
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE shared.ProcessingJobs
               SET status      = 'running',
                   started_at  = now(),
                   claimed_by  = %s,
                   attempts    = attempts + 1
             WHERE processing_job_id = (
                 SELECT processing_job_id
                   FROM shared.ProcessingJobs
                  WHERE status = 'pending'
                    AND workflow_name = ANY(%s)
                    AND attempts < max_attempts
                    AND (next_attempt_at IS NULL OR next_attempt_at <= now())
                  ORDER BY submitted_at
                    FOR UPDATE SKIP LOCKED
                  LIMIT 1
             )
            RETURNING processing_job_id, workflow_name, input_data, attempts, max_attempts
            """,
            (cfg.name, list(claimable)),
        )
        row = cur.fetchone()
    conn.commit()
    return row


def finish(
    conn,
    cfg: RunnerConfig,
    job_id: int,
    attempts: int,
    max_attempts: int,
    *,
    succeeded: bool,
    output: dict[str, Any] | None = None,
    error: str | None = None,
) -> None:
    """Record the end of a job.

    A failure with attempts left goes back to `pending` with next_attempt_at
    set, rather than to `failed`: the columns were added with the intention
    that max_attempts governs this, and defaulting it to 1 is what makes "no
    automatic retry" the behaviour without making it the only possible one.
    """
    if succeeded:
        status = "completed"
    elif attempts < max_attempts:
        status = "pending"
    else:
        status = "failed"

    with conn.cursor() as cur:
        if status == "pending":
            cur.execute(
                """
                UPDATE shared.ProcessingJobs
                   SET status          = 'pending',
                       started_at      = NULL,
                       claimed_by      = NULL,
                       completed_at    = NULL,
                       next_attempt_at = now() + make_interval(secs => %s),
                       error_message   = %s,
                       output_data     = %s
                 WHERE processing_job_id = %s
                """,
                (cfg.retry_backoff_seconds, error, Json(output) if output else None, job_id),
            )
        else:
            cur.execute(
                """
                UPDATE shared.ProcessingJobs
                   SET status        = %s,
                       completed_at  = now(),
                       error_message = %s,
                       output_data   = %s
                 WHERE processing_job_id = %s
                """,
                (status, error, Json(output) if output else None, job_id),
            )
    conn.commit()


def run_job(conn, cfg: RunnerConfig, workflow: Workflow, row) -> bool:
    """Run one claimed job to completion. Returns True if it succeeded."""
    job_id, workflow_name, params, attempts, max_attempts = row
    params = params or {}

    problem = validation_error(conn, workflow_name, params)
    if problem is not None:
        log(f"job {job_id} ({workflow_name}): rejected -- {problem}")
        finish(conn, cfg, job_id, attempts, max_attempts, succeeded=False, error=problem)
        return False

    argv = build_argv(workflow, params)
    # shlex.join, not ' '.join: a parameter may legitimately contain spaces or
    # a semicolon, and an unquoted log line invites someone reproducing a
    # failure to paste something into a shell that the runner never ran.
    log(f"job {job_id} ({workflow_name}): running {shlex.join(argv)}")

    started = time.monotonic()
    try:
        proc = subprocess.run(  # noqa: S603 - argv list, never a shell
            argv,
            capture_output=True,
            text=True,
            timeout=workflow.timeout_seconds,
            shell=False,
        )
    except FileNotFoundError:
        elapsed = int(time.monotonic() - started)
        message = f"command not found: {argv[0]}"
        log(f"job {job_id} ({workflow_name}): {message}")
        finish(
            conn, cfg, job_id, attempts, max_attempts,
            succeeded=False, error=message,
            output={"duration_seconds": elapsed},
        )
        return False
    except subprocess.TimeoutExpired as exc:
        elapsed = int(time.monotonic() - started)
        message = f"timed out after {workflow.timeout_seconds}s"
        log(f"job {job_id} ({workflow_name}): {message}")
        finish(
            conn, cfg, job_id, attempts, max_attempts,
            succeeded=False, error=message,
            output={
                "duration_seconds": elapsed,
                "stdout": tail(exc.stdout.decode() if isinstance(exc.stdout, bytes) else exc.stdout or ""),
                "stderr": tail(exc.stderr.decode() if isinstance(exc.stderr, bytes) else exc.stderr or ""),
            },
        )
        return False

    elapsed = int(time.monotonic() - started)
    succeeded = proc.returncode == 0
    output = {
        "exit_code": proc.returncode,
        "duration_seconds": elapsed,
        "stdout": tail(proc.stdout),
        "stderr": tail(proc.stderr),
    }
    error = None if succeeded else f"exit code {proc.returncode}"

    log(
        f"job {job_id} ({workflow_name}): "
        f"{'completed' if succeeded else 'FAILED'} in {elapsed}s"
    )
    finish(
        conn, cfg, job_id, attempts, max_attempts,
        succeeded=succeeded, output=output, error=error,
    )
    return succeeded


# =============================================================================
# Subcommands
# =============================================================================


def cmd_list(conn, cfg: RunnerConfig) -> int:
    claimable = claimable_workflows(conn, cfg)
    log(f"runner '{cfg.name}': {len(claimable)} claimable workflow(s)")
    for key, wf in sorted(claimable.items()):
        log(f"  {key:<18} timeout {wf.timeout_seconds}s  {shlex.join(wf.command)}")
    if not claimable:
        log("  (none -- this host will claim nothing)")
    return 0


def cmd_drain(conn, cfg: RunnerConfig) -> int:
    claimable = claimable_workflows(conn, cfg)
    if not claimable:
        log("nothing claimable on this host; exiting")
        return 0

    started = failed = 0
    for _ in range(cfg.max_jobs):
        row = claim_one(conn, cfg, claimable)
        if row is None:
            break
        started += 1
        if not run_job(conn, cfg, claimable[row[1]], row):
            failed += 1

    if started == 0:
        log("no pending jobs")
    else:
        log(f"drain finished: {started} started, {failed} failed")

    # An unattended run's exit code is the only signal cron mail carries.
    return 1 if failed else 0


def cmd_reap(conn, cfg: RunnerConfig) -> int:
    """Fail jobs this runner claimed and never finished.

    Only this runner's rows, matched on claimed_by. A host cannot tell whether
    another host's process is alive, and guessing would kill live work; each
    runner cleaning up after itself covers the real case, which is a drain that
    was killed mid-job and whose next cron wake-up finds the row still running.
    """
    claimable = claimable_workflows(conn, cfg)
    reaped = 0

    for key, wf in sorted(claimable.items()):
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT processing_job_id, attempts, max_attempts, started_at
                  FROM shared.ProcessingJobs
                 WHERE status        = 'running'
                   AND claimed_by    = %s
                   AND workflow_name = %s
                   AND started_at    < now() - make_interval(secs => %s)
                   FOR UPDATE SKIP LOCKED
                """,
                (cfg.name, key, wf.timeout_seconds + cfg.reap_grace_seconds),
            )
            rows = cur.fetchall()
        conn.commit()

        for job_id, attempts, max_attempts, started_at in rows:
            message = (
                f"no result recorded; running since {started_at:%Y-%m-%d %H:%M:%S} on "
                f"'{cfg.name}', past the {wf.timeout_seconds}s timeout -- the process is gone"
            )
            log(f"job {job_id} ({key}): reaped -- {message}")
            finish(conn, cfg, job_id, attempts, max_attempts, succeeded=False, error=message)
            reaped += 1

    log(f"reap finished: {reaped} job(s) recovered")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("command", choices=["list", "drain", "reap"])
    parser.add_argument(
        "--config",
        type=Path,
        default=None,
        help="Path to workflows.toml (default: config/workflows.toml)",
    )
    args = parser.parse_args()

    try:
        cfg = load_config(args.config)
    except ConfigError as exc:
        log(f"ERROR: {exc}")
        return 2

    conn = get_db_connection()
    try:
        return {"list": cmd_list, "drain": cmd_drain, "reap": cmd_reap}[args.command](conn, cfg)
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
