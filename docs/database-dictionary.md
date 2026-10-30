# Data Dictionary

> **Generated** by `scripts/utils/generate_schema_docs.py` from the database, as of migration
> `20261030120000_close_anon_writes_and_fix_audit`. Do not edit by hand: change the schema (and its `COMMENT ON`s) with a
> migration, then regenerate. The descriptions are the comments stored in the database.
> How the schemas fit together, conventions and design notes: [database-schema.md](database-schema.md).

Every table of the seven domain schemas. The REST API exposes most of them as a view of the
same name in `public` (listed at the end); write and read through those.

| Schema | Tables | Holds |
|---|---:|---|
| [`shared`](#shared) | 31 | Sites, scenarios and forest states, species, campaigns, events, processes, jobs, audit |
| [`trees`](#trees) | 29 | Trees per forest state, stems, observations, SILVA output, tree structure, morphology lookups |
| [`sensor`](#sensor) | 5 | Sensors, their time series, units, sensor-tree links |
| [`environments`](#environments) | 1 | Climate and soil per location, scenario and period |
| [`pointclouds`](#pointclouds) | 3 | Point clouds and scanners |
| [`imagery`](#imagery) | 1 | Images |
| [`forest_floor`](#forest_floor) | 2 | Plot-level dead wood and ground vegetation surveys |

## shared

Sites, scenarios and forest states, species, campaigns, events, processes, jobs, audit

[`account_events`](#sharedaccount_events) · [`attribute_provenance`](#sharedattribute_provenance) · [`audit_log`](#sharedaudit_log) · [`audit_log_environments`](#sharedaudit_log_environments) · [`audit_log_phenology_observations`](#sharedaudit_log_phenology_observations) · [`audit_log_point_clouds`](#sharedaudit_log_point_clouds) · [`audit_log_stems`](#sharedaudit_log_stems) · [`audit_log_trees`](#sharedaudit_log_trees) · [`campaigns`](#sharedcampaigns) · [`climate_pathways`](#sharedclimate_pathways) · [`climate_zones`](#sharedclimate_zones) · [`disturbance_events`](#shareddisturbance_events) · [`disturbance_events_trees`](#shareddisturbance_events_trees) · [`locations`](#sharedlocations) · [`lookup_registry`](#sharedlookup_registry) · [`management_events`](#sharedmanagement_events) · [`management_regimes`](#sharedmanagement_regimes) · [`plots`](#sharedplots) · [`process_metrics`](#sharedprocess_metrics) · [`process_parameters`](#sharedprocess_parameters) · [`process_parameters_environments`](#sharedprocess_parameters_environments) · [`process_parameters_point_clouds`](#sharedprocess_parameters_point_clouds) · [`process_parameters_stems`](#sharedprocess_parameters_stems) · [`process_parameters_trees`](#sharedprocess_parameters_trees) · [`processes`](#sharedprocesses) · [`processing_jobs`](#sharedprocessing_jobs) · [`scenarios`](#sharedscenarios) · [`soil_types`](#sharedsoil_types) · [`species`](#sharedspecies) · [`variant_types`](#sharedvariant_types) · [`variants`](#sharedvariants)

### shared.account_events

Account creations, role changes and password resets made through public.create_account / set_account_role / reset_account_password. Written only by those functions; curators and admins can read it.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `account_event_id` | bigint |  | identity |  |  |
| `occurred_at` | timestamp with time zone |  | `now()` |  |  |
| `actor_id` | uuid | yes |  |  |  |
| `actor_email` | text | yes |  |  |  |
| `target_email` | text |  |  |  |  |
| `action` | text |  |  |  |  |
| `old_role` | text | yes |  |  |  |
| `new_role` | text | yes |  |  |  |

Constraints: `CHECK ((action = ANY (ARRAY['create'::text, 'set_role'::text, 'reset_password'::text])))`; primary key (account_event_id).

### shared.attribute_provenance

Where each value in a shared.locations column came from: one row per (location, column), replaced when the value is refreshed. Written by public.set_location_attributes in the same transaction as the value itself, so an attribute cannot be updated without saying what produced it.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `attribute_provenance_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `column_name` | character varying(64) |  |  |  | Name of the shared.locations column this row describes. Not FK-checkable; the allowed set is enforced by public.set_location_attributes, which is the only writer. |
| `process_id` | integer |  |  | `shared.processes.process_id` | shared.processes row for the source -- its name, version, licence and citation. NOT NULL: an acquired value with no registered source is exactly what this table exists to prevent. |
| `fetched_at` | timestamp with time zone |  | `now()` |  | When the value was retrieved from the source, which is not the same as when the source published it (shared.processes.publication_date) nor when the row was written. |
| `source_uri` | text | yes |  |  | Direct reference to the fetched artefact -- API request URL, DOI, or file identifier -- so a value can be traced to one retrieval, not just to a dataset. |
| `license` | character varying(100) | yes |  |  | Licence of the source value, e.g. CC-BY-4.0, Copernicus. Carried per value because this database is published and the attribution requirements travel with the data. |

Constraints: primary key (attribute_provenance_id); unique (location_id, column_name).

### shared.audit_log

Field-level change tracking with user attribution (linked via junction tables)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `audit_log_id` | bigint |  | serial |  |  |
| `field_name` | character varying(200) |  |  |  | Name of the field that was changed |
| `old_value` | text | yes |  |  | Previous value (stored as JSON text) |
| `new_value` | text | yes |  |  | New value (stored as JSON text) |
| `change_reason` | text | yes |  |  |  |
| `user_id` | character varying(200) | yes |  |  |  |
| `timestamp` | timestamp with time zone | yes | `now()` |  |  |
| `change_type` | character varying(50) | yes |  |  |  |
| `ip_address` | inet | yes |  |  |  |
| `user_agent` | text | yes |  |  |  |

Constraints: `CHECK (((change_type)::text = ANY (ARRAY[('field_update'::character varying)::text, ('bulk_update'::character varying)::text, ('revert'::character varying)::text, ('insert'::character varying)::text, ('delete'::character varying)::text])))`; primary key (audit_log_id).

### shared.audit_log_environments

Links audit log entries to environment records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `audit_log_id` | bigint |  |  | `shared.audit_log.audit_log_id` (cascade) |  |
| `environment_id` | integer |  |  | `environments.environments.environment_id` (cascade) |  |

Constraints: primary key (audit_log_id, environment_id).

### shared.audit_log_phenology_observations

Links audit log entries to phenology observation records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `audit_log_id` | bigint |  |  | `shared.audit_log.audit_log_id` (cascade) |  |
| `phenology_observation_id` | integer |  |  | `trees.phenology_observations.phenology_observation_id` (cascade) |  |

Constraints: primary key (audit_log_id, phenology_observation_id).

### shared.audit_log_point_clouds

Links audit log entries to point cloud records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `audit_log_id` | bigint |  |  | `shared.audit_log.audit_log_id` (cascade) |  |
| `point_cloud_id` | integer |  |  | `pointclouds.point_clouds.point_cloud_id` (cascade) |  |

Constraints: primary key (audit_log_id, point_cloud_id).

### shared.audit_log_stems

Links audit log entries to individual stems

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `audit_log_id` | bigint |  |  | `shared.audit_log.audit_log_id` (cascade) |  |
| `stem_id` | integer |  |  | `trees.stems.stem_id` (cascade) |  |

Constraints: primary key (audit_log_id, stem_id).

### shared.audit_log_trees

Links audit log entries to tree records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `audit_log_id` | bigint |  |  | `shared.audit_log.audit_log_id` (cascade) |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |

Constraints: primary key (audit_log_id, tree_id).

### shared.campaigns

Data collection campaigns (LiDAR flights, field inventories, sensor deployments)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `campaign_id` | integer |  | serial |  |  |
| `campaign_name` | character varying(200) |  |  |  |  |
| `campaign_type` | character varying(50) |  |  |  | Type of data collection campaign |
| `location_id` | integer | yes |  | `shared.locations.location_id` (set null) |  |
| `start_date` | date |  |  |  |  |
| `end_date` | date | yes |  |  |  |
| `description` | text | yes |  |  |  |
| `methodology` | text | yes |  |  | Description of data collection methodology used |
| `equipment` | text | yes |  |  | Equipment used (e.g., scanner model, measurement tools) |
| `personnel` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((campaign_type)::text = ANY (ARRAY[('lidar_flight'::character varying)::text, ('field_inventory'::character varying)::text, ('sensor_deployment'::character varying)::text, ('drone_survey'::character varying)::text, ('manual_update'::character varying)::text])))`; `CHECK (((end_date IS NULL) OR (end_date >= start_date)))`; primary key (campaign_id); unique (campaign_name).

### shared.climate_pathways

Climate axis of a scenario. Pathway 0 (historical) is the observed 1981-2010 climatology held constant; the others are the CMIP6 SSPs the open-data connector acquires (CHELSA temperature/precipitation, SSP CO2). Names are single tokens because they are the suffix of a scenario name.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `climate_pathway_id` | smallint |  |  |  |  |
| `climate_pathway_name` | character varying(50) |  |  |  |  |
| `label` | character varying(50) | yes |  |  |  |
| `description` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: `CHECK (((climate_pathway_id >= 0) AND (climate_pathway_id <= 9)))`; `CHECK (((climate_pathway_name)::text ~ '^[a-z][a-z0-9]*$'::text))`; primary key (climate_pathway_id); unique (climate_pathway_name).

### shared.climate_zones

Köppen climate classification zones

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `climate_zone_id` | integer |  | serial |  |  |
| `climate_zone_name` | character varying(10) |  |  |  | Köppen climate classification code (e.g., Cfb, Dfb, ET, EF, BWh) |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((climate_zone_name)::text ~ '^[A-Z][A-Za-z]{0,3}$'::text))`; primary key (climate_zone_id); unique (climate_zone_name).

### shared.disturbance_events

Natural disturbance events affecting forest areas (storms, fire, insects, etc.)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `disturbance_event_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) |  |
| `disturbance_type` | character varying(50) |  |  |  | Type of natural disturbance |
| `event_date` | date |  |  |  |  |
| `end_date` | date | yes |  |  |  |
| `severity` | character varying(20) | yes |  |  | Disturbance severity level |
| `affected_area_m2` | numeric(12,2) | yes |  |  | Estimated area affected in m² |
| `description` | text | yes |  |  |  |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK ((affected_area_m2 > (0)::numeric))`; `CHECK (((disturbance_type)::text = ANY (ARRAY[('storm'::character varying)::text, ('fire'::character varying)::text, ('insect'::character varying)::text, ('drought'::character varying)::text, ('disease'::character varying)::text, ('flood'::character varying)::text, ('frost'::character varying)::text, ('snow_damage'::character varying)::text, ('landslide'::character varying)::text, ('other'::character varying)::text])))`; `CHECK (((end_date IS NULL) OR (end_date >= event_date)))`; `CHECK (((severity)::text = ANY (ARRAY[('low'::character varying)::text, ('moderate'::character varying)::text, ('high'::character varying)::text, ('severe'::character varying)::text])))`; primary key (disturbance_event_id).

### shared.disturbance_events_trees

Links disturbance events to affected individual trees with damage assessment

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `disturbance_event_id` | integer |  |  | `shared.disturbance_events.disturbance_event_id` (cascade) |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `damage_level` | character varying(50) | yes |  |  | Level of damage to individual tree |
| `notes` | text | yes |  |  |  |

Constraints: `CHECK (((damage_level)::text = ANY (ARRAY[('none'::character varying)::text, ('light'::character varying)::text, ('moderate'::character varying)::text, ('severe'::character varying)::text, ('destroyed'::character varying)::text])))`; primary key (disturbance_event_id, tree_id).

### shared.locations

Forest plot locations with spatial boundaries and environmental context

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `location_id` | integer |  | serial |  |  |
| `location_name` | character varying(200) |  |  |  |  |
| `boundary` | geometry(Polygon,4326) | yes |  |  | PostGIS polygon defining plot boundaries in WGS84 |
| `center_point` | geometry(Point,4326) | yes |  |  | PostGIS point for plot center in WGS84 |
| `description` | text | yes |  |  |  |
| `elevation_m` | numeric(8,2) | yes |  |  |  |
| `slope_deg` | numeric(5,2) | yes |  |  |  |
| `aspect` | character varying(3) | yes |  |  |  |
| `soil_type_id` | integer | yes |  | `shared.soil_types.soil_type_id` |  |
| `climate_zone_id` | integer | yes |  | `shared.climate_zones.climate_zone_id` |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |
| `forest_growth_region` | character varying(16) | yes |  |  | German forest growth region code (Wuchsgebiet.Wuchsbezirk), e.g. '99.73.11'. Keys SILVA/silvaR's internal climate table, which supplies temperature, precipitation and vegetation-period length for the site. Derived once by point-in-polygon against the Thuenen Wuchsbezirke 2020 layer; see silva-connector/docs/site-conditions.md for provenance. |
| `soil_moistness` | smallint | yes |  |  | SILVA soil moisture class, 1-9 (1 = very dry, 5 = fresh, 9 = very wet). Not derivable from soil_type_id: shared.soil_types holds USDA soil orders (Alfisol, Spodosol, ...), which describe pedogenesis rather than water supply. Requires a site survey value. |
| `soil_nutrient_supply` | smallint | yes |  |  | SILVA soil nutrient supply class, 1-5 (1 = very low, 5 = very high). Like soil_moistness, independent of the USDA order in soil_type_id and requires a site survey value. |
| `crs_epsg` | integer | yes |  |  | Declared internal projected CRS of the site as an EPSG code (e.g. 32632 = WGS 84 / UTM zone 32N). The one frame in which per-site planimetric work (engine placement, terrain, distances) is done; every input in another frame is transformed on ingestion and its source frame retained on the record (trees.trees.source_crs / position_original). Geometry columns stay EPSG:4326. Seeded from data/lookups/locations.csv. |

Constraints: `CHECK (((aspect)::text = ANY (ARRAY[('N'::character varying)::text, ('NE'::character varying)::text, ('E'::character varying)::text, ('SE'::character varying)::text, ('S'::character varying)::text, ('SW'::character varying)::text, ('W'::character varying)::text, ('NW'::character varying)::text])))`; `CHECK (((crs_epsg IS NULL) OR ((crs_epsg >= 1024) AND (crs_epsg <= 32767))))`; `CHECK (((slope_deg >= (0)::numeric) AND (slope_deg <= (90)::numeric)))`; `CHECK (((soil_moistness IS NULL) OR ((soil_moistness >= 1) AND (soil_moistness <= 9))))`; `CHECK (((soil_nutrient_supply IS NULL) OR ((soil_nutrient_supply >= 1) AND (soil_nutrient_supply <= 5))))`; primary key (location_id); unique (location_name).

### shared.lookup_registry

Drives shared.refresh_lookup. csv_columns lists the TARGET column for each CSV column, in file order -- the CSV header is ignored, so a header whose spelling predates a column rename does not silently misload. natural_key is the column the upsert conflicts on.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `logical_key` | text |  |  |  |  |
| `schema_name` | text |  |  |  |  |
| `table_name` | text |  |  |  |  |
| `csv_file` | text |  |  |  |  |
| `csv_columns` | text[] |  |  |  | Target column per CSV column, in file order. Length must equal the CSV's column count; the loader asserts this rather than trusting it. |
| `natural_key` | text |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (logical_key).

### shared.management_events

Forest management activities (thinning, planting, harvesting, etc.)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `management_event_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) |  |
| `event_type` | character varying(50) |  |  |  | Type of management activity |
| `event_date` | date |  |  |  |  |
| `end_date` | date | yes |  |  |  |
| `description` | text | yes |  |  |  |
| `affected_area_m2` | numeric(12,2) | yes |  |  | Area affected by the management activity in m² |
| `performed_by` | character varying(200) | yes |  |  |  |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK ((affected_area_m2 > (0)::numeric))`; `CHECK (((end_date IS NULL) OR (end_date >= event_date)))`; `CHECK (((event_type)::text = ANY (ARRAY[('thinning'::character varying)::text, ('planting'::character varying)::text, ('harvesting'::character varying)::text, ('pruning'::character varying)::text, ('fertilization'::character varying)::text, ('prescribed_burn'::character varying)::text, ('salvage_logging'::character varying)::text, ('site_preparation'::character varying)::text, ('other'::character varying)::text])))`; primary key (management_event_id).

### shared.management_regimes

Management axis of a scenario. Small integer id + snake_case name, so Unreal can sort on the number and label with the text. Regime 0 (none) marks scenarios that hold acquired data only, never trees.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `management_regime_id` | smallint |  |  |  |  |
| `management_regime_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `silva_rules` | jsonb | yes |  |  | silvaR thinning preset: {"removal_method","max_removal_fraction","rules":[{species, thinning_type, guide_curve, metric, intervention, crop_trees_per_ha, n_competitors, target_dbh_cm, target_probability}]}. Species by scientific name or "all". NULL = no management. silva-connector turns this into silva_thinning_regime(). |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: `CHECK (((management_regime_id >= 0) AND (management_regime_id <= 99)))`; `CHECK (((management_regime_name)::text ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$'::text))`; primary key (management_regime_id); unique (management_regime_name).

### shared.plots

Sub-plot divisions within locations for detailed research grids

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `plot_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_name` | character varying(200) |  |  |  | Plot identifier, unique within a location |
| `plot_number` | integer | yes |  |  | Numeric plot identifier for ordering |
| `area_m2` | numeric(12,2) | yes |  |  | Plot area in square meters |
| `boundary` | geometry(Polygon,4326) | yes |  |  | PostGIS polygon defining plot boundaries in WGS84 |
| `center_point` | geometry(Point,4326) | yes |  |  |  |
| `description` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK ((area_m2 > (0)::numeric))`; primary key (plot_id); unique (location_id, plot_name).

### shared.process_metrics

Published performance metrics for processes

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_metric_id` | integer |  | serial |  |  |
| `process_id` | integer |  |  | `shared.processes.process_id` (cascade) |  |
| `metric_name` | character varying(200) |  |  |  |  |
| `metric_value` | numeric(10,6) | yes |  |  |  |
| `source` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: `CHECK (((metric_name)::text = ANY (ARRAY[('accuracy'::character varying)::text, ('precision'::character varying)::text, ('recall'::character varying)::text, ('f1_score'::character varying)::text, ('rmse'::character varying)::text, ('mae'::character varying)::text, ('r_squared'::character varying)::text])))`; primary key (process_metric_id).

### shared.process_parameters

Process parameters used for variants (linked via junction tables)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_parameter_id` | integer |  | serial |  |  |
| `parameter_name` | character varying(200) |  |  |  |  |
| `parameter_value` | text |  |  |  | Parameter value as text (cast based on data_type) |
| `data_type` | character varying(50) | yes |  |  |  |
| `description` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: `CHECK (((data_type)::text = ANY (ARRAY[('float'::character varying)::text, ('int'::character varying)::text, ('string'::character varying)::text, ('boolean'::character varying)::text, ('json'::character varying)::text])))`; primary key (process_parameter_id).

### shared.process_parameters_environments

Links process parameters to environment records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_parameter_id` | integer |  |  | `shared.process_parameters.process_parameter_id` (cascade) |  |
| `environment_id` | integer |  |  | `environments.environments.environment_id` (cascade) |  |

Constraints: primary key (process_parameter_id, environment_id).

### shared.process_parameters_point_clouds

Links process parameters to point cloud records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_parameter_id` | integer |  |  | `shared.process_parameters.process_parameter_id` (cascade) |  |
| `point_cloud_id` | integer |  |  | `pointclouds.point_clouds.point_cloud_id` (cascade) |  |

Constraints: primary key (process_parameter_id, point_cloud_id).

### shared.process_parameters_stems

Links process parameters to individual stems

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_parameter_id` | integer |  |  | `shared.process_parameters.process_parameter_id` (cascade) |  |
| `stem_id` | integer |  |  | `trees.stems.stem_id` (cascade) |  |

Constraints: primary key (process_parameter_id, stem_id).

### shared.process_parameters_trees

Links process parameters to tree records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_parameter_id` | integer |  |  | `shared.process_parameters.process_parameter_id` (cascade) |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |

Constraints: primary key (process_parameter_id, tree_id).

### shared.processes

Processing algorithms and methods with versioning and academic attribution

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `process_id` | integer |  | serial |  |  |
| `process_name` | character varying(200) |  |  |  | Process name (e.g., LiDAR_Segmentation, Tree_Detection, Growth_Simulation) |
| `algorithm_name` | character varying(200) | yes |  |  | Algorithm used (e.g., RandomForest, DeepLearning, RulesBased) |
| `version` | character varying(50) | yes |  |  |  |
| `description` | text | yes |  |  |  |
| `author` | character varying(200) | yes |  |  |  |
| `publication_date` | date | yes |  |  |  |
| `citation` | text | yes |  |  |  |
| `category` | character varying(100) | yes |  |  | What kind of step this is. `acquisition` (added 2026-09-02) is a fetch from an external system -- Aquarius, ERA5, SoilGrids -- as opposed to a computation over data already held. |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `param_schema` | jsonb | yes |  |  | JSON Schema for the workflow's run_params. Properties marked "readOnly": true are recorded by the run rather than offered by the job menu -- web/jobs skips them when building its form, and emit_ro_crate includes them in the reproducibility record. Every key a run writes into run_params must be declared here; tests/automated/e2e/provenance/test_ro_crate.py asserts it. |
| `workflow_key` | character varying(50) | yes |  |  | Short machine name of a runnable workflow -- the string request_job() takes and the runner matches against its local workflows.toml. NULL means the row is provenance only: it records what produced some data and cannot be requested. UNIQUE, so exactly one row (one version) is runnable per workflow; on a version bump the key is moved to the new row, not copied. |

Constraints: `CHECK (((category)::text = ANY (ARRAY['detection'::text, 'classification'::text, 'simulation'::text, 'analysis'::text, 'aggregation'::text, 'acquisition'::text])))`; `CHECK (((param_schema IS NULL) OR (jsonb_typeof(param_schema) = 'object'::text)))`; `CHECK (((workflow_key IS NULL) OR (param_schema IS NOT NULL)))`; primary key (process_id); unique (process_name, version); unique (workflow_key).

### shared.processing_jobs

Tracks external processing jobs and compute workflows

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `processing_job_id` | integer |  | serial |  |  |
| `external_job_id` | character varying(200) | yes |  |  | Idempotency key supplied by the caller. Already UNIQUE, and adopted as the deduplication key: enqueueing the same key twice yields one job, so a repeated request from VR or a double-clicked button cannot start the same run twice. NULL for jobs that do not need deduplication. |
| `workflow_name` | character varying(200) |  |  |  |  |
| `workflow_version` | character varying(50) | yes |  |  |  |
| `status` | character varying(50) |  | `'pending'::character varying` |  | Job status: pending, running, completed, failed |
| `submitted_at` | timestamp with time zone |  | `now()` |  |  |
| `completed_at` | timestamp with time zone | yes |  |  |  |
| `input_data` | jsonb | yes |  |  | JSON representation of input parameters and data references |
| `output_data` | jsonb | yes |  |  | JSON representation of output data references and results |
| `error_message` | text | yes |  |  |  |
| `submitted_by` | character varying(200) | yes |  |  |  |
| `started_at` | timestamp with time zone | yes |  |  | When a runner claimed the job and began executing it. NULL while pending. |
| `claimed_by` | character varying(200) | yes |  |  | Identity of the runner instance holding the job (host and process), so `runner reap` can tell a live claim from an abandoned one. |
| `attempts` | integer |  | `0` |  | How many times the job has been claimed. Incremented on claim, so an abandoned job that is reaped and re-queued is not retried forever. |
| `max_attempts` | integer |  | `1` |  | Claim budget. DEFAULT 1 = no automatic retry, which is the v1 policy: these workflows fail for parameter reasons far more often than transient ones. |
| `next_attempt_at` | timestamp with time zone | yes |  |  | Earliest time a runner may claim the job. NULL means immediately. Set by `runner reap` to hold a recovered job back. |

Constraints: `CHECK (((attempts >= 0) AND (max_attempts >= 1)))`; `CHECK (((completed_at IS NULL) OR (completed_at >= submitted_at)))`; `CHECK (((started_at IS NULL) OR (started_at >= submitted_at)))`; `CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('running'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text])))`; primary key (processing_job_id); unique (external_job_id).

### shared.scenarios

One scenario per (location, management regime, climate pathway). scenario_code = regime*10 + pathway is the numeric key, scenario_name the text one; the name follows <pathway> | <regime> | <regime>_<pathway> and the axes are derived from it on insert when not given. Regime 0 scenarios hold acquired data only; the rest own a baseline and a variant timeline (Location -> Scenario -> Variant).

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `scenario_id` | integer |  | serial |  |  |
| `scenario_name` | character varying(200) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) | The site this management regime belongs to — top of the Location -> Scenario -> Variant hierarchy. |
| `management_regime_id` | smallint |  |  | `shared.management_regimes.management_regime_id` | Management axis -> shared.management_regimes. Filled from scenario_name by trigger when omitted (grammar: <pathway> \| <regime> \| <regime>_<pathway>). |
| `climate_pathway_id` | smallint |  |  | `shared.climate_pathways.climate_pathway_id` | Climate axis -> shared.climate_pathways. 0 = historical. Filled from scenario_name by trigger when omitted. |
| `scenario_code` | integer | yes | generated: `((management_regime_id * 10) + climate_pathway_id)` |  | management_regime_id * 10 + climate_pathway_id, generated. The sort key Unreal uses: tens digit = regime, units digit = pathway. natural_growth = 10, crop_tree_thinning_ssp585 = 23, a bare ssp370 climate bucket = 2. |

Constraints: primary key (scenario_id); unique (location_id, management_regime_id, climate_pathway_id); unique (location_id, scenario_name).

### shared.soil_types

USDA soil classification reference table

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `soil_type_id` | integer |  | serial |  |  |
| `soil_type_name` | character varying(100) |  |  |  | USDA soil classification type |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((soil_type_name)::text = ANY (ARRAY[('Alfisol'::character varying)::text, ('Andisol'::character varying)::text, ('Aridisol'::character varying)::text, ('Entisol'::character varying)::text, ('Gelisol'::character varying)::text, ('Histosol'::character varying)::text, ('Inceptisol'::character varying)::text, ('Mollisol'::character varying)::text, ('Oxisol'::character varying)::text, ('Spodosol'::character varying)::text, ('Ultisol'::character varying)::text, ('Vertisol'::character varying)::text])))`; primary key (soil_type_id); unique (soil_type_name).

### shared.species

Tree species reference with growth characteristics

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `species_id` | integer |  | serial |  |  |
| `common_name` | character varying(200) | yes |  |  |  |
| `scientific_name` | character varying(200) |  |  |  |  |
| `max_height_m` | numeric(6,2) | yes |  |  | Maximum typical height in meters |
| `max_dbh_cm` | numeric(6,2) | yes |  |  | Maximum typical diameter at breast height in centimeters |
| `typical_lifespan_years` | integer | yes |  |  | Typical lifespan in years |
| `growth_rate` | character varying(20) | yes |  |  | Relative growth rate (very_slow, slow, moderate, fast, very_fast) |
| `shade_tolerance` | character varying(20) | yes |  |  | Shade tolerance level (very_low, low, moderate, high, very_high) |
| `is_deciduous` | boolean | yes |  |  | Whether species is deciduous (true) or evergreen (false), NULL if unknown |
| `gbif_key` | integer | yes |  |  |  |
| `gbif_accepted_name` | character varying(200) | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `leaf_type` | character varying(20) | yes |  |  | Leaf habit: needleleaf (conifers, larch included) or broadleaf. Independent of is_deciduous. Matches the Copernicus Dominant Leaf Type classes. |

Constraints: `CHECK (((growth_rate)::text = ANY (ARRAY[('very_slow'::character varying)::text, ('slow'::character varying)::text, ('moderate'::character varying)::text, ('fast'::character varying)::text, ('very_fast'::character varying)::text])))`; `CHECK (((leaf_type)::text = ANY ((ARRAY['needleleaf'::character varying, 'broadleaf'::character varying])::text[])))`; `CHECK (((shade_tolerance)::text = ANY (ARRAY[('very_low'::character varying)::text, ('low'::character varying)::text, ('moderate'::character varying)::text, ('high'::character varying)::text, ('very_high'::character varying)::text])))`; primary key (species_id); unique (scientific_name).

### shared.variant_types

Types of data variants (original, processed, simulated, etc.)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `variant_type_id` | integer |  | serial |  |  |
| `variant_type_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((variant_type_name)::text = ANY (ARRAY[('original'::character varying)::text, ('processed'::character varying)::text, ('manual'::character varying)::text, ('simulated_growth'::character varying)::text, ('user_input'::character varying)::text, ('sensor_derived'::character varying)::text, ('model_output'::character varying)::text, ('repeat_measurement'::character varying)::text])))`; primary key (variant_type_id); unique (variant_type_name).

### shared.variants

Forest state snapshots — each row is one time step at one location within one scenario. variant_id groups all trees at that state. Use for UE time-travel switching.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `variant_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) | The forest site this variant belongs to — top level of the Location → Scenario → Variant hierarchy |
| `scenario_id` | integer |  |  | `shared.scenarios.scenario_id` (cascade) | The scenario (set of assumptions) this variant belongs to |
| `variant_type_id` | integer |  |  | `shared.variant_types.variant_type_id` | Type of data in this variant (original field measurement, simulated growth, etc.) |
| `variant_name` | character varying(200) |  |  |  |  |
| `simulation_year` | integer | yes |  |  | Calendar year this forest state represents |
| `time_delta_yrs` | numeric(8,2) | yes |  |  | Years elapsed from the scenario baseline |
| `sort_order` | integer |  | `0` |  | Display order for time-slider UI in UE (0=earliest) |
| `description` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `parent_variant_id` | integer | yes |  | `shared.variants.variant_id` (set null) | The variant this state developed from (baseline has none). Encodes the timeline/intervention lineage within a scenario. |

Constraints: `CHECK (((simulation_year >= 1900) AND (simulation_year <= 2300)))`; `CHECK ((time_delta_yrs >= (0)::numeric))`; primary key (variant_id); unique (location_id, scenario_id, variant_name).

## trees

Trees per forest state, stems, observations, SILVA output, tree structure, morphology lookups

[`axis_structures`](#treesaxis_structures) · [`bark_characteristics`](#treesbark_characteristics) · [`branch_elongation_habits`](#treesbranch_elongation_habits) · [`branching_patterns`](#treesbranching_patterns) · [`crown_architectures`](#treescrown_architectures) · [`crown_classes`](#treescrown_classes) · [`crown_foliage_profiles`](#treescrown_foliage_profiles) · [`crown_shapes`](#treescrown_shapes) · [`damage_agents`](#treesdamage_agents) · [`data_source_types`](#treesdata_source_types) · [`geometric_crown_solids`](#treesgeometric_crown_solids) · [`growth_forms`](#treesgrowth_forms) · [`growth_orientations`](#treesgrowth_orientations) · [`growth_simulations`](#treesgrowth_simulations) · [`phanerophyte_height_classes`](#treesphanerophyte_height_classes) · [`phenology_observations`](#treesphenology_observations) · [`qsm_cylinders`](#treesqsm_cylinders) · [`qsms`](#treesqsms) · [`root_system_types`](#treesroot_system_types) · [`roots`](#treesroots) · [`shoot_elongation_types`](#treesshoot_elongation_types) · [`simulation_runs`](#treessimulation_runs) · [`stems`](#treesstems) · [`straightness_types`](#treesstraightness_types) · [`taper_types`](#treestaper_types) · [`tree_graph_edges`](#treestree_graph_edges) · [`tree_part_types`](#treestree_part_types) · [`tree_status`](#treestree_status) · [`trees`](#treestrees)

### trees.axis_structures

Main axis configuration (single leader vs polycormic)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `axis_structure_id` | integer |  | serial |  |  |
| `axis_structure_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (axis_structure_id); unique (axis_structure_name).

### trees.bark_characteristics

Bark texture and appearance classifications

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `bark_characteristic_id` | integer |  | serial |  |  |
| `bark_characteristic_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `typical_species` | text | yes |  |  |  |

Constraints: primary key (bark_characteristic_id); unique (bark_characteristic_name).

### trees.branch_elongation_habits

Branch elongation patterns determining crown shape (acrotony, mesotony, basitony)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `elongation_habit_id` | integer |  | serial |  |  |
| `elongation_habit_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (elongation_habit_id); unique (elongation_habit_name).

### trees.branching_patterns

Branch arrangement patterns on stems

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `branching_pattern_id` | integer |  | serial |  |  |
| `branching_pattern_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (branching_pattern_id); unique (branching_pattern_name).

### trees.crown_architectures

Crown architecture classification (excurrent, decurrent, etc.)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `crown_architecture_id` | integer |  | serial |  |  |
| `crown_architecture_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `typical_examples` | text | yes |  |  | Example tree types with this architecture |

Constraints: primary key (crown_architecture_id); unique (crown_architecture_name).

### trees.crown_classes

Crown social/competitive position classification (FIA CCLCD / NEON canopyPosition analog)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `crown_class_id` | integer |  | serial |  |  |
| `crown_class_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((crown_class_name)::text = ANY (ARRAY[('dominant'::character varying)::text, ('co_dominant'::character varying)::text, ('intermediate'::character varying)::text, ('overtopped'::character varying)::text, ('open_grown'::character varying)::text])))`; primary key (crown_class_id); unique (crown_class_name).

### trees.crown_foliage_profiles

Crown leaf area density/distribution (not per-leaf geometry -- QSM is wood-only) for growpy/PVE procedural leaf instancing

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `crown_foliage_profile_id` | bigint |  | serial |  |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) |  |
| `distribution_type` | text |  |  |  | beta (Le Port et al. 2000) \| johnson_sb (Jerez et al. 2005) \| uniform (no species-specific shape known yet -- not a placeholder pretending to be fitted data) |
| `vertical_params` | numeric[] | yes |  |  | Distribution shape parameters (e.g. Beta's two shape params); NULL when distribution_type = uniform |
| `horizontal_params` | numeric[] | yes |  |  |  |
| `total_leaf_area_m2` | numeric(10,2) | yes |  |  |  |
| `source` | text |  |  |  | species_literature_default = literature parameters for this species; fitted = fit to our own data; measured = destructive/allometric measurement |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK ((distribution_type = ANY (ARRAY['beta'::text, 'johnson_sb'::text, 'uniform'::text])))`; `CHECK ((source = ANY (ARRAY['species_literature_default'::text, 'fitted'::text, 'measured'::text])))`; `CHECK ((total_leaf_area_m2 >= (0)::numeric))`; primary key (crown_foliage_profile_id).

### trees.crown_shapes

Common crown shape descriptions (pyramidal, conical, globose, etc.)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `crown_shape_id` | integer |  | serial |  |  |
| `crown_shape_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (crown_shape_id); unique (crown_shape_name).

### trees.damage_agents

Cause of tree damage, decline, or mortality (FIA AGENTCD analog)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `damage_agent_id` | integer |  | serial |  |  |
| `damage_agent_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((damage_agent_name)::text = ANY (ARRAY[('none'::character varying)::text, ('insect'::character varying)::text, ('disease'::character varying)::text, ('fire'::character varying)::text, ('wind'::character varying)::text, ('snow_ice'::character varying)::text, ('drought'::character varying)::text, ('mechanical'::character varying)::text, ('animal'::character varying)::text, ('human_activity'::character varying)::text, ('competition'::character varying)::text, ('unknown'::character varying)::text])))`; primary key (damage_agent_id); unique (damage_agent_name).

### trees.data_source_types

How tree measurement data was collected or generated

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `data_source_type_id` | integer |  | serial |  |  |
| `data_source_type_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (data_source_type_id); unique (data_source_type_name).

### trees.geometric_crown_solids

Geometric crown shape models for simulation (area, volume, drag calculations)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `geometric_crown_solid_id` | integer |  | serial |  |  |
| `geometric_crown_solid_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `relative_lateral_area` | numeric(4,2) | yes |  |  | Relative frontal/lateral area (1.0 = cylinder baseline) |
| `relative_volume` | numeric(4,2) | yes |  |  | Relative crown volume (1.0 = cylinder baseline) |
| `relative_drag` | numeric(4,2) | yes |  |  | Relative wind drag coefficient (1.0 = cylinder baseline) |

Constraints: `CHECK (((relative_drag >= (0)::numeric) AND (relative_drag <= (1)::numeric)))`; `CHECK (((relative_lateral_area >= (0)::numeric) AND (relative_lateral_area <= (1)::numeric)))`; `CHECK (((relative_volume >= (0)::numeric) AND (relative_volume <= (1)::numeric)))`; primary key (geometric_crown_solid_id); unique (geometric_crown_solid_name).

### trees.growth_forms

General growth form classification (dendroid, arborescent, etc.)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `growth_form_id` | integer |  | serial |  |  |
| `growth_form_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (growth_form_id); unique (growth_form_name).

### trees.growth_orientations

Shoot growth orientation (orthotropic=vertical, plagiotrophic=horizontal)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `growth_orientation_id` | integer |  | serial |  |  |
| `growth_orientation_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (growth_orientation_id); unique (growth_orientation_name).

### trees.growth_simulations

Per-tree forest growth projections from SILVA, FVS, iLand, or manual estimation. One row per (run_id, tree_entity_id, projection_year). run_id groups all rows produced by a single simulation run.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `growth_simulation_id` | bigint |  | serial |  |  |
| `simulation_run_id` | uuid |  |  | `trees.simulation_runs.simulation_run_id` (cascade) | UUID identifying a single simulation run. All rows with the same run_id belong to one simulator execution and can be compared as a complete forest state. |
| `tree_entity_id` | uuid |  |  |  | Stable UUID of the physical tree (cross-variant identity from trees.trees.tree_entity_id). |
| `base_tree_id` | integer | yes |  | `trees.trees.tree_id` (set null) | trees.trees row (tree_id) used as the simulation input (baseline measurement). |
| `location_id` | integer | yes |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) |  |
| `scenario_id` | integer | yes |  | `shared.scenarios.scenario_id` (set null) |  |
| `species_id` | integer | yes |  | `shared.species.species_id` (set null) |  |
| `simulator_name` | character varying(100) |  |  |  |  |
| `simulator_version` | character varying(50) | yes |  |  |  |
| `projection_year` | integer |  |  |  | Calendar year this projection describes. |
| `time_delta_yrs` | numeric(8,2) | yes |  |  |  |
| `height_m` | numeric(6,2) | yes |  |  |  |
| `dbh_cm` | numeric(6,2) | yes |  |  |  |
| `basal_area_m2` | numeric(8,4) | yes |  |  |  |
| `crown_width_m` | numeric(6,2) | yes |  |  |  |
| `crown_base_height_m` | numeric(6,2) | yes |  |  |  |
| `volume_m3` | numeric(10,3) | yes |  |  |  |
| `biomass_kg` | numeric(12,2) | yes |  |  |  |
| `carbon_content_kg` | numeric(12,2) | yes |  |  |  |
| `health_score` | numeric(3,2) | yes |  |  |  |
| `is_mortality` | boolean |  | `false` |  | True if this tree dies in this projection time step. |
| `stand_basal_area_m2ha` | numeric(8,4) | yes |  |  | Stand-level basal area (m²/ha) — same value repeated for all trees in this run_id+Year. |
| `stand_volume_m3ha` | numeric(10,3) | yes |  |  |  |
| `stand_biomass_tha` | numeric(10,3) | yes |  |  |  |
| `stand_stem_count_ha` | integer | yes |  |  |  |
| `created_at` | timestamp with time zone |  | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((basal_area_m2 IS NULL) OR (basal_area_m2 >= (0)::numeric)))`; `CHECK (((biomass_kg IS NULL) OR (biomass_kg >= (0)::numeric)))`; `CHECK (((carbon_content_kg IS NULL) OR (carbon_content_kg >= (0)::numeric)))`; `CHECK (((crown_base_height_m IS NULL) OR (crown_base_height_m >= (0)::numeric)))`; `CHECK (((crown_base_height_m IS NULL) OR (height_m IS NULL) OR (crown_base_height_m <= height_m)))`; `CHECK (((crown_width_m IS NULL) OR (crown_width_m >= (0)::numeric)))`; `CHECK (((dbh_cm IS NULL) OR (dbh_cm > (0)::numeric)))`; `CHECK (((health_score IS NULL) OR ((health_score >= (0)::numeric) AND (health_score <= (1)::numeric))))`; `CHECK (((height_m IS NULL) OR (height_m > (0)::numeric)))`; `CHECK (((projection_year >= 1900) AND (projection_year <= 2300)))`; `CHECK (((simulator_name)::text = ANY (ARRAY[('SILVA'::character varying)::text, ('FVS'::character varying)::text, ('iLand'::character varying)::text, ('manual'::character varying)::text, ('other'::character varying)::text])))`; `CHECK (((stand_basal_area_m2ha IS NULL) OR (stand_basal_area_m2ha >= (0)::numeric)))`; `CHECK (((stand_biomass_tha IS NULL) OR (stand_biomass_tha >= (0)::numeric)))`; `CHECK (((stand_stem_count_ha IS NULL) OR (stand_stem_count_ha >= 0)))`; `CHECK (((stand_volume_m3ha IS NULL) OR (stand_volume_m3ha >= (0)::numeric)))`; `CHECK (((volume_m3 IS NULL) OR (volume_m3 >= (0)::numeric)))`; primary key (growth_simulation_id).

### trees.phanerophyte_height_classes

Tree height classification (mega/meso/micro-phanerophyte)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `height_class_id` | integer |  | serial |  |  |
| `height_class_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `min_height_m` | numeric(6,2) | yes |  |  | Minimum height for this class (NULL = no lower bound) |
| `max_height_m` | numeric(6,2) | yes |  |  | Maximum height for this class (NULL = no upper bound) |

