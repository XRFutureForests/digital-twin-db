# Patterns Catalog

Architectural patterns with 4-score evaluation.

> **SCOPE:** Pattern inventory for Digital Forest Twin Database — schema exposure, lineage, and access control patterns. Updated by ln-640 Pattern Evolution Auditor.
> **Last Audit:** 2026-05-11
<!-- DOC_KIND: reference -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need the current inventory of architectural patterns and their audit status. -->
<!-- SKIP_WHEN: Skip when you only need one specific ADR or implementation guide. -->
<!-- PRIMARY_SOURCES: docs/reference/adrs/, docs/project/architecture.md, docker/docker-compose.yml -->

## Quick Navigation

- [Architecture](../project/architecture.md)
- [ADRs](../reference/adrs/)
- [Guides](../reference/guides/)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Tracks active architectural patterns, links to supporting docs, and records audit posture for digital-twin-db. |
| Read When | You need pattern inventory, trend, or audit status. |
| Skip When | You already know the exact ADR or guide to inspect. |
| Canonical | Yes |
| Next Docs | [Architecture](../project/architecture.md), [ADRs](../reference/adrs/), [Guides](../reference/guides/) |
| Primary Sources | `docs/reference/adrs/`, `docs/project/architecture.md` |

---

## Score Legend

| Score | Measures | Threshold |
|-------|----------|-----------| 
| **Compliance** | Industry standards, naming, schema conventions, layer boundaries | 70% |
| **Completeness** | All components, error handling, observability, RLS coverage | 70% |
| **Quality** | Readability, maintainability, no duplication, clean naming | 70% |
| **Implementation** | Code/schema exists, production use, monitored | 70% |

---

## Pattern Inventory

<!-- Auto-detected by ln-112, audit with ln-640 -->

| # | Pattern | ADR | Guide | Compl | Complt | Qual | Impl | Avg | Notes |
|---|---------|-----|-------|-------|--------|------|------|-----|-------|
| 1 | Schema-per-Domain | — | — | —% | —% | —% | —% | **—%** | 6 PostgreSQL schemas isolate domain tables |
| 2 | Variant Lineage | — | — | —% | —% | —% | —% | **—%** | scan_variants, tree variants track temporal processing lineage |
| 3 | PostgREST Schema Exposure | — | — | —% | —% | —% | —% | **—%** | REST API auto-generated from schema; no hand-written routes |
| 4 | Row-Level Security (RLS) | — | — | —% | —% | —% | —% | **—%** | Supabase Auth enforces per-row access control on all tables |
| 5 | Audit Trail | — | — | —% | —% | —% | —% | **—%** | AuditLog tables in shared schema; field-level change tracking with IP |
| 6 | External Reference Integration | — | — | —% | —% | —% | —% | **—%** | ExternalID/ExternalMetadata columns link to Aquarius API time-series |

---

## Discovered Patterns (Adaptive)

Patterns found via heuristic discovery (ln-112 auto-scan, 2026-05-11).

| # | Pattern | Confidence | Evidence | Compl | Complt | Qual | Impl | Avg |
|---|---------|------------|----------|-------|--------|------|------|-----|
| 1 | Connection Pooling | HIGH | Supavisor service in docker-compose.yml; POOLER_* env vars | —% | —% | —% | —% | **—%** |
| 2 | API Gateway Routing | HIGH | Kong service; kong.yml route config; /rest/v1, /auth/v1, /storage/v1 prefixes | —% | —% | —% | —% | **—%** |
| 3 | Script-Based ETL | MEDIUM | scripts/import/sync_aquarius.py, import_sensor_data.py | —% | —% | —% | —% | **—%** |

---

## Layer Boundary Status

Audit results from ln-642-layer-ownership-boundary-auditor (not yet run).

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Layer Violations | — | 0 | not audited |
| API Route Centralization | — | 100% (PostgREST) | not audited |
| RLS Coverage | — | 100% | not audited |

---

## API Contract Status

Audit results from ln-643-api-contract-auditor (not yet run).

| Check | Status | Details |
|-------|--------|---------|
| Schema leakage to REST | not audited | PostgREST exposes schema directly — intentional |
| Error format consistency | not audited | — |
| Auth header enforcement | not audited | — |

---

## Excluded Patterns

Patterns detected by keyword but excluded after verification.

| # | Pattern | Keywords Found | Exclusion Reason |
|---|---------|---------------|-----------------|
| 1 | Message Queue | none | No queue/worker/job code in scripts/; Supabase Realtime is pub/sub but not a queue |
| 2 | Caching | none | No Redis/Memcached; Supavisor is connection pool only |
| 3 | Circuit Breaker | none | No retry/circuit-breaker code detected; scripts use simple subprocess calls |

---

## Summary

**Architecture Health Score:** Not yet audited (run ln-640)

| Status | Count | Patterns |
|--------|-------|----------|
| Detected, not scored | 9 | Schema-per-Domain, Variant Lineage, PostgREST Exposure, RLS, Audit Trail, External Ref Integration, Connection Pooling, API Gateway Routing, Script ETL |
| Excluded | 3 | Message Queue, Caching, Circuit Breaker |

---

## Maintenance

**Updated by:** ln-640-pattern-evolution-auditor
**Layer audit by:** ln-642-layer-ownership-boundary-auditor
**Last Updated:** 2026-05-11

**Update Triggers:**
- New pattern implemented
- Schema or service architecture changes
- ADR/Guide created or updated
- RLS policy changes

**Verification:**
- [ ] Pattern rows match current docker-compose.yml services and schema
- [ ] ADR and Guide links resolve (populate when ADRs created)
- [ ] Audit fields reflect latest review state

**Next Audit:** 2026-06-11 (30 days)
