"""
Who may run which function (XRFF-661).

PostgREST serves the base schemas as well as `public`, and PostgreSQL lets
PUBLIC execute every new function. A SECURITY DEFINER function runs with its
owner's rights, so one that anon can execute is an open door: until
2026-11-09 anyone could reload the lookup tables or write the audit log
through POST /rest/v1/rpc/<name> with a Content-Profile header.

These tests pin the DEFINER functions anon and authenticated may execute to a
named list. A new DEFINER function stays closed unless it is added here and
granted in its migration.

Needs the local stack running (`docker compose up -d`).
"""

import os
import sys
from pathlib import Path

import requests
from dotenv import dotenv_values

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from utils.db import get_db_connection  # noqa: E402

ENV = dotenv_values(REPO_ROOT / "docker" / ".env")
BASE = os.getenv("DFTDB_API", f"http://localhost:{ENV.get('KONG_HTTP_PORT', '8000')}")

BASE_SCHEMAS = ("shared", "trees", "sensor", "point_clouds", "environments", "imagery", "forest_floor")

# Row-level security helpers: each answers only about the caller's own token.
POLICY_HELPERS = {
    "shared.has_restricted_campaigns", "shared.hidden_observation_ids", "shared.hidden_point_cloud_ids",
    "shared.hidden_qsm_ids", "shared.hidden_sensor_ids", "shared.hidden_tree_ids", "shared.is_admin",
    "shared.is_contributor", "shared.is_curator", "shared.my_curated_team_ids", "shared.my_team_ids",
    "shared.readable_campaign_ids", "shared.writable_campaign_ids", "shared.writable_observation_ids",
}
ALLOWED = {
    "anon": POLICY_HELPERS,
    "authenticated": POLICY_HELPERS | {
        "shared.may_manage_role", "shared.unwritable_tree_ids", "shared.unwritable_sensor_ids",
        "shared.unwritable_point_cloud_ids", "shared.unwritable_qsm_ids",
    },
}


def definer_functions_executable_by(role):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT n.nspname || '.' || p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                "WHERE p.prosecdef AND p.prorettype <> 'trigger'::regtype AND n.nspname = ANY(%s) "
                "AND has_function_privilege(%s, p.oid, 'EXECUTE')",
                (list(BASE_SCHEMAS), role),
            )
            return {row[0] for row in cur.fetchall()}
    finally:
        conn.close()


def test_anon_runs_only_the_policy_helpers():
    assert definer_functions_executable_by("anon") == ALLOWED["anon"]


def test_authenticated_runs_only_the_listed_helpers():
    assert definer_functions_executable_by("authenticated") == ALLOWED["authenticated"]


def test_admin_rpc_is_refused_through_the_api():
    response = requests.post(
        f"{BASE}/rest/v1/rpc/refresh_lookup",
        headers={"apikey": ENV["ANON_KEY"], "Content-Profile": "shared", "Content-Type": "application/json"},
        json={"p_table_name": "no_such_lookup"},
        timeout=15,
    )
    assert response.status_code in (401, 403)
    assert response.json()["code"] == "42501"