Constraints: `CHECK ((max_height_m > (0)::numeric))`; `CHECK ((min_height_m >= (0)::numeric))`; `CHECK (((min_height_m IS NULL) OR (max_height_m IS NULL) OR (min_height_m < max_height_m)))`; primary key (height_class_id); unique (height_class_name).

### trees.phenology_observations

Tree phenology observations tracking seasonal development phases

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `phenology_observation_id` | integer |  | serial |  |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `observation_date` | date |  |  |  |  |
| `phenophase_type` | character varying(50) |  |  |  | Type of phenological phase being observed |
| `phenophase_status` | character varying(50) | yes |  |  | Current status of the phenophase |
| `intensity_percent` | numeric(5,2) | yes |  |  | Intensity of the phenophase (0-100%) |
| `observer` | character varying(200) | yes |  |  |  |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((intensity_percent >= (0)::numeric) AND (intensity_percent <= (100)::numeric)))`; `CHECK (((phenophase_status)::text = ANY (ARRAY[('not_started'::character varying)::text, ('beginning'::character varying)::text, ('intermediate'::character varying)::text, ('peak'::character varying)::text, ('ending'::character varying)::text, ('completed'::character varying)::text])))`; `CHECK (((phenophase_type)::text = ANY (ARRAY[('bud_break'::character varying)::text, ('leaf_out'::character varying)::text, ('flowering'::character varying)::text, ('fruit_set'::character varying)::text, ('leaf_color'::character varying)::text, ('leaf_fall'::character varying)::text, ('dormancy'::character varying)::text])))`; primary key (phenology_observation_id).

### trees.qsm_cylinders

QSM cylinder geometry, Real Twig / rTwig standardised column set -- ~10^3-10^4 rows per tree

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `qsm_cylinder_id` | bigint |  | serial |  |  |
| `qsm_id` | bigint |  |  | `trees.qsms.qsm_id` (cascade) |  |
| `cylinder_index` | integer |  |  |  | Cylinder id within the QSM, as published (rTwig 'id') |
| `parent_cylinder_index` | integer | yes |  |  | Parent cylinder_index, self-referenced by index (not FK) to match the source files -- 0 for the base cylinder, per rTwig convention |
| `start_point` | geometry(PointZ) | yes |  |  | Cylinder base coordinate in the QSM's local frame (trees.qsms.local_crs / origin_position) |
| `axis` | double precision[] | yes |  |  | Unit vector [x,y,z] from cylinder base to top |
| `length_m` | numeric(8,4) |  |  |  | Cylinder length; 0 is allowed because TreeQSM output contains zero-length cylinders that other cylinders hang off |
| `radius_m` | numeric(8,5) |  |  |  | Radius as the source delivered it: radius-corrected where the source corrects (see trees.qsms.is_corrected), raw otherwise |
| `branch_index` | integer | yes |  |  | Axis (branch) id from 1, by the lab's single axis rule (the child with the longer supported subtree continues the axis), not the producing tool's own id |
| `branch_order` | integer | yes |  |  | Axis order, 0 = trunk, by the same single axis rule |
| `branch_position` | integer | yes |  |  | Position along the axis, from 1 at its base |
| `part_type_id` | smallint | yes |  | `trees.tree_part_types.part_type_id` | CityGML part semantic (trunk/branch/twig) -- see trees.tree_part_types; assignment rule documented in this migration's header |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `raw_radius_m` | numeric(8,5) | yes |  |  | Radius of the fitted cylinder before any correction (rTwig raw_radius, TreeQSM UnmodRadius); NULL when the source does not keep it |
| `is_virtual` | boolean |  | `false` |  | Cylinder added to bridge a gap in the point cloud (TreeQSM added, TreeML addedVirtual), not fitted to points |

Constraints: `CHECK (((axis IS NULL) OR (array_length(axis, 1) = 3)))`; `CHECK ((branch_order >= 0))`; `CHECK ((length_m >= (0)::numeric))`; `CHECK ((radius_m >= (0)::numeric))`; `CHECK (((raw_radius_m IS NULL) OR (raw_radius_m >= (0)::numeric)))`; primary key (qsm_cylinder_id); unique (qsm_id, cylinder_index).

### trees.qsms

QSM (Quantitative Structure Model) reconstructions -- one row per reconstruction, several per physical tree possible

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `qsm_id` | bigint |  | serial |  |  |
| `tree_entity_id` | uuid |  |  |  | Stable physical-tree identity (trees.trees.tree_entity_id) -- groups QSMs of the same tree across scans/tools/parameter sets |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `point_cloud_id` | integer | yes |  | `pointclouds.point_clouds.point_cloud_id` (set null) |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) |  |
| `lod` | smallint | yes |  |  | CityGML representation level of detail, 0-4: 0 = 2D footprint, 1 = 2.5D height/root depth, 2 = crown + trunk as separable volumes, 3 = 3D morphological structure, 4 = internal detail plus structured semantics. This is the ONLY meaning of "LoD" in this database. It is not a rendering resolution and not a count of which parts exist -- for those see the render-resolution and structural-detail axes in docs/level-of-detail-vocabulary.md (XRFF-404). |
| `local_crs` | text | yes |  |  | CRS of the cylinder coordinates in trees.qsmcylinders, or the literal value 'local' if none |
| `origin_position` | geometry(PointZ,4326) | yes |  |  | Georeferences the local cylinder coordinate frame |
| `cylinder_count` | integer | yes |  |  |  |
| `total_volume_m3` | numeric(10,3) | yes |  |  | QSM-derived total volume -- kept separate from the allometric trees.trees.volume_m3 |
| `trunk_volume_m3` | numeric(10,3) | yes |  |  |  |
| `branch_volume_m3` | numeric(10,3) | yes |  |  |  |
| `dbh_qsm_cm` | numeric(6,2) | yes |  |  | DBH as derived from the QSM -- kept separate from trees.stems.dbh_cm to allow validating one against the other |
| `height_qsm_m` | numeric(6,2) | yes |  |  |  |
| `crown_area_qsm_m2` | numeric(10,2) | yes |  |  |  |
| `is_corrected` | boolean |  | `false` |  | Raw TreeQSM (false) vs Real Twig radius-corrected (true) |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK ((branch_volume_m3 >= (0)::numeric))`; `CHECK ((crown_area_qsm_m2 >= (0)::numeric))`; `CHECK ((cylinder_count >= 0))`; `CHECK (((dbh_qsm_cm > (0)::numeric) AND (dbh_qsm_cm <= (1000)::numeric)))`; `CHECK (((height_qsm_m > (0)::numeric) AND (height_qsm_m <= (200)::numeric)))`; `CHECK (((lod >= 0) AND (lod <= 4)))`; `CHECK ((total_volume_m3 >= (0)::numeric))`; `CHECK ((trunk_volume_m3 >= (0)::numeric))`; primary key (qsm_id).

