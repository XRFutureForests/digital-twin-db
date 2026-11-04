# Changelog

All notable user-facing changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

**Tree re-identification across campaigns** (XRFF-465)

- Migration `20261104130000_tree_reidentification` (init `85-`). `trees.trees` gains the unique
  key `(variant_id, tree_entity_id)`: a physical tree appears at most once per forest state.
- New `trees.observations`: one tree as one campaign detected or measured it. A field tree points
  at its tree row; a detection from a point cloud carries position, DBH, height, planimetric
  position uncertainty in metres, `point_cloud_id` and `instance_id` (unique per cloud).
- New `trees.entity_matches`: which physical tree (`tree_entity_id`) an observation belongs to,
  with `decision` (`matched`, `new`, `ambiguous`), `method`, `score`, the campaign matched
  against, who decided and when. A revision supersedes the previous decision, which is kept;
  per observation exactly one decision is current.
- Views `public.observations`, `public.entity_matches` (contributors write) and
  `public.current_entity_matches`. Both tables follow the dataset access levels; a match is
  hidden with its observation.

**Five Pathfinder superplots as new locations** (XRFF-641)

- `scripts/import/import_pathfinder.py`: `fetch` reads the field-data GeoPackages of the
  Pathfinder superplots (doi 10.5281/zenodo.20623034, CC BY 4.0) out of the Zenodo country ZIPs
  by HTTP range requests, never the point clouds; `sql` writes one idempotent SQL file keyed on
  natural keys, so the same file loads any instance. Locations `tratice`, `krucmanove`,
  `goettingen2`, `valsain`, `vallombrosa_douglas` (also in `data/lookups/locations.csv`), each
  with a census sampling design on its 0.25 ha plot, a `natural_growth` scenario with a
  `baseline_<year>` variant, 496 trees, 343 deadwood pieces and 14 regeneration tallies.
- Migration `20261103120000_species_lawson_cypress_holly_wych_elm` (init `82-`): three species
  of those plots, also in `data/lookups/species.csv`.
- Migration `20261103130000_regeneration_survey_area` (init `83-`): regeneration tallies carry
  their survey area (`survey_area_m2`) instead of sitting on subplots. A subplot with its own
  area counted as a second census unit without trees and lowered stems per hectare.
- `scripts/seed/census_site_plots.sql` leaves locations alone that carry their own sampling
  design, so it no longer replaces a measured plot by the convex hull of its stems.

**Outside inventories: source ids, protocol codes, regeneration, richer deadwood** (XRFF-639, XRFF-640)

