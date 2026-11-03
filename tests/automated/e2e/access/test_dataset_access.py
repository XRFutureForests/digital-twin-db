"""
Dataset access levels (migration 20261102180000, XRFF-625).

Inside a transaction that is rolled back: two accounts, a team with one member,
five campaigns (public, campus, registered, team, public under embargo) with
five existing trees each. Then each caller reads the trees and their stems the
way PostgREST would call the database (SET ROLE plus the request.jwt.claims
and request.headers settings PostgREST sets), and must see exactly:

    caller            public campus registered team embargo
    anon, internet      5      0        0        0     0
    anon, campus        5      5        0        0     0
    signed-in account   5      5        5        0     0
    team member         5      5        5        5     5
    curator             5      5        5        5     5

Plus the write rules (an outsider cannot add rows to a team's campaign or create
a campaign for a team it is not in; a licence is required), and, through the
real API, that the X-DT-Network header reaches the database. On dt.unr nginx
overwrites that header from the client address, so a client cannot forge it
there; locally Kong is reachable directly and passes what it gets.

Needs the local stack running (`docker compose up -d`).
"""

import json
import os
import sys
from pathlib import Path

import psycopg2
import pytest
import requests
from dotenv import dotenv_values

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
from utils.db import get_db_connection  # noqa: E402

ENV = dotenv_values(REPO_ROOT / "docker" / ".env")
BASE = os.getenv("DFTDB_API", f"http://localhost:{ENV.get('KONG_HTTP_PORT', '8000')}")

MEMBER = "00000000-0000-0000-0000-00000000a625"
OUTSIDER = "00000000-0000-0000-0000-00000000b625"
LEVELS = ("c_public", "c_campus", "c_registered", "c_team", "c_embargo")


@pytest.fixture
def db():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO auth.users (id, email, aud, role) VALUES (%s, 'member625@test.invalid', 'authenticated', "
        "'authenticated'), (%s, 'outsider625@test.invalid', 'authenticated', 'authenticated')",
        (MEMBER, OUTSIDER),
    )
    cur.execute("INSERT INTO shared.teams (team_name) VALUES ('t625') RETURNING team_id")
    team = cur.fetchone()[0]
    cur.execute("INSERT INTO shared.team_members (team_id, user_id) VALUES (%s, %s)", (team, MEMBER))
    cur.execute("SELECT location_id FROM shared.variants ORDER BY variant_id LIMIT 1")
    loc = cur.fetchone()[0]
    for name, level, owned, embargo in (
        ("c_public", "public", False, False), ("c_campus", "campus", False, False),
        ("c_registered", "registered", False, False), ("c_team", "team", True, False),
        ("c_embargo", "public", True, True),
    ):
        cur.execute(
            "INSERT INTO shared.campaigns (campaign_name, campaign_type, location_id, start_date, licence, "
            "access_level, owner_team_id, embargo_until) VALUES (%s, 'field_inventory', %s, current_date, "
            "'CC-BY-4.0', %s, %s, CASE WHEN %s THEN current_date + 30 END) RETURNING campaign_id",
            (name, loc, level, team if owned else None, embargo),
        )
        campaign = cur.fetchone()[0]
        cur.execute(
            "UPDATE trees.trees SET campaign_id = %s WHERE tree_id IN (SELECT tree_id FROM trees.trees "
            "WHERE campaign_id IS NULL AND variant_id = (SELECT min(variant_id) FROM shared.variants) "
            "ORDER BY tree_id LIMIT 5)",
            (campaign,),
        )
    cur.execute(
        "SELECT c.campaign_name, array_agg(t.tree_id) FROM trees.trees t "
        "JOIN shared.campaigns c USING (campaign_id) GROUP BY c.campaign_name"
    )
    ids = dict(cur.fetchall())
    yield cur, team, ids
    conn.rollback()
    conn.close()


def as_caller(cur, role, claims=None, network=None):
    cur.execute("RESET ROLE")
    cur.execute("SELECT set_config('request.jwt.claims', %s, true)", (json.dumps(claims) if claims else "",))
    cur.execute(
        "SELECT set_config('request.headers', %s, true)",
        (json.dumps({"x-dt-network": network}) if network else "",),
    )
    cur.execute(f"SET LOCAL ROLE {role}")


