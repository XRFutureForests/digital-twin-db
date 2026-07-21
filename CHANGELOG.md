# Changelog

All notable user-facing changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.0] - 2025

Initial release: Supabase-based PostgreSQL + PostGIS digital twin database
with schemas for trees, sensors, pointclouds, imagery, and environments.
