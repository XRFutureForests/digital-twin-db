"""The local half of a workflow declaration: what this host may execute.

A workflow is declared in two places that never overlap. `shared.Processes`
names it and describes its parameters; `config/workflows.toml` -- gitignored,
per host -- says what command that name runs. The runner claims a job only when
its workflow appears in both. Nothing a caller sends can name a command,
because commands exist only here.

Arguments are derived from the parameter names rather than listed, so
`param_schema` in the database stays the single description of what a workflow
accepts and this file does not repeat it. See `build_argv`.
"""

from __future__ import annotations

import socket
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).parent.parent.parent
DEFAULT_CONFIG_PATH = REPO_ROOT / "config" / "workflows.toml"


class ConfigError(Exception):
    """The runner configuration is unusable. Never a job-level failure."""


@dataclass(frozen=True)
class Workflow:
    key: str
    command: tuple[str, ...]
    timeout_seconds: int
    positional: tuple[str, ...] = ()


@dataclass(frozen=True)
class RunnerConfig:
    name: str
    max_jobs: int
    retry_backoff_seconds: int
    reap_grace_seconds: int
    workflows: dict[str, Workflow] = field(default_factory=dict)


def _require_positive_int(table: dict[str, Any], key: str, default: int, where: str) -> int:
    value = table.get(key, default)
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ConfigError(f"{where}: {key} must be a positive integer, got {value!r}")
    return value


def load_config(path: Path | None = None) -> RunnerConfig:
    """Read and validate workflows.toml.

    Validation is strict and happens once, at startup, so a typo in a host's
    configuration is a loud failure before any job is claimed rather than a
    confusing job failure afterwards.
    """
    path = path or DEFAULT_CONFIG_PATH
    if not path.exists():
        raise ConfigError(
            f"no runner configuration at {path}. "
            f"Copy config/workflows.example.toml to config/workflows.toml and edit it."
        )

    try:
        with path.open("rb") as handle:
            raw = tomllib.load(handle)
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError(f"{path}: {exc}") from exc

    runner = raw.get("runner", {})
    if not isinstance(runner, dict):
        raise ConfigError(f"{path}: [runner] must be a table")

    name = runner.get("name") or socket.gethostname()
    if not isinstance(name, str) or not name.strip():
        raise ConfigError(f"{path}: runner.name must be a non-empty string")

    workflows: dict[str, Workflow] = {}
    for key, table in (raw.get("workflows") or {}).items():
        where = f"{path}: [workflows.{key}]"
        if not isinstance(table, dict):
            raise ConfigError(f"{where} must be a table")

        command = table.get("command")
        if (
            not isinstance(command, list)
            or not command
            or not all(isinstance(part, str) and part for part in command)
        ):
            raise ConfigError(
                f"{where}: command must be a non-empty list of non-empty strings. "
                f"A list, never a string: the command is executed directly, not through a shell."
            )

        positional = table.get("positional", [])
        if not isinstance(positional, list) or not all(isinstance(p, str) for p in positional):
            raise ConfigError(f"{where}: positional must be a list of parameter names")
        if len(set(positional)) != len(positional):
            raise ConfigError(f"{where}: positional lists a parameter twice")

        unknown = set(table) - {"command", "timeout_seconds", "positional"}
        if unknown:
            raise ConfigError(f"{where}: unknown key(s) {', '.join(sorted(unknown))}")

        workflows[key] = Workflow(
            key=key,
            command=tuple(command),
            timeout_seconds=_require_positive_int(table, "timeout_seconds", 3600, where),
            positional=tuple(positional),
        )

    return RunnerConfig(
        name=name.strip(),
        max_jobs=_require_positive_int(runner, "max_jobs", 3, f"{path}: [runner]"),
        retry_backoff_seconds=_require_positive_int(
            runner, "retry_backoff_seconds", 300, f"{path}: [runner]"
        ),
        reap_grace_seconds=_require_positive_int(
            runner, "reap_grace_seconds", 120, f"{path}: [runner]"
        ),
        workflows=workflows,
    )


def _render(value: Any) -> str:
    """One parameter value as one argv element.

    Never quoted or escaped, because it is never parsed: the argv list is
    passed to execve, so a value containing spaces, quotes or a semicolon is
    one argument and nothing more.
    """
    if isinstance(value, bool):  # not reachable via build_argv; guards misuse
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def build_argv(workflow: Workflow, params: dict[str, Any]) -> list[str]:
    """Turn a job's input_data into the argv for its command.

    `foo_bar` becomes `--foo-bar <value>`; a true boolean becomes the bare flag
    and a false one is omitted, matching how every CLI in this project declares
    its switches; a key named in `positional` becomes a bare value, in the
    order the configuration lists it.

    Parameters are sorted so the same job always produces the same command line
    -- worth having when a failure is reproduced by hand from a log.
    """
    argv = list(workflow.command)

    for key in workflow.positional:
        if key in params:
            argv.append(_render(params[key]))

    for key, value in sorted(params.items()):
        if key in workflow.positional:
            continue
        flag = "--" + key.replace("_", "-")
        if isinstance(value, bool):
            if value:
                argv.append(flag)
        else:
            argv.extend([flag, _render(value)])

    return argv
