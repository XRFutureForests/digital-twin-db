# Testing Strategy

Universal testing philosophy and strategy for digital-twin-db: PostgreSQL/PostGIS database infrastructure, PostgREST API, and Python import scripts.

<!-- SCOPE: Universal testing philosophy (Risk-Based Testing, test pyramid, isolation patterns) -->
<!-- DOC_KIND: how-to -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need testing philosophy, prioritization rules, or isolation guidance. -->
<!-- SKIP_WHEN: Skip when you only need current test inventory or project-specific execution commands. -->
<!-- PRIMARY_SOURCES: tests/README.md, docs/tasks/README.md, docs/project/architecture.md -->
<!-- DO NOT add here: project structure, framework-specific patterns, CI/CD configuration, test tooling setup -->

## Quick Navigation

- **Tests Organization:** [tests/README.md](../../../tests/README.md) — Directory structure, Story-Level Pattern, running tests
- **Task Rules:** [docs/tasks/README.md](../../tasks/README.md) — Workflow rules for Story-Level test tasks
- **API Spec:** [docs/project/api_spec.md](../../project/api_spec.md) — PostgREST endpoint reference
- **DB Schema:** [docs/project/database_schema.md](../../project/database_schema.md) — Schema definitions

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Defines the testing philosophy, prioritization thresholds, and isolation expectations for this database-infrastructure repo. |
| Read When | You need risk-based testing rules or guidance on what to automate for migrations, API, or import scripts. |
| Skip When | You only need current test commands or directory map (see tests/README.md). |
| Canonical | Yes |
| Next Docs | [tests/README.md](../../../tests/README.md), [docs/tasks/README.md](../../tasks/README.md) |
| Primary Sources | `tests/README.md`, `docs/project/database_schema.md`, `docs/project/api_spec.md` |

---

## Testing Philosophy

### Test Your Code, Not Frameworks

Focus testing effort on business logic and integration usage — not on database engine internals, PostGIS geometry math, or Supabase platform behavior.

**Rule of thumb:** If deleting your code would not fail the test, you are testing someone else's code.

**Database-specific examples to avoid:**
- Testing that PostgreSQL enforces a `NOT NULL` constraint you declared
- Testing that PostGIS correctly computes a bounding box
- Testing that Supabase Auth issues a JWT token

### Risk-Based Testing

Automate only high-value scenarios using **Business Impact (1-5) x Probability (1-5)**.

| Priority Score | Action | Example Scenarios |
|----------------|--------|-------------------|
| **>=15** | Must test | Schema migrations altering live data, import script data transformations, PostgREST RLS policy enforcement |
| **10-14** | Consider testing | Edge cases in geometry parsing, partial import recovery |
| **<10** | Usually skip automation | Lookup table content, read-only query helpers |

### Test Usefulness Criteria

Before keeping a test, validate:

| Check | Question |
|-------|----------|
| Risk Priority | Does it cover a >=15 scenario or a justified exception? |
| Confidence ROI | Will failure teach us something important about data integrity or correctness? |
| Behavioral Value | Does it validate our import/transformation logic, not the library's serialization? |
| Predictive Value | Would failure warn us about a real regression in schema or data pipeline? |
| Specificity | If it fails, is the cause obvious enough to fix quickly? |

---

## Test Levels

### End-to-End

Use for full import-to-database workflows and critical data pipeline paths. In this repo, E2E means: raw input file → Python import script → Supabase DB → PostgREST API response.

### Integration

Use for cross-component interaction when E2E would be too slow or too broad. Examples: verifying that a migration script leaves the schema in a consistent state, or that PostgREST exposes the correct columns after a schema change.

### Unit

Use for dense transformation logic and branch-heavy code that cannot be covered efficiently at higher levels. Examples: coordinate reprojection logic, species name validation, sensor data parsing functions.

### Recommended Balance

- Prefer fewer, higher-value tests over many shallow tests.
- Keep E2E focused on the critical import → query path.
- Use integration tests to cover migration correctness and RLS boundaries.
- Use unit tests only when the Python business logic justifies them (Priority >=15).

---

## Test Organization

- `tests/automated/e2e/` — end-to-end import pipeline and API path tests
- `tests/automated/integration/` — migration correctness, RLS enforcement, schema checks
- `tests/automated/unit/` — complex Python transformation and parsing logic
- `tests/manual/` — bash scripts for DB state verification against a live Supabase instance

Use `test_*.py` naming convention (pytest default). Manual scripts use `test-*.sh`.

---

## Isolation Patterns

- Each automated test creates its own data (e.g., test schema or transaction rollback).
- Use transaction rollback as the default isolation strategy for DB tests: begin → test → rollback.
- Do not rely on a specific row count or ID sequence across test runs.
- Manual bash scripts target a dedicated test Supabase project — never the production DB.
- No real Supabase Cloud calls in automated tests; use a local Docker Compose stack or mock the client.

---

## What to Test vs Skip

| Test This | Usually Skip This |
|-----------|-------------------|
| Import script data transformation logic | PostgreSQL constraint enforcement (NOT NULL, FK) |
| PostgREST RLS policy boundaries (own data vs. other users) | Supabase Auth JWT issuance |
| Migration SQL correctness (column additions, type changes) | PostGIS geometry math correctness |
| Species name validation logic in `validate_species_gbif.py` | Third-party GBIF API internals |
| Coordinate reprojection in import scripts | SQLAlchemy ORM internal behavior |

---

## Maintenance

**Update Triggers:**
- New testing patterns discovered
- Supabase/PostgREST version changes affecting test isolation
- Significant changes to the import pipeline architecture
- New isolation issues identified with Docker Compose stack

**Verification:**
- [ ] Philosophy still matches risk-based testing guidance
- [ ] Thresholds and examples still reflect current project standards
- [ ] Linked docs resolve (tests/README.md, api_spec.md, database_schema.md)

**Last Updated:** 2026-05-12
