# ADR-001: Database — PostgreSQL 15 + PostGIS 3

**Date:** 2026-05-11 | **Status:** Accepted | **Category:** database | **Decision Makers:** XR Future Forests Lab, Uni Freiburg

<!-- SCOPE: Architecture Decision Record for the database platform selection ONLY. -->
<!-- DOC_KIND: record -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need the rationale for PostgreSQL+PostGIS over other databases. -->
<!-- SKIP_WHEN: Skip when you only need schema details — see docs/project/database_schema.md. -->
<!-- PRIMARY_SOURCES: docs/project/architecture.md, docs/project/tech_stack.md, docs/reference/README.md -->

## Quick Navigation

- [Reference Hub](../README.md)
- [Architecture](../../project/architecture.md)
- [Tech Stack](../../project/tech_stack.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Records the decision to use PostgreSQL 15 + PostGIS 3 as the spatial database platform. |
| Read When | You need rationale for PostgreSQL+PostGIS over MongoDB, MySQL, or SQLite. |
| Skip When | You need schema details — see docs/project/database_schema.md instead. |
| Canonical | Yes |
| Next Docs | [Architecture](../../project/architecture.md), [Database Schema](../../project/database_schema.md) |
| Primary Sources | `docs/project/architecture.md`, `docs/project/database_schema.md` |

---

## Context

The Digital Forest Twin project stores heterogeneous forest research data: tree positions, LiDAR point cloud metadata, sensor time-series, environmental variants, and aerial imagery — all with spatial coordinates (WGS84 and local CRS). The database must support spatial queries (nearest-neighbor, bounding-box, CRS transform), time-series storage, row-level security, and auto-generated REST APIs. A single multi-schema data model spanning 6 domains must remain consistent and auditable.

---

## Decision

We use PostgreSQL 15 with PostGIS 3 extension as the sole relational database. All spatial data uses PostGIS geometry columns. The database is self-hosted via Docker Compose and is also the backing store for Supabase services (auth, REST API, realtime).

---

## Rationale

1. **PostGIS spatial operations** — ST_X, ST_Y, ST_Within, ST_Distance, ST_Transform available as SQL functions; no application-layer coordinate handling needed. No other RDBMS matches PostGIS spatial capability.
2. **Supabase platform dependency** — Supabase Auth (GoTrue), PostgREST, and Realtime all require PostgreSQL as backing store. Choosing PostgreSQL aligns database with platform.
3. **Multi-schema + RLS** — PostgreSQL schemas (6: shared, pointclouds, trees, sensor, environments, imagery) give domain isolation with shared auth. Row-Level Security policies enforced at DB layer without application code.

---

## Consequences

**Positive:**
- PostGIS covers all spatial query needs (tree positions, sensor placement, imagery footprints)
- Schema-per-domain isolation without separate databases
- RLS policies enforce access control at the database layer
- JSONB columns for flexible ExternalMetadata (Aquarius API payloads)

**Negative:**
- PostgreSQL requires more operational care than managed cloud databases (backup, WAL, upgrade path)
- PostGIS extension must be installed and version-pinned separately
- Supabase self-hosted Docker image pins PostgreSQL version — upgrade path tied to Supabase releases

---

## Alternatives Considered

| Alternative | Pros | Cons | Why Rejected |
|-------------|------|------|--------------|
| MongoDB | Flexible schema, good time-series support | No true spatial SQL; no native multi-schema isolation; no Supabase platform support | Supabase requires PostgreSQL; spatial queries need PostGIS |
| MySQL 8 + spatial | Widely deployed, familiar | Spatial support weaker than PostGIS; no Supabase platform; no schema-per-domain partitioning | Spatial capability inferior; breaks Supabase dependency |

---

## Related Decisions

- ADR-003: Self-Hosted Supabase (platform wraps this database)
- See [docs/project/database_schema.md](../../project/database_schema.md) for schema details

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- PostgreSQL major version upgrade
- PostGIS version change
- Alternative evaluated

**Verification:**
- [ ] Decision still reflects accepted choice
- [ ] docker-compose.yml DB image version matches this ADR
- [ ] Related ADR links resolve
