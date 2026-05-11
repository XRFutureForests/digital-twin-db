# Development Principles

<!-- SCOPE: Project development principles and tradeoffs ONLY. Contains reusable principles, decision order, anti-patterns, and verification guidance. -->
<!-- DOC_KIND: explanation -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when making implementation or documentation decisions and you need the governing principles. -->
<!-- SKIP_WHEN: Skip when you only need routing or exact factual lookup. -->
<!-- PRIMARY_SOURCES: docs/principles.md, docs/documentation_standards.md -->

## Quick Navigation

| Need | Read |
|------|------|
| Documentation rules | [documentation_standards.md](documentation_standards.md) |
| Documentation map | [README.md](README.md) |
| Architecture | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Canonical project entry | [../AGENTS.md](../AGENTS.md) |

## Agent Entry

- Purpose: Explain the project's governing principles and decision hierarchy.
- Read when: You need to choose between alternatives or justify a tradeoff.
- Skip when: You only need a direct factual lookup.
- Canonical: Yes.
- Read next: The relevant project or reference doc for the concrete domain.
- Primary sources: `docs/principles.md`, `docs/documentation_standards.md`.

## Core Principles

| # | Principle | Application |
|---|-----------|-------------|
| 1 | Standards First | PostgreSQL/PostGIS conventions and Supabase API contracts override convenience shortcuts |
| 2 | YAGNI | Build only what the current research pipeline requires — no speculative schemas or endpoints |
| 3 | KISS | Prefer the simplest correct schema migration or query over a clever solution |
| 4 | DRY | One canonical definition per schema object; link outward from docs instead of duplicating |
| 5 | Data Integrity First | Constraints, foreign keys, and PostGIS validity checks are required, not optional |
| 6 | Security by Design | Row-level security, JWT scoping, and secret separation are non-negotiable design concerns |
| 7 | Reproducible Environments | `docker compose up -d` must produce a fully working environment from scratch every time |
| 8 | Documentation-as-Code | Schema changes require matching docs updates in the same changeset |
| 9 | No Legacy Accumulation | Remove deprecated tables, views, and compatibility layers promptly after migration |

## Decision Framework

When choosing between alternatives, evaluate in this order:

1. Security — does this introduce credential exposure or permission bypass risk?
2. Data integrity — does this preserve constraint and referential integrity?
3. Standards compliance — does this follow PostgreSQL, PostGIS, and Supabase conventions?
4. Correctness — does this produce accurate results for forest research data?
5. Simplicity — is there a simpler approach that meets the same requirements?
6. Necessity — is this feature needed now, or is it speculative?
7. Maintainability — will the next contributor understand this without explanation?
8. Performance — only optimize after correctness is verified and a bottleneck is measured.

## Anti-Patterns

| Anti-Pattern | Why It Is Harmful |
|--------------|-------------------|
| Hardcoded credentials or JWT secrets in scripts | Security breach risk; use env vars from `docker/.env` |
| Schema changes without migration scripts | Breaks reproducibility; makes resets unreliable |
| Bypassing row-level security with service role for routine queries | Undermines the permission model |
| Embedding raw SQL in documentation | Creates drift as schema evolves; link to source instead |
| God schemas with no domain separation | Defeats the 6-schema separation (shared, pointclouds, trees, sensor, environments, imagery) |
| Skipping PostGIS validity checks on geometry imports | Silent data corruption in spatial queries |
| Accumulating commented-out migration code | Adds noise and confusion; remove after applying |

## Database-Specific Principles

| Principle | Guidance |
|-----------|----------|
| Schema ownership | Each of the 6 custom schemas owns its domain — cross-schema queries are explicit, not implicit |
| Spatial data | Always validate geometry with `ST_IsValid` before insert; store in EPSG:4326 unless a specific CRS is required |
| Timestamps | Use `timestamptz` (not `timestamp`) for all temporal columns |
| Naming | `snake_case` for all schema objects; plural table names; singular column names |
| Migrations | Idempotent scripts only; test with `reset_database.py` before committing |

## Verification Checklist

- [ ] Security implications checked (secrets, RLS, JWT scope)
- [ ] Data integrity constraints in place (FK, NOT NULL, CHECK, PostGIS validity)
- [ ] Standards compliance verified (PostgreSQL, PostGIS, Supabase conventions)
- [ ] Unnecessary complexity avoided
- [ ] Documentation updated with code changes
- [ ] Migration script tested via `python scripts/admin/reset_database.py`

## Maintenance

**Update Triggers:**
- When project principles change based on research pipeline evolution
- When new recurring anti-patterns are identified in code review
- When tradeoff priorities shift (e.g., new security requirements)

**Verification:**
- [ ] Principles still reflect the current research pipeline needs
- [ ] Decision order still matches team expectations
- [ ] Anti-pattern list reflects actual issues encountered

**Last Updated:** 2026-05-11
