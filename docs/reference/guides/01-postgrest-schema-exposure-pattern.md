# PostgREST Schema Exposure Pattern

<!-- SCOPE: Pattern documentation for how schema design drives REST API shape and RLS enforcement in digital-twin-db ONLY. -->
<!-- DO NOT add here: ADR decisions → ADR-001/002/003, API endpoint URLs → docs/project/api_spec.md, schema definitions → docs/project/database_schema.md -->
<!-- NO_CODE_EXAMPLES: Guides document PATTERNS, not implementations.
     FORBIDDEN: Full function implementations, SQL blocks > 5 lines
     ALLOWED: Do/Don't/When tables, column references (1 line), pattern names -->
<!-- DOC_KIND: reference -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when designing new tables, adding RLS policies, or understanding how schema changes affect the REST API. -->
<!-- SKIP_WHEN: Skip when you need specific endpoint URLs — see docs/project/api_spec.md. -->
<!-- PRIMARY_SOURCES: docs/project/api_spec.md, docs/project/database_schema.md, docs/reference/adrs/ -->

## Quick Navigation

- [Reference Hub](../README.md)
- [API Spec](../../project/api_spec.md)
- [Database Schema](../../project/database_schema.md)
- [ADRs](../adrs/)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Captures how PostgREST automatically exposes PostgreSQL schema as REST endpoints and how RLS shapes access. |
| Read When | You need conventions for adding tables, designing RLS policies, or understanding API-schema coupling. |
| Skip When | You only need specific endpoint URLs or historical ADR decisions. |
| Canonical | Yes |
| Next Docs | [API Spec](../../project/api_spec.md), [ADR-002: Auth](../adrs/adr-002-supabase-auth.md), [ADR-001: PostgreSQL](../adrs/adr-001-postgresql-postgis.md) |
| Primary Sources | `docs/project/api_spec.md`, `docs/project/database_schema.md` |

## Principle

PostgREST automatically generates a REST API from the PostgreSQL schema. Every table or view in an exposed schema becomes an endpoint; column names become query filter parameters; column types determine JSON serialization. Schema changes are immediately reflected in the API without code deployment. Source: [PostgREST documentation — Schema Cache](https://docs.postgrest.org/en/stable/references/schema_cache.html), 2026.

## Our Implementation

Digital Forest Twin Database exposes 6 PostgreSQL schemas via PostgREST through Kong (/rest/v1). Each schema maps to a set of REST endpoints. Row-Level Security policies on every table enforce access control at the database layer — the JWT `role` claim (`anon` or `service_role`) selects which RLS policies apply. Schema changes (add/rename column, new table) require a PostgREST schema cache reload (`NOTIFY pgrst, 'reload schema'`) to take effect without restarting the service.

## Patterns

| Do This | Don't Do This | When to Use |
|---------|--------------|-------------|
| Add RLS policy to every new table before exposing it | Create a table without RLS policies — all rows become accessible to anon role | When creating any new table in an exposed schema |
| Use `service_role` JWT for Python import scripts that write data | Use `anon` key for scripts that INSERT/UPDATE — will be blocked by RLS | When running data ingestion scripts |
| Name columns with snake_case to match PostgREST filter syntax (`sensor_id=eq.123`) | Use camelCase column names — causes filter mismatch in API clients | All new table/column definitions |
| Signal schema changes via `NOTIFY pgrst, 'reload schema'` after DDL migrations | Restart the PostgREST container to apply schema changes — causes downtime | After ALTER TABLE, CREATE TABLE in exposed schemas |

## Sources

- [PostgREST — Schema Cache](https://docs.postgrest.org/en/stable/references/schema_cache.html)
- [Supabase — Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- Internal: [API Spec](../../project/api_spec.md), [Database Schema](../../project/database_schema.md)

## Related

**ADRs:** [ADR-001: PostgreSQL+PostGIS](../adrs/adr-001-postgresql-postgis.md), [ADR-002: Supabase Auth](../adrs/adr-002-supabase-auth.md), [ADR-003: Self-Hosted Supabase](../adrs/adr-003-self-hosted-supabase.md)
**Guides:** —

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- PostgREST version upgrade changes schema exposure behavior
- New schema added or RLS policy pattern changes
- API client naming convention changes

**Verification:**
- [ ] Do/Don't/When rows still match current project practice
- [ ] Related links resolve
- [ ] Guidance still references current architecture