- Migration `20261103100000_outside_inventory_tree_source` (init `80-`). Trees gain
  `source_tree_id` (the producer's own id; unique per campaign and variant, requires a campaign)
  and `source_attributes` (a JSON object of protocol codes without a column, keyed by the
  source's column names). Both are in `public.trees`. `campaign_type` accepts `laser_scan` for
  ground-based TLS and MLS.
- Migration `20261103110000_forest_floor_regeneration_and_deadwood` (init `81-`). New table
  `forest_floor.regeneration` (live and dead counts per species and size class `seedling` /
  `sapling` on a plot or subplot), with views `regeneration` and `regeneration_per_ha` (counts
  per hectare through the plot's survey area). Deadwood gains `campaign_id`, `geom` (the piece as
  any geometry, e.g. a line), `diameter_top_cm`, `void_diameter_cm`, `source_deadwood_id` and
  `source_attributes`; ground vegetation gains `campaign_id`. All three follow the dataset
  access levels: before, a deadwood row was hidden only through its tree.

**Dataset ownership, licence and access levels** (XRFF-625)

- Migration `20261102180000_dataset_access_levels` (init `79-`). Campaigns gain `owner_team_id`,
  `licence` (required), `access_level` (`public`, `campus`, `registered`, `team`; default
  `public`), `embargo_until`, `citation` and `doi`. Restrictive row-level policies hide the rows
  of a campaign the caller may not read and the rows hanging off them. `campus` means the
  university network (header `X-DT-Network`, set by the server's nginx) or any signed-in
  account. Curators and the owning team see everything. Rows without a campaign stay public, so
  existing data is unchanged.
- Teams: `shared.teams`, `shared.team_members`, view `teams`, RPCs `add_team_member`,
  `remove_team_member`, `list_team_members`; `my_access` shows what the database knows about the
  caller. Contributors may only write into campaigns without an owner team or of their own teams.
- `ue_trees`, `growth_simulations` and `simulation_runs` now run with the caller's rights;
  `trees.growth_simulations` and `sensor.sensor_tree_links` have row-level security.
- New role `dashboard_reader` (member of `anon`) for the dashboards, which read as `postgres`
  until now and bypassed row-level security. Each host sets its password (RUNBOOK §9).

**Faster summaries; which SILVA run holds the chain**

- Migration `20261102150000_set_based_summaries_and_chain_run` (init `76-`): `plot_summaries`
  and `tree_expansion_factors` resolve each plot once (new view `shared.plot_inclusion`) and
  share one formula (`shared.ef_value`) with `shared.expansion_factor_ha`. Same results; an
  unfiltered `plot_summaries` takes 0.1 s instead of 16 s on dev. On dt.unr it still ran past
  the 3 s anonymous limit; migration `20261102160000_stand_summaries_compute_once` (init `77-`)
  makes `shared.ef_value` inlinable (no `SET` clause) and computes each tree's factor once:
  1.5 s unfiltered and 9 ms per variant on dt.unr, so the portal can list and download it.
  Migration `20261102170000_stand_summaries_one_pass` (init `78-`): `stand_summaries` gets the
  all-species and per-species rows from one pass (`shared.estimate_stand_domains`) instead of
  two calls per forest state; `estimate_stand` is unchanged for callers.
- `public.simulation_runs` gains `holds_variant_chain`. `is_promoted` is never cleared when a
  later run takes the chain over (`--replace`), so a scenario can have several promoted runs;
  the newest holds the chain. No data changes.

**Stand summaries with sampling error** (XRFF-627)

- Migration `20261102140000_stand_summaries` (init `75-`) computes stand-level results in the
  database. `public.plot_summaries`: per sample unit, variant and species, living stems, basal
  area, volume, biomass and carbon per hectare (a value is NULL when a counted tree lacks it).
  `shared.estimate_stand(design, variant, by_species, confidence)`, also
  `/rest/v1/rpc/estimate_stand`: the design-based estimate for census, simple random,
  systematic (as simple random) and stratified designs, with standard error, relative
  standard error %, margin of error, sampling error % and confidence interval at 90, 95 or
  99 % (Student t), number of units, area and total. Values agree with R `survey`.
  `public.stand_summaries` and `public.ue_stand_summary`: every variant for each design of its
  site at 95 %. Two-phase designs are not estimated yet.

**Sampling designs and expansion factors** (XRFF-626)

- Migration `20261102130000_sampling_designs` (init `74-`) lets the database hold sampled
  inventories, not only full censuses. New tables `shared.sampling_designs` (strategy,
  protocol and version, DBH measuring height, minimum DBH, reporting area),
  `shared.inclusion_rules` (per DBH range a fixed radius or an angle-count basal-area factor;
  several rules make nested circles) and `shared.strata` (with area). `shared.plots` gains
  `sampling_design_id`, `stratum_id`, `parent_plot_id` (cluster → plot → subplot),
  `sampling_weight` (default 1) and `area_source`; `trees.stems` gains
  `dbh_measuring_height_m`.
- `shared.expansion_factor_ha(plot_id, dbh_cm)` returns the trees per hectare one tree
  stands for: 10000/(π r²) for a fixed radius, BAF/basal area for angle count, 10000/area
  otherwise; NULL when unknown. A plot without a design or area takes them from its nearest
  enclosing plot. New views `sampling_designs`, `inclusion_rules`, `strata` (contributors
  write) and `tree_expansion_factors`; `plots` and `stems` gain the new columns at the end.
  Additive: no existing column changes.
- Seed `scripts/seed/census_site_plots.sql` gives each fully mapped site a census plot
  `<location>_site` (area = convex hull of the measured baseline, as silva-connector uses)
  and hangs the existing plots under it: Ecosense 2.891 ha, Mathisle 1.173 ha. Baseline
  stems per hectare from it match silva-connector's stand values (515 + 6 trees without a
  plot = 517; 622).
- `docs/deployment-guide.md` has a section **Applying a migration** for dt.unr: how to tell
  which migrations the server has (compare a schema dump with dev; the server keeps no record),
  then pull, back up, apply each migration in one transaction, change the environment, verify,
  and what to do when a step fails.

## [2.0.3] - 2026-11-02

**The schema `pointclouds` is now `point_clouds`**

- Migration `20261102100000_rename_pointclouds_schema` (init `71-`) renames the schema, so
  every schema and table name is snake_case; its table is `point_clouds.point_clouds`. Tables,
  views, policies and grants follow the rename; the view trigger `public.point_clouds_insert()`
  is rewritten. The REST resource `/rest/v1/point_clouds` is unchanged.
- **Action for self-hosters:** in `docker/.env`, replace `pointclouds` with `point_clouds` in
  `PGRST_DB_SCHEMAS` and restart PostgREST (`docker compose up -d rest`), or PostgREST cannot
  load its schema cache. Clients that select the base schema with `Accept-Profile: pointclouds`
  must send `point_clouds`.

**Audit labels are table names**

- `shared.create_audit_log()` and `shared.get_audit_history()` take the table name
  (`'point_clouds'`, `'trees'`, `'environments'`, `'stems'`, `'phenology_observations'`) instead
  of the CamelCase labels `'PointClouds'`, `'Trees'` and so on, and `shared.recent_changes.table_name`
  returns the same names. Migration `20261102120000_audit_table_labels_snake_case` (init `73-`).
  No stored data changes. A caller passing an old label now gets an error instead of an empty
  history.

**Fixed**

- Inserting through `public.point_clouds`, `public.environments`, `public.sensors` or
  `public.stems` without the id failed with a NOT NULL violation, and `created_at` (plus
  `is_active`, `installation_date` and `external_metadata` on sensors) was written as NULL. Their
  insert triggers copy the whole row, and the views had no column defaults. Migration
  `20261102110000_view_insert_defaults` (init `72-`) gives the four views their base tables'
  defaults.
- A fresh init stopped in `30-load-lookup-tables.sql`, which still loaded `datasource_types.csv`
  after the file was renamed to `data_source_types.csv` in September. Existing databases were not
  affected.

## [2.0.2] - 2026-11-02

**Documentation for new users and data providers**

- The README now presents the repository as a single-tree inventory database for forest
  digital twins, with the database architecture first: the location, scenario and variant
  model with one row per tree per forest state, the provenance mechanisms, the seven schemas,
  the API and the access tiers. Then how each kind of data gets in, how to run your own
  instance, and the University of Freiburg instance as one example deployment.
- Portal: the start page opens with the tree look survey as its own section, has a general
  introduction and links the inventory CSV template and its preparation guide; the docs page
  begins with what the lab means by a forest digital twin; the job page `/jobs/` now uses
  the portal's stylesheet and shows the shared logo band and top bar.

## [2.0.1] - 2026-11-02

### 2026-11-02

**Portal in the lab and university corporate design**

- `/portal/` and `/jobs/` follow the XR Future Forests Lab design spec on the University of
  Freiburg corporate design: a logo band with the university wordmark and the lab logo
  (`web/portal/img/`, trademarks outside this repository's licence), dark blue headings, CD
  green accents with an accessible darker green for links and buttons, square corners, the
  Social/Arial font stack, stronger form borders, and a matching dark mode.

### 2026-10-30 (after 2.0.0)

**Security: three writes the role model never allowed are closed**

- The connector RPCs `bulk_insert_readings`, `bulk_upsert_sensors`, `set_location_attributes`,
  `upsert_environment` and `refresh_soil_aggregates` run as their owner and check no role,
  yet anyone with the public anon key could call them — insert readings, upsert sensors,
  overwrite site attributes and environments. EXECUTE is now `service_role` only; every
  connector already sends that key.
- `trees.growth_simulations` was writable (INSERT/UPDATE) by any signed-in account, including
  ones with no role. Revoked; silva-connector writes over libpq and is unaffected.
- Fix: updates to `pointclouds.point_clouds` and `trees.phenology_observations` were never
  audited since the 2026-09-23 rename — the audit trigger still dispatched on the old table
  names. They are logged again.
- Migration `20261030120000` + init `70`; regression tests in `tests/automated/e2e/access/`.

**Documentation brought up to date with the database**

- `docs/database-dictionary.md` (new) and `docs/database-erd.dbml` are generated from the live
  database by `scripts/utils/generate_schema_docs.py` (`--check` exits 1 when stale): all 72
  tables, columns, types, references, constraints and the comments stored in the database.
  The hand-written ERD was missing 27 tables and used pre-rename names.
- The reference docs were audited against the live schema and corrected; stale duplicates
  were merged into RUNBOOK and `docs/troubleshooting.md`.
- Portal: `/portal/docs/` (data model, a clickable schema map, per-schema tables with live row
  counts, links to the reference docs and all repositories) and `/portal/api/` rewritten as a
  developer guide (sign-in, read/write recipes, running a model with the live SILVA parameter
  table, ground rules); the start page links the tree look survey. `docs/requesting-a-job.md`
  gains the SILVA run modes.
- `ue_sensor_readings_latest` (2026-10-28) is now applied on dt.unr too.

## [2.0.0] - 2026-10-30

### 2026-10-30

**Access for other teams: the portal, curator-managed accounts, read-only by default**

- `web/portal/`: a static site at `/portal/` (and `/`) with one door per level of experience —
  browse/download any table, add rows by form or CSV and correct them (`/portal/data/`, forms
  generated from the OpenAPI description), sign-in and team account management
  (`/portal/account/`), and a developer quick start (`/portal/api/`). Shares the sign-in with
  `/jobs/`. Served by the dashboard's nginx.
- Curators create accounts, grant or revoke `contributor` and reset passwords; admins also
  grant `curator`/`admin`. New RPCs `create_account`, `set_account_role`,
  `reset_account_password`, `list_accounts` (SECURITY DEFINER, role-checked); every change is
  logged to the new `shared.account_events`. One-time passwords are shown to the curator,
  since mail does not leave dt.unr; accounts carry `must_change_password` until the holder
  changes it.
- **Breaking for no-role accounts:** the 18 metadata write policies (species, sensors,
  scanners, plots, scenarios, campaigns, processes, process parameters, events, locations)
  were open to any signed-in account and now require `contributor`. Connectors use
  `service_role` and are unaffected.
- Signup closed: `DISABLE_SIGNUP=true` in `.env.example` (XRFF-435).
- Fix: `public.trees`, `public.sensors` and `public.campaigns` reported an UPDATE/DELETE that
  RLS had skipped as successful (their INSTEAD OF triggers returned the row regardless). They
  now return no row, like the auto-updatable views.
- Migrations `20261030100000`, `20261030110000` + init `68`, `69`; tests in
  `tests/automated/e2e/access/`. On dt.unr since 2026-10-30 (the 10 tests pass there through nginx).

### 2026-10-28

**`ue_sensor_readings_latest(p_limit, p_location_id)`: the newest readings, sorted by sensor**

- New RPC returning the newest `p_limit` rows of `ue_sensor_readings` (optionally one site),
  sorted by `sensor_id`, then `timestamp_unix`, so Unreal's `DT_SensorReadings` reads one
  sensor's series at a time. `GET /rest/v1/rpc/ue_sensor_readings_latest?p_limit=100000`.
  Same 100,000 rows as `?order=timestamp.desc&limit=100000`; filter by site with
  `p_location_id`, not `?location_id=eq.` (a PostgREST filter on an RPC applies after the
  limit). An `ORDER BY` on the view was rejected: it made the all-sites fetch 24 s instead of
  0.1 s. Migration `20261028120000` + init `65-ue-sensor-readings-latest.sql`. Dev only; not
  on dt.unr.

**dt.unr brought level with dev (XRFF-491)**

- The 21 migrations from `20260916130000` to `20261023120000` were applied on dt.unr in one
  transaction, including the snake_case rename. Every entry below that says "Not on dt.unr"
  is now on dt.unr. Schema fingerprint (columns, functions, views, indexes) identical to dev.
- Data: the trees, variants, SILVA runs and growth simulations, sensors, scenarios,
  processes and audit log were copied from dev, so dt.unr now carries the 2026-10-26 canopy
  height fix and the re-run ecosense chains. Sensor readings were already identical and stay;
  `shared.processing_jobs` keeps the server's own history.

**QSM cylinder columns now ship in a fresh init**

- `61-qsm-cylinders-raw-radius-virtual.sql` (new) mirrors migration `20261006120000`:
  `trees.qsm_cylinders.raw_radius_m` and `is_virtual`, and `length_m >= 0` instead of `> 0`.
  The migration had no init mirror, so a fresh stack lacked both columns and
  `import_qsm.py` failed against it. The migration itself had also never been applied on
  dev; it is now applied on dev and dt.unr.

### 2026-10-26

**ecosense baseline: 396 canopy heights replaced by yield-table heights**

- `scripts/seed/ecosense_canopy_height_fix.sql` (new, run after the import and
  `ecosense_baseline_variant.sql`): 396 of the 1,198 measured ecosense heights were the
  canopy surface sampled at the stem, not the stem's own height. For example, small beech
  stood at 27–29 m with 5 cm stems. Their DBH is right. Each gets growpy's yield-table height
  for its DBH (`height_source` = `allometric_yield_table`), and the TLS value moves to
  `field_notes` as `tls_canopy_height_m`. The values derived from the old height (crown width
  and base, volumes, age, biomass, carbon) are cleared for the fills.
- **Keys:** location + plot + tree number, or the surveyed position for the four stems without
  a number.
- **Re-run:** guarded on the current height, so a re-run changes nothing.
- **Applied on dev, 2026-10-26,** followed by the fills and the eight ecosense SILVA chains
  (`--replace`). Not on dt.unr.

### 2026-10-23

**`ue_sensor_readings` publishes the sensor's `location_id`**

- `64-ue-sensor-readings-location.sql` / migration `20261023120000`: `s.location_id`
  appended as the last column of `public.ue_sensor_readings`, so a site fetches only its own
  readings with `?location_id=eq.<site>`. Before this, Unreal's readings fetcher took the
  newest 100,000 readings of all locations for every site. Same columns, names and types
  otherwise; `security_invoker` and the owner are unchanged.
- Unreal: the readings fetcher adds the filter; `ST_SensorReading` needs no new field.
- Applied on dev (as `supabase_admin`, the view's owner). Not on dt.unr (XRFF-491).

### 2026-10-08

**Species carry a leaf type, and `ue_trees` publishes it**

- `63-species-leaf-type.sql` / migration `20261008120000`: new column
  `shared.species.leaf_type` (`needleleaf` / `broadleaf`), filled for all 14 species, and
  appended as the last column of `public.ue_trees`. `is_deciduous` could not serve: European
  Larch is a deciduous conifer, and the Copernicus leaf-type map the Unreal forest reads
  counts it as coniferous. The species loaders upsert a fixed column list, so a lookup reload
  keeps the values; a species added later through the CSV arrives with `leaf_type` NULL.
- Unreal: `ST_Tree` needs a `leaf_type` String field before DT_Trees is re-fetched.
- Applied on dev. Not on dt.unr (XRFF-491).

**`ue_trees` has projected coordinates for every variant**

- `62-ue-trees-silva-positions.sql` / migration `20261008100000`: `original_x`,
  `original_y` and `source_crs` fall back to `position` transformed into the location's CRS
  when a row has no `position_original`. The SILVA variants are written that way, so before
  this all ten simulated years of ECOSENSE (and every MathIsle variant) returned NULL, and
  Unreal placed every simulated tree at UTM (0,0). The fallback reproduces the baseline UTM
  position of the same `tree_entity_id` to < 1e-8 m. Same columns, names and types; no
  consumer change beyond re-fetching.
- Applied on dev. Not on dt.unr: Unreal reads the dev database through JSON bundles for
  now, and moving dev to the server (XRFF-491) is a separate task.

### 2026-09-27

**The last view columns renamed to the naming convention (XRFF-485)**

- `60-view-column-names-remaining.sql` / migration `20260927100000`, in place with
  `ALTER VIEW ... RENAME COLUMN` (owner, grants and `security_invoker` kept):
  - `public.variants`: `management_regime`, `climate_pathway` → `_name`
  - `public.simulation_runs`: `base_variant` → `base_variant_name`
  - `sensor.sensor_tree_view`: `sensor_type`, `tree_species`, `tree_location` → `_name`,
    `sensor_active` → `is_sensor_active`
  - `environments.location_environment_summary`: `avg_temperature` → `avg_temperature_c`,
    `avg_humidity` → `avg_humidity_percent`, `avg_co2` → `avg_co2_ppm`
  - `public.ue_scenarios`: `climate_label` → `climate_pathway_label`
  - `public.ue_climate`: `variants`, `processes` → `variant_names`, `process_names`
  - `public.ue_sensors` and `ue_sensor_state_at()`: `linked_tree_id` → `tree_id`;
    `ue_sensors.linked_tree_entity_id` → `tree_entity_id`
  - `public.job_status`: `job_id` → `processing_job_id`
- **Breaking for two consumers.** `ST_Sensor` in Unreal reads `linked_tree_entity_id`, so
  it imports as null until the struct field is renamed. `web/jobs/index.html` reads
  `processing_job_id` now, so the page and the migration have to reach dt.unr together.
- `scripts/utils/check_naming.py` rule 9 now also sees a suffix dropped through an
  aggregate (`avg(e.avg_co2_ppm) AS avg_co2`). `KNOWN` is down to one XRFF-490 entry
  plus two computed carve-outs.

### 2026-09-22

**Naming conventions: written down correctly, two identifiers corrected, a checker added**

- `docs/database-schema.md` §7.2 described neither the case nor the number of the
  identifiers in this database — it claimed PascalCase singular tables (`Trees`,
  `SensorReadings`) and PascalCase columns (`Height_m`), where every identifier is
  lowercase snake_case and every table is plural. Its own examples contradicted its own
  rules. Rewritten to the live schema, with the units, boolean, enumerated-text and
  `public` API rules that were previously unstated (XRFF-484).
- `scripts/utils/check_naming.py`: asserts the rewritten rules against a live connection
  and exits non-zero on a **new** deviation. Existing deviations are listed against the
  issue that tracks them, so the backlog does not mask a regression. CI has been off
  workspace-wide since 2026-09-01, so run it by hand before opening a migration PR.
- `46-sensor-identifier-spelling.sql` / migration `20260922120000`:
  `sensor.SensorTreeLinks.sensortreelinkid` → `sensor_tree_link_id`. It was the only
  single-column primary key among 69 base tables not spelled `<stem>_id`. The sequence
  and the `sensorreadings_sensorid_timestamp_unique` index (which spelled `sensor_id` as
  `sensorid`) are renamed with it, and `public.sensor_tree_links` republishes the
  corrected name (XRFF-488).
- `47-growth-simulations-stand-biomass-name.sql` / migration `20260922130000`:
  `public.growth_simulations` stops aliasing `stand_biomass_tha` to `standbio_tha`. The
  other three stand aggregates were already passed through unrenamed (XRFF-485, partial).

  Both renames were cleared by the consumer grep AGENTS.md requires: neither identifier
  appears in digital-twin-dashboard, silva-connector, aquarius-connector,
  open-data-connector or any of the four Unreal projects. The remaining XRFF-485 columns
  (`linked_tree_scientificname`, `sensor_label`, `sensor_type`, `management_regime`,
  `climate_pathway`) are cached verbatim into Unreal DataTable JSON and are **not**
  changed here — they need a matching change to the row structs.

### 2026-09-16

**Sites declare their internal projected CRS**

- `29a-declare-site-crs.sql` / migration `20260916130000`: `shared.Locations.crs_epsg`
  (EPSG code, checked 1024–32767) records the one projected frame per site in which
  planimetric work is done — both research sites 32632 (WGS 84 / UTM 32N), the frame the
  surveyed positions arrive in and the engine places from. Geometry storage stays
  EPSG:4326. Seeded from `data/lookups/locations.csv` (new `CrsEpsg` column) by both
  lookup loaders and exposed on `public.locations`. Required by the Forest Digital Twin
  Schema profile's Core (one declared CRS per site). The file sorts before the `30-`/`31-`
  loaders that read the column; `11`–`29` were taken, hence the letter suffix.

**Sensor readings: hourly thinning of fast series, two redundant indexes dropped**

- `44-thin-fast-series-to-hourly.sql`: every series sampling faster than every 15 minutes
  (decided from the data, not from names) is thinned to one reading per hour — the raw point
  nearest each hour boundary, timestamp as measured, not a mean. Four Ecosense soil-temperature
  profile probes (13 depths each) and three ground probes log every 10 or 60 s; their 55 series
  were 68 % of the readings table and none is linked to a tree. `sampling_interval_seconds`
  becomes the **stored** cadence (3600 for these) and `external_metadata.native_interval_seconds`
  the logger's own. The aquarius connector applies the identical rule on ingest from the same
  day; the two must stay in step.
- `43-drop-redundant-sensorreadings-indexes.sql`: `idx_sensor_readings_sensor_timestamp`
  `(sensor_id, timestamp DESC)` and `idx_sensor_readings_sensor_id` duplicated the unique key
  `(sensor_id, timestamp)` — 28 % of the table's bytes for no query the unique index does not
  already serve.
- `45-ue-sensor-state-at-lookback-per-sensor.sql`: `ue_sensor_state_at`'s default lookback is
  now 4 × the sensor's `sampling_interval_seconds` instead of a fixed hour — unchanged for the
  15-min network, four hours for the hourly series (open-meteo weather, thinned probes), which a
  fixed hour ending a few seconds past the hour could miss entirely. Explicit `p_lookback` still
  overrides.
- 2025 sensor readings backfilled to the full year on dev and dt.unr (previously one window per
  season): 32.9 M rows, identical on both, ~2.7 M a month for ~1,050 reporting sensors; the 55
  hourly series are 194 k rows where native cadence would have been 62 M.

### 2026-09-02 → 2026-09-14 (52 commits, condensed by theme)

**Production on dt.unr.uni-freiburg.de** (`9cf0201`, `5864735`, `f8a4358`, `b105f56`, `7f31fb5`)

- First server deployment (XRFF-238): PGDATA and object storage on the NFS export,
  `STORAGE_PATH`/`PGDATA_PATH` in `.env`, `scripts/server/setup_data_dirs.py` refusing a
  soft NFS mount, a systemd drop-in so Docker waits for the mount. API published at
  `https://dt.unr.uni-freiburg.de/db/` on 443 through the dashboard's nginx.
- Kong reaches GoTrue as `dftdb-auth`, not `auth` — campus DNS resolved the short name to a
  university web host and every `/auth/v1/` call left the server for a week (XRFF-428).
- Four systemd timers replace the "no cron" gap: job runner + reaper (`scripts/runner/`),
  nightly `pg_dump` minus sensor readings (`scripts/server/dt-db-backup.*`), TLS renewal
  (in digital-twin-dashboard). `scripts/server/create-user.sh` creates an account with its
  role claim in one call (`5f9e0e1`).

**Job control plane** (`fdc96e5`, `3839a2d`, `b614ec1`, `1900ac7`, `8c46763`, `2033e99`)

- `request_job()` RPC + `public.job_status` (XRFF-347); `shared.Processes` is a readable
  workflow menu (XRFF-348); a generic runner drains `shared.ProcessingJobs` (XRFF-349);
  the open-data refreshes that need no host path are queueable (XRFF-380); `/jobs/` trigger
  page generated from `param_schema` (XRFF-423); a refused request says why (XRFF-422).
  Edge Functions are not used and never will be (XRFF-257).

**Open-data landing zones and provenance** (`612bc50`, `6a4bf9e`, `aaf35a2`, `6e7bd1f`,
`ac1b4e7`, `3a044bd`, `5f69a3b`, `7aa46e7`)

- `set_location_attributes()` and `upsert_environment()` write RPCs with
  `shared.AttributeProvenance`; a lookup refresh no longer reverts acquired site attributes;
  an unstamped write can no longer claim to be a field measurement (XRFF-400); derived
  values carry provenance and uncertainty by decision (XRFF-401); a Process Run Crate per
  recorded run (XRFF-407); `refresh_soil_aggregates()` derives annual soil means from the
  twin's own sensors; `sensor.Sensors` admits modelled series.

**Unreal Engine feed** (`f695e5a`, `16b10a5`, `6fdbe3a`)

- `ue_sensor_state_at(ts)` for the VR time slider; `ue_environments` and `ue_climate`
  (one row per period merged across datasets); Postgres memory settings tuned for NFS.

**SILVA** (`62d0bd5`, `3b20546`, `ae40dfa`, `e1fa860`)

- `trees.SimulationRuns` records run parameters (XRFF-374); the CSV round-trip and the
  `silva_input` view are gone (XRFF-351); site-condition columns exposed on
  `public.locations`; a scenario is now a point on two axes, management regime × climate
  pathway, with `scenario_code` (2026-09-14).

**Data fixes** (`bc2f46e`, `2e19262`, `bf64fd7`, `dc5b223`)

- ecosense `center_point` was 30.7 km from its own trees (XRFF-388); the 4_56 Zwisel second
  stem is seeded; `security_invoker` on four public views; the importer exits non-zero when
  any record failed.

**Docs and housekeeping** (`1e69342`, `97a1bcc`, `c041ad3`, `cad7c68`, `802fa00`)

- Root docs consolidated to `README.md` + `RUNBOOK.md`; the init-file history explained
  truthfully; workspace `data/` layout adopted; GitHub Actions CI removed (all CI is off
  workspace-wide since 2026-09-01); one meaning per level-of-detail axis (XRFF-404).

### 2026-09-01

### Fixed

- **All 40 sensors typed `barometric_pressure` were stem water potential
  probes.** Their serials are `*_StemWaterPotential`, their units `bar` and
  `MPa`, and their values run -31.19 to 0.67 -- against a type whose typical
  range is 900-1100 hPa. Not one measured atmospheric pressure. The cause was
  aquarius-connector mapping on the Aquarius `Parameter` field alone, which
  reports these as "BarPressure" because they are read through a pressure
  transducer, while the Label and Unit carry the real quantity. Migration
  `20260901140000_add_stem_water_potential` adds the missing `stem_water_potential`
  lookup row and reclassifies the 40 sensors; the connector now disambiguates on
  the series label so a re-sync will not reintroduce it. 22 of the 40 are logged
  in bar and 18 are `_in_MPa` duplicates of the same series -- both kept, since
  they are distinct Aquarius series and `sensor.Sensors.unit` tells them apart.
- `trees.GrowthSimulations.biomass_kg` and `carbon_content_kg` were NULL on all
  8,900 rows. `fill_missing_biomass.py` only ever targeted `trees.Trees`, so the
  mirrored `simulated_growth` variants there were filled while the trajectory
  table itself was not. It now runs a second pass over
  `trees.GrowthSimulations`, computing from that table's own `dbh_cm` and
  `height_m` with the same equations and fitted-range rules rather than copying
  across -- which keeps the two consistent (verified: 8,868 of 8,868 agree
  exactly) and still works for a `run_simulation.R --no-promote` run, where the
  trajectory exists with no `trees.Trees` rows to copy from.

### Added

- `stem_water_potential` in `data/lookups/sensor_types.csv` (MPa, -10 to 1;
  water potential is negative under xylem tension). 15 sensor types now.

### Notes

Two things audited and found **not** to be defects, recorded so they are not
"fixed" later by mistake:

- Three EcoSense `(plot, tree_number)` pairs -- 4/46, 4/50 and 11/4 -- carry two
  distinct trees each, not duplicated imports. Plot 4/50 holds a 10.5 m and a
  26.2 m Silver Fir about 15 m apart. The field *label* collides; both trees are
  real and neither should be deleted. Resolution belongs in the field records.
- The EcoSense import is complete: `ecosense_trees_import.csv` holds exactly
  1,495 data rows and 1,495 trees are in the database. The apparent 1,527 came
  from counting the file's comment header lines. The "1,504" figure circulating
  in older notes is wrong.

Still open, deliberately not guessed at: `age_years` is NULL on 328 measured
trees (Silver fir, Douglas fir, larch and scattered broadleaves) and
`biomass_kg` on 8, because pylometree carries no published equation for those
species. See `scripts/import/fill_missing_ages.py` for why substituting a
congener's equation is refused.

## [1.0.2] - 2026-07-29

### Security

- Purged real field-site data — `data/ecosense_250911.csv`,
  `data/mathisle_250904.csv`, `data/imports/{ecosense,mathisle}_trees_import.csv`,
  and `data/reference/ecosense_sensor_tree_map.csv` — from the entire git
  history, not just the current tree. These contained precise UTM/GPS
  coordinates of actual research plots and URLs to an internal ODK instance.
  They remain available locally as gitignored files; `link_sensors_to_trees.py`
  and the documented import commands are unaffected.
- Purged an accidentally-committed 89 MB `Miniforge3-Linux-x86_64.sh`
  installer sitting in the repo's first commit, and an unrelated
  garbage-named debris file from a historical shell-quoting accident.
- **History was rewritten on `main`, `dev`, and `feature/simple-postgres`
  (all tags re-pointed).** Existing local clones or forks should re-clone
  rather than pull/rebase.

### Removed

- `AGENTS.md` and `CLAUDE.md` from `main` — dev-workflow tooling, not
  project documentation; they now live on a `dev` branch instead.

## [1.0.1] - 2026-07-27

### Changed

- Consolidated `get_db_connection()` — duplicated across five scripts and
  drifted — into `scripts/utils/db.py`. Three copies hardcoded
  `POSTGRES_HOST = "localhost"`, silently ignoring the documented
  configurable variable; two others resolved `docker/.env` relative to
  `scripts/` instead of the repo root and never loaded credentials
  (`test_import_upload.py` exited at startup on "Environment file not
  found").
- Rebuilt `trees_import_template.csv` to the 24 columns `TEMPLATE_COLUMNS`
  actually declares (it shipped 23 and omitted `LocationName`, the
  importer's preferred resolution path, with two misaligned example rows).
  `ScenarioName` moved to `EXTRA_COLUMNS` since scenario assignment belongs
  to the seed scripts.
- Corrected "6 schemas" to 7 (`forest_floor` was added by a migration but
  never counted) in `AGENTS.md`, `README.md`, and `docs/README.md`, and
  added `forest_floor` to the pg_dump re-snapshot scope.
- README's Zenodo DOI badge switched to a static shields.io badge — the
  dynamic badge endpoint was intermittently failing GitHub's image proxy.
- CI: dropped the pip cache step from the lint job (this repo has no
  `requirements.txt`/`pyproject.toml` for it to key on; dependencies live in
  `environment.yml`).

### Removed

- Dead code: `scripts/import/archive/` (456 lines, superseded by
  `import_trees.py`) and `docker/volumes/functions/_shared/{database,retry}.ts`
  (197 lines, imported by nothing).

### Security

- **Git history rewritten (2026-07-21).** `docker/.env.backup` — tracked in
  git with real generated secrets (Postgres password, JWT signing secret,
  dashboard password, vault/crypto keys, Logflare tokens, and the Aquarius
  API credential) — has been removed from every commit, and every leaked
  secret literal has been redacted from all history, including old versions
  of `docker/.env.example` and a since-deleted `TESTING_GUIDE.md`. All
  commit hashes changed as a result.
  **If you already cloned or forked this repo, discard your local copy and
  re-clone** — pulling or merging will reintroduce the purged secrets into
  your local history.
  The Aquarius credential could not be rotated (shared university system);
  treat it as potentially exposed regardless of the history purge.
- `.gitignore` (root and `docker/`) now ignores all `.env.*` variants except
  `.env.example`, closing the gap that let `.env.backup` get committed.

### Added

- `.editorconfig` for cross-editor consistency.
- `CONTRIBUTING.md` with contribution workflow.
- `CHANGELOG.md` (this file).

### Changed

- Sanitized `docker/.env.example`: placeholder values replace previously
  committed real-looking secrets. Operators must rotate any secrets that were
  ever deployed from the old file.
- Python version requirement from `3.11.8` to `3.12`.
- `environment.yml`: Python version from `3.11.8` to `3.12`.
- `CITATION.cff`, README's citation block, and `CONTRIBUTING.md`'s issue
  tracker link now point to the public GitHub repository instead of the
  internal GitLab instance.

### Fixed

- Five broken documentation links (`docs/runbook.md`, `docs/troubleshooting.md`,
  `docs/docker/README.md`, `data/reference/README.md`) now resolve; the
  runbook's port-mapping appendix links to a real table instead of a
  never-written `infrastructure.md`.
- Removed `HANDOVER.md`, a stale internal session note whose proposed
  follow-up work (XRFF-253 through XRFF-257) is filed and completed in Linear.

## [1.0.0] - 2026-07-23

## [0.1.0] - 2025

Initial release: Supabase-based PostgreSQL + PostGIS digital twin database
with schemas for trees, sensors, pointclouds, imagery, and environments.