### trees.root_system_types

Root system morphology lookup (Koestler et al. 1968 classification; Guerrero Inigez 2017 LoD-matched geometric models)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `root_system_type_id` | smallint |  | serial |  |  |
| `root_system_type_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((root_system_type_name)::text = ANY (ARRAY[('tap_root'::character varying)::text, ('heart_root'::character varying)::text, ('lateral_root'::character varying)::text])))`; primary key (root_system_type_id); unique (root_system_type_name).

### trees.roots

Root system classification/geometry (Guerrero Inigez 2017 LoD-matched models) -- classifiable from species now, geometrized later

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `root_id` | bigint |  | serial |  |  |
| `tree_entity_id` | uuid |  |  |  | Stable physical-tree identity (trees.trees.tree_entity_id) |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `root_system_type_id` | smallint |  |  | `trees.root_system_types.root_system_type_id` |  |
| `lod` | smallint | yes |  |  | CityGML representation level of detail, 0-4; same ladder as trees.qsms.lod. Read together with geometry_class: implicit = a prototype instanced with a transform (a generic asset placed on this tree), explicit = this tree's own geometry. The number alone cannot tell those apart. See docs/level-of-detail-vocabulary.md (XRFF-404). |
| `geometry_class` | text | yes |  |  | implicit = prototype instanced with a transform, so LoD2-LoD3 at best; explicit = this tree's own measured geometry, which is what qualifies a row as LoD4. Always interpreted alongside lod, never on its own. See docs/citygml-qsm-mapping.md §5. |
| `root_depth_m` | numeric(6,2) | yes |  |  |  |
| `root_spread_radius_m` | numeric(6,2) | yes |  |  |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) |  |
| `source` | text |  |  |  | species_default = classified from silvics literature, no measurement; field_observed = seen but not measured; measured = geometry actually captured |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((geometry_class IS NULL) OR (geometry_class = ANY (ARRAY['implicit'::text, 'explicit'::text]))))`; `CHECK (((lod >= 0) AND (lod <= 4)))`; `CHECK ((root_depth_m >= (0)::numeric))`; `CHECK ((root_spread_radius_m >= (0)::numeric))`; `CHECK ((source = ANY (ARRAY['species_default'::text, 'field_observed'::text, 'measured'::text])))`; primary key (root_id).

### trees.shoot_elongation_types

Shoot elongation classification (long, short, spur shoots)

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `shoot_elongation_type_id` | integer |  | serial |  |  |
| `shoot_elongation_type_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (shoot_elongation_type_id); unique (shoot_elongation_type_name).

