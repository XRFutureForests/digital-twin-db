# The portal

Static pages served at **<https://dt.unr.uni-freiburg.de/portal/>** — the site's front door
(`/` redirects here). One place for every level of experience with the database:

| Page | For | What it does |
|---|---|---|
| `/portal/` | everyone | landing page: which door fits what you want to do, and how to get access |
| `/portal/data/` | read: anyone; write: `contributor`+ | browse any public table or view, filter, download CSV; add rows by form or pasted CSV; correct a row |
| `/portal/account/` | everyone with an account; team tools for `curator`+ | sign in, change your own password; curators create accounts, grant/revoke `contributor`, reset passwords |
| `/portal/docs/` | everyone | data model in five sentences, schema map, per-schema tables with live row counts, links to the reference docs and the repositories |
| `/portal/api/` | developers | developer guide: connection, sign-in, read and write recipes (curl/Python/R), running a model (SILVA modes, live parameter table), ground rules, live endpoint list |

The job page (`web/jobs/`, `/jobs/`) is part of the same site and shares the sign-in: both
keep the session under the same `sessionStorage` key.

## Nothing here knows the schema

The data page builds its table list, columns, forms, foreign-key dropdowns and CSV checks
from PostgREST's OpenAPI description of `/rest/v1/`. A migration that adds a view or a
column changes the page with it; there is nothing to edit here per table.

Permissions are not decided here either. Every call carries the signed-in user's own token
and RLS decides. Account management goes through `public.create_account` /
`set_account_role` / `reset_account_password` / `list_accounts` (migration
`20261030100000`), which check the caller's role claim themselves; the service-role key never
reaches a browser.

## Files

| | |
|---|---|
| `index.html` | landing page |
| `data/index.html` | browse / add / correct / CSV |
| `account/index.html` | sign-in, own password, team accounts |
| `docs/index.html` | data model, schema map, docs and repository links |
| `api/index.html` | developer guide |
| `lib.js` | config, session (with token refresh), API calls, top bar |
| `portal.css` | shared look, same palette as `web/jobs/` |
| `config.example.js` | copy to `config.js` and fill in; `config.js` is gitignored |

No build step and no dependencies, for the same reason as the job page: nginx serves the
files as they are.

## Deploying it

Served by the **dashboard's** nginx, which mounts this directory read-only at
`/usr/share/nginx/portal` (`PORTAL_UI_PATH` overrides the side-by-side checkout assumption)
and adds `location /portal/`.

```bash
cd ~/dev/digital-twin-db && git pull
cp web/portal/config.example.js web/portal/config.js
# put ANON_KEY from docker/.env and a contact address into it
cd ~/dev/digital-twin-dashboard && git pull
cd docker && docker compose --profile proxy up -d --force-recreate nginx
docker exec dtdash-nginx grep -c 'location /portal/' /etc/nginx/nginx.conf   # expect 2
```

`--force-recreate` because `nginx.conf` is a single-file bind mount: a reload keeps the old
file.

## Testing it locally

Serve `web/` and point a local `config.js` at the dev stack (Kong allows any origin):

```bash
printf 'window.DFTDB = { apiBase: "http://localhost:8000", anonKey: "%s" };\n' \
  "$(grep ^ANON_KEY= docker/.env | cut -d= -f2-)" > web/portal/config.js
cd web && python -m http.server 5500
# open http://localhost:5500/portal/
```

The database side of account management has its own tests:
`pytest tests/automated/e2e/access`.
