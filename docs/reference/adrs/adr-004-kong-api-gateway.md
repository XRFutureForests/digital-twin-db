# ADR-004: API Gateway — Kong 2.8.1

**Date:** 2026-05-11 | **Status:** Accepted | **Category:** api_gateway | **Decision Makers:** XR Future Forests Lab, Uni Freiburg

<!-- SCOPE: Architecture Decision Record for API gateway selection ONLY. -->
<!-- DOC_KIND: record -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when you need rationale for Kong over nginx/Traefik as API gateway. -->
<!-- SKIP_WHEN: Skip when you need endpoint routing details — see docs/project/api_spec.md. -->
<!-- PRIMARY_SOURCES: docs/project/api_spec.md, docs/reference/README.md, docker/docker-compose.yml -->

## Quick Navigation

- [Reference Hub](../README.md)
- [API Spec](../../project/api_spec.md)
- [Architecture](../../project/architecture.md)

## Agent Entry

| Signal | Value |
|--------|-------|
| Purpose | Records decision to use Kong 2.8.1 as API gateway routing all Supabase service traffic. |
| Read When | You need rationale for Kong over nginx/Traefik for Supabase API routing. |
| Skip When | You need endpoint URLs — see docs/project/api_spec.md. |
| Canonical | Yes |
| Next Docs | [API Spec](../../project/api_spec.md), [ADR-003: Self-Hosted Supabase](adr-003-self-hosted-supabase.md) |
| Primary Sources | `docker/docker-compose.yml`, `docker/volumes/api/kong.yml` |

---

## Context

The self-hosted Supabase stack exposes multiple internal services (PostgREST, GoTrue, Storage, Realtime) that must be accessible via a single port with path-based routing. API key authentication, CORS, and plugin-based middleware must apply uniformly to all routes without modifying individual services.

---

## Decision

We use Kong 2.8.1 (declarative config mode, `kong.yml`) as the single entry-point gateway on port 8000/8443. All routes (/rest/v1, /auth/v1, /storage/v1, /realtime/v1) are declared in `docker/volumes/api/kong.yml`.

---

## Rationale

1. **Supabase official choice** — Kong is the API gateway in the official Supabase self-hosted Docker Compose stack. Using it avoids divergence from upstream `supabase/supabase` configs and maintains compatibility with Supabase CLI tooling.
2. **Declarative plugin config** — Kong's `kong.yml` declares routes, plugins (key-auth, CORS, rate-limiting, ACL) without running a database. `KONG_DATABASE: "off"` mode is simpler to operate than Kong with Postgres backing.
3. **Single entry point** — Kong terminates all external traffic on port 8000, routing internally to PostgREST:3000, GoTrue:9999, Storage:5000, Realtime:4000. Clients need only one base URL.

---

## Consequences

**Positive:**
- Single `localhost:8000` entry point for all API clients (Python, R, Studio, browser)
- Declarative route config in `kong.yml` — version-controllable, no DB state
- Supabase upstream updates to `kong.yml` apply cleanly

**Negative:**
- Kong 2.8.1 is an older LTS; Supabase has not yet migrated to Kong 3.x — upgrade blocked by Supabase release schedule
- `kong.yml` customization (adding custom routes) requires understanding Kong declarative syntax
- Two ports exposed (8000 HTTP, 8443 HTTPS) — HTTPS not configured by default in dev setup

---

## Alternatives Considered

| Alternative | Pros | Cons | Why Rejected |
|-------------|------|------|--------------|
| nginx | Lightweight, familiar, simple reverse proxy | No native API key auth plugin; no ACL/rate-limiting without custom Lua; diverges from Supabase upstream | Supabase uses Kong; diverging breaks upstream updates |
| Traefik | Docker-label-based config, auto-discovery | No built-in Supabase integration; requires manual route mapping; breaks Supabase upstream Docker Compose | Same divergence problem as nginx |

---

## Related Decisions

- ADR-003: Self-Hosted Supabase (Kong is bundled in the Supabase Docker Compose stack)
- See [docs/project/api_spec.md](../../project/api_spec.md) for route details

---

## Maintenance

**Last Updated:** 2026-05-11

**Update Triggers:**
- Supabase upgrades Kong version
- Custom routes added to kong.yml
- HTTPS/TLS configured

**Verification:**
- [ ] Decision still reflects accepted choice
- [ ] docker-compose.yml Kong image version matches
- [ ] Related ADR links resolve
