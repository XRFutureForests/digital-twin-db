# docs — digital-twin-db

Reference for the schema, the API and deployment. Start with [README.md](../README.md) for
what the database is, and [RUNBOOK.md](../RUNBOOK.md) for how to run and load it.

## The schema

| Document | Contents |
|----------|----------|
| [database-overview.md](database-overview.md) | The seven schemas, how they connect, key patterns, working query examples |
| [database-dictionary.md](database-dictionary.md) | Generated: every table, column, type, constraint and DB comment, plus the `public` views |
| [database-erd.dbml](database-erd.dbml) | Generated ERD (DBML) |
| [database-schema.md](database-schema.md) | Conventions, column semantics, constraints, indexes and data types |
| [variant-scenario-model.md](variant-scenario-model.md) | Location → scenario → variant, scenarios as regime × climate pathway, and the UE query sequence |
| [growth-simulation-schema.md](growth-simulation-schema.md) | `trees.simulation_runs` and `trees.growth_simulations`: tables, views, permissions |
| [citygml-qsm-mapping.md](citygml-qsm-mapping.md) | Column-by-column mapping to the CityGML conceptual tree model |
| [level-of-detail-vocabulary.md](level-of-detail-vocabulary.md) | What `lod` means in the database, and the detail terms used with growpy |

`database-dictionary.md` and `database-erd.dbml` are written by
`scripts/utils/generate_schema_docs.py` from the live database — regenerate them after a
migration, never edit them by hand.

## Provenance

| Document | Contents |
|----------|----------|
| [derived-value-provenance.md](derived-value-provenance.md) | How a derived value is distinguished from a measured one |
| [run-provenance.md](run-provenance.md) | What a processing run records about itself |

## Using it

| Document | Contents |
|----------|----------|
| [api-spec.md](api-spec.md) | REST endpoints, views, RPC signatures |
| [data-access-guide.md](data-access-guide.md) | Query patterns per client — SQL, REST, R, Python, Unreal; accounts and role tiers |
| [requesting-a-job.md](requesting-a-job.md) | Queueing a connector run — the `/jobs/` page, the RPC underneath it, and what claims the job |
| [silva-coupling.md](silva-coupling.md) | The contract with silva-connector |

## Running it

| Document | Contents |
|----------|----------|
| [deployment-guide.md](deployment-guide.md) | Production deployment on dt.unr, TLS, Kong, NFS-backed PGDATA |
| [troubleshooting.md](troubleshooting.md) | Symptom-by-symptom, including container-level problems |
| [docker/](docker/README.md) | Container stack and how it differs from upstream Supabase; image versions in [docker/versions.md](docker/versions.md) |

Starting the stack locally, loading data, reset and rebuild are in [RUNBOOK.md](../RUNBOOK.md).

---

Why the variant model, the CityGML alignment and the scaling decisions were chosen — and the
audits behind them — live in the XR Future Forests Lab knowledge hub, `03-DATA-TIER/`.
