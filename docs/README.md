# docs — digital-twin-db

Reference for the schema, the API and deployment. Start with [README.md](../README.md) for
what the database is, and [RUNBOOK.md](../RUNBOOK.md) for how to run and load it.

## The schema

| Document | Contents |
|----------|----------|
| [database-overview.md](database-overview.md) | The seven schemas, how they connect, the key design patterns |
| [database-schema.md](database-schema.md) | Full data dictionary — every table, column, type and constraint |
| [variant-scenario-model.md](variant-scenario-model.md) | Location → Scenario → Variant, and the query patterns that depend on it |
| [growth-simulation-schema.md](growth-simulation-schema.md) | `trees.growth_simulations` and `trees.simulation_runs` |
| [citygml-qsm-mapping.md](citygml-qsm-mapping.md) | Column-by-column mapping to the CityGML conceptual tree model |
| [level-of-detail-vocabulary.md](level-of-detail-vocabulary.md) | The LOD terms used across schemas |

## Provenance

| Document | Contents |
|----------|----------|
| [derived-value-provenance.md](derived-value-provenance.md) | How a derived value is distinguished from a measured one |
| [run-provenance.md](run-provenance.md) | What a processing run records about itself |

## Using it

| Document | Contents |
|----------|----------|
| [api-spec.md](api-spec.md) | REST endpoints, views, RPC signatures |
| [data-access-guide.md](data-access-guide.md) | Query patterns per client — SQL, REST, R, Python, Unreal |
| [requesting-a-job.md](requesting-a-job.md) | Queueing a connector run — the `/jobs/` page, the RPC underneath it, and what claims the job |
| [silva-coupling.md](silva-coupling.md) | The contract with silva-connector |

## Running it

| Document | Contents |
|----------|----------|
| [local-deployment-guide.md](local-deployment-guide.md) | Local stack, step by step |
| [deployment-guide.md](deployment-guide.md) | Production deployment on dt.unr, TLS, Kong, NFS-backed PGDATA |
| [troubleshooting.md](troubleshooting.md) | Symptom-by-symptom |
| [docker/](docker/README.md) | Container stack, versions, container-level troubleshooting |

---

Why the variant model, the CityGML alignment and the scaling decisions were chosen — and the
audits behind them — live in the XR Future Forests Lab knowledge hub, `03-DATA-TIER/`.
