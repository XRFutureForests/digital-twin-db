"""
Delegated account management (migration 20261030100000), through the real API.

The functions write auth.users and auth.identities directly, so the test that
matters is GoTrue accepting what they wrote: an account made by create_account()
must sign in with the password it returned, carry the role claim, change its
own password, and lose its sessions on reset. Everything goes through Kong the
way the portal does -- PostgREST for the RPCs, GoTrue for sign-in.

Actor tokens (curator, admin) are minted from JWT_SECRET with a random `sub`:
the functions only read the role claim and compare `sub` to the target, so the
actor does not need a row in auth.users. Accounts created here are deleted at
the end, with their shared.account_events rows, through the service-role API.

Needs the local stack running (`docker compose up -d`).
"""

import base64
import hashlib
import hmac
import json
import os
import time
import uuid
from pathlib import Path

import pytest
import requests
from dotenv import dotenv_values

REPO_ROOT = Path(__file__).parents[4]
ENV = dotenv_values(REPO_ROOT / "docker" / ".env")
BASE = os.getenv("DFTDB_API", f"http://localhost:{ENV.get('KONG_HTTP_PORT', '8000')}")
ANON = ENV["ANON_KEY"]
SERVICE = {"apikey": ENV["SERVICE_ROLE_KEY"], "Authorization": f"Bearer {ENV['SERVICE_ROLE_KEY']}"}
PREFIX = f"acct-test-{int(time.time())}"


def mint(role_claim):
    now = int(time.time())
    payload = {
        "aud": "authenticated", "role": "authenticated", "iss": "supabase",
        "sub": str(uuid.uuid4()), "email": f"{role_claim}-actor@test.invalid",
        "app_metadata": {"role": role_claim}, "iat": now, "exp": now + 600,
    }

    def b64(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()

    msg = f"{b64({'alg': 'HS256', 'typ': 'JWT'})}.{b64(payload)}"
    sig = hmac.new(ENV["JWT_SECRET"].encode(), msg.encode(), hashlib.sha256).digest()
    return f"{msg}.{base64.urlsafe_b64encode(sig).rstrip(b'=').decode()}"


def rpc(name, body, token=None):
    headers = {"apikey": ANON, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return requests.post(f"{BASE}/rest/v1/rpc/{name}", headers=headers, json=body, timeout=15)


def sign_in(email, password):
    return requests.post(
        f"{BASE}/auth/v1/token?grant_type=password",
        headers={"apikey": ANON, "Content-Type": "application/json"},
        json={"email": email, "password": password}, timeout=15,
    )


def claims(token):
    part = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))


@pytest.fixture(scope="module", autouse=True)
def cleanup():
    yield
    requests.delete(f"{BASE}/rest/v1/account_events?target_email=like.{PREFIX}*",
                    headers={**SERVICE, "Content-Profile": "shared"}, timeout=15).raise_for_status()
    users = requests.get(f"{BASE}/auth/v1/admin/users?per_page=1000", headers=SERVICE, timeout=15).json()["users"]
    for u in users:
        if u["email"].startswith(PREFIX):
            requests.delete(f"{BASE}/auth/v1/admin/users/{u['id']}", headers=SERVICE, timeout=15).raise_for_status()


CURATOR = mint("curator")
ADMIN = mint("admin")


def test_created_account_signs_in_changes_password_and_loses_sessions_on_reset():
    email = f"{PREFIX}-a@test.invalid"

    r = rpc("create_account", {"p_email": email.upper(), "p_role": "contributor"}, CURATOR)
    assert r.status_code == 200, r.text
    (row,) = r.json()
    assert row["email"] == email and row["role"] == "contributor" and len(row["password"]) == 20

    s = sign_in(email, row["password"])
    assert s.status_code == 200, s.text
    session = s.json()
    c = claims(session["access_token"])
    assert c["app_metadata"]["role"] == "contributor"
    assert c["user_metadata"]["must_change_password"] is True

    # The holder changes it with their own token -- no mail involved.
    new_password = "portal-" + uuid.uuid4().hex
    u = requests.put(
        f"{BASE}/auth/v1/user",
        headers={"apikey": ANON, "Authorization": f"Bearer {session['access_token']}",
                 "Content-Type": "application/json"},
        json={"password": new_password, "data": {"must_change_password": False}}, timeout=15,
    )
    assert u.status_code == 200, u.text
    assert sign_in(email, row["password"]).status_code == 400
    s2 = sign_in(email, new_password)
    assert s2.status_code == 200
    assert claims(s2.json()["access_token"])["user_metadata"]["must_change_password"] is False

    # A reset issues a new password and ends every session.
    r = rpc("reset_account_password", {"p_email": email}, CURATOR)
    assert r.status_code == 200, r.text
    reset_pw = r.json()[0]["password"]
    refresh = requests.post(
        f"{BASE}/auth/v1/token?grant_type=refresh_token",
        headers={"apikey": ANON, "Content-Type": "application/json"},
        json={"refresh_token": s2.json()["refresh_token"]}, timeout=15,
    )
    assert refresh.status_code >= 400
    assert sign_in(email, new_password).status_code == 400
    assert sign_in(email, reset_pw).status_code == 200


