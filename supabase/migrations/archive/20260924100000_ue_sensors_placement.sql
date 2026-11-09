-- =============================================================================
-- public.ue_sensors: expose where a probe sits (ring, direction, depth, distance)
-- =============================================================================
-- Several soil probes are linked to one tree, and until now Unreal had no way
-- to tell them apart: a tree carries twelve soil_moisture and twelve
-- soil_temperature rows that differ only in their label. The placement is in
-- that label (sensor.sensors.serial_number = the Aquarius Label) and nowhere
-- else -- no Aquarius field and no row of the sensor catalogue CSV carries it.
--
-- Four columns are APPENDED at the end of the view, parsed from the label:
--
--   placement_ring         stem | middle | edge   radial class, near -> far
--   placement_direction    N | E | S | W | NE     compass side of the tree/pit
--   placement_depth_cm     integer, positive = below ground
--   placement_distance_cm  integer, horizontal distance from the stem
--
-- Label grammars covered (counts are dev, 2026-09-24, both SMT100 channels):
--
--   <Beech|DouglasFir|SilverFir>_<Pure|Mixed>_<n>_<stem|middle|edge>_<NESW>
--       744 rows -> ring + direction. The only tree-linked grammar. No depth.
--   <Beech|Dougl>_<n>_depth<ddd>cm_dist<ddd>cm_<W|O>[_...]
--       85 rows -> depth + distance + direction (O = Ost = E). Not linked.
--   SoilPit_<plot>_<n>_-<d>cm, <Clay|Stone|Clay_Stone|Test>_Profile_-<d>cm
--       212 rows -> depth.
--   SoilMoistureProfile_<south|west|northeast>_<d>cm
--       36 rows -> depth + direction.
--
-- Every other label yields NULL in all four columns; NULL means "the label
-- says nothing", never "at the stem".
--
-- Parsed in the view rather than stored, so a sensor the connector adds
-- tomorrow is covered without a backfill. Appended rather than inserted, so
-- CREATE OR REPLACE applies (Postgres forbids reordering an existing view's
-- columns) and keeps the view's owner, grants, comment and security_invoker;
-- and so the existing Unreal row struct ST_Sensor keeps importing unchanged --
-- the JSON -> struct fill matches by field name and ignores extra keys.
--
-- Mirrored to init 58-ue-sensors-placement.sql.
-- =============================================================================

CREATE OR REPLACE VIEW public.ue_sensors WITH (security_invoker=on) AS
SELECT s.sensor_id,
    s.source,
    s.external_id,
    s.serial_number AS sensor_label,
    s.external_metadata ->> 'Parameter'::text AS parameter,
    st.sensor_type_id,
    st.sensor_type_name AS sensor_type,
    s.unit,
    s.sensor_model,
    s.external_metadata ->> 'DataOwner'::text AS data_owner,
    s.is_active,
    s.installation_height_m,
    s.sampling_interval_seconds,
    s.installation_date,
    l.location_id,
    l.location_name,
    s.plot_id,
    p.plot_name,
    lr."timestamp" AS latest_timestamp,
    lr.value AS latest_value,
    lr.quality AS latest_quality,
    t.tree_id AS linked_tree_id,
    t.tree_entity_id AS linked_tree_entity_id,
    sp.common_name AS linked_tree_species,
    sp.scientific_name AS linked_tree_scientificname,
    t.height_m AS linked_tree_height_m,
    st_y(s."position") AS latitude,
    st_x(s."position") AS longitude,
    EXTRACT(epoch FROM lr."timestamp")::bigint AS latest_timestamp_unix,
    substring(s.serial_number FROM '^(?:Beech|DouglasFir|SilverFir)_(?:Pure|Mixed)_[0-9]+_(stem|middle|edge)_[NESW]$') AS placement_ring,
    CASE
        WHEN s.serial_number ~ '^(?:Beech|DouglasFir|SilverFir)_(?:Pure|Mixed)_[0-9]+_(?:stem|middle|edge)_[NESW]$'
            THEN right(s.serial_number, 1)
        WHEN s.serial_number ~ '_depth[0-9]+cm_dist[0-9]+cm_[OW](?:_|$)'
            THEN CASE substring(s.serial_number FROM '_dist[0-9]+cm_([OW])') WHEN 'O' THEN 'E' ELSE 'W' END
        WHEN s.serial_number ~ '^SoilMoistureProfile_(?:south|west|northeast)_'
            THEN CASE substring(s.serial_number FROM '^SoilMoistureProfile_([a-z]+)_')
                WHEN 'south' THEN 'S' WHEN 'west' THEN 'W' WHEN 'northeast' THEN 'NE' END
    END AS placement_direction,
    COALESCE(
        substring(s.serial_number FROM '_depth([0-9]+)cm_dist[0-9]+cm_'),
        substring(s.serial_number FROM '^(?:SoilPit_.+|(?:Clay|Stone|Clay_Stone|Test)_Profile)_-([0-9]+)cm$'),
        substring(s.serial_number FROM '^SoilMoistureProfile_[a-z]+_([0-9]+)cm$')
    )::integer AS placement_depth_cm,
    substring(s.serial_number FROM '_depth[0-9]+cm_dist([0-9]+)cm_')::integer AS placement_distance_cm
   FROM sensor.sensors s
     JOIN sensor.sensor_types st ON s.sensor_type_id = st.sensor_type_id
     JOIN shared.locations l ON s.location_id = l.location_id
     LEFT JOIN shared.plots p ON s.plot_id = p.plot_id
     LEFT JOIN LATERAL ( SELECT sr."timestamp",
            sr.value,
            sr.quality
           FROM sensor.sensor_readings sr
          WHERE sr.sensor_id = s.sensor_id
          ORDER BY sr."timestamp" DESC
         LIMIT 1) lr ON true
     LEFT JOIN sensor.sensor_tree_links stl ON stl.sensor_id = s.sensor_id
     LEFT JOIN trees.trees t ON stl.tree_id = t.tree_id
     LEFT JOIN shared.species sp ON t.species_id = sp.species_id;

COMMENT ON VIEW public.ue_sensors IS 'Flat sensor catalogue for UE Blueprint. One row per sensor with type, model (enriched instrument), data owner, location, latest reading (ISO and latest_timestamp_unix epoch seconds), linked tree info (populated after sensor_tree_links is filled), and the probe placement parsed from the label (placement_ring stem|middle|edge, placement_direction N|E|S|W|NE, placement_depth_cm, placement_distance_cm; NULL = the label carries none). GET /ue_sensors?linked_tree_entity_id=eq.<tree_entity_id>';