### trees.simulation_runs

One row per forest growth simulation run: what was simulated, by which simulator, and with which parameters. trees.growth_simulations holds the per-tree result rows of a run and references this table by run_id.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `simulation_run_id` | uuid |  |  |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `scenario_id` | integer | yes |  | `shared.scenarios.scenario_id` (set null) |  |
| `base_variant_id` | integer | yes |  | `shared.variants.variant_id` (set null) | shared.variants row the run was projected forward from. The reproducibility anchor: variant names are reused and deleted by --replace, so the reference is stored, not the name. |
| `base_year` | integer | yes |  |  | Calendar year of the base variant (year zero). First projected year = base_year + one simulator period. |
| `simulator_name` | character varying(100) |  |  |  |  |
| `simulator_version` | character varying(50) | yes |  |  |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) | shared.processes row the run registered itself under (algorithm, version, citation). |
| `horizon_years` | integer | yes |  |  | Projection horizon in years, as requested (silva-connector: --years, a multiple of 5). |
| `seed` | integer | yes |  |  | Random seed. The one parameter that makes two otherwise identical runs differ, and the reason this table exists. |
| `is_mortality_enabled` | boolean | yes |  |  | True if the simulator was allowed to kill trees during the run. |
| `is_promoted` | boolean | yes |  |  | True if the run was promoted to the shared.variants chain UE reads. False for a comparison-only run (silva-connector --no-promote). |
| `run_params` | jsonb |  | `'{}'::jsonb` |  | Simulator-specific parameters as named keys, e.g. {"competition": "sf_polygon", "variant_prefix": "silva", "replace": true}. Named parameters only -- never a command line. An absent key on a run predating 2026-09-02 means the value was not recorded, not that it was unset. |
| `created_at` | timestamp with time zone |  | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((base_year IS NULL) OR ((base_year >= 1900) AND (base_year <= 2300))))`; `CHECK (((horizon_years IS NULL) OR (horizon_years >= 0)))`; `CHECK ((jsonb_typeof(run_params) = 'object'::text))`; `CHECK (((simulator_name)::text = ANY (ARRAY['SILVA'::text, 'FVS'::text, 'iLand'::text, 'manual'::text, 'other'::text])))`; primary key (simulation_run_id).

### trees.stems

Individual stem measurements for multi-stem trees

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `stem_id` | integer |  | serial |  |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `stem_number` | integer |  |  |  | Stem number (1=main stem, 2+=secondary stems) |
| `taper_type_id` | integer | yes |  | `trees.taper_types.taper_type_id` |  |
| `straightness_type_id` | integer | yes |  | `trees.straightness_types.straightness_type_id` |  |
| `dbh_cm` | numeric(6,2) | yes |  |  | Diameter at breast height (1.3m) in centimeters |
| `taper_ratio` | numeric(4,3) | yes |  |  | Ratio of top diameter to bottom diameter |
| `sweep_cm_per_m` | numeric(5,2) | yes |  |  | Maximum horizontal deviation per meter of height |
| `stem_height_m` | numeric(6,2) | yes |  |  |  |
| `stem_volume_m3` | numeric(10,3) | yes |  |  |  |
| `bark_thickness_mm` | numeric(5,2) | yes |  |  |  |
| `wood_density_kg_m3` | numeric(6,2) | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |

Constraints: `CHECK (((bark_thickness_mm >= (0)::numeric) AND (bark_thickness_mm <= (200)::numeric)))`; `CHECK (((dbh_cm > (0)::numeric) AND (dbh_cm <= (1000)::numeric)))`; `CHECK (((stem_height_m > (0)::numeric) AND (stem_height_m <= (200)::numeric)))`; `CHECK ((stem_number >= 1))`; `CHECK ((stem_volume_m3 >= (0)::numeric))`; `CHECK ((sweep_cm_per_m >= (0)::numeric))`; `CHECK (((taper_ratio >= (0)::numeric) AND (taper_ratio <= (1)::numeric)))`; `CHECK (((wood_density_kg_m3 >= (100)::numeric) AND (wood_density_kg_m3 <= (2000)::numeric)))`; primary key (stem_id); unique (tree_id, stem_number).

### trees.straightness_types

Stem straightness classifications

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `straightness_type_id` | integer |  | serial |  |  |
| `straightness_type_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `deviation_angle_min_deg` | numeric(5,2) | yes |  |  |  |
| `deviation_angle_max_deg` | numeric(5,2) | yes |  |  |  |

