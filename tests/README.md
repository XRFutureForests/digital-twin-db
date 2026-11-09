# Test Documentation

**Last Updated:** 2026-05-12

<!-- SCOPE: Test organization structure (directory layout, Story-Level Test Task Pattern) -->
<!-- DOC_KIND: index -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need the current test layout, execution commands, or links to test policy. -->
<!-- SKIP_WHEN: Skip when you only need the universal testing philosophy. -->
<!-- PRIMARY_SOURCES: tests/, environment.yml -->
<!-- DO NOT add here: Test code -> test files, Story/task tracking -> Linear -->

## Quick Navigation

- [API Spec](../docs/api-spec.md)
- [DB Schema](../docs/database-schema.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Maps the test directories, execution commands, and links to the broader testing policy for digital-twin-db. |
| Read When | You need to find tests, run them, or understand the local test layout for migrations, import scripts, or PostgREST API. |
| Skip When | You only need general testing philosophy (see "Testing Philosophy" below). |
| Canonical | Yes |
| Next Docs | None — task tracking is in Linear, not a markdown doc |
| Primary Sources | `tests/`, `environment.yml` |

---

## Overview

This directory contains all automated and manual tests for the digital-twin-db repository, following the **Story-Level Test Task Pattern**. Automated tests live under `tests/automated/` and are consolidated in the final Story test task. Manual bash scripts for DB state verification live under `tests/manual/`.

---

## Testing Philosophy

**Test your code, not frameworks.** Focus on import script transformation logic, RLS policy boundaries, and migration correctness — not on PostgreSQL constraint enforcement or PostGIS geometry math.

**Risk-based testing:** Automate only Priority `>=15` scenarios (`Business Impact x Probability`). Each test should satisfy the usefulness criteria in the Testing Philosophy section above.

---

## Test Organization

```
tests/
`-- automated/
    |-- e2e/                    # Against the running local stack (database and API)
    |   |-- access/             # Row-level security, dataset access levels, accounts, function privileges
    |   |-- import/             # QSM and GraphML import round-trips
    |   |-- integrity/          # Variant consistency of tree rows
    |   |-- provenance/         # Process Run Crate emitter
    |   `-- sampling/           # Expansion factors and stand estimates
    `-- unit/                   # No database: parsing logic of the import scripts
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
pytest tests/automated/e2e/      # needs `docker compose up -d`
pytest tests/automated/unit/
```

**Run a single test file:**

```bash
pytest tests/automated/e2e/access/test_function_privileges.py -v
```

**Run with coverage:**

```bash
pytest tests/automated/ --cov=scripts --cov-report=term-missing
```

The e2e tests write only inside transactions they roll back, against the local Docker
Compose stack, never the production database.

---

## Maintenance

**Update Triggers:**
- When adding new test directories or test suites
- When changing test execution commands or conda environment
- When modifying Story-Level Test Task Pattern workflow
- When Docker Compose Supabase stack version changes

**Verification:**
- [ ] The tree above matches `tests/automated/`
- [ ] Test execution commands match current conda environment and pytest version
- [ ] Links to API Spec and DB Schema resolve

**Last Updated:** 2026-11-09
