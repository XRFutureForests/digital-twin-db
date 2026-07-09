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

## `ecosense_sensor_metadata.csv`

Project-wide Ecosense sensor metadata catalogue, keyed by `external_id`
(Aquarius `TimeSeriesUniqueID` = `sensor.Sensors.ExternalID`). Extracted from the
Aquarius *Insitu DataUpload* form export.

**Why it exists.** The Aquarius API sync populates `sensor.Sensors.SensorModel`
with a generic `Ecosense Node` placeholder and does not carry the instrument or
data-owner. This catalogue holds the real values so they can be restored.

| Column | Description |
|--------|-------------|
| `external_id` | Aquarius TimeSeriesUniqueID (= `sensor.Sensors.ExternalID`) |
| `sensor_id` | Aquarius numeric sensor ID |
| `label` | Aquarius series label (≈ `sensor.Sensors.SerialNumber`) |
| `location` | Aquarius LocationIdentifier |
| `parameter`, `parameter_unit` | Measured quantity + unit |
| `instrument` | Hardware model (e.g. `SMT100`, `Implexx Sap Flow Sensor`) |
| `data_owner` | Responsible person/subproject |
| `measurement_type` | Aquarius computation type |
| `gap_tolerance` | Aquarius gap tolerance (ISO-8601 duration) |

### How it is used

`scripts/import/enrich_sensor_metadata.py` matches by `external_id` and backfills
`instrument` into `SensorModel` plus `data_owner` / `measurement_type` /
`gap_tolerance` into `ExternalMetadata`.

```bash
python scripts/import/enrich_sensor_metadata.py                 # uses this CSV
python scripts/import/enrich_sensor_metadata.py form.xlsx       # refresh from a raw export
```

**Run it after every Aquarius sync** — the sync upsert resets `SensorModel` and
`ExternalMetadata`. To refresh the catalogue from a newer form export, re-run the
extraction that produced this file.