Constraints: `CHECK (((deviation_angle_max_deg >= (0)::numeric) AND (deviation_angle_max_deg <= (90)::numeric)))`; `CHECK (((deviation_angle_min_deg >= (0)::numeric) AND (deviation_angle_min_deg <= (90)::numeric)))`; `CHECK ((deviation_angle_min_deg <= deviation_angle_max_deg))`; primary key (straightness_type_id); unique (straightness_type_name).

### trees.taper_types

Stem taper form classifications

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `taper_type_id` | integer |  | serial |  |  |
| `taper_type_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `typical_taper_ratio_min` | numeric(4,3) | yes |  |  | Minimum typical taper ratio (diameter at top / diameter at bottom) |
| `typical_taper_ratio_max` | numeric(4,3) | yes |  |  |  |

Constraints: `CHECK (((typical_taper_ratio_max >= (0)::numeric) AND (typical_taper_ratio_max <= (1)::numeric)))`; `CHECK (((typical_taper_ratio_min >= (0)::numeric) AND (typical_taper_ratio_min <= (1)::numeric)))`; `CHECK ((typical_taper_ratio_min <= typical_taper_ratio_max))`; primary key (taper_type_id); unique (taper_type_name).

### trees.tree_graph_edges

QSM topology edges whose type deviates from the trees.qsmcylinders parent-chain default ('observed'); see this migration's header for the observed/synthetic/derived distinction

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `tree_graph_edge_id` | bigint |  | serial |  |  |
| `qsm_id` | bigint |  |  | `trees.qsms.qsm_id` (cascade) |  |
| `from_cylinder_index` | integer |  |  |  | Parent cylinder_index -- the CityGML Edge's first Node |
| `to_cylinder_index` | integer |  |  |  | Child cylinder_index -- the CityGML Edge's second Node |
| `edge_type` | text |  |  |  | observed = measured by the source; synthetic = the source itself flagged this as inferred; derived = we added/overrode it ourselves |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: `CHECK ((edge_type = ANY (ARRAY['observed'::text, 'synthetic'::text, 'derived'::text])))`; primary key (tree_graph_edge_id); unique (qsm_id, from_cylinder_index, to_cylinder_index).

### trees.tree_part_types

CityGML tree feature-class lookup (Ambarwari et al. 2024) -- join point for a future CityGML ADE

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `part_type_id` | smallint |  | serial |  |  |
| `part_type_name` | character varying(50) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((part_type_name)::text = ANY (ARRAY[('root'::character varying)::text, ('trunk'::character varying)::text, ('branch'::character varying)::text, ('twig'::character varying)::text, ('leaf'::character varying)::text, ('crown'::character varying)::text])))`; primary key (part_type_id); unique (part_type_name).

### trees.tree_status

