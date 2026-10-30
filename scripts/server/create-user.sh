#!/usr/bin/env bash
#
# Create an account that can request jobs, or inspect the ones that exist.
#
# WHY THIS EXISTS AND NOT STUDIO'S "INVITE USER"
# ----------------------------------------------
# Studio generates an invitation and mails it. `SMTP_HOST` is `supabase-mail` --
# the dftdb-mail container, an inbucket catch-all that accepts a message and
# forwards nothing. So an invited colleague is never invited. The GoTrue admin
# endpoint is the route that works, and it sets the role in the same call rather
# than the create-then-UPDATE pair the older docs describe.
#
# WHY A SCRIPT AND NOT THE CURL
# -----------------------------
# The raw call needs the service-role key, the right port, `email_confirm` and a
# correctly nested `app_metadata`. Getting `email_confirm` wrong is the quiet
# failure: the account is created, lands unconfirmed, its confirmation mail dies
# in inbucket, and it can never sign in. Nothing tells you -- the account is
# simply there and does not work.
#
# PORTS DIFFER BETWEEN THE STACKS, WHICH IS WHY NOTHING IS HARDCODED
# ------------------------------------------------------------------
# KONG_HTTP_PORT is 8000 on dev and 8001 on the server -- the same class of trap
# as Postgres on 5433 there and 5432 on dev. Both are read from docker/.env, so
# this script is identical on both hosts and correct on both.
#
# RUNNING IT
# ----------
#   scripts/server/create-user.sh someone@uni-freiburg.de
#   scripts/server/create-user.sh someone@uni-freiburg.de curator
#   scripts/server/create-user.sh --list
#   scripts/server/create-user.sh --set-role someone@uni-freiburg.de curator
#
# From a workstation, over ssh:
#   ssh dt.unr.uni-freiburg.de dev/digital-twin-db/scripts/server/create-user.sh you@example.org
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/docker/.env}"

# shared.is_contributor() accepts these three; anything else reads the menu and
# its own job history but cannot request a run. Keep this list in step with that
# function -- a role it does not know is not an error here, it is a silent
# nothing.
VALID_ROLES="admin curator contributor"

log()  { printf '[%s] %s\n' "$(date -u '+%H:%M:%S')" "$*"; }
die()  { log "FATAL: $*"; exit 1; }

usage() {
    sed -n '3,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

[ -r "$ENV_FILE" ] || die "cannot read $ENV_FILE -- run this from the digital-twin-db checkout"

env_val() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'"'"'\r'; }

SERVICE_ROLE_KEY="$(env_val SERVICE_ROLE_KEY)"
KONG_PORT="$(env_val KONG_HTTP_PORT)"
[ -n "$SERVICE_ROLE_KEY" ] || die "SERVICE_ROLE_KEY is not set in $ENV_FILE"
API="${SUPABASE_URL:-http://localhost:${KONG_PORT:-8000}}"

auth() {
    # $1 method, $2 path, $3 optional JSON body
    local method="$1" path="$2" body="${3:-}"
    if [ -n "$body" ]; then
        curl -sS -X "$method" "$API$path" \
            -H "apikey: $SERVICE_ROLE_KEY" \
            -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
            -H "Content-Type: application/json" \
            -d "$body"
    else
        curl -sS -X "$method" "$API$path" \
            -H "apikey: $SERVICE_ROLE_KEY" \
            -H "Authorization: Bearer $SERVICE_ROLE_KEY"
    fi
}

# Reads the whole user list and prints "<id> <email> <role>" per line. GoTrue
# has no filter-by-email on this endpoint, so this is also how an existing
# account is found.
list_users() {
    auth GET "/auth/v1/admin/users?per_page=200" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for u in d.get("users", []):
    print(u["id"], u["email"], (u.get("app_metadata") or {}).get("role") or "-",
          "confirmed" if u.get("email_confirmed_at") else "UNCONFIRMED")
'
}

id_for() { list_users | awk -v e="$1" '$2 == e { print $1 }'; }

case "${1:-}" in
    -h|--help)  usage 0 ;;
    --list)
        log "accounts on $API"
        printf '%s\n' "$(list_users)" | column -t
        exit 0
        ;;
    --set-role)
        EMAIL="${2:-}"; ROLE="${3:-}"
        [ -n "$EMAIL" ] && [ -n "$ROLE" ] || usage 1
        grep -qw "$ROLE" <<<"$VALID_ROLES" || die "role must be one of: $VALID_ROLES"
        UID_="$(id_for "$EMAIL")"
        [ -n "$UID_" ] || die "no account for $EMAIL -- create it first"
        auth PUT "/auth/v1/admin/users/$UID_" \
            "$(printf '{"app_metadata":{"role":"%s"}}' "$ROLE")" >/dev/null
        log "$EMAIL is now $ROLE"
        exit 0
        ;;
    "") usage 1 ;;
esac

EMAIL="$1"
ROLE="${2:-contributor}"
grep -qw "$ROLE" <<<"$VALID_ROLES" || die "role must be one of: $VALID_ROLES"
[[ "$EMAIL" == *@*.* ]] || die "'$EMAIL' does not look like an email address"

if [ -n "$(id_for "$EMAIL")" ]; then
    die "$EMAIL already exists -- use --set-role to change its tier, or --list to see it"
fi

# Generated, not prompted: a password typed at a prompt ends up in shell history
# on some setups, and a chosen one is usually weaker than this. It is printed
# once, below, and there is no way to recover it afterwards -- GoTrue stores a
# hash, and the reset mail would go to inbucket and never arrive.
PASSWORD="${USER_PASSWORD:-$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)}"

# email_confirm:true is the load-bearing part. Without it the account cannot
# sign in and nothing says so.
RESPONSE="$(auth POST "/auth/v1/admin/users" "$(python3 -c '
import json, sys
print(json.dumps({
    "email": sys.argv[1],
    "password": sys.argv[2],
    "email_confirm": True,
    "app_metadata": {"role": sys.argv[3]},
}))' "$EMAIL" "$PASSWORD" "$ROLE")")"

CREATED_ID="$(printf '%s' "$RESPONSE" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("id", ""))
if not d.get("id"):
    print(d.get("msg") or d.get("error_description") or json.dumps(d), file=sys.stderr)
')"
[ -n "$CREATED_ID" ] || die "GoTrue refused the request (message above)"

log "created $EMAIL as $ROLE"
cat <<INFO

  Hand these over, once:

    https://dt.unr.uni-freiburg.de/jobs/
    $EMAIL
    $PASSWORD

  There is no password-change page and no reset mail, so this password is the
  password. Not recoverable -- if it is lost, delete the account and make
  another.
INFO
