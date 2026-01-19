#!/usr/bin/env python3
"""
Sync sensor data from Aquarius API via the ecosense-ingest edge function.

This script:
1. Checks Docker services are running
2. Verifies VPN connectivity to Aquarius
3. Calls the ecosense-ingest edge function
4. Reports sync results

Requires: University VPN connection for Aquarius access
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
DOCKER_DIR = PROJECT_ROOT / "docker"
ENV_PATH = DOCKER_DIR / ".env"

# Load environment
load_dotenv(ENV_PATH)

SERVICE_ROLE_KEY = os.getenv("SERVICE_ROLE_KEY", "")
AQUARIUS_HOSTNAME = os.getenv(
    "AQUARIUS_HOSTNAME", "http://fuhys006.public.ads.uni-freiburg.de"
)


def run_command(
    cmd: list, capture: bool = True, check: bool = False
) -> subprocess.CompletedProcess:
    """Run a shell command and return result."""
    return subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        check=check,
    )


def check_docker_services() -> bool:
    """Check if required Docker services are running."""
    result = run_command(
        [
            "docker",
            "compose",
            "-f",
            str(DOCKER_DIR / "docker-compose.yml"),
            "ps",
            "--quiet",
            "kong",
        ]
    )
    return result.returncode == 0 and result.stdout.strip() != ""


def get_docker_network() -> str | None:
    """Get the Docker network name for the project."""
    # Try to find network by name pattern
    result = run_command(["docker", "network", "ls", "--format", "{{.Name}}"])
    if result.returncode == 0:
        for line in result.stdout.strip().split("\n"):
            if re.search(
                r"digital.*forest.*twin.*default|dftdb.*default", line, re.IGNORECASE
            ):
                return line.strip()

    # Fallback: get network from kong container
    result = run_command(
        [
            "docker",
            "inspect",
            "dftdb-kong",
            "--format",
            "{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}",
        ]
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip().split()[0]

    return None


def check_vpn_connectivity() -> bool:
    """Check VPN connectivity to Aquarius from edge-functions container."""
    result = run_command(
        [
            "docker",
            "exec",
            "dftdb-edge-functions",
            "sh",
            "-c",
            f"wget -q --spider --timeout=5 '{AQUARIUS_HOSTNAME}/AQUARIUS/'",
        ]
    )
    return result.returncode == 0


def call_ecosense_ingest(network: str, days_back: int) -> dict:
    """Call the ecosense-ingest edge function."""
    api_url = "http://kong:8000"

    result = run_command(
        [
            "docker",
            "run",
            "--rm",
            "--network",
            network,
            "curlimages/curl:latest",
            "-s",
            "-X",
            "POST",
            f"{api_url}/functions/v1/ecosense-ingest?days_back={days_back}",
            "-H",
            f"Authorization: Bearer {SERVICE_ROLE_KEY}",
            "-H",
            "Content-Type: application/json",
        ]
    )

    if result.returncode != 0:
        return {"success": False, "error": f"curl failed: {result.stderr}"}

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"success": False, "error": f"Invalid JSON response: {result.stdout}"}


def main():
    """Main sync workflow."""
    # Parse arguments
    days_back = 30
    if len(sys.argv) > 1:
        try:
            days_back = int(sys.argv[1])
        except ValueError:
            print(f"Usage: {sys.argv[0]} [days_back]")
            print("  days_back: Number of days to sync (default: 30)")
            sys.exit(1)

    print("=" * 50)
    print("Aquarius Data Sync")
    print("=" * 50)
    print(f"Days back: {days_back}")
    print()

    # Check Docker services
    print("Checking Docker services...")
    if not check_docker_services():
        print("❌ Kong API gateway is not running")
        print("   Start services with: cd docker && docker compose up -d")
        sys.exit(1)
    print("✓ Docker services running")

    # Get Docker network
    network = get_docker_network()
    if not network:
        print("❌ Could not determine Docker network name")
        sys.exit(1)
    print(f"✓ Docker network: {network}")

    # Check VPN connectivity
    print("\nChecking Aquarius connectivity...")
    if not check_vpn_connectivity():
        print("⚠️  Warning: Cannot reach Aquarius server from container")
        print("   Make sure you are connected to the university VPN")
        print()
    else:
        print("✓ Aquarius reachable")

    # Call edge function
    print("\nCalling ecosense-ingest function...")
    response = call_ecosense_ingest(network, days_back)

    # Print response
    print(json.dumps(response, indent=2))

    # Check result
    if response.get("success"):
        print()
        print("=" * 50)
        print("✅ Sync completed successfully!")
        print(f"   Sensors: {response.get('sensors', 'N/A')}")
        print(f"   Readings: {response.get('count', 'N/A')}")
        print("=" * 50)
    else:
        error = response.get("error") or response.get("message") or "Unknown error"
        print()
        print(f"❌ Error: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()