Tree health and status classification

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `tree_status_id` | integer |  | serial |  |  |
| `tree_status_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: `CHECK (((tree_status_name)::text = ANY (ARRAY[('healthy'::character varying)::text, ('stressed'::character varying)::text, ('declining'::character varying)::text, ('dead'::character varying)::text, ('harvested'::character varying)::text, ('missing'::character varying)::text, ('downed'::character varying)::text, ('broken'::character varying)::text])))`; primary key (tree_status_id); unique (tree_status_name).

### trees.trees

Tree measurement and simulation records with spatial positions

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `tree_id` | integer |  | serial |  | Unique row identifier for this tree record |
| `tree_entity_id` | uuid | yes | `gen_random_uuid()` |  | Persistent UUID identifying the physical tree across all variants |
| `variant_id` | integer | yes |  | `shared.variants.variant_id` (set null) | Forest state group — all trees sharing this variant_id belong to the same time step within a scenario. Use for UE time-travel switching. |
| `parent_tree_id` | integer | yes |  | `trees.trees.tree_id` (set null) | Parent tree record for tracking growth or modifications |
| `point_cloud_id` | integer | yes |  | `pointclouds.point_clouds.point_cloud_id` (set null) | Source point cloud if tree was detected from LiDAR |
| `campaign_id` | integer | yes |  | `shared.campaigns.campaign_id` (set null) | Data collection campaign this measurement belongs to |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) | Sub-plot within the location where tree is located |
| `scenario_id` | integer | yes |  | `shared.scenarios.scenario_id` (set null) |  |
| `variant_type_id` | integer |  |  | `shared.variant_types.variant_type_id` |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) |  |
| `species_id` | integer | yes |  | `shared.species.species_id` (set null) |  |
| `tree_status_id` | integer | yes |  | `trees.tree_status.tree_status_id` |  |
| `branching_pattern_id` | integer | yes |  | `trees.branching_patterns.branching_pattern_id` |  |
| `bark_characteristic_id` | integer | yes |  | `trees.bark_characteristics.bark_characteristic_id` |  |
| `measurement_date` | date | yes |  |  | Actual date of field measurement (may differ from created_at) |
| `data_source_type_id` | integer | yes |  | `trees.data_source_types.data_source_type_id` (set null) | FK to trees.data_source_types — how the data was collected or generated |
| `height_m` | numeric(6,2) | yes |  |  |  |
| `height_source` | character varying(50) | yes |  |  | How height_m was arrived at. NULL means unrecorded -- it is not a claim that the height was measured. Values in use: 'measured' (field instrument), 'allometric_pylometree' (H-D model fill, see scripts/import/fill_missing_heights.py), 'simulated_silva' (SILVA projection, see silva-connector). Pair with data_source_type_id, which records how the tree record as a whole was produced, and process_id, which identifies the run. |
| `crown_width_m` | numeric(6,2) | yes |  |  |  |
| `crown_base_height_m` | numeric(6,2) | yes |  |  |  |
| `crown_boundary` | geometry(Polygon,4326) | yes |  |  | PostGIS polygon defining crown extent |
| `crown_offset_x_m` | numeric(5,2) | yes |  |  | Crown center offset from trunk position (X/East-West in meters) |
| `crown_offset_y_m` | numeric(5,2) | yes |  |  | Crown center offset from trunk position (Y/North-South in meters) |
| `volume_m3` | numeric(10,3) | yes |  |  |  |
| `position` | geometry(Point,4326) |  |  |  | PostGIS point for tree location in WGS84 |
| `position_original` | geometry | yes |  |  | Original coordinates in source CRS before WGS84 transformation |
| `source_crs` | integer | yes |  |  | EPSG code of original coordinate reference system for position_original |
| `lean_angle_deg` | numeric(5,2) | yes |  |  |  |
| `lean_direction_azimuth` | integer | yes |  |  |  |
| `time_delta_yrs` | numeric(8,2) | yes |  |  | Time elapsed since parent variant (for growth simulations) |
| `age_years` | integer | yes |  |  |  |
| `health_score` | numeric(3,2) | yes |  |  | Tree health assessment score (0=dead, 1=optimal) |
| `biomass_kg` | numeric(12,2) | yes |  |  |  |
| `carbon_content_kg` | numeric(12,2) | yes |  |  |  |
| `species_confidence` | numeric(3,2) | yes |  |  | Confidence in species identification (0-1) |
| `position_confidence` | numeric(3,2) | yes |  |  | Confidence in position accuracy (0-1) |
| `height_confidence` | numeric(3,2) | yes |  |  | Confidence in height measurement (0-1) |
| `status_change_date` | date | yes |  |  | Date when tree status changed (e.g., mortality date) |
| `tree_number` | integer | yes |  |  | Local tree identifier within the location/plot (e.g., 62 in ecosense plot 4, or 367 in mathisle) |
| `field_notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |
| `height_class_id` | integer | yes |  | `trees.phanerophyte_height_classes.height_class_id` | Phanerophyte height classification |
| `crown_architecture_id` | integer | yes |  | `trees.crown_architectures.crown_architecture_id` | Crown architecture type (excurrent, decurrent, etc.) |
| `elongation_habit_id` | integer | yes |  | `trees.branch_elongation_habits.elongation_habit_id` | Branch elongation pattern (acrotony, mesotony, basitony) |
| `growth_orientation_id` | integer | yes |  | `trees.growth_orientations.growth_orientation_id` | Predominant growth orientation (orthotropic/plagiotrophic) |
| `shoot_elongation_type_id` | integer | yes |  | `trees.shoot_elongation_types.shoot_elongation_type_id` | Typical shoot elongation type |
| `crown_shape_id` | integer | yes |  | `trees.crown_shapes.crown_shape_id` | Observed crown shape |
| `geometric_crown_solid_id` | integer | yes |  | `trees.geometric_crown_solids.geometric_crown_solid_id` | Geometric model for crown volume/drag calculations |
| `axis_structure_id` | integer | yes |  | `trees.axis_structures.axis_structure_id` | Main axis structure (single leader/polycormic) |
| `growth_form_id` | integer | yes |  | `trees.growth_forms.growth_form_id` | General growth form classification |
| `live_crown_ratio` | numeric(4,3) | yes | generated: `CASE WHEN ((height_m IS NOT NULL) AND (height_m > (0)::numeric) AND (crown_base_height_m IS NOT NULL)) THEN ((height_m - crown_base_height_m) / height_m) ELSE NULL::numeric END` |  | Computed ratio of live crown height to total tree height |
| `crown_class_id` | integer | yes |  | `trees.crown_classes.crown_class_id` | Crown competitive/social position (dominant/co_dominant/intermediate/overtopped/open_grown) |
| `damage_agent_id` | integer | yes |  | `trees.damage_agents.damage_agent_id` | Primary agent responsible for observed damage or decline, if any |
| `defoliation_percent` | numeric(5,2) | yes |  |  | ICP Forests-style defoliation assessment (0-100%, in 5% steps by convention) |
| `discolouration_percent` | numeric(5,2) | yes |  |  | ICP Forests-style foliage discolouration assessment (0-100%) |
| `crown_transparency_percent` | numeric(5,2) | yes |  |  | ICP Forests-style crown transparency assessment (0-100%) |
| `sensor_ref` | character varying(100) | yes |  |  | Source-agnostic reference identifying the sensor cluster installed on this tree. Matches the prefix of sensor.sensors.serial_number, so all of a tree's sensors resolve from it. For the current Ecosense data this value is the external provider's name prefix (e.g. Beech_Mixed_8), but the column carries no provider semantics. NULL for non-instrumented trees. |

Constraints: `CHECK (((age_years >= 0) AND (age_years <= 5000)))`; `CHECK ((biomass_kg >= (0)::numeric))`; `CHECK ((carbon_content_kg >= (0)::numeric))`; `CHECK ((crown_base_height_m >= (0)::numeric))`; `CHECK (((crown_base_height_m IS NULL) OR (crown_base_height_m <= height_m)))`; `CHECK (((crown_transparency_percent >= (0)::numeric) AND (crown_transparency_percent <= (100)::numeric)))`; `CHECK (((crown_width_m >= (0)::numeric) AND (crown_width_m <= (100)::numeric)))`; `CHECK (((defoliation_percent >= (0)::numeric) AND (defoliation_percent <= (100)::numeric)))`; `CHECK (((discolouration_percent >= (0)::numeric) AND (discolouration_percent <= (100)::numeric)))`; `CHECK (((health_score >= (0)::numeric) AND (health_score <= (1)::numeric)))`; `CHECK (((height_confidence >= (0)::numeric) AND (height_confidence <= (1)::numeric)))`; `CHECK (((height_m > (0)::numeric) AND (height_m <= (200)::numeric)))`; `CHECK (((lean_angle_deg >= (0)::numeric) AND (lean_angle_deg <= (90)::numeric)))`; `CHECK (((lean_direction_azimuth >= 0) AND (lean_direction_azimuth < 360)))`; `CHECK (((position_confidence >= (0)::numeric) AND (position_confidence <= (1)::numeric)))`; `CHECK (((species_confidence >= (0)::numeric) AND (species_confidence <= (1)::numeric)))`; `CHECK ((volume_m3 >= (0)::numeric))`; primary key (tree_id).

## sensor

Sensors, their time series, units, sensor-tree links

