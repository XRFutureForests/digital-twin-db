#!/usr/bin/env python3
"""Create the on-disk data directories the Supabase stack bind-mounts.

Run once as root on a host where PGDATA_PATH / STORAGE_PATH in
docker/.env point outside the repo -- typically a large secondary filesystem.
On dt.unr.uni-freiburg.de that is /media/data, a 100 GB NFS export, because the
28 GB root LV has repeatedly filled up and taken the server offline with it.

The containers cannot create these directories themselves: an NFS export is not
writable by an unprivileged user, and Postgres refuses to initialise a PGDATA it
does not own. The two checks below exist because getting either wrong fails late
and confusingly -- a soft mount corrupts the cluster on the first network blip,
and an export that will not let go of ownership leaves Postgres unable to start.

    sudo python3 scripts/server/setup_data_dirs.py
    sudo python3 scripts/server/setup_data_dirs.py --data-root /srv/dftdb

Where host sudo is not available but the Docker group is, the daemon's own root
does just as well:

    docker run --rm -v /media/data:/media/data         -v "$PWD/scripts/server:/s:ro" python:3.12-alpine         python3 /s/setup_data_dirs.py

Stdlib only, by design: this runs before any environment exists.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# UIDs the images actually run as, read off the pinned tags:
#   docker run --rm --entrypoint sh supabase/postgres:15.8.1.085 -c 'id -u postgres'
# postgres drops from root to 105:106 in its entrypoint; storage-api stays root.
POSTGRES_UID, POSTGRES_GID = 105, 106
STORAGE_UID, STORAGE_GID = 0, 0

DEFAULT_DATA_ROOT = Path("/media/data/dftdb")

# (subdirectory, owner uid, owner gid, mode)
LAYOUT = [
    ("pgdata", POSTGRES_UID, POSTGRES_GID, 0o700),
    ("storage", STORAGE_UID, STORAGE_GID, 0o755),
    ("backups", POSTGRES_UID, POSTGRES_GID, 0o755),
]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def mount_options(path: Path) -> tuple[str, str]:
    """Return (fstype, options) of the filesystem carrying path.

    Reads /proc/self/mountinfo rather than shelling out to findmnt, which is
    absent from the slim images this script is sometimes run inside. Both the
    per-mount and per-superblock option lists matter: NFS records `hard` in the
    latter.
    """
    target = path.resolve()
    best: tuple[int, str, str] | None = None

    with open("/proc/self/mountinfo", encoding="utf-8") as handle:
        for line in handle:
            # <id> <parent> <maj:min> <root> <mountpoint> <opts> [tags...] - <fstype> <source> <super opts>
            head, _, tail = line.partition(" - ")
            head_fields = head.split()
            tail_fields = tail.split()
            if len(head_fields) < 6 or len(tail_fields) < 3:
                continue
            mountpoint = Path(head_fields[4])
            if target != mountpoint and mountpoint not in target.parents:
                continue
            depth = len(mountpoint.parts)
            if best is None or depth > best[0]:
                options = f"{head_fields[5]},{tail_fields[2]}"
                best = (depth, tail_fields[0], options)

    if best is None:
        fail(f"could not identify the filesystem holding {path}")
    return best[1], best[2]


def check_mount_is_safe_for_postgres(path: Path) -> None:
    """Abort on an NFS mount Postgres cannot safely use.

    A soft mount returns an I/O error instead of blocking when the server stalls,
    which can leave a half-written fsync behind and corrupt the cluster. Postgres
    only supports hard mounts. Local filesystems need no check.
    """
    fstype, options = mount_options(path)
    opts = {opt.split("=", 1)[0] for opt in options.split(",")}
    print(f"  filesystem: {fstype} ({options})")

    if not fstype.startswith("nfs"):
        return
    if "soft" in opts:
        fail(
            f"{path} is a soft NFS mount. Postgres can corrupt its cluster on a "
            "soft mount; remount with 'hard' before using it for PGDATA."
        )
    if "hard" not in opts:
        # Hard is the kernel default, but say so rather than silently assuming it.
        print("  note: 'hard' not listed explicitly; it is the NFS default")


def check_can_take_ownership(path: Path) -> None:
    """Abort unless we can hand a directory to the container UIDs.

    The test is chown, not identity. /media/data is an Isilon NFS export that
    squashes root to nobody on create -- every directory there is owned by 65534
    -- yet still honours a chown afterwards, which is all Postgres needs. A
    check for "root stays root" would reject a working export, so probe the
    operation itself.
    """
    probe = path / ".dftdb-ownership-probe"
    try:
        probe.mkdir(exist_ok=True)
        os.chown(probe, POSTGRES_UID, POSTGRES_GID)
        owner = probe.stat().st_uid
    except OSError as exc:
        fail(
            f"cannot create and chown under {path}: {exc}. Postgres will not "
            "start on a PGDATA it does not own."
        )
    finally:
        try:
            probe.rmdir()
        except OSError:
            pass

    if owner != POSTGRES_UID:
        fail(
            f"chown under {path} did not stick (owner is {owner}, expected "
            f"{POSTGRES_UID}). The export is squashing ownership changes; ask "
            "the storage admins to allow them on this export."
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--data-root",
        type=Path,
        default=DEFAULT_DATA_ROOT,
        help=f"parent directory for the stack's data (default: {DEFAULT_DATA_ROOT})",
    )
    args = parser.parse_args()
    data_root: Path = args.data_root

    if os.geteuid() != 0:
        fail("must run as root: sudo python3 scripts/server/setup_data_dirs.py")

    parent = data_root if data_root.exists() else data_root.parent
    if not parent.exists():
        fail(f"{parent} does not exist -- is the filesystem mounted?")

    print(f"Data root: {data_root}")
    check_mount_is_safe_for_postgres(parent)
    check_can_take_ownership(parent)

    data_root.mkdir(parents=True, exist_ok=True)
    os.chmod(data_root, 0o755)

    for name, uid, gid, mode in LAYOUT:
        target = data_root / name
        existed = target.exists()
        target.mkdir(exist_ok=True)
        os.chown(target, uid, gid)
        os.chmod(target, mode)
        state = "exists" if existed else "created"
        print(f"  {state}: {target}  {uid}:{gid} {mode:04o}")

    print("\nAdd to docker/.env:")
    print(f"  PGDATA_PATH={data_root / 'pgdata'}")
    print(f"  STORAGE_PATH={data_root / 'storage'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
