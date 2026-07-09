-- XR Future Forests Lab - Ecosense Aquarius Sensor <-> Tree Mapping
-- Adds a durable Aquarius sensor-name anchor to the trees table so that
-- Ecosense sensor time-series can be joined to the physical inventory tree
-- they are installed on.
--
-- Background: Aquarius names each sensor time-series with a per-species,
-- per-plot-type sequence number (e.g. "Beech_Mixed_8", "DouglasFir_Pure_10").
-- That number is INDEPENDENT of our inventory tree numbering (plot x
-- TreeNumber, e.g. tree 8_16), and Aquarius does not carry the inventory ID.
-- The two systems therefore cannot be joined from Aquarius data alone. The
-- field survey (data/reference/ecosense_sensor_tree_map.csv) provides the
-- missing decoder ring; it is applied by scripts/import/link_sensors_to_trees.py.
--
-- Depends on: 13-trees-schema.sql, 16-sensor-tree-links-schema.sql

SET search_path TO trees, sensor, shared, public;

-- =============================================================================
-- TREES: AQUARIUS SENSOR-NAME ANCHOR
-- =============================================================================
-- The Aquarius name here equals the PREFIX of the sensor.sensors.serialnumber
-- values for that tree's cluster (e.g. AquariusName "Beech_Mixed_8" matches
-- "Beech_Mixed_8_Dendrometer", "Beech_Mixed_8_Total_SapFlow", ...).
-- Populated only for the ~46 instrumented Ecosense trees; NULL elsewhere.

ALTER TABLE trees.Trees
    ADD COLUMN IF NOT EXISTS AquariusName VARCHAR(100);

COMMENT ON COLUMN trees.Trees.AquariusName IS
    'Aquarius sensor-name prefix ({Species}_{PlotType}_{Seq}, e.g. Beech_Mixed_8) '
    'identifying the sensor cluster installed on this tree. Matches the prefix of '
    'sensor.sensors.serialnumber. Populated from data/reference/ecosense_sensor_tree_map.csv '
    'by scripts/import/link_sensors_to_trees.py. NULL for non-instrumented trees.';

CREATE INDEX IF NOT EXISTS idx_trees_aquarius_name ON trees.Trees(AquariusName);

-- =============================================================================
-- DEPRECATE THE OLD PATTERN-MATCH LINKER
-- =============================================================================
-- sensor.link_sensors_to_trees_by_pattern() guessed the tree by extracting a
-- number from the Aquarius label and matching it against trees.TreeNumber. That
-- is unreliable: Aquarius sequence numbers are not inventory tree numbers, and
-- TreeNumber repeats across plots at the single Ecosense location, so every
-- match is ambiguous. It is superseded by AquariusName-based linking. The
-- function is kept only to avoid breaking existing references.

COMMENT ON FUNCTION sensor.link_sensors_to_trees_by_pattern() IS
    'DEPRECATED - unreliable (see 32-ecosense-sensor-tree-map.sql). Use '
    'scripts/import/link_sensors_to_trees.py, which links via trees.AquariusName.';