def visible(cur, ids):
    """Trees and stems visible per campaign, as {campaign: (trees, stems)}.

    The tree ids were collected as admin, so a hidden tree's stems are still
    looked for -- and must not be found."""
    out = {}
    for name in LEVELS:
        cur.execute(
            "SELECT (SELECT count(*) FROM public.trees WHERE tree_id = ANY(%s)),"
            "       (SELECT count(*) FROM public.stems WHERE tree_id = ANY(%s))",
            (ids[name], ids[name]),
        )
        out[name] = cur.fetchone()
    cur.execute("RESET ROLE")
    return out


def expect(*counts):
    return {name: (n, n) for name, n in zip(LEVELS, counts)}


def test_anonymous_from_the_internet(db):
    cur, _, ids = db
    as_caller(cur, "anon", {"role": "anon"})
    assert visible(cur, ids) == expect(5, 0, 0, 0, 0)


def test_anonymous_from_campus(db):
    cur, _, ids = db
    as_caller(cur, "anon", {"role": "anon"}, network="campus")
    assert visible(cur, ids) == expect(5, 5, 0, 0, 0)


def test_signed_in_account(db):
    cur, _, ids = db
    as_caller(cur, "authenticated", {"role": "authenticated", "sub": OUTSIDER, "app_metadata": {}})
    assert visible(cur, ids) == expect(5, 5, 5, 0, 0)


def test_team_member(db):
    cur, _, ids = db
    as_caller(cur, "authenticated", {"role": "authenticated", "sub": MEMBER, "app_metadata": {}})
    assert visible(cur, ids) == expect(5, 5, 5, 5, 5)


def test_curator(db):
    cur, _, ids = db
    as_caller(cur, "authenticated", {"role": "authenticated", "sub": OUTSIDER, "app_metadata": {"role": "curator"}})
    assert visible(cur, ids) == expect(5, 5, 5, 5, 5)


def test_outsider_cannot_write_into_or_claim_a_team_campaign(db):
    cur, team, _ = db
    contributor = {"role": "authenticated", "sub": OUTSIDER, "app_metadata": {"role": "contributor"}}
    as_caller(cur, "authenticated", contributor)
    cur.execute("SAVEPOINT s")
    with pytest.raises(psycopg2.errors.InsufficientPrivilege):
        cur.execute(
            "INSERT INTO trees.trees (location_id, variant_type_id, variant_id, position, campaign_id) "
            "SELECT 1, 1, (SELECT min(variant_id) FROM shared.variants), ST_SetSRID(ST_MakePoint(8, 48), 4326), "
            "campaign_id FROM shared.campaigns WHERE campaign_name = 'c_team'"
        )
    cur.execute("ROLLBACK TO SAVEPOINT s")
    as_caller(cur, "authenticated", contributor)
    with pytest.raises(psycopg2.errors.InsufficientPrivilege):
        cur.execute(
            "INSERT INTO public.campaigns (campaign_name, campaign_type, location_id, start_date, licence, "
            "access_level, owner_team_id) VALUES ('c_claim', 'field_inventory', 1, current_date, 'CC0-1.0', "
            "'team', %s)",
            (team,),
        )
    cur.execute("ROLLBACK TO SAVEPOINT s")


def test_licence_is_required(db):
    cur, _, _ = db
    cur.execute("SAVEPOINT s")
    with pytest.raises(psycopg2.errors.NotNullViolation):
        cur.execute(
            "INSERT INTO shared.campaigns (campaign_name, campaign_type, location_id, start_date) "
            "VALUES ('c_nolicence', 'field_inventory', 1, current_date)"
        )
    cur.execute("ROLLBACK TO SAVEPOINT s")


def test_network_header_reaches_the_database():
    anon = {"apikey": ENV["ANON_KEY"], "Content-Type": "application/json"}
    plain = requests.post(f"{BASE}/rest/v1/rpc/my_access", headers=anon, json={}, timeout=15)
    campus = requests.post(f"{BASE}/rest/v1/rpc/my_access", headers={**anon, "X-DT-Network": "campus"},
                           json={}, timeout=15)
    assert plain.status_code == 200 and campus.status_code == 200
    assert plain.json()[0]["network"] == "internet"
    assert campus.json()[0]["network"] == "campus"
