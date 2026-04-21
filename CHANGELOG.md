# Changelog

All notable user-facing changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.0] - 2025

Initial release: Supabase-based PostgreSQL + PostGIS digital twin database
with schemas for trees, sensors, pointclouds, imagery, and environments.
