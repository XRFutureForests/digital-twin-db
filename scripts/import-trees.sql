-- Import Mathisle tree data
-- This script should be run with the CSV file piped to stdin after the temp table is created

-- Create a temporary table to hold the CSV data
DROP TABLE IF EXISTS mathisle_import;
CREATE TEMP TABLE mathisle_import (
    row_num TEXT,
    species_short TEXT,
    date_time TEXT,
    qr_code TEXT,
    tree_id_fallback TEXT,
    gps_latitude TEXT,
    gps_longitude TEXT,
    gps_height TEXT,
    dbh TEXT,
    tree_id TEXT,
    species_label TEXT
);

-- Create species mapping
DROP TABLE IF EXISTS species_mapping;
CREATE TEMP TABLE species_mapping (
    code TEXT PRIMARY KEY,
    speciesid INTEGER
);

INSERT INTO species_mapping (code, speciesid) VALUES
('BE', 1),   -- European Beech
('NS', 3),   -- Norway Spruce
('ESF', 4),  -- Silver Fir
('ELA', 7),  -- European Larch
('NOM', 8),  -- Norway Maple
('SY', 9),   -- Sycamore Maple
('WCH', 10), -- Wild Cherry
('WST', 11), -- Wild Service Tree
('XBI', 12); -- Birch
-- 'other' will map to NULL

-- Copy CSV data - this line will be replaced with actual data insert
\echo 'Temp tables created. Now run the data import.'
