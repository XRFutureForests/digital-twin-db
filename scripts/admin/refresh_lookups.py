#!/usr/bin/env python3
"""
Refresh lookup tables from CSV files without full database rebuild.

This script calls database functions to reload lookup tables from their
source CSV files in data/lookups/.

Usage:
    python refresh_lookups.py              # Refresh all lookup tables
    python refresh_lookups.py species      # Refresh specific table
    python refresh_lookups.py --list       # List available tables
"""

import subprocess
import sys

# Configuration
CONTAINER_NAME = "dftdb-db"

# Keep in step with shared.lookup_registry. The two lists were maintained by
# hand and drifted -- three keys the SQL supported were missing here, so --all
# silently skipped them (XRFF-496). validate_against_registry() below now fails
# loudly on a mismatch instead of leaving it to be noticed by accident.
AVAILABLE_TABLES = {
    "species": ("species.csv", "Tree species definitions"),
    "locations": ("locations.csv", "Research plot locations"),
    "sensor_types": ("sensor_types.csv", "Sensor type definitions"),
    "tree_status": ("tree_status.csv", "Tree health status values"),
    "soil_types": ("soil_types.csv", "USDA soil classification"),
    "climate_zones": ("climate_zones.csv", "Köppen climate zones"),
    "scenarios": ("scenarios.csv", "Simulation scenarios"),
    "variant_types": ("variant_types.csv", "Tree variant types"),
    "taper_types": ("taper_types.csv", "Stem taper form types"),
    "straightness_types": ("straightness_types.csv", "Stem straightness categories"),
    "branching_patterns": ("branching_patterns.csv", "Branch arrangement patterns"),
    "bark_characteristics": ("bark_characteristics.csv", "Bark texture types"),
    "height_classes": ("phanerophyte_height_classes.csv", "Raunkiær height classes"),
    "crown_architectures": ("crown_architectures.csv", "Crown architecture models"),
    "branch_elongation_habits": (
        "branch_elongation_habits.csv",
        "Branch elongation habits",
    ),
    "growth_orientations": ("growth_orientations.csv", "Growth orientation types"),
    "shoot_elongation_types": ("shoot_elongation_types.csv", "Shoot elongation types"),
    "crown_shapes": ("crown_shapes.csv", "Crown shape classifications"),
    "geometric_crown_solids": (
        "geometric_crown_solids.csv",
        "Geometric crown solid models",
    ),
    "axis_structures": ("axis_structures.csv", "Tree axis structure models"),
    "growth_forms": ("growth_forms.csv", "Tree growth form types"),
    # These three exist in shared.refresh_lookup but were missing here, so
    # --all silently skipped them. The two lists are maintained by hand and
    # nothing checks they agree (XRFF-496).
    "data_source_types": ("data_source_types.csv", "Tree data source types"),
    "crown_classes": ("crown_classes.csv", "Crown class definitions"),
    "damage_agents": ("damage_agents.csv", "Damage agent types"),
}


class Colors:
    """ANSI color codes for terminal output."""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    RESET = "\033[0m"


def print_color(text: str, color: str) -> None:
    """Print colored text."""
    print(f"{color}{text}{Colors.RESET}")


def show_help() -> None:
    """Display help message."""
    print("Refresh Lookup Tables")
    print()
    print("Usage:")
    print("  python refresh_lookups.py              Refresh all lookup tables")
    print("  python refresh_lookups.py <table>      Refresh specific table")
    print("  python refresh_lookups.py --list       List available tables")
    print("  python refresh_lookups.py --help       Show this help")
    print()
    print("Available tables:")
    print("  " + ", ".join(AVAILABLE_TABLES.keys()))
    print()
    print("Examples:")
    print("  python refresh_lookups.py species      Refresh species from species.csv")
    print(
        "  python refresh_lookups.py locations    Refresh locations from locations.csv"
    )


def list_tables() -> None:
    """List available lookup tables."""
    print("Available lookup tables:")
    print()
    print(f"  {'Table Name':<15} {'CSV File':<25} Description")
    print(f"  {'─' * 15:<15} {'─' * 25:<25} {'─' * 30}")

    for table, (csv_file, description) in AVAILABLE_TABLES.items():
        print(f"  {table:<15} {csv_file:<25} {description}")

    print()
    print("CSV files location: data/lookups/")


