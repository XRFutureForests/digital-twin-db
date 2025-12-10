-- Link Sensors to Trees Migration
-- Automatically creates links between sensors (dendrometers, sap flow) and their corresponding trees

SET search_path TO sensor, trees, shared, public;

-- Create the sensor_tree_links table
CREATE TABLE IF NOT EXISTS sensor.sensor_tree_links (
    link_id SERIAL PRIMARY KEY,
    sensor_id INTEGER NOT NULL,
    tree_variant_id INTEGER NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(sensor_id, tree_variant_id),
    FOREIGN KEY (sensor_id) REFERENCES sensor.sensors(sensorid) ON DELETE CASCADE,
    FOREIGN KEY (tree_variant_id) REFERENCES trees.trees(variantid) ON DELETE CASCADE
);

COMMENT ON TABLE sensor.sensor_tree_links IS 'Links sensors to specific tree variants based on naming patterns';

-- Grant permissions
GRANT ALL ON sensor.sensor_tree_links TO service_role;
GRANT SELECT ON sensor.sensor_tree_links TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE sensor.sensor_tree_links_link_id_seq TO service_role, authenticated, anon;

-- Function to populate sensor-tree links (kept for reference but using direct INSERT below)
CREATE OR REPLACE FUNCTION link_sensors_to_trees()
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
    plot_pattern TEXT;
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
        -- Extract tree number from sensor name
        -- Patterns: "Beech_Mixed_5_Dendrometer" -> "5"
        --           "Beech_Pure_10_Dendrometer" -> "10"
        --           "Beech_18_SapFlow" -> "18"
        --           "Beech_Mixed_137_Drought" -> "137"
        
        tree_number := NULL;
        plot_pattern := NULL;
        
        -- Try to extract tree number from different patterns
        IF sensor_rec.serialnumber ~* '.*_([0-9]+)_(Dendrometer|SapFlow)$' THEN
            tree_number := substring(sensor_rec.serialnumber from '.*_([0-9]+)_(Dendrometer|SapFlow)$');
        ELSIF sensor_rec.serialnumber ~* '.*_([0-9]+)_(Drought|Control)$' THEN
            tree_number := substring(sensor_rec.serialnumber from '.*_([0-9]+)_(Drought|Control)$');
        END IF;
        
        -- Determine plot pattern from location or sensor name
        IF sensor_rec.location LIKE '%MixedPlot%' OR sensor_rec.serialnumber LIKE '%Mixed%' THEN
            plot_pattern := 'mixed';
        ELSIF sensor_rec.location LIKE '%BeechPlot%' OR sensor_rec.serialnumber LIKE '%Pure%' THEN
            plot_pattern := 'pure_beech';
        ELSIF sensor_rec.location LIKE '%DouglasFirPlot%' OR sensor_rec.serialnumber LIKE '%Douglas%' THEN
            plot_pattern := 'douglas';
        END IF;
        
        -- Try to find matching tree
        IF tree_number IS NOT NULL THEN
            -- Look for tree with matching identifier in fieldnotes
            -- This is a best-effort match based on naming conventions
            SELECT t.variantid, t.fieldnotes
            INTO tree_rec
            FROM trees.trees t
            WHERE t.fieldnotes IS NOT NULL
            AND (
                -- Match exact tree ID
                t.fieldnotes ~* ('TreeID: [0-9_]*' || tree_number || '[^0-9]')
                OR
                -- Match FID
                t.fieldnotes ~* ('FID: ' || tree_number || ' ')
            )
            LIMIT 1;
            
            -- If found, create link
            IF tree_rec.variantid IS NOT NULL THEN
                BEGIN
                    INSERT INTO sensor.sensor_tree_links (sensor_id, tree_variant_id, description)
                    VALUES (
                        sensor_rec.sensorid,
                        tree_rec.variantid,
                        'Auto-linked based on sensor name: ' || sensor_rec.serialnumber
                    )
                    ON CONFLICT (sensorid, treevariantid) DO NOTHING;
                    
                    links_created := links_created + 1;
                    
                    sensor_id := sensor_rec.sensorid;
                    sensor_name := sensor_rec.serialnumber;
                    tree_variant_id := tree_rec.variantid;
                    tree_info := tree_rec.fieldnotes;
                    link_created := TRUE;
                    
                    RETURN NEXT;
                EXCEPTION WHEN OTHERS THEN
                    -- Skip if error occurs
                    CONTINUE;
                END;
            END IF;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Created % sensor-tree links', links_created;
END;
$$ LANGUAGE plpgsql;

-- Execute direct sensor-tree linking using pattern matching
INSERT INTO sensor.sensor_tree_links (sensor_id, tree_variant_id, description)
SELECT DISTINCT
    s.sensorid,
    t.variantid,
    'Auto-linked: ' || s.serialnumber || ' to tree ' || substring(t.fieldnotes from 'TreeID: [^ |]+')
FROM sensor.sensors s
JOIN sensor.sensortypes st ON s.sensortypeid = st.sensortypeid
CROSS JOIN trees.trees t
WHERE s.externalid IS NOT NULL
AND st.sensortypename IN ('Stem_Radial_Variation', 'Sap_Flow')
AND t.fieldnotes IS NOT NULL
AND s.serialnumber ~ '_([0-9]+)_'
AND t.fieldnotes ~ ('FID: ' || substring(s.serialnumber from '_([0-9]+)_') || ' ')
ON CONFLICT (sensor_id, tree_variant_id) DO NOTHING;

-- Show summary
DO $$
DECLARE
    total_links INTEGER;
    sensor_types_linked TEXT;
BEGIN
    SELECT COUNT(*) INTO total_links FROM sensor.sensor_tree_links;
    
    SELECT string_agg(DISTINCT st.sensortypename, ', ')
    INTO sensor_types_linked
    FROM sensor.sensor_tree_links stl
    JOIN sensor.sensors s ON stl.sensor_id = s.sensorid
    JOIN sensor.sensortypes st ON s.sensortypeid = st.sensortypeid;
    
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'Sensor-Tree Linking Summary';
    RAISE NOTICE '======================================================';
    RAISE NOTICE 'Total sensor-tree links created: %', total_links;
    RAISE NOTICE 'Sensor types linked: %', sensor_types_linked;
    RAISE NOTICE '======================================================';
END $$;

-- Create a view for easy querying of sensor-tree relationships
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

