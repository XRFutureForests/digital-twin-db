-- Sensor-Tree Links Schema
-- Creates the linking table and utility function for connecting sensors to trees
-- 
-- NOTE: This file only creates the schema/function. 
-- Linking is executed by the user AFTER importing tree and sensor data.
-- See scripts/import/link_sensors_to_trees.py for usage.

SET search_path TO sensor, trees, shared, public;

-- =============================================================================
-- SENSOR-TREE LINKS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS sensor.sensor_tree_links (
    SensorTreeLinkID SERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL,
    tree_id INTEGER NOT NULL,
    description TEXT,
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(sensor_id, tree_id),
    FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensor_id) ON DELETE CASCADE,
    FOREIGN KEY (tree_id) REFERENCES trees.trees(tree_id) ON DELETE CASCADE
);

COMMENT ON TABLE sensor.sensor_tree_links IS 'Links sensors to specific tree records';

-- Grant permissions
GRANT ALL ON sensor.sensor_tree_links TO service_role;
GRANT SELECT ON sensor.sensor_tree_links TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE sensor.sensor_tree_links_sensortreelinkid_seq TO service_role, authenticated, anon;

-- =============================================================================
-- LINKING FUNCTION (called by user after data import)
-- =============================================================================

CREATE OR REPLACE FUNCTION sensor.link_sensors_to_trees_by_pattern()
RETURNS TABLE (
    sensor_id INTEGER,
    sensor_name TEXT,
    tree_id INTEGER,
    tree_info TEXT,
    link_created BOOLEAN
) AS $$
DECLARE
    sensor_rec RECORD;
    tree_rec RECORD;
    tree_number TEXT;
    links_created INTEGER := 0;
BEGIN
    -- Loop through all dendrometer and sap flow sensors
    FOR sensor_rec IN
        SELECT
            s.sensor_id,
            s.serial_number,
            s.external_metadata->>'LocationIdentifier' as location,
            st.sensor_type_name
        FROM sensor.sensors s
        JOIN sensor.sensortypes st ON s.sensor_type_id = st.sensor_type_id
        WHERE s.external_id IS NOT NULL
        AND st.sensor_type_name IN ('Stem_Radial_Variation', 'Sap_Flow')
        ORDER BY s.serial_number
    LOOP
        tree_number := NULL;

        -- Extract tree number from sensor name patterns
        IF sensor_rec.serial_number ~* '.*_([0-9]+)_(Dendrometer|SapFlow)$' THEN
            tree_number := substring(sensor_rec.serial_number from '.*_([0-9]+)_(Dendrometer|SapFlow)$');
        ELSIF sensor_rec.serial_number ~* '.*_([0-9]+)_(Drought|Control)$' THEN
            tree_number := substring(sensor_rec.serial_number from '.*_([0-9]+)_(Drought|Control)$');
        END IF;

        IF tree_number IS NOT NULL THEN
            SELECT t.tree_id, t.field_notes
            INTO tree_rec
            FROM trees.trees t
            WHERE t.field_notes IS NOT NULL
            AND (
                t.field_notes ~* ('tree_id: [0-9_]*' || tree_number || '[^0-9]')
                OR t.field_notes ~* ('FID: ' || tree_number || ' ')
            )
            LIMIT 1;

            IF tree_rec.tree_id IS NOT NULL THEN
                BEGIN
                    INSERT INTO sensor.sensor_tree_links (sensor_id, tree_id, description)
                    VALUES (
                        sensor_rec.sensor_id,
                        tree_rec.tree_id,
                        'Auto-linked based on sensor name: ' || sensor_rec.serial_number
                    )
                    ON CONFLICT (sensor_id, tree_id) DO NOTHING;

                    links_created := links_created + 1;

                    sensor_id := sensor_rec.sensor_id;
                    sensor_name := sensor_rec.serial_number;
                    tree_id := tree_rec.tree_id;
                    tree_info := tree_rec.field_notes;
                    link_created := TRUE;

                    RETURN NEXT;
                EXCEPTION WHEN OTHERS THEN
                    CONTINUE;
                END;
            END IF;
        END IF;
    END LOOP;

    RAISE NOTICE 'Created % sensor-tree links', links_created;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION sensor.link_sensors_to_trees_by_pattern IS 'Auto-links sensors to trees based on naming patterns. Call after importing tree and sensor data.';

-- =============================================================================
-- VIEW FOR QUERYING SENSOR-TREE RELATIONSHIPS
-- =============================================================================

CREATE OR REPLACE VIEW sensor.sensor_tree_view AS
SELECT 
    s.sensor_id AS sensor_id,
    s.serial_number AS sensor_name,
    st.sensor_type_name AS sensor_type,
    s.unit AS sensor_unit,
    s.is_active AS sensor_active,
    stl.description AS link_description,
    stl.created_at AS link_created_at,
    t.tree_id AS tree_id,
    sp.common_name AS tree_species,
    t.height_m AS tree_height_m,
    substring(t.field_notes from 'tree_id: [^|]+') AS tree_identifier,
    substring(t.field_notes from 'FID: [0-9]+') AS tree_fid,
    l.location_name AS tree_location,
    extensions.ST_X(t.position) AS tree_longitude,
    extensions.ST_Y(t.position) AS tree_latitude
FROM sensor.sensor_tree_links stl
JOIN sensor.sensors s ON stl.sensor_id = s.sensor_id
JOIN sensor.sensortypes st ON s.sensor_type_id = st.sensor_type_id
LEFT JOIN trees.trees t ON stl.tree_id = t.tree_id
LEFT JOIN shared.species sp ON t.species_id = sp.species_id
LEFT JOIN shared.locations l ON t.location_id = l.location_id;

COMMENT ON VIEW sensor.sensor_tree_view IS 'View showing relationships between sensors and trees with detailed information';

-- Grant permissions
GRANT SELECT ON sensor.sensor_tree_view TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sensor.link_sensors_to_trees_by_pattern TO service_role, authenticated;

