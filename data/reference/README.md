# Reference Data

Curated reference tables that are **not** database lookup tables (those live in
[`../lookups/`](../lookups/)) but are needed to reconcile external identifiers
with our own records. These files are the source of truth for the mappings they
describe and are consumed by import scripts, not loaded automatically at DB
bootstrap.

## `ecosense_sensor_tree_map.csv`

Maps each Ecosense **Aquarius sensor name** to the physical inventory tree the
sensor cluster is installed on.

**Why it exists.** Aquarius names its sensor time-series with a per-species,
per-plot-type sequence number — e.g. `Beech_Mixed_8`, `DouglasFir_Pure_10`.
That number is **independent** of our inventory tree numbering
(`plot_id` × `tree_number`, e.g. tree `8_16`). Aquarius does not carry the
inventory ID, so the two systems cannot be joined from Aquarius data alone.
This table — derived from the field survey (`Insitu` upload form /
`measurement_trees_inventory` ODK export) — is the missing decoder ring.

The Aquarius name here matches the **prefix** of the sensor `serialnumber`
values in `sensor.sensors` (e.g. `Beech_Mixed_8` → `Beech_Mixed_8_Dendrometer`,
`Beech_Mixed_8_Total_SapFlow`, `Beech_Mixed_8_stem_N`, …).

| Column | Description |
|--------|-------------|
| `aquarius_name` | Aquarius sensor-name prefix (`{Species}_{PlotType}_{Seq}`) |
| `full_id` | Inventory tree ID `{plot_id}_{tree_id}` |
| `plot_id` | Sub-plot number |
| `tree_id` | Tree number within the plot (= `trees.Trees.TreeNumber`) |
| `plot_type` | Field plot label (MixedPlot / BeechPlot / DouglasFirPlot) |
| `species` | Field-recorded species |
| `x_32632`, `y_32632` | Position in UTM 32N (EPSG:32632) |
| `dbh_m` | Field diameter (m) |
| `tls_height_m` | TLS-derived tree height (m), where available |
| `qr_code_id` | In-field QR code URL (`/ecosense/{full_id}`) |

### How it is used

`scripts/import/link_sensors_to_trees.py`:

1. Backfills `trees.Trees.AquariusName` for the matching trees (resolved by
   `plot_id` + `tree_number`).
2. Links every `sensor.sensors` row whose `serialnumber` prefix equals a tree's
   `AquariusName` to that tree in `sensor.sensor_tree_links` — the whole
   monitoring cluster (dendrometer, sap flow, stem water potential, and the
   surrounding soil-moisture / soil-temperature probes).

```bash
python scripts/import/link_sensors_to_trees.py
```

Run it after tree and sensor data have been imported. It is idempotent
(`ON CONFLICT DO NOTHING`).

## `ecosense_sensor_metadata.csv` (moved)

This catalogue moved to the [aquarius-connector](https://github.com/XRFutureForests/aquarius-connector) repo's
`data/` directory as part of extracting the Aquarius integration out of this
repo (it's the input to that repo's `enrich_metadata.py`, which now talks to
this DB only via the `bulk_upsert_sensors` REST RPC rather than direct SQL).