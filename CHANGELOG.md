# Changelog

All notable user-facing changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **All 40 sensors typed `barometric_pressure` were stem water potential
  probes.** Their serials are `*_StemWaterPotential`, their units `bar` and
  `MPa`, and their values run -31.19 to 0.67 -- against a type whose typical
  range is 900-1100 hPa. Not one measured atmospheric pressure. The cause was
  aquarius-connector mapping on the Aquarius `Parameter` field alone, which
  reports these as "BarPressure" because they are read through a pressure
  transducer, while the Label and Unit carry the real quantity. Migration
  `20260901140000_add_stem_water_potential` adds the missing `stem_water_potential`
  lookup row and reclassifies the 40 sensors; the connector now disambiguates on
  the series label so a re-sync will not reintroduce it. 22 of the 40 are logged
  in bar and 18 are `_in_MPa` duplicates of the same series -- both kept, since
  they are distinct Aquarius series and `sensor.Sensors.unit` tells them apart.
- `trees.GrowthSimulations.biomass_kg` and `carbon_content_kg` were NULL on all
  8,900 rows. `fill_missing_biomass.py` only ever targeted `trees.Trees`, so the
  mirrored `simulated_growth` variants there were filled while the trajectory
  table itself was not. It now runs a second pass over
  `trees.GrowthSimulations`, computing from that table's own `dbh_cm` and
  `height_m` with the same equations and fitted-range rules rather than copying
  across -- which keeps the two consistent (verified: 8,868 of 8,868 agree
  exactly) and still works for a `run_simulation.R --no-promote` run, where the
  trajectory exists with no `trees.Trees` rows to copy from.

### Added

- `stem_water_potential` in `data/lookups/sensor_types.csv` (MPa, -10 to 1;
  water potential is negative under xylem tension). 15 sensor types now.

### Notes

Two things audited and found **not** to be defects, recorded so they are not
"fixed" later by mistake:

- Three EcoSense `(plot, tree_number)` pairs -- 4/46, 4/50 and 11/4 -- carry two
  distinct trees each, not duplicated imports. Plot 4/50 holds a 10.5 m and a
  26.2 m Silver Fir about 15 m apart. The field *label* collides; both trees are
  real and neither should be deleted. Resolution belongs in the field records.
- The EcoSense import is complete: `ecosense_trees_import.csv` holds exactly
  1,495 data rows and 1,495 trees are in the database. The apparent 1,527 came
  from counting the file's comment header lines. The "1,504" figure circulating
  in older notes is wrong.

Still open, deliberately not guessed at: `age_years` is NULL on 328 measured
trees (Silver fir, Douglas fir, larch and scattered broadleaves) and
`biomass_kg` on 8, because pylometree carries no published equation for those
species. See `scripts/import/fill_missing_ages.py` for why substituting a
congener's equation is refused.


## [1.0.1] - 2026-07-27

### Changed

- Consolidated `get_db_connection()` — duplicated across five scripts and
  drifted — into `scripts/utils/db.py`. Three copies hardcoded
  `POSTGRES_HOST = "localhost"`, silently ignoring the documented
  configurable variable; two others resolved `docker/.env` relative to
  `scripts/` instead of the repo root and never loaded credentials
  (`test_import_upload.py` exited at startup on "Environment file not
  found").
- Rebuilt `trees_import_template.csv` to the 24 columns `TEMPLATE_COLUMNS`
  actually declares (it shipped 23 and omitted `LocationName`, the
  importer's preferred resolution path, with two misaligned example rows).
  `ScenarioName` moved to `EXTRA_COLUMNS` since scenario assignment belongs
  to the seed scripts.
- Corrected "6 schemas" to 7 (`forest_floor` was added by a migration but
  never counted) in `AGENTS.md`, `README.md`, and `docs/README.md`, and
  added `forest_floor` to the pg_dump re-snapshot scope.
- README's Zenodo DOI badge switched to a static shields.io badge — the
  dynamic badge endpoint was intermittently failing GitHub's image proxy.
- CI: dropped the pip cache step from the lint job (this repo has no
  `requirements.txt`/`pyproject.toml` for it to key on; dependencies live in
  `environment.yml`).

### Removed

- Dead code: `scripts/import/archive/` (456 lines, superseded by
  `import_trees.py`) and `docker/volumes/functions/_shared/{database,retry}.ts`
  (197 lines, imported by nothing).

### Security

- **Git history rewritten (2026-07-21).** `docker/.env.backup` — tracked in
  git with real generated secrets (Postgres password, JWT signing secret,
  dashboard password, vault/crypto keys, Logflare tokens, and the Aquarius
  API credential) — has been removed from every commit, and every leaked
  secret literal has been redacted from all history, including old versions
  of `docker/.env.example` and a since-deleted `TESTING_GUIDE.md`. All
  commit hashes changed as a result.
  **If you already cloned or forked this repo, discard your local copy and
  re-clone** — pulling or merging will reintroduce the purged secrets into
  your local history.
  The Aquarius credential could not be rotated (shared university system);
  treat it as potentially exposed regardless of the history purge.
- `.gitignore` (root and `docker/`) now ignores all `.env.*` variants except
  `.env.example`, closing the gap that let `.env.backup` get committed.

### Added

- `.editorconfig` for cross-editor consistency.
- `CONTRIBUTING.md` with contribution workflow.
- `CHANGELOG.md` (this file).

### Changed

- Sanitized `docker/.env.example`: placeholder values replace previously
  committed real-looking secrets. Operators must rotate any secrets that were
  ever deployed from the old file.
- Python version requirement from `3.11.8` to `3.12`.
- `environment.yml`: Python version from `3.11.8` to `3.12`.
- `CITATION.cff`, README's citation block, and `CONTRIBUTING.md`'s issue
  tracker link now point to the public GitHub repository instead of the
  internal GitLab instance.

### Fixed

- Five broken documentation links (`docs/runbook.md`, `docs/troubleshooting.md`,
  `docs/docker/README.md`, `data/reference/README.md`) now resolve; the
  runbook's port-mapping appendix links to a real table instead of a
  never-written `infrastructure.md`.
- Removed `HANDOVER.md`, a stale internal session note whose proposed
  follow-up work (XRFF-253 through XRFF-257) is filed and completed in Linear.

## [1.0.0] - 2026-07-23

## [0.1.0] - 2025

Initial release: Supabase-based PostgreSQL + PostGIS digital twin database
with schemas for trees, sensors, pointclouds, imagery, and environments.
