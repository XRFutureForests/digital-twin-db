# Documentation Standards

<!-- SCOPE: Reference rules for generated project documentation ONLY. Defines structure, writing, and verification requirements. -->
<!-- DOC_KIND: reference -->
<!-- DOC_ROLE: canonical -->
<!-- READ_WHEN: Read when creating, updating, auditing, or validating project documentation. -->
<!-- SKIP_WHEN: Skip when you only need the project map or a specific project-domain fact. -->
<!-- PRIMARY_SOURCES: docs/documentation_standards.md, docs/principles.md -->

## Quick Navigation

| Need | Read |
|------|------|
| Project map | [README.md](README.md) |
| Principles behind the rules | [principles.md](principles.md) |
| Canonical project entry | [../AGENTS.md](../AGENTS.md) |

## Agent Entry

- Purpose: Canonical reference for documentation requirements and validation rules.
- Read when: You are creating, editing, or auditing documentation.
- Skip when: You only need a domain-specific project fact.
- Canonical: Yes.
- Read next: `principles.md` for rationale or the target doc you are editing.
- Primary sources: `docs/documentation_standards.md`, `docs/principles.md`.

## Critical Requirements

| Requirement | Why It Exists |
|-------------|---------------|
| `AGENTS.md` is the canonical machine-facing root doc | Keeps the always-loaded entrypoint small and stable |
| `CLAUDE.md` is a `@AGENTS.md` import stub with a `## Claude Code` delta (≤50 lines) | Keeps Claude Code's auto-loaded file tiny; the import expands AGENTS.md into context at session start |
| Every generated doc has the standard header contract | Enables deterministic routing and auditing |
| Every generated doc has `Quick Navigation`, `Agent Entry`, and `Maintenance` | Enables section-first reading |
| No raw placeholders outside allowlisted task setup docs | Published docs must be immediately usable |
| Prefer links and source references over embedded implementation code | Keeps docs concise and reduces drift |
| Secrets never appear in documentation | `docker/.env` is gitignored; reference env vars by name only |

## Structural Rules

| Rule | Requirement |
|------|-------------|
| Header contract | `SCOPE`, `DOC_KIND`, `DOC_ROLE`, `READ_WHEN`, `SKIP_WHEN`, `PRIMARY_SOURCES` in first 12 lines |
| Top sections | `Quick Navigation`, `Agent Entry`, `Maintenance` |
| Doc kinds | `index`, `reference`, `how-to`, `explanation`, `record` |
| Doc roles | `canonical`, `navigation`, `working`, `derived` |
| Root model | `AGENTS.md` canonical; `CLAUDE.md` is an `@AGENTS.md` import stub |
| Format priority | Tables > lists (enumeration only) > prose (last resort) |
| Code fences | Allowed for: `shell`, `yaml`, `json`, `toml`, `env`, `sql`, `mermaid`, `text` |
| Line endings | POSIX (LF), single newline at end of file |

## Writing Rules

| Rule | Guidance |
|------|----------|
| Map-first | Put routing and purpose before details |
| Section-first | Make top sections enough for initial triage |
| Single source of truth | One canonical document per topic; link outward from others |
| Stack adaptation | Use official PostgreSQL, PostGIS, Supabase, and Docker references |
| Token efficiency | Prefer tables, short bullets, and direct links over long prose |
| No implementation code | Link to source files instead of embedding SQL or Python snippets |
| No forbidden markers | Never leave `{{...}}`, `[TBD: ...]`, `TODO`, or `Coming soon` in published docs |

## Document Map

| Document | Kind | Role | Purpose |
|----------|------|------|---------|
| `AGENTS.md` | index | canonical | Machine-facing repo entry point |
| `CLAUDE.md` | index | derived | Claude Code stub (`@AGENTS.md` + harness delta) |
| `docs/README.md` | index | navigation | Human-facing documentation map |
| `docs/documentation_standards.md` | reference | canonical | This file — documentation rules |
| `docs/principles.md` | explanation | canonical | Governing principles and decision framework |
| `docs/ARCHITECTURE.md` | explanation | canonical | System architecture and service topology |
| `docs/database-schema.md` | reference | canonical | Schema definitions and entity relationships |
| `docs/project/deployment-guide.md` | how-to | canonical | Step-by-step deployment instructions |
| `docs/project/troubleshooting.md` | how-to | canonical | Common issues and resolution steps |

## Verification Checklist

- [ ] Header contract complete (`SCOPE`, `DOC_KIND`, `DOC_ROLE`, `READ_WHEN`, `SKIP_WHEN`, `PRIMARY_SOURCES`)
- [ ] Top sections present (`Quick Navigation`, `Agent Entry`, `Maintenance`)
- [ ] Internal markdown links resolve to existing files
- [ ] No leaked template metadata or forbidden placeholders
- [ ] External links use official domains (postgresql.org, postgis.net, supabase.com, docs.docker.com)
- [ ] `Maintenance` section has update triggers and verification checklist
- [ ] No secrets, credentials, or `.env` values embedded

## Maintenance

**Update Triggers:**
- When the document map changes (files added, renamed, or removed)
- When structural or writing rules change
- When the root entrypoint model changes
- When new forbidden placeholder types are identified

**Verification:**
- [ ] Document map matches actual files in `docs/`
- [ ] Critical requirements align with current project conventions
- [ ] Verification checklist remains actionable

**Last Updated:** 2026-05-11
