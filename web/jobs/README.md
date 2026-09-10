# The job trigger page

One static file, served at **<https://dt.unr.uni-freiburg.de/jobs/>**. Sign in,
pick a workflow, fill in the form, watch it run.

It exists because **Supabase Studio can never call `request_job()`**: Studio
reaches the database through the `meta` service as `supabase_admin`, so
`auth.jwt()` is null in the SQL editor and `is_contributor()` is false however
privileged the person at the keyboard is. Requesting a run needs a caller
carrying a *user* token, and this is the one for people. (Unreal is the one for
headsets — XRFF-352. `curl` is the one for scripts — see
[docs/requesting-a-job.md](../../docs/requesting-a-job.md).)

## Nothing here is SILVA-specific

Each form is generated from that workflow's own `param_schema`, including
`enum`, `minimum`/`maximum` and `multipleOf`, so the form agrees with the
server's validator by construction. **A new connector gets a form the moment it
lands a `workflow_key` and a `param_schema`** — there is nothing to add here.

Fields left blank are not sent, so the tool's own default applies. Prefilled
ones are sent explicitly even when they equal the default: that makes
`job_status.input_data` a complete record of what was asked for, rather than a
record that has to be read against a schema to be understood.

## Files

| | |
|---|---|
| `index.html` | the page — markup, styles and script in one file, no build step, no dependencies |
| `config.example.js` | copy to `config.js` and fill in the anon key; `config.js` is gitignored |
| `smoke.mjs` | headless test of the generated form (below) |

## Deploying it

The page is served by the **dashboard's** nginx, which already terminates TLS on
443 and already proxies the API at `/db/`. `digital-twin-dashboard` mounts this
directory read-only and adds a `location /jobs/`; that repo stays a read-only
viewer, since serving a file is not the Shiny app gaining a write path.

```bash
cd ~/dev/digital-twin-db
cp web/jobs/config.example.js web/jobs/config.js
# put ANON_KEY from docker/.env into it, then recreate nginx:
cd ~/dev/digital-twin-dashboard/docker && docker compose --profile proxy up -d nginx
```

The two repos must be checked out side by side, or `JOBS_UI_PATH` must say where
this one is.

## Testing it

The interesting part of the page is generated rather than written, so reading
the HTML proves nothing. `smoke.mjs` runs the page's own script against a
minimal DOM shim and a fake API and checks what it would actually send:

```bash
docker exec dftdb-db psql -U postgres -d postgres -tAc \
  "select param_schema from shared.processes where workflow_key='silva'" > /tmp/silva.json
node web/jobs/smoke.mjs /tmp/silva.json
```

Seventeen checks: the password grant, the bearer token on the menu read, the
role badge, one control per schema property with required fields first, defaults
prefilled, `min`/`max`/`step` carried across, enums as selects, booleans as
checkboxes, integers sent as integers rather than strings, blank fields omitted,
no key outside the schema, and an idempotency key on the request.
