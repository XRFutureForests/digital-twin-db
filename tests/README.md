# Test Documentation

**Last Updated:** 2026-05-12

<!-- SCOPE: Test organization structure (directory layout, Story-Level Test Task Pattern) -->
<!-- DOC_KIND: index -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need the current test layout, execution commands, or links to test policy. -->
<!-- SKIP_WHEN: Skip when you only need the universal testing philosophy. -->
<!-- PRIMARY_SOURCES: tests/, environment.yml, docs/reference/guides/testing-strategy.md -->
<!-- DO NOT add here: Test code -> test files, Story implementation -> docs/tasks/kanban_board.md, Test strategy -> docs/reference/guides/testing-strategy.md -->

## Quick Navigation

- [Testing Strategy](../docs/reference/guides/testing-strategy.md)
- [Task Rules](../docs/tasks/README.md)
- [Kanban Board](../docs/tasks/kanban_board.md)
- [API Spec](../docs/project/api_spec.md)
- [DB Schema](../docs/project/database_schema.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Maps the test directories, execution commands, and links to the broader testing policy for digital-twin-db. |
| Read When | You need to find tests, run them, or understand the local test layout for migrations, import scripts, or PostgREST API. |
| Skip When | You only need general testing philosophy (see testing-strategy.md). |
| Canonical | Yes |
| Next Docs | [Testing Strategy](../docs/reference/guides/testing-strategy.md), [Task Rules](../docs/tasks/README.md) |
| Primary Sources | `tests/`, `environment.yml`, `docs/reference/guides/testing-strategy.md` |

---

## Overview

This directory contains all automated and manual tests for the digital-twin-db repository, following the **Story-Level Test Task Pattern**. Automated tests live under `tests/automated/` and are consolidated in the final Story test task. Manual bash scripts for DB state verification live under `tests/manual/`.

---

## Testing Philosophy

**Test your code, not frameworks.** Focus on import script transformation logic, RLS policy boundaries, and migration correctness — not on PostgreSQL constraint enforcement or PostGIS geometry math.

**Risk-based testing:** Automate only Priority `>=15` scenarios (`Business Impact x Probability`). Each test should satisfy the usefulness criteria in [testing-strategy.md](../docs/reference/guides/testing-strategy.md).

---

## Test Organization

```
tests/
|-- automated/
|   |-- e2e/                    # End-to-End import pipeline and API path tests (Priority >=15)
|   |   |-- import/             # Full import script → DB → PostgREST round-trips
|   |   `-- api/                # PostgREST endpoint response validation
|   |-- integration/            # Migration correctness, RLS enforcement, schema checks
|   |   |-- migrations/         # Schema migration SQL verification
|   |   |-- rls/                # Row-Level Security policy tests
|   |   `-- schema/             # PostgREST schema exposure checks
|   `-- unit/                   # Complex Python transformation and parsing logic only
|       |-- import/             # Data transformation functions in import scripts
|       `-- utils/              # Coordinate reprojection, species validation, sensor parsing
`-- manual/                     # Manual test scripts (bash)
    |-- config.sh               # Shared DB connection and environment configuration
    |-- README.md               # Manual test documentation
    |-- test-all.sh             # Run all manual test suites
    |-- results/                # Test outputs (in .gitignore)
    `-- NN-feature/             # Test suites by Story
        |-- samples/            # Input files (CSV, JSON, LAS)
        |-- expected/           # Expected DB state or query outputs (REQUIRED)
        `-- test-*.sh           # Test scripts using psql / curl against Supabase
```

**Naming conventions:**
- Automated (pytest): `test_*.py`
- Manual (bash): `test-*.sh`

---

## Story-Level Test Task Pattern

**Rule:** All E2E, integration, and unit tests for a Story are written in the **final Story test task** created after manual testing.

**Workflow:**
1. Implementation tasks complete.
2. Manual testing runs (`tests/manual/NN-feature/`) and bugs are fixed.
3. Test planner creates the final Story test task.
4. Test executor adds automated tests under `tests/automated/`.
5. Story is done only after tests pass.

---

## Running Tests

**Test framework:** pytest (Python 3.12, conda env `digital-twin`)

**Activate environment first:**

```bash
conda activate digital-twin
```

**Run all automated tests:**

```bash
pytest tests/automated/
```

**Run a specific test level:**

```bash
pytest tests/automated/e2e/
pytest tests/automated/integration/
pytest tests/automated/unit/
```

**Run a single test file:**

```bash
pytest tests/automated/unit/import/test_transform.py -v
```

**Run with coverage:**

```bash
pytest tests/automated/ --cov=scripts --cov-report=term-missing
```

**Run manual DB verification scripts:**

```bash
# Configure DB connection
cp tests/manual/config.sh.example tests/manual/config.sh
# Edit config.sh with your local Supabase credentials

# Run all manual tests
bash tests/manual/test-all.sh

# Run a specific Story's manual tests
bash tests/manual/01-tree-import/test-import-trees.sh
```

**Note:** Manual scripts target the local Docker Compose Supabase stack, never the production database.

---

## Maintenance

**Update Triggers:**
- When adding new test directories or test suites
- When changing test execution commands or conda environment
- When modifying Story-Level Test Task Pattern workflow
- When Docker Compose Supabase stack version changes

**Verification:**
- [ ] All test directories exist (`automated/e2e/`, `automated/integration/`, `automated/unit/`, `manual/`)
- [ ] `tests/manual/results/` is in `.gitignore`
- [ ] Test execution commands match current conda environment and pytest version
- [ ] Links to testing strategy and task workflow resolve

**Last Updated:** 2026-05-12
