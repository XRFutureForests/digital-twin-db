# ADR-003: Infrastructure — Self-Hosted Supabase via Docker Compose

**Date:** 2026-05-11 | **Status:** Accepted | **Category:** infrastructure | **Decision Makers:** XR Future Forests Lab, Uni Freiburg

<!-- SCOPE: Architecture Decision Record for Supabase deployment model selection ONLY. -->
<!-- DOC_KIND: record -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need the rationale for self-hosting Supabase over managed Supabase Cloud. -->
<!-- SKIP_WHEN: Skip when you need Docker setup steps — see docs/project/runbook.md. -->
<!-- PRIMARY_SOURCES: docs/project/infrastructure.md, docs/project/runbook.md, docs/reference/README.md -->

## Quick Navigation

- [Reference Hub](../README.md)
- [Infrastructure](../../project/infrastructure.md)
- [Runbook](../../project/runbook.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Records the decision to run Supabase services self-hosted via Docker Compose rather than using Supabase Cloud. |
| Read When | You need rationale for self-hosting over managed cloud. |
| Skip When | You need operational setup — see docs/project/runbook.md. |
| Canonical | Yes |
| Next Docs | [Infrastructure](../../project/infrastructure.md), [Runbook](../../project/runbook.md) |
| Primary Sources | `docker/docker-compose.yml`, `docker/.env.example` |

---

## Context

The project stores research data that must remain under institutional control (University of Freiburg data governance). The database contains LiDAR scans, sensor readings, and tree measurements from ongoing FoWiTA grant research. Data must not reside on third-party infrastructure without explicit DFG/EU grant compliance review. Local developer workstations need full offline operation for field data processing.

---

## Decision

We self-host all Supabase services (Studio, Kong, GoTrue, PostgREST, Realtime, Storage, Supavisor, PostgreSQL+PostGIS) via Docker Compose on a single developer workstation. No data is sent to Supabase Cloud.

---

## Rationale

1. **Data sovereignty** — Research data (species measurements, sensor telemetry, LiDAR metadata) must stay on university infrastructure per DFG grant requirements. Supabase Cloud would store data on AWS/Vercel infrastructure outside institutional control.
2. **Full offline capability** — Field data processing on laptops with no internet access. Self-hosted Docker Compose starts without network connectivity.
3. **Cost** — Supabase Cloud free tier has row/storage limits that would be exceeded by continuous sensor time-series. Self-hosted has no per-row cost.

---

## Consequences

**Positive:**
- Full data control — no third-party data processing agreement needed
- Offline operation — works on field laptops without internet
- No platform vendor lock-in for data storage
- Full access to PostgreSQL internals (extensions, init scripts, RLS)

**Negative:**
- Operational burden — backups, version upgrades, secret rotation are self-managed
- Supabase version upgrades require manual docker-compose.yml image tag updates
- No managed global CDN for storage (acceptable — no public-facing assets)
- 11+ Docker services consume significant RAM (~3-4 GB); requires capable workstation

---

## Alternatives Considered

| Alternative | Pros | Cons | Why Rejected |
|-------------|------|------|--------------|
| Supabase Cloud (managed) | Zero ops, global CDN, auto-upgrades | Research data on AWS/Vercel; data sovereignty unclear for DFG grants; row/storage limits; requires internet | Data governance requirement eliminates this option |
| Raw PostgreSQL + custom REST | Minimal Docker footprint, full control | Must build auth, REST API, studio manually; loses Supabase tooling ecosystem | Reinventing what Supabase already provides; higher dev cost |

---

## Related Decisions

- ADR-001: PostgreSQL + PostGIS (the backing database for all Supabase services)
- ADR-002: Supabase Auth (GoTrue is part of this deployment)
- ADR-004: Kong API Gateway (part of this Supabase stack)
- See [docs/project/infrastructure.md](../../project/infrastructure.md) for service inventory

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- Supabase version upgrade
- Move to university server deployment
- DFG grant requirements change

**Verification:**
- [ ] Decision still reflects accepted choice
- [ ] Data sovereignty requirement still applies
- [ ] Related ADR links resolve
