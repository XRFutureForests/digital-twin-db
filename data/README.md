# Tree Inventory Data

This directory contains CSV files with tree inventory data that are automatically loaded into the database when the Docker container starts.

## Files

### `ecosense_250911.csv`

- **Source**: EcoSense Mixed Plot
- **Count**: ~1,500 trees
- **Coordinates**: UTM Zone 32N (EPSG:32632) → automatically converted to WGS84
- **Key Fields**: TreeID, QRCode, Species, Easting, Northing, DBH, Height

### `mathisle_250904.csv`

- **Source**: Mathisleweiher Plot
- **Count**: ~740 trees
- **Coordinates**: GPS (WGS84) → Latitude, Longitude
- **Key Fields**: TreeID, QRCode, Species, Longitude, Latitude, DBH, Height

## Automatic Import

Both CSV files are automatically imported when the database initializes. The import:

1. Loads tree records into `trees.TreeInventory`
2. Creates corresponding stems in `trees.Stems`
3. Converts coordinates to PostGIS geometry (SRID 4326)
4. Links trees to their respective plot locations

No manual import steps are required.