def test_role_change_reaches_the_next_token():
    email = f"{PREFIX}-b@test.invalid"
    pw = rpc("create_account", {"p_email": email}, CURATOR).json()[0]["password"]
    first = sign_in(email, pw).json()
    assert "role" not in claims(first["access_token"])["app_metadata"]

    assert rpc("set_account_role", {"p_email": email, "p_role": "contributor"}, CURATOR).status_code == 200
    refreshed = requests.post(
        f"{BASE}/auth/v1/token?grant_type=refresh_token",
        headers={"apikey": ANON, "Content-Type": "application/json"},
        json={"refresh_token": first["refresh_token"]}, timeout=15,
    ).json()
    assert claims(refreshed["access_token"])["app_metadata"]["role"] == "contributor"

    assert rpc("set_account_role", {"p_email": email, "p_role": None}, CURATOR).status_code == 200
    again = sign_in(email, pw).json()
    assert "role" not in claims(again["access_token"])["app_metadata"]


@pytest.mark.parametrize("call,body", [
    ("create_account", {"p_email": f"{PREFIX}-c@test.invalid", "p_role": "curator"}),
    ("create_account", {"p_email": f"{PREFIX}-c@test.invalid", "p_role": "admin"}),
])
def test_curator_cannot_hand_out_curator_or_admin(call, body):
    r = rpc(call, body, CURATOR)
    assert r.status_code == 403, r.text
    assert "only admins" in r.json()["hint"].lower()


def test_curator_cannot_touch_a_curator_account_but_admin_can():
    email = f"{PREFIX}-d@test.invalid"
    assert rpc("create_account", {"p_email": email, "p_role": "curator"}, ADMIN).status_code == 200
    assert rpc("set_account_role", {"p_email": email, "p_role": None}, CURATOR).status_code == 403
    assert rpc("reset_account_password", {"p_email": email}, CURATOR).status_code == 403
    assert rpc("set_account_role", {"p_email": email, "p_role": "contributor"}, ADMIN).status_code == 200


def test_contributor_and_anon_are_refused():
    body = {"p_email": f"{PREFIX}-e@test.invalid"}
    assert rpc("create_account", body, mint("contributor")).status_code == 403
    assert rpc("list_accounts", {}, mint("contributor")).status_code == 403
    assert rpc("create_account", body).status_code in (401, 403)


def test_duplicate_and_bad_input_are_refused():
    email = f"{PREFIX}-f@test.invalid"
    assert rpc("create_account", {"p_email": email}, CURATOR).status_code == 200
    dup = rpc("create_account", {"p_email": email}, CURATOR)
    assert dup.status_code == 409, dup.text
    assert rpc("create_account", {"p_email": "not-an-address"}, CURATOR).status_code == 400
    assert rpc("create_account", {"p_email": f"{PREFIX}-g@test.invalid", "p_role": "owner"}, CURATOR).status_code == 400


def test_list_accounts_marks_what_the_caller_may_change_and_events_are_logged():
    rows = {r["email"]: r for r in rpc("list_accounts", {}, CURATOR).json()}
    assert rows[f"{PREFIX}-f@test.invalid"]["manageable"] is True
    assert rows[f"{PREFIX}-d@test.invalid"]["role"] == "contributor"

    events = requests.get(f"{BASE}/rest/v1/account_events?select=action&target_email=like.{PREFIX}*",
                          headers={**SERVICE, "Accept-Profile": "shared"}, timeout=15).json()
    counts = {}
    for e in events:
        counts[e["action"]] = counts.get(e["action"], 0) + 1
    assert counts.get("create", 0) >= 4 and counts.get("set_role", 0) >= 3 and counts.get("reset_password") == 1


def test_no_role_account_is_read_only_on_metadata():
    email = f"{PREFIX}-h@test.invalid"
    pw = rpc("create_account", {"p_email": email}, CURATOR).json()[0]["password"]
    token = sign_in(email, pw).json()["access_token"]
    r = requests.post(
        f"{BASE}/rest/v1/plots",
        headers={"apikey": ANON, "Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"location_id": 1, "plot_name": PREFIX}, timeout=15,
    )
    assert r.status_code in (401, 403), r.text
    assert "row-level security" in r.text


def test_blocked_update_through_a_trigger_view_reports_zero_rows():
    # Migration 20261030110000: public.trees updates through an INSTEAD OF
    # trigger; when RLS skips the row (contributors may not update trees) the
    # caller must see [] -- before the fix it got the row back as if saved.
    # Same-value PATCH, so nothing changes even if the check regresses.
    tree = requests.get(f"{BASE}/rest/v1/trees?select=tree_id,height_m&height_m=not.is.null&limit=1",
                        headers={"apikey": ANON}, timeout=15).json()[0]
    r = requests.patch(
        f"{BASE}/rest/v1/trees?tree_id=eq.{tree['tree_id']}",
        headers={"apikey": ANON, "Authorization": f"Bearer {mint('contributor')}",
                 "Content-Type": "application/json", "Prefer": "return=representation"},
        json={"height_m": tree["height_m"]}, timeout=15,
    )
    assert r.status_code == 200 and r.json() == [], r.text
