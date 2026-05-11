# ADR-002: Authentication — GoTrue (Supabase Auth) with JWT

**Date:** 2026-05-11 | **Status:** Accepted | **Category:** auth | **Decision Makers:** XR Future Forests Lab, Uni Freiburg

<!-- SCOPE: Architecture Decision Record for authentication mechanism selection ONLY. -->
<!-- DOC_KIND: record -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need rationale for JWT/GoTrue over OAuth2 or session-based auth. -->
<!-- SKIP_WHEN: Skip when you need API usage details — see docs/project/api_spec.md. -->
<!-- PRIMARY_SOURCES: docs/project/architecture.md, docs/project/api_spec.md, docs/reference/README.md -->

## Quick Navigation

- [Reference Hub](../README.md)
- [API Spec](../../project/api_spec.md)
- [Architecture](../../project/architecture.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Records decision to use GoTrue (Supabase Auth) with HS256 JWT for all API access control. |
| Read When | You need rationale for JWT auth over OAuth2 or session-based approaches. |
| Skip When | You need API token usage — see docs/project/api_spec.md instead. |
| Canonical | Yes |
| Next Docs | [API Spec](../../project/api_spec.md), [ADR-003: Self-Hosted Supabase](adr-003-self-hosted-supabase.md) |
| Primary Sources | `docs/project/api_spec.md`, `docker/docker-compose.yml` |

---

## Context

All REST API access (PostgREST) must be authenticated and row-level secured. The system needs differentiated access: anonymous read-only clients (dashboards, public sensors), service-role clients (import scripts, admin), and future researcher accounts. Auth must integrate with PostgreSQL RLS policies without application middleware — the JWT must be verifiable at the database layer.

---

## Decision

We use GoTrue v2.182.1 (Supabase Auth service) issuing HS256 JWT tokens. Two permanent tokens are pre-generated: `ANON_KEY` (read-only) and `SERVICE_ROLE_KEY` (full access). These are validated by PostgREST directly against `JWT_SECRET`, enabling database-layer RLS without an application server.

---

## Rationale

1. **Database-native auth** — PostgREST reads the JWT `role` claim and sets the PostgreSQL session role before executing queries. RLS policies fire automatically. No middleware needed.
2. **Supabase platform integration** — GoTrue is the auth service for Supabase; replacing it with a custom auth system would break PostgREST JWT validation and Supabase Studio dashboard access.
3. **Simplicity for research tooling** — Static pre-generated ANON_KEY and SERVICE_ROLE_KEY cover all current use cases (Python scripts, R clients, Studio UI). No OAuth2 dance needed for batch data ingestion.

---

## Consequences

**Positive:**
- Zero application-layer auth code — JWT → DB role → RLS policy chain is fully PostgreSQL
- ANON_KEY and SERVICE_ROLE_KEY cover all current client types
- GoTrue supports future user account creation if per-researcher access is needed

**Negative:**
- HS256 shared secret — if JWT_SECRET leaks, all tokens are compromised (must rotate all keys)
- Static tokens (no expiry for service keys) — require secure storage in docker/.env (gitignored)
- GoTrue adds Docker service weight; overkill for current single-institution use

---

## Alternatives Considered

| Alternative | Pros | Cons | Why Rejected |
|-------------|------|------|--------------|
| OAuth2 (e.g., Keycloak) | Standard, supports federated identity | Requires separate Keycloak server; far more complex for research-only use; PostgREST JWT integration requires custom claims mapping | Over-engineered for current single-institution, script-driven access pattern |
| Session-based (cookie) | Familiar, easy to implement | No database-layer enforcement; requires application middleware; incompatible with PostgREST stateless model | PostgREST requires JWT for role propagation to PostgreSQL |

---

## Related Decisions

- ADR-003: Self-Hosted Supabase (GoTrue is part of Supabase stack)
- See [docs/project/api_spec.md](../../project/api_spec.md) for auth header usage

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- JWT_SECRET rotation
- GoTrue version upgrade
- Per-researcher accounts added

**Verification:**
- [ ] Decision still reflects accepted choice
- [ ] docker-compose.yml GoTrue image version matches
- [ ] Related ADR links resolve