[`sensor_readings`](#sensorsensor_readings) · [`sensor_tree_links`](#sensorsensor_tree_links) · [`sensor_types`](#sensorsensor_types) · [`sensors`](#sensorsensors) · [`units`](#sensorunits)

### sensor.sensor_readings

Time-series environmental sensor measurements

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `sensor_reading_id` | bigint |  | serial |  |  |
| `sensor_id` | integer |  |  | `sensor.sensors.sensor_id` (cascade) |  |
| `timestamp` | timestamp with time zone |  |  |  |  |
| `value` | numeric(12,4) |  |  |  |  |
| `quality` | character varying(50) | yes |  |  | Data quality flag (good, suspect, bad, missing, calibration) |
| `scenario_id` | integer | yes |  | `shared.scenarios.scenario_id` (set null) | NULL for real readings, references scenario for simulated data |
| `battery_voltage_v` | numeric(4,2) | yes |  |  |  |
| `signal_strength` | numeric(6,2) | yes |  |  | Wireless signal strength in dBm |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: `CHECK (((quality)::text = ANY (ARRAY[('good'::character varying)::text, ('suspect'::character varying)::text, ('bad'::character varying)::text, ('missing'::character varying)::text, ('calibration'::character varying)::text])))`; primary key (sensor_reading_id); unique (sensor_id, timestamp).

### sensor.sensor_tree_links

Links sensors to specific tree records

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `sensor_tree_link_id` | integer |  | serial |  | Surrogate key. Renamed from sensortreelinkid in XRFF-488 -- it was the only primary key in the database not spelled <stem>_id. |
| `sensor_id` | integer |  |  | `sensor.sensors.sensor_id` (cascade) |  |
| `tree_id` | integer |  |  | `trees.trees.tree_id` (cascade) |  |
| `description` | text | yes |  |  |  |
| `start_date` | date | yes |  |  |  |
| `end_date` | date | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |

Constraints: primary key (sensor_tree_link_id); unique (sensor_id, tree_id).

### sensor.sensor_types

Environmental sensor type classifications

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `sensor_type_id` | integer |  | serial |  |  |
| `sensor_type_name` | character varying(100) |  |  |  |  |
| `description` | text | yes |  |  |  |
| `typical_unit` | character varying(50) | yes |  | `sensor.units.unit_name` | Default unit for this sensor type, from sensor.units. NULL where the type has no single natural unit. |
| `typical_range_min` | numeric(12,4) | yes |  |  |  |
| `typical_range_max` | numeric(12,4) | yes |  |  |  |

Constraints: `CHECK (((typical_range_min IS NULL) OR (typical_range_max IS NULL) OR (typical_range_min <= typical_range_max)))`; primary key (sensor_type_id); unique (sensor_type_name).

### sensor.sensors

Sensors and the series they produce, physical or modelled. Most rows are physical installations with an instrument, a serial number and a position. Rows whose `source` names a model or reanalysis (e.g. 'open-meteo') are virtual: one series per location and quantity, no hardware, `serial_number` NULL and no entry in sensor.sensor_tree_links. Discriminate on `source`, never on `sensor_type_id` -- the types are quantities, shared by both kinds.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `sensor_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `sensor_type_id` | integer |  |  | `sensor.sensor_types.sensor_type_id` |  |
| `campaign_id` | integer | yes |  | `shared.campaigns.campaign_id` (set null) | Deployment campaign this sensor was installed during |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) | Named monitoring sub-area (plot) within the location, e.g. douglas_fir_plot. Populated from the location identifier of the external sensor sync; the site is location_id. |
| `sensor_model` | character varying(200) |  |  |  |  |
| `serial_number` | character varying(100) | yes |  |  |  |
| `position` | geometry(Point,4326) |  |  |  | PostGIS point for sensor location in WGS84 |
| `position_original` | geometry | yes |  |  | Original coordinates in source CRS before WGS84 transformation |
| `source_crs` | integer | yes |  |  | EPSG code of original coordinate reference system for position_original |
| `installation_date` | timestamp with time zone |  | `now()` |  |  |
| `installation_height_m` | numeric(5,2) | yes |  |  | Height of sensor installation above ground in meters |
| `decommission_date` | timestamp with time zone | yes |  |  |  |
| `calibration_date` | timestamp with time zone | yes |  |  |  |
| `next_calibration_date` | timestamp with time zone | yes |  |  |  |
| `sampling_interval_seconds` | integer |  |  |  | Frequency of sensor measurements in seconds |
| `unit` | character varying(50) | yes |  | `sensor.units.unit_name` | Canonical unit of this sensor's readings, from sensor.units. ASCII with _ as the divisor; render sensor.units.unit_display instead of this value. |
| `min_value` | numeric(12,4) | yes |  |  |  |
| `max_value` | numeric(12,4) | yes |  |  |  |
| `accuracy` | numeric(8,4) | yes |  |  |  |
| `battery_level_percent` | numeric(5,2) | yes |  |  |  |
| `is_active` | boolean | yes | `true` |  | Whether sensor is currently collecting data |
| `maintenance_notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |
| `source` | text | yes |  |  | External system this sensor's data comes from (e.g. 'aquarius'). One of many possible providers. |
| `external_id` | character varying(200) | yes |  |  | Unique identifier for this sensor within its source system (see source). |
| `external_metadata` | jsonb | yes | `'{}'::jsonb` |  | Additional source-specific metadata (raw payload from the provider). |

Constraints: `CHECK (((battery_level_percent >= (0)::numeric) AND (battery_level_percent <= (100)::numeric)))`; `CHECK (((decommission_date IS NULL) OR (decommission_date >= installation_date)))`; `CHECK ((installation_height_m >= (0)::numeric))`; `CHECK (((min_value IS NULL) OR (max_value IS NULL) OR (min_value <= max_value)))`; `CHECK ((sampling_interval_seconds > 0))`; primary key (sensor_id); unique (external_id).

### sensor.units

Canonical physical units for sensor.sensors.unit and sensor.sensor_types.typical_unit. unit_name is ASCII with _ as the divisor so it survives JSON, CSV, R and Unreal DataTable round trips; unit_display is the symbol to render.

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `unit_id` | integer |  | serial |  |  |
| `unit_name` | character varying(32) |  |  |  |  |
| `unit_display` | character varying(32) |  |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (unit_id); unique (unit_name).

## environments

Climate and soil per location, scenario and period

[`environments`](#environmentsenvironments)

### environments.environments

Environmental condition variants derived from sensors, models, or user input

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `environment_id` | integer |  | serial |  | Unique identifier for this environment record |
| `parent_environment_id` | integer | yes |  | `environments.environments.environment_id` (set null) | Parent environment for tracking environmental modifications |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `scenario_id` | integer | yes |  | `shared.scenarios.scenario_id` (set null) |  |
| `variant_type_id` | integer |  |  | `shared.variant_types.variant_type_id` |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) |  |
| `variant_name` | character varying(300) |  |  |  |  |
| `start_date` | timestamp with time zone | yes |  |  | Start of environmental measurement period |
| `end_date` | timestamp with time zone | yes |  |  | End of environmental measurement period (NULL for ongoing) |
| `avg_temperature_c` | numeric(6,2) | yes |  |  |  |
| `avg_humidity_percent` | numeric(5,2) | yes |  |  |  |
| `total_precipitation_mm` | numeric(8,2) | yes |  |  |  |
| `avg_global_radiation_w_m2` | numeric(8,2) | yes |  |  | Average global radiation in W/m² |
| `avg_co2_ppm` | numeric(7,2) | yes |  |  |  |
| `avg_wind_speed_ms` | numeric(6,2) | yes |  |  |  |
| `dominant_wind_direction_deg` | numeric(5,2) | yes |  |  |  |
| `avg_soil_moisture_percent` | numeric(5,2) | yes |  |  |  |
| `avg_soil_temperature_c` | numeric(6,2) | yes |  |  |  |
| `soil_ph` | numeric(4,2) | yes |  |  |  |
| `nutrient_nitrogen_mg_kg` | numeric(8,2) | yes |  |  |  |
| `nutrient_phosphorus_mg_kg` | numeric(8,2) | yes |  |  |  |
| `nutrient_potassium_mg_kg` | numeric(8,2) | yes |  |  |  |
| `stress_factor` | numeric(3,2) | yes |  |  | Environmental stress index (0=optimal, 1=severe stress) |
| `description` | text | yes |  |  |  |
| `research_notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((avg_co2_ppm >= (200)::numeric) AND (avg_co2_ppm <= (2000)::numeric)))`; `CHECK ((avg_global_radiation_w_m2 >= (0)::numeric))`; `CHECK (((avg_humidity_percent >= (0)::numeric) AND (avg_humidity_percent <= (100)::numeric)))`; `CHECK (((avg_soil_moisture_percent >= (0)::numeric) AND (avg_soil_moisture_percent <= (100)::numeric)))`; `CHECK (((avg_soil_temperature_c >= ('-20'::integer)::numeric) AND (avg_soil_temperature_c <= (40)::numeric)))`; `CHECK (((avg_temperature_c >= ('-50'::integer)::numeric) AND (avg_temperature_c <= (60)::numeric)))`; `CHECK (((avg_wind_speed_ms >= (0)::numeric) AND (avg_wind_speed_ms <= (100)::numeric)))`; `CHECK (((dominant_wind_direction_deg >= (0)::numeric) AND (dominant_wind_direction_deg < (360)::numeric)))`; `CHECK (((end_date IS NULL) OR (start_date IS NULL) OR (end_date >= start_date)))`; `CHECK ((nutrient_nitrogen_mg_kg >= (0)::numeric))`; `CHECK ((nutrient_phosphorus_mg_kg >= (0)::numeric))`; `CHECK ((nutrient_potassium_mg_kg >= (0)::numeric))`; `CHECK (((soil_ph >= (3)::numeric) AND (soil_ph <= (10)::numeric)))`; `CHECK (((stress_factor >= (0)::numeric) AND (stress_factor <= (1)::numeric)))`; `CHECK ((total_precipitation_mm >= (0)::numeric))`; primary key (environment_id).

## pointclouds

Point clouds and scanners

[`point_clouds`](#pointcloudspoint_clouds) · [`scanner_types`](#pointcloudsscanner_types) · [`scanners`](#pointcloudsscanners)

### pointclouds.point_clouds

LiDAR point cloud variants - original scans and processed results

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `point_cloud_id` | integer |  | serial |  | Unique identifier for this point cloud record |
| `parent_point_cloud_id` | integer | yes |  | `pointclouds.point_clouds.point_cloud_id` (set null) | Parent point cloud for processing lineage tracking |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `scenario_id` | integer | yes |  | `shared.scenarios.scenario_id` (set null) |  |
| `variant_type_id` | integer |  |  | `shared.variant_types.variant_type_id` |  |
| `process_id` | integer | yes |  | `shared.processes.process_id` (set null) |  |
| `campaign_id` | integer | yes |  | `shared.campaigns.campaign_id` (set null) | Data collection campaign this scan belongs to |
| `scanner_id` | integer | yes |  | `pointclouds.scanners.scanner_id` (set null) | Physical scanner hardware used for this scan |
| `variant_name` | character varying(300) |  |  |  |  |
| `scan_date` | timestamp with time zone | yes |  |  |  |
| `sensor_model` | character varying(200) | yes |  |  |  |
| `source_crs` | integer | yes |  |  | EPSG code of original coordinate reference system |
| `platform_type` | character varying(50) | yes |  |  | Scanning platform: terrestrial, aerial, mobile, UAV |
| `scan_bounds` | geometry(Polygon,4326) | yes |  |  | PostGIS polygon defining point cloud coverage area in WGS84 |
| `file_path` | text |  |  |  | S3 URI to point cloud file (e.g., s3://bucket-name/path/file.las) |
| `flight_altitude_m` | numeric(8,2) | yes |  |  | Flight altitude above ground in meters (for aerial/UAV) |
| `flight_speed_ms` | numeric(6,2) | yes |  |  | Platform speed during scanning in m/s |
| `scan_angle_deg` | numeric(5,2) | yes |  |  | Scanner field of view angle in degrees |
| `overlap_percent` | numeric(5,2) | yes |  |  | Swath overlap percentage (for aerial scans) |
| `point_count` | bigint | yes |  |  |  |
| `point_density_per_m2` | numeric(10,2) | yes |  |  | Average point density in points per square meter |
| `file_size_mb` | numeric(12,2) | yes |  |  |  |
| `processing_status` | character varying(50) | yes |  |  | NULL for original scans, status for processed variants |
| `processing_progress` | numeric(5,2) | yes |  |  | Processing completion percentage (0-100) |
| `error_message` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK ((file_path ~ '^s3://[a-z0-9][a-z0-9\-]*[a-z0-9]/.*\.(las|laz|ply)$'::text))`; `CHECK ((file_size_mb >= (0)::numeric))`; `CHECK ((flight_altitude_m > (0)::numeric))`; `CHECK ((flight_speed_ms >= (0)::numeric))`; `CHECK (((overlap_percent >= (0)::numeric) AND (overlap_percent <= (100)::numeric)))`; `CHECK (((platform_type)::text = ANY (ARRAY[('terrestrial'::character varying)::text, ('aerial'::character varying)::text, ('mobile'::character varying)::text, ('UAV'::character varying)::text])))`; `CHECK ((point_count >= 0))`; `CHECK ((point_density_per_m2 >= (0)::numeric))`; `CHECK (((processing_progress >= (0)::numeric) AND (processing_progress <= (100)::numeric)))`; `CHECK (((processing_status)::text = ANY (ARRAY[('pending'::character varying)::text, ('processing'::character varying)::text, ('completed'::character varying)::text, ('failed'::character varying)::text, ('cancelled'::character varying)::text])))`; `CHECK (((scan_angle_deg >= (0)::numeric) AND (scan_angle_deg <= (360)::numeric)))`; primary key (point_cloud_id).

### pointclouds.scanner_types

LiDAR scanner type classifications and manufacturers

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `scanner_type_id` | integer |  | serial |  |  |
| `scanner_type_name` | character varying(100) |  |  |  | Scanner type name (e.g., Terrestrial_TLS, Aerial_ALS, Mobile_MLS, UAV_ULS) |
| `manufacturer` | character varying(200) | yes |  |  |  |
| `description` | text | yes |  |  |  |

Constraints: primary key (scanner_type_id); unique (scanner_type_name).

### pointclouds.scanners

Individual LiDAR scanner hardware instances

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `scanner_id` | integer |  | serial |  |  |
| `scanner_type_id` | integer |  |  | `pointclouds.scanner_types.scanner_type_id` |  |
| `serial_number` | character varying(100) | yes |  |  | Unique hardware serial number |
| `acquisition_date` | date | yes |  |  | Date scanner was acquired |
| `calibration_date` | date | yes |  |  | Last calibration date |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |

Constraints: primary key (scanner_id); unique (serial_number).

## imagery

Images

[`images`](#imageryimages)

### imagery.images

Aerial and ground-based imagery with spatial metadata and camera parameters

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `image_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) |  |
| `campaign_id` | integer | yes |  | `shared.campaigns.campaign_id` (set null) |  |
| `capture_date` | timestamp with time zone | yes |  |  |  |
| `file_path` | text |  |  |  | Path or URI to image file |
| `file_format` | character varying(20) | yes |  |  | Image file format (jpg, png, tiff, raw, geotiff) |
| `resolution_px` | character varying(50) | yes |  |  | Image resolution in pixels (e.g., 4000x3000) |
| `camera_model` | character varying(200) | yes |  |  |  |
| `position` | geometry(Point,4326) | yes |  |  | Camera position in WGS84 (EPSG:4326) |
| `altitude_m` | numeric(8,2) | yes |  |  | Camera altitude above ground in meters |
| `heading_deg` | numeric(5,2) | yes |  |  | Camera heading in degrees (0=North, clockwise) |
| `pitch_deg` | numeric(5,2) | yes |  |  | Camera pitch angle (-90 to 90 degrees) |
| `roll_deg` | numeric(5,2) | yes |  |  | Camera roll angle (-180 to 180 degrees) |
| `ground_sample_distance_cm` | numeric(8,4) | yes |  |  | Ground sample distance in centimeters per pixel |
| `description` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `updated_at` | timestamp with time zone | yes |  |  |  |
| `created_by` | character varying(200) | yes |  |  |  |
| `updated_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((file_format)::text = ANY (ARRAY[('jpg'::character varying)::text, ('png'::character varying)::text, ('tiff'::character varying)::text, ('raw'::character varying)::text, ('geotiff'::character varying)::text])))`; `CHECK ((ground_sample_distance_cm > (0)::numeric))`; `CHECK (((heading_deg >= (0)::numeric) AND (heading_deg < (360)::numeric)))`; `CHECK (((pitch_deg >= ('-90'::integer)::numeric) AND (pitch_deg <= (90)::numeric)))`; `CHECK (((roll_deg >= ('-180'::integer)::numeric) AND (roll_deg <= (180)::numeric)))`; primary key (image_id).

## forest_floor

Plot-level dead wood and ground vegetation surveys

[`deadwood`](#forest_floordeadwood) · [`ground_vegetation`](#forest_floorground_vegetation)

### forest_floor.deadwood

Dead wood inventory including standing dead, fallen logs, stumps, and branches

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `deadwood_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) |  |
| `tree_id` | integer | yes |  | `trees.trees.tree_id` (set null) | Optional link to known dead tree record |
| `species_id` | integer | yes |  | `shared.species.species_id` (set null) |  |
| `wood_type` | character varying(50) |  |  |  | Type of dead wood: standing, fallen, stump, or branch |
| `length_m` | numeric(6,2) | yes |  |  |  |
| `diameter_cm` | numeric(6,2) | yes |  |  |  |
| `decay_class` | integer | yes |  |  | Decay stage from 1 (fresh) to 5 (fully decomposed) |
| `volume_m3` | numeric(10,3) | yes |  |  |  |
| `position` | geometry(Point,4326) | yes |  |  |  |
| `measurement_date` | date | yes |  |  |  |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((decay_class >= 1) AND (decay_class <= 5)))`; `CHECK ((diameter_cm > (0)::numeric))`; `CHECK ((length_m > (0)::numeric))`; `CHECK ((volume_m3 >= (0)::numeric))`; `CHECK (((wood_type)::text = ANY (ARRAY[('standing'::character varying)::text, ('fallen'::character varying)::text, ('stump'::character varying)::text, ('branch'::character varying)::text])))`; primary key (deadwood_id).

### forest_floor.ground_vegetation

Ground vegetation survey records by plot and layer

| Column | Type | Null | Default | References | Description |
|---|---|---|---|---|---|
| `ground_vegetation_id` | integer |  | serial |  |  |
| `location_id` | integer |  |  | `shared.locations.location_id` (cascade) |  |
| `plot_id` | integer | yes |  | `shared.plots.plot_id` (set null) |  |
| `species_name` | character varying(200) | yes |  |  |  |
| `cover_percent` | numeric(5,2) | yes |  |  | Estimated cover percentage (0-100) |
| `height_cm` | numeric(6,2) | yes |  |  |  |
| `layer` | character varying(50) | yes |  |  | Vegetation layer: herb, shrub, moss, litter, fern, grass |
| `measurement_date` | date | yes |  |  |  |
| `notes` | text | yes |  |  |  |
| `created_at` | timestamp with time zone | yes | `now()` |  |  |
| `created_by` | character varying(200) | yes |  |  |  |

Constraints: `CHECK (((cover_percent >= (0)::numeric) AND (cover_percent <= (100)::numeric)))`; `CHECK ((height_cm >= (0)::numeric))`; `CHECK (((layer)::text = ANY (ARRAY[('herb'::character varying)::text, ('shrub'::character varying)::text, ('moss'::character varying)::text, ('litter'::character varying)::text, ('fern'::character varying)::text, ('grass'::character varying)::text])))`; primary key (ground_vegetation_id).

## Views

### Views in the domain schemas

| View | Description |
|---|---|
| `environments.active_environments` | Currently active environment variants with location and scenario context |
| `environments.location_environment_summary` | Summary statistics of environmental conditions by location |
| `pointclouds.processing_lineage` | Recursive view showing point cloud processing lineage and depth |
| `sensor.active_sensors_status` | Active sensors with their latest reading information |
| `sensor.sensor_tree_view` | View showing relationships between sensors and trees with detailed information |
| `shared.recent_changes` | Unified view of recent changes across all audited tables |
| `shared.user_activity_summary` | Summary of user activity and change patterns |
| `trees.trees_with_metrics` | Trees with computed metrics (basal area, crown volume, stem count) |

### Public API views

The REST API (`/rest/v1/<name>`). Their columns, live: `GET /rest/v1/` (OpenAPI), or the
portal's API page.

| View | Description |
|---|---|
| `attribute_provenance` | Where every acquired shared.locations value came from, with the name, version and citation of the source resolved from shared.processes. |
| `axis_structures` | Public API view for axis structures lookup table |
| `branch_elongation_habits` | Public API view for branch elongation habits lookup table |
| `campaigns` | Public API view for data collection campaigns |
| `climate_pathways` | Climate axis of scenarios: id + name + label. 0 = historical (observed climatology held constant), 1..3 = CMIP6 SSPs. |
| `crown_architectures` | Public API view for crown architectures lookup table |
| `crown_classes` | Public API view for crown classes (competitive/social position) lookup table |
| `crown_foliage_profiles` | Public API view for crown foliage density/distribution profiles |
| `crown_shapes` | Public API view for crown shapes lookup table |
| `damage_agents` | Public API view for damage agents lookup table |
| `data_source_types` | Data source type classifications (field, lidar, photogrammetry, estimated, simulated) |
| `deadwood` | Public API view for dead wood inventory |
| `disturbance_events` | Public API view for natural disturbance events |
| `environments` | Public API view for environments table |
| `geometric_crown_solids` | Public API view for geometric crown solids lookup table |
| `ground_vegetation` | Public API view for ground vegetation surveys |
| `growth_forms` | Public API view for growth forms lookup table |
| `growth_orientations` | Public API view for growth orientations lookup table |
| `growth_simulations` | Flat view of growth simulation projections with scenario and species names resolved. Filter by scenario_name + projection_year to get a full forest state for UE Time Machine. |
| `images` | Public API view for imagery table |
| `job_status` | Every job the caller is allowed to see -- their own, or all of them for a curator. Omits claimed_by and next_attempt_at, which are the runner's bookkeeping rather than the submitter's answer. An anon caller matches no policy and so reads an empty list. |
| `locations` | Public API view for locations reference table |
| `management_events` | Public API view for forest management events |
| `management_regimes` | Management axis of scenarios: id + name + description + the silvaR thinning preset (silva_rules). Regime 0 holds no trees. |
| `phanerophyte_height_classes` | Public API view for phanerophyte height classes lookup table |
| `phenology_observations` | Public API view for tree phenology observations |
| `plots` | Public API view for sub-plot divisions within locations |
| `point_clouds` | Public API view for point clouds table |
| `qsms` | Public API view for QSM reconstructions |
| `root_system_types` | Public API view for root system types lookup table |
| `roots` | Public API view for root system classification/geometry |
| `scenarios` | Public API view: location-scoped scenarios (Location -> Scenario -> Variant), each a (management regime, climate pathway) pair with scenario_code = regime*10 + pathway. Insertable; omit the axis ids and they are derived from a conforming scenario_name. For names alongside ids use ue_scenarios. |
| `sensor_readings` | Public API view for sensor readings table |
| `sensor_tree_links` | Public API view for sensor-tree link table |
| `sensor_types` | Public API view for sensor types reference table |
| `sensors` | Public API view for sensors table |
| `shoot_elongation_types` | Public API view for shoot elongation types lookup table |
| `simulation_runs` | One row per growth simulation run: identity, configuration and the size of the trajectory it produced. Backed by trees.simulation_runs; counts aggregated from trees.growth_simulations. |
| `species` | Public API view for tree species reference table |
| `stems` | Public API view for tree stems table |
| `tree_graph_edges` | Public API view for QSM topology edge overrides (observed/synthetic/derived) |
| `tree_part_types` | Public API view for tree part types (CityGML feature classes) lookup table |
| `trees` | Public API view for trees table |
| `ue_climate` | environments.environments merged across variant_name: one row per location, scenario, variant type and period, with each measurement column taken from whichever dataset supplied it. This is the read a scene makes -- ue_environments returns one row per dataset, which since XRFF-395 means two half-empty rows per window where a scenario picker wants one full one. `variant_names` and `process_names` carry the provenance the merge folds away; `conflicting_columns` is empty unless two datasets supplied the same measurement for the same window, in which case the value shown is an arbitrary one of them. Despite the name it also returns the scenario-less rows -- soil chemistry (both years NULL) and the measured soil aggregate -- because the grouping is by period, not by topic. GET /rest/v1/ue_climate?location_id=eq.1&scenario_name=eq.ssp370&order=start_year |
| `ue_environments` | environments.environments with its location, scenario, variant type and process joined to text, for Unreal. Every column is a scalar and the period is exposed as integer years as well as timestamps. A NULL scenario_name means the row is not a projection (an observed climatology or a permanent site property), not that a pathway is missing -- variant_name says which dataset it is. GET /rest/v1/ue_environments?location_id=eq.1&scenario_name=eq.ssp370&order=start_year |
| `ue_scenarios` | Scenario picker for Unreal: every scenario with its numeric code and text axes, how many tree-holding variants it has and the years they span, and baseline_variant_id -- the measured state (in natural_growth) its chain was projected from, so a picker can offer the base year in every scenario. has_trees=false rows are climate-data buckets. GET /rest/v1/ue_scenarios?location_id=eq.1&has_trees=eq.true&order=scenario_code |
| `ue_sensor_readings` | Enriched sensor time-series for UE Blueprint. Includes sensor type, unit, timestamp_unix (epoch seconds) and the sensor's location_id, keyed by sensor_id. Look up the linked tree once via ue_sensors, not per reading. GET /ue_sensor_readings?location_id=eq.<site>&order=timestamp.desc&limit=100000 (one site), or ?sensor_id=eq.<id>&order=timestamp.desc&limit=96 (one sensor). |
| `ue_sensors` | Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading (ISO and latest_timestamp_unix epoch seconds), linked tree info (populated after sensor_tree_links is filled), and the probe placement parsed from the label (placement_ring stem\|middle\|edge, placement_direction N\|E\|S\|W\|NE, placement_depth_cm, placement_distance_cm; NULL = the label carries none). GET /ue_sensors?tree_entity_id=eq.<tree_entity_id> |
| `ue_trees` | Flat tree catalogue for UE Blueprint import. One row per tree with the location/scenario/variant hierarchy (id + name at each level), the scenario axes (scenario_code = regime*10 + pathway, management_regime, climate_pathway), the variant's simulation_year / sort_order / time_delta_yrs, species, main-stem DBH, competition flag, tree_status (healthy \| dead = standing snag, render it \| harvested = gone, hide it), sensor cross-reference and projected source coordinates (original_x/original_y in source_crs, EPSG:32632 -- preferred for UE placement) plus flattened latitude/longitude. Filter by variant_id to load one time step. Pickers: ue_scenarios, ue_variants. |
| `ue_variants` | Time-step picker for Unreal: one row per variant with simulation_year (the number), variant_name (the text), sort_order, lineage and the scenario axes. GET /rest/v1/ue_variants?location_id=eq.1&scenario_code=eq.23&order=sort_order then GET /rest/v1/ue_trees?variant_id=eq.<id> |
| `variant_types` | Public API view for data variant type classifications |
| `variants` | Forest-state variants with location/scenario/type names, parent_variant_id lineage and the scenario axes (scenario_code, management_regime_name, climate_pathway_name) joined. Filter by location_id+scenario_id and order by sort_order for a site+scenario timeline. |
| `workflows` | The workflows that can be requested with request_job(), one row each, with the JSON Schema of the parameters each accepts. A row here is a name and a contract only -- what it executes is defined solely in the runner private config on the host that runs it. |
