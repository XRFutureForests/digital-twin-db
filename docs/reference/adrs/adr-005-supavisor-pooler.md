# ADR-005: Connection Pooler — Supavisor

**Date:** 2026-05-11 | **Status:** Accepted | **Category:** pooler | **Decision Makers:** XR Future Forests Lab, Uni Freiburg

<!-- SCOPE: Architecture Decision Record for PostgreSQL connection pooler selection ONLY. -->
<!-- DOC_KIND: record -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need rationale for Supavisor over PgBouncer. -->
<!-- SKIP_WHEN: Skip when you need connection string details — see docs/project/runbook.md. -->
<!-- PRIMARY_SOURCES: docs/project/infrastructure.md, docs/reference/README.md, docker/docker-compose.yml -->

## Quick Navigation

- [Reference Hub](../README.md)
- [Infrastructure](../../project/infrastructure.md)
- [Runbook](../../project/runbook.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Records decision to use Supavisor as connection pooler over PgBouncer. |
| Read When | You need rationale for Supavisor for PostgreSQL connection pooling. |
| Skip When | You need pool connection strings — see docs/project/runbook.md. |
| Canonical | Yes |
| Next Docs | [Infrastructure](../../project/infrastructure.md), [ADR-003: Self-Hosted Supabase](adr-003-self-hosted-supabase.md) |
| Primary Sources | `docker/docker-compose.yml`, `docker/.env.example` (POOLER_* variables) |

---

## Context

PostgreSQL has a hard connection limit (~100 by default). Python import scripts, R dashboard connections, PostgREST, and GoTrue all open connections simultaneously. Without pooling, the connection limit is reached under concurrent load from multiple data ingestion sessions. A pooler must support multi-tenant operation (multiple applications sharing pools) and be configurable via environment variables.

---

## Decision

We use Supavisor (Supabase's Elixir-based connection pooler) in transaction pooling mode on port 6543. `POOLER_DEFAULT_POOL_SIZE=20`, `POOLER_MAX_CLIENT_CONN=100`, `POOLER_TENANT_ID=digital-forest-twin-local`.

---

## Rationale

1. **Supabase official component** — Supavisor replaced PgBouncer in the official Supabase self-hosted stack. Using it keeps the stack synchronized with upstream Supabase Docker Compose releases.
2. **Multi-tenant pooling** — Supavisor supports tenant isolation via `POOLER_TENANT_ID`, enabling future multi-project pooling on shared PostgreSQL without configuration changes.
3. **Env-driven config** — Pool size, max client connections, and tenant ID are all env vars (`POOLER_*`). No separate PgBouncer `.ini` file to manage.

---

## Consequences

**Positive:**
- Connection limit exceeded → rejected → prevents PostgreSQL crash under load
- Transaction pooling allows short-lived Python/R connections to share limited PostgreSQL backends
- Supabase upstream upgrades include Supavisor version bumps — no separate maintenance

**Negative:**
- Supavisor is newer than PgBouncer with less community operational history
- Transaction pooling mode incompatible with PostgreSQL session features (prepared statements, advisory locks) — scripts must use simple queries only
- Port 6543 must be free on host machine

---

## Alternatives Considered

| Alternative | Pros | Cons | Why Rejected |
|-------------|------|------|--------------|
| PgBouncer | Battle-tested, widely documented, session/statement/transaction modes | No native Supabase integration; requires separate .ini config; Supabase officially replaced it with Supavisor | Supabase upstream dropped PgBouncer in favor of Supavisor |
| No pooler (direct port 5432) | Simplest setup | Connection limit hit under concurrent Python/R sessions; no tenant isolation | Insufficient for multi-script concurrent data ingestion |

---

## Related Decisions

- ADR-003: Self-Hosted Supabase (Supavisor is part of this stack)
- ADR-001: PostgreSQL + PostGIS (the pool targets this database)
- See `docker/.env.example` for `POOLER_*` variable documentation

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- Supabase upgrades Supavisor version
- Pool size tuned for production server deployment
- Transaction pooling limitation encountered

**Verification:**
- [ ] Decision still reflects accepted choice
- [ ] docker-compose.yml Supavisor image version matches
- [ ] Related ADR links resolve
