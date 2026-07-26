"""Shared PostgreSQL connection helper for the scripts in this repo.

`get_db_connection()` was previously copy-pasted into five scripts, and the
copies had drifted: three hardcoded `POSTGRES_HOST = "localhost"` while
`AGENTS.md` documents `POSTGRES_HOST` as configurable, so the documented
variable silently did nothing in most of them.

Connection settings come from `docker/.env` (gitignored). When
`POOLER_TENANT_ID` is set, Supavisor requires the tenant-qualified username
form `postgres.<tenant>`; direct connections use the bare username.
"""

import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).parent.parent.parent

load_dotenv(REPO_ROOT / "docker" / ".env")

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
# `docker/.env` sets POSTGRES_HOST to the compose service name so the containers
# can reach each other. These scripts are host-run tools (see README: activate
# the conda env, then `python scripts/...`), where that name does not resolve --
# so map it back to localhost. Only relevant if a script is ever run from inside
# the compose network, in which case set POSTGRES_HOST to something else.
if POSTGRES_HOST == "db":
    POSTGRES_HOST = "localhost"
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DATABASE = os.getenv("POSTGRES_DB", "postgres")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")
POOLER_TENANT_ID = os.getenv("POOLER_TENANT_ID", "")

POSTGRES_USER_POOLER = (
    f"{POSTGRES_USER}.{POOLER_TENANT_ID}" if POOLER_TENANT_ID else POSTGRES_USER
)


def get_db_connection():
    """Open a psycopg2 connection to the digital twin database."""
    return psycopg2.connect(
        host=POSTGRES_HOST,
        user=POSTGRES_USER_POOLER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DATABASE,
        port=POSTGRES_PORT,
    )
