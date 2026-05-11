# Archive: Superseded Documentation

**Archived:** 2026-05-11
**Archived by:** documentation pipeline (ln-100)

## Files

| File | Superseded by | Reason |
|------|--------------|--------|
| `ARCHITECTURE.md` | `docs/project/architecture.md` | arc42 arch doc; schema detail now in database_schema.md (SQL-sourced) |
| `database-schema.md` | `docs/project/database_schema.md` | New doc sourced directly from docker/volumes/db/init SQL files; more complete |
| `api-quick-reference.md` | `docs/project/api_spec.md` | PostgREST API spec replaces quick-reference cheatsheet |

## Not Archived

`deployment-guide.md` — retained because it contains production deployment section (Linux server, SSL, S3 bucket) not covered in `docs/project/runbook.md`. Runbook explicitly links to it.

## Rollback

Copy any file from this directory back to `d:\Git\digital-twin-db\docs\` to restore.
