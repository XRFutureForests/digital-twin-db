# Test Dataset — Black Forest Test Site (LocationID=3)

## Purpose

This dataset serves two purposes:

1. **Unreal Engine integration testing** — a complete, importable set of 20 trees across three scenarios that exercises all foreign-key relationships and the full column surface of `trees.Trees` and `trees.Stems`.
2. **Reference import example** — shows exactly how to prepare any inventory CSV for the database, with all optional fields filled and realistic values.

The site is centred at 48.51°N, 8.11°E (~950 m elevation, Black Forest montane zone). Species mix: European beech (1), Norway spruce (3), Silver fir (4), Scots pine (5), Sycamore maple (9).

## Files

| File | Trees | ScenarioName | Notes |
|------|-------|--------------|-------|
| `baseline_current.csv` | 20 | `Current_Conditions` | Field-measured baseline, all species, VariantTypeID=1 |
| `growth_2035.csv` | 20 | `TestPlot_Growth_2035` | Simulated +10yr growth, VariantTypeID=4 |
| `management_thinning.csv` | 15 | `TestPlot_Management_2030` | Post-selective-thinning state (5 trees removed), VariantTypeID=7 |

## How to Import

Import the files in any order. Unknown `ScenarioName` values are created automatically in `shared.Scenarios`.

```bash
python scripts/import/import_trees.py data/test_dataset/baseline_current.csv
python scripts/import/import_trees.py data/test_dataset/growth_2035.csv
python scripts/import/import_trees.py data/test_dataset/management_thinning.csv
```

Add `--dry-run` to validate without writing to the database.

## Scenarios Created

| ScenarioName | Description |
|---|---|
| `Current_Conditions` | Observed 2024 field survey baseline |
| `TestPlot_Growth_2035` | Projected state after 10 years of undisturbed growth |
| `TestPlot_Management_2030` | State after selective thinning of 5 trees in 2030 |

## Querying the Result

REST API (PostgREST via Kong on port 8000):

```
GET /ue_trees?scenarioname=eq.Current_Conditions&locationid=eq.3
GET /ue_trees?scenarioname=eq.TestPlot_Growth_2035&locationid=eq.3
GET /ue_trees?scenarioname=eq.TestPlot_Management_2030&locationid=eq.3
```

Direct SQL:

```sql
SELECT t.TreeNumber, s.ScenarioName, t.Height_m, t.DBH_cm, t.HealthScore
FROM trees.Trees t
JOIN shared.Scenarios s ON s.ScenarioID = t.ScenarioID
WHERE t.LocationID = 3
ORDER BY s.ScenarioName, t.TreeNumber;
```

## Adapting for Your Own Data

### Required columns

| Column | Notes |
|---|---|
| `LocationID` | Must exist in `shared.Locations` |
| `Latitude` | WGS84 decimal degrees |
| `Longitude` | WGS84 decimal degrees |

All other columns are optional. Rows with missing `Latitude`/`Longitude` are skipped.

### Optional columns

| Column | Notes |
|---|---|
| `PlotID` | Integer FK to `shared.Plots`; leave empty if no plot subdivision |
| `TreeNumber` | Your field tag number |
| `CampaignID` | FK to `shared.Campaigns` |
| `SpeciesID` | FK to `shared.Species` (1=Beech, 3=Spruce, 4=SilverFir, 5=ScotsPine, 9=SycamoreMaple, …) |
| `VariantTypeID` | 1=original, 4=simulated_growth, 7=model_output |
| `DataSourceType` | String name looked up in `trees.DataSourceTypes` table: `field`, `lidar`, `photogrammetry`, `estimated`, `simulated` (IDs 1–5) |
| `DBH_cm` | Diameter at breast height; triggers a row in `trees.Stems` |
| `Height_m`, `CrownWidth_m`, `CrownBaseHeight_m` | Structural dimensions in metres |
| `TreeStatusID` | 1=healthy, 2=stressed |
| `BranchingPatternID` | 3=Whorled (conifers), 5=Random (broadleaves) |
| `BarkCharacteristicID` | 1=Smooth, 2=Furrowed, 5=Scaly |
| `TaperTypeID` | 2=Cone (conifers), 3=Paraboloid (broadleaves) |
| `StraightnessTypeID` | 1=Straight, 2=Slight_sweep |
| `Age_years`, `HealthScore` | HealthScore in [0, 1] |
| `MeasurementDate` | ISO 8601 date (YYYY-MM-DD) |
| `FieldNotes` | Free text |
| `ScenarioName` | Any string; scenario is created automatically if it does not exist |
| `SourceCRS` | EPSG code for `PositionOriginal`; omit if using WGS84 only |

The CSV header must exactly match the column names above (case-sensitive). Extra columns are ignored with a warning.
