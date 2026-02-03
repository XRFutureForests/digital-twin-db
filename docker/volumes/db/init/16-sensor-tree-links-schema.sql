-- Sensor-Tree Links Schema
-- Creates the linking table and utility function for connecting sensors to trees
-- 
-- NOTE: This file only creates the schema/function. 
-- Linking is executed by the user AFTER importing tree and sensor data.
-- See scripts/link-sensors-to-trees.py for usage.

SET search_path TO sensor, trees, shared, public;

-- =============================================================================
-- SENSOR-TREE LINKS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS sensor.sensor_tree_links (
    link_id SERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL,
    tree_variant_id INTEGER NOT NULL,
    description TEXT,
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(sensor_id, tree_variant_id),
    FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensorid) ON DELETE CASCADE,
    FOREIGN KEY (tree_variant_id) REFERENCES trees.trees(variantid) ON DELETE CASCADE
);

COMMENT ON TABLE sensor.sensor_tree_links IS 'Links sensors to specific tree variants';

-- Grant permissions
GRANT ALL ON sensor.sensor_tree_links TO service_role;
GRANT SELECT ON sensor.sensor_tree_links TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE sensor.sensor_tree_links_link_id_seq TO service_role, authenticated, anon;

-- =============================================================================
-- LINKING FUNCTION (called by user after data import)
-- =============================================================================

CREATE OR REPLACE FUNCTION sensor.link_sensors_to_trees_by_pattern()
RETURNS TABLE (
    sensor_id INTEGER,
    sensor_name TEXT,
    tree_variant_id INTEGER,
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
            s.sensorid,
            s.serialnumber,
            s.externalmetadata->>'LocationIdentifier' as location,
            st.sensortypename
        FROM sensor.sensors s
        JOIN sensor.sensortypes st ON s.sensortypeid = st.sensortypeid
        WHERE s.externalid IS NOT NULL
        AND st.sensortypename IN ('Stem_Radial_Variation', 'Sap_Flow')
        ORDER BY s.serialnumber
    LOOP
        tree_number := NULL;
        
        -- Extract tree number from sensor name patterns
        IF sensor_rec.serialnumber ~* '.*_([0-9]+)_(Dendrometer|SapFlow)$' THEN
            tree_number := substring(sensor_rec.serialnumber from '.*_([0-9]+)_(Dendrometer|SapFlow)$');
        ELSIF sensor_rec.serialnumber ~* '.*_([0-9]+)_(Drought|Control)$' THEN
            tree_number := substring(sensor_rec.serialnumber from '.*_([0-9]+)_(Drought|Control)$');
        END IF;
        
        IF tree_number IS NOT NULL THEN
            SELECT t.variantid, t.fieldnotes
            INTO tree_rec
            FROM trees.trees t
            WHERE t.fieldnotes IS NOT NULL
            AND (
                t.fieldnotes ~* ('TreeID: [0-9_]*' || tree_number || '[^0-9]')
                OR t.fieldnotes ~* ('FID: ' || tree_number || ' ')
            )
            LIMIT 1;
            
            IF tree_rec.variantid IS NOT NULL THEN
                BEGIN
                    INSERT INTO sensor.sensor_tree_links (sensor_id, tree_variant_id, description)
                    VALUES (
                        sensor_rec.sensorid,
                        tree_rec.variantid,
                        'Auto-linked based on sensor name: ' || sensor_rec.serialnumber
                    )
                    ON CONFLICT (sensor_id, tree_variant_id) DO NOTHING;
                    
                    links_created := links_created + 1;
                    
                    sensor_id := sensor_rec.sensorid;
                    sensor_name := sensor_rec.serialnumber;
                    tree_variant_id := tree_rec.variantid;
                    tree_info := tree_rec.fieldnotes;
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
    s.sensorid AS sensor_id,
    s.serialnumber AS sensor_name,
    st.sensortypename AS sensor_type,
    s.unit AS sensor_unit,
    s.isactive AS sensor_active,
    stl.description AS link_description,
    stl.created_at AS link_created_at,
    t.variantid AS tree_variant_id,
    sp.commonname AS tree_species,
    t.height_m AS tree_height_m,
    substring(t.fieldnotes from 'TreeID: [^|]+') AS tree_identifier,
    substring(t.fieldnotes from 'FID: [0-9]+') AS tree_fid,
    l.locationname AS tree_location,
    extensions.ST_X(t.position) AS tree_longitude,
    extensions.ST_Y(t.position) AS tree_latitude
FROM sensor.sensor_tree_links stl
JOIN sensor.sensors s ON stl.sensor_id = s.sensorid
JOIN sensor.sensortypes st ON s.sensortypeid = st.sensortypeid
LEFT JOIN trees.trees t ON stl.tree_variant_id = t.variantid
LEFT JOIN shared.species sp ON t.speciesid = sp.speciesid
LEFT JOIN shared.locations l ON t.locationid = l.locationid;

COMMENT ON VIEW sensor.sensor_tree_view IS 'View showing relationships between sensors and trees with detailed information';

-- Grant permissions
GRANT SELECT ON sensor.sensor_tree_view TO authenticated, anon;
GRANT EXECUTE ON FUNCTION sensor.link_sensors_to_trees_by_pattern TO service_role, authenticated;

