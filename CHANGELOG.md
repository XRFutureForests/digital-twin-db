# Changelog

All notable user-facing changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 2026-09-02 → 2026-09-14 (52 commits, condensed by theme)

**Production on dt.unr.uni-freiburg.de** (`9cf0201`, `5864735`, `f8a4358`, `b105f56`, `7f31fb5`)

- First server deployment (XRFF-238): PGDATA and object storage on the NFS export,
  `STORAGE_PATH`/`PGDATA_PATH` in `.env`, `scripts/server/setup_data_dirs.py` refusing a
  soft NFS mount, a systemd drop-in so Docker waits for the mount. API published at
  `https://dt.unr.uni-freiburg.de/db/` on 443 through the dashboard's nginx.
- Kong reaches GoTrue as `dftdb-auth`, not `auth` — campus DNS resolved the short name to a
  university web host and every `/auth/v1/` call left the server for a week (XRFF-428).
- Four systemd timers replace the "no cron" gap: job runner + reaper (`scripts/runner/`),
  nightly `pg_dump` minus sensor readings (`scripts/server/dt-db-backup.*`), TLS renewal
  (in digital-twin-dashboard). `scripts/server/create-user.sh` creates an account with its
  role claim in one call (`5f9e0e1`).

**Job control plane** (`fdc96e5`, `3839a2d`, `b614ec1`, `1900ac7`, `8c46763`, `2033e99`)

- `request_job()` RPC + `public.job_status` (XRFF-347); `shared.Processes` is a readable
  workflow menu (XRFF-348); a generic runner drains `shared.ProcessingJobs` (XRFF-349);
  the open-data refreshes that need no host path are queueable (XRFF-380); `/jobs/` trigger
  page generated from `param_schema` (XRFF-423); a refused request says why (XRFF-422).
  Edge Functions are not used and never will be (XRFF-257).

**Open-data landing zones and provenance** (`612bc50`, `6a4bf9e`, `aaf35a2`, `6e7bd1f`,
`ac1b4e7`, `3a044bd`, `5f69a3b`, `7aa46e7`)

- `set_location_attributes()` and `upsert_environment()` write RPCs with
  `shared.AttributeProvenance`; a lookup refresh no longer reverts acquired site attributes;
  an unstamped write can no longer claim to be a field measurement (XRFF-400); derived
  values carry provenance and uncertainty by decision (XRFF-401); a Process Run Crate per
  recorded run (XRFF-407); `refresh_soil_aggregates()` derives annual soil means from the
  twin's own sensors; `sensor.Sensors` admits modelled series.

**Unreal Engine feed** (`f695e5a`, `16b10a5`, `6fdbe3a`)

- `ue_sensor_state_at(ts)` for the VR time slider; `ue_environments` and `ue_climate`
  (one row per period merged across datasets); Postgres memory settings tuned for NFS.

**SILVA** (`62d0bd5`, `3b20546`, `ae40dfa`, `e1fa860`)

- `trees.SimulationRuns` records run parameters (XRFF-374); the CSV round-trip and the
  `silva_input` view are gone (XRFF-351); site-condition columns exposed on
  `public.locations`; a scenario is now a point on two axes, management regime × climate
  pathway, with `scenario_code` (2026-09-14).

**Data fixes** (`bc2f46e`, `2e19262`, `bf64fd7`, `dc5b223`)

- ecosense `center_point` was 30.7 km from its own trees (XRFF-388); the 4_56 Zwisel second
  stem is seeded; `security_invoker` on four public views; the importer exits non-zero when
  any record failed.

**Docs and housekeeping** (`1e69342`, `97a1bcc`, `c041ad3`, `cad7c68`, `802fa00`)

- Root docs consolidated to `README.md` + `RUNBOOK.md`; the init-file history explained
  truthfully; workspace `data/` layout adopted; GitHub Actions CI removed (all CI is off
  workspace-wide since 2026-09-01); one meaning per level-of-detail axis (XRFF-404).

### 2026-09-01

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
