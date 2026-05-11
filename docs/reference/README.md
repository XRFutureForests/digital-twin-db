# Reference Documentation

**Version:** 1.0.0
**Last Updated:** 2026-05-11

<!-- SCOPE: Reference documentation hub (ADRs, Guides, Manuals) with links to subdirectories -->
<!-- DO NOT add here: ADR/Guide/Manual content → specific files, Project details → project/README.md -->
<!-- DOC_KIND: index -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need to route to ADRs, guides, manuals, or research notes. -->
<!-- SKIP_WHEN: Skip when you already know the exact reference document to open. -->
<!-- PRIMARY_SOURCES: docs/reference/, docs/project/architecture.md, docs/project/tech_stack.md -->

## Quick Navigation

- [Docs Hub](../README.md)
- [ADRs](adrs/)
- [Guides](guides/)
- [Manuals](manuals/)
- [Research](research/)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Routes agents and humans to canonical reference artifacts for decisions and reusable knowledge about Digital Forest Twin Database. |
| Read When | You need the right ADR, guide, manual, or research note. |
| Skip When | You already know the exact file you need. |
| Canonical | Yes |
| Next Docs | [ADRs](adrs/), [Guides](guides/), [Manuals](manuals/), [Research](research/) |
| Primary Sources | `docs/reference/`, `docs/project/architecture.md`, `docs/project/tech_stack.md` |

---

## Overview

This directory contains reusable knowledge base and architecture decisions:

- **Architecture Decision Records (ADRs)** — Key technical decisions with context, rationale, and alternatives
- **Project Guides** — Reusable patterns and best practices specific to digital-twin-db
- **Package Manuals** — API reference for external libraries
- **Research** — Investigation documents answering specific questions

---

## Architecture Decision Records (ADRs)

| ADR | Decision | Status | Date |
|-----|----------|--------|------|
| [ADR-001: PostgreSQL + PostGIS](adrs/adr-001-postgresql-postgis.md) | PostgreSQL 15 + PostGIS 3 as spatial database | Accepted | 2026-05-11 |
| [ADR-002: Supabase Auth (GoTrue)](adrs/adr-002-supabase-auth.md) | GoTrue JWT auth over OAuth2/session-based | Accepted | 2026-05-11 |
| [ADR-003: Self-Hosted Supabase](adrs/adr-003-self-hosted-supabase.md) | Self-hosted Docker Compose over managed Supabase Cloud | Accepted | 2026-05-11 |
| [ADR-004: Kong API Gateway](adrs/adr-004-kong-api-gateway.md) | Kong 2.8.1 as API gateway over nginx/Traefik | Accepted | 2026-05-11 |
| [ADR-005: Supavisor Connection Pooler](adrs/adr-005-supavisor-pooler.md) | Supavisor over PgBouncer for connection pooling | Accepted | 2026-05-11 |

---

## Project Guides

| Guide | Topic | Date |
|-------|-------|------|
| [01-PostgREST Schema Exposure Pattern](guides/01-postgrest-schema-exposure-pattern.md) | How schema design drives REST API shape and RLS | 2026-05-11 |

---

## Package Manuals

- No package manuals yet. Existing `docs/` files cover API spec, schema, and deployment.

---

## Research

- No research notes yet. Add research only when a concrete question is investigated.

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- New ADRs added to adrs/ directory
- New guides added to guides/ directory
- Schema or service architecture changes
- RLS policy changes

**Verification:**
- [ ] All ADR links in registry are valid
- [ ] All guide links in registry are valid
- [ ] Registries synced with actual files
