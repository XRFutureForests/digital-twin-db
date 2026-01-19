#!/usr/bin/env python3
"""
Reset the database by removing all containers, data, and volumes.

This script:
1. Stops all docker compose services
2. Removes volumes and orphan containers
3. Deletes the database data directory

WARNING: All database data will be permanently deleted!

Usage:
    python reset_database.py
    python reset_database.py --force  # Skip confirmation prompt
"""

import shutil
import subprocess
import sys
from pathlib import Path

# Docker folder is at ../docker relative to scripts/admin
DOCKER_DIR = Path(__file__).parent.parent.parent / "docker"
DB_DATA_DIR = DOCKER_DIR / "volumes" / "db" / "data"


def confirm_reset() -> bool:
    """Prompt user for confirmation."""
    print("⚠️  WARNING: This will remove all containers, data, and volumes.")
    print("    All database data will be permanently deleted!")
    print()
    response = input("Continue? (y/N) ").strip().lower()
    return response in ("y", "yes")


def run_command(cmd: list[str], cwd: Path) -> bool:
    """Run a command and return success status."""
    try:
        result = subprocess.run(
            cmd, cwd=cwd, check=True, capture_output=True, text=True
        )
        if result.stdout:
            print(result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.stderr}")
        return False


def reset_database(force: bool = False) -> int:
    """Reset the database and all docker resources."""

    if not DOCKER_DIR.exists():
        print(f"Error: Docker directory not found: {DOCKER_DIR}")
        return 1

    if not force and not confirm_reset():
        print("Cancelled.")
        return 0

    print()
    print("Stopping all services...")
    if not run_command(
        ["docker", "compose", "down", "-v", "--remove-orphans"], cwd=DOCKER_DIR
    ):
        print("Warning: Could not stop docker services")

    print()
    print("Removing database data...")
    if DB_DATA_DIR.exists():
        try:
            shutil.rmtree(DB_DATA_DIR)
            print(f"  Removed: {DB_DATA_DIR}")
        except PermissionError:
            print(f"  Warning: Could not remove {DB_DATA_DIR} (permission denied)")
            print("  Try running with sudo or manually remove the directory")
    else:
        print(f"  Directory does not exist: {DB_DATA_DIR}")

    print()
    print("✅ Reset complete. Start fresh with:")
    print(f"   cd {DOCKER_DIR} && docker compose up -d")

    return 0


def main():
    force = "--force" in sys.argv or "-f" in sys.argv
    sys.exit(reset_database(force=force))


if __name__ == "__main__":
    main()