def check_container() -> bool:
    """Check if the database container is running."""
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=True,
        )
        running_containers = result.stdout.strip().split("\n")

        if CONTAINER_NAME not in running_containers:
            print_color(
                f"Error: Database container '{CONTAINER_NAME}' is not running",
                Colors.RED,
            )
            print("Start the database with: cd docker && docker compose up -d")
            return False

        return True
    except subprocess.CalledProcessError:
        print_color("Error: Could not check docker containers", Colors.RED)
        return False


def run_psql(sql: str) -> bool:
    """Execute SQL via psql in the container."""
    try:
        result = subprocess.run(
            [
                "docker",
                "exec",
                "-i",
                CONTAINER_NAME,
                "psql",
                "-U",
                "postgres",
                "-c",
                sql,
            ],
            capture_output=True,
            text=True,
        )

        # Color the output
        output = result.stdout
        output = output.replace("OK", f"{Colors.GREEN}OK{Colors.RESET}")
        output = output.replace("ERROR", f"{Colors.RED}ERROR{Colors.RESET}")

        # Filter empty lines
        for line in output.split("\n"):
            if line.strip():
                print(line)

        if result.returncode != 0:
            print_color(result.stderr, Colors.RED)
            return False

        return True
    except subprocess.CalledProcessError as e:
        print_color(f"Error: {e}", Colors.RED)
        return False


def refresh_all() -> bool:
    """Refresh all lookup tables."""
    print_color("Refreshing all lookup tables...", Colors.YELLOW)
    print()

    success = run_psql("SELECT * FROM shared.refresh_all_lookups();")

    print()
    if success:
        print_color("Done!", Colors.GREEN)
        print("Edit CSV files in data/lookups/ and run again to update.")

    return success


def refresh_table(table: str) -> bool:
    """Refresh a specific lookup table."""
    if table not in AVAILABLE_TABLES:
        print_color(f"Error: Unknown table '{table}'", Colors.RED)
        print(f"Available tables: {', '.join(AVAILABLE_TABLES.keys())}")
        return False

    print_color(f"Refreshing {table}...", Colors.YELLOW)
    print()

    return run_psql(f"SELECT * FROM shared.refresh_lookup('{table}');")


def main() -> int:
    """Main entry point."""
    args = sys.argv[1:]

    if not args:
        # Refresh all tables
        if not check_container():
            return 1
        return 0 if refresh_all() else 1

    arg = args[0]

    if arg in ("--help", "-h"):
        show_help()
        return 0

    if arg in ("--list", "-l"):
        list_tables()
        return 0

    # Refresh specific table
    if not check_container():
        return 1

    return 0 if refresh_table(arg) else 1


if __name__ == "__main__":
    sys.exit(main())


def validate_against_registry(conn) -> list[str]:
    """Return the discrepancies between this module and shared.lookup_registry.

    The registry drives the loader; this dict drives the CLI. They are two hand-
    maintained lists of the same thing, which is exactly how three lookups came
    to be missing here while the SQL supported them.
    """
    cur = conn.cursor()
    cur.execute("SELECT logical_key, csv_file FROM shared.lookup_registry")
    registry = dict(cur.fetchall())
    # locations and scenarios keep bespoke branches and are not in the registry.
    BESPOKE = {"locations", "scenarios"}

    problems = []
    for key in sorted(set(registry) - set(AVAILABLE_TABLES)):
        problems.append(f"in shared.lookup_registry but not in AVAILABLE_TABLES: {key}")
    for key in sorted(set(AVAILABLE_TABLES) - set(registry) - BESPOKE):
        problems.append(f"in AVAILABLE_TABLES but not in shared.lookup_registry: {key}")
    for key in sorted(set(registry) & set(AVAILABLE_TABLES)):
        csv_here = AVAILABLE_TABLES[key][0]
        if csv_here != registry[key]:
            problems.append(
                f"{key}: CSV differs -- AVAILABLE_TABLES says {csv_here!r}, "
                f"shared.lookup_registry says {registry[key]!r}"
            )
    return problems
