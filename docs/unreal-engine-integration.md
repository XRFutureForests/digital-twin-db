# Unreal Engine Integration Guide

> **Blueprint-only guide for querying Digital Forest Twin data from Unreal Engine**

This guide shows how to fetch tree data from the Digital Forest Twin PostgreSQL database into Unreal Engine using HTTP requests and Blueprints (no C++ required).

---

## Overview

The Digital Forest Twin database exposes a REST API via Supabase/PostgREST. Unreal Engine can query this API using HTTP requests and parse the JSON response into usable data structures.

**Architecture:**

```
Unreal Engine  →  HTTP GET Request  →  PostgREST API  →  PostgreSQL Database
                                    ←  JSON Response  ←
```

---

## Prerequisites

1. **Digital Forest Twin database running** (Docker stack)
2. **Unreal Engine 5.3+** with HTTP plugin enabled
3. **Network access** to the API (localhost:8000 for local development)

---

## Part 1: API Configuration

### API Endpoint

| Setting | Value |
|---------|-------|
| **Base URL** | `http://localhost:8000/rest/v1` |
| **Trees Endpoint** | `/trees` |
| **Full URL** | `http://localhost:8000/rest/v1/trees` |

### Authentication

The API requires an API key passed as a header or query parameter.

**API Key (ANON_KEY):**

```
eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3MDQwNjcyMDAsICJleHAiOiAxODkzNDU2MDAwfQ.5QXqD_LbVJmY9x4M5aWeeP8kbjiKFyt-PztkzrDovYY
```

> ⚠️ **Security Note:** This is the public `anon` key for read-only access. Never ship the `service_role` key in a packaged game.

### Example Query URLs

**Get trees with species and diameter (browser-friendly):**

```
http://localhost:8000/rest/v1/trees?select=variantid,height_m,position,species(commonname,scientificname),stems(dbh_cm)&limit=100&apikey=eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3MDQwNjcyMDAsICJleHAiOiAxODkzNDU2MDAwfQ.5QXqD_LbVJmY9x4M5aWeeP8kbjiKFyt-PztkzrDovYY
```

**Using curl with header:**

```bash
curl "http://localhost:8000/rest/v1/trees?select=variantid,height_m,position,species(commonname),stems(dbh_cm)&limit=10" \
  -H "apikey: eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3MDQwNjcyMDAsICJleHAiOiAxODkzNDU2MDAwfQ.5QXqD_LbVJmY9x4M5aWeeP8kbjiKFyt-PztkzrDovYY"
```

### JSON Response Format

```json
[
  {
    "variantid": 1,
    "height_m": 25.5,
    "position": {
      "type": "Point",
      "coordinates": [7.877994506894085, 48.26845182025935]
    },
    "species": {
      "commonname": "Douglas Fir",
      "scientificname": "Pseudotsuga menziesii"
    },
    "stems": [
      { "dbh_cm": 54.43 }
    ]
  }
]
```

### Available Query Parameters

| Parameter | Example | Description |
|-----------|---------|-------------|
| `select` | `select=variantid,height_m,position` | Choose columns to return |
| `limit` | `limit=100` | Limit number of results |
| `offset` | `offset=50` | Skip first N results (pagination) |
| `order` | `order=height_m.desc` | Sort results |
| `height_m` | `height_m=gt.20` | Filter: height > 20m |

**Filter operators:** `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `is`, `in`

---

## Part 2: Unreal Engine Setup

### Step 1: Enable HTTP Plugin

1. Go to **Edit → Plugins**
2. Search for **"HTTP"**
3. Enable the **HTTP** plugin (HTTP Blueprint support)
4. Restart the editor

Optional: Install **"VaRest"** or **"JSON Blueprint Utilities"** plugin from Marketplace for easier JSON parsing.

### Step 2: Create the Row Struct

This struct mirrors the JSON response structure.

1. **Right-click** in Content Browser → **Blueprints → Structure**
2. Name it `ST_TreeRow`
3. Add the following fields:

| Variable Name | Type | Description |
|---------------|------|-------------|
| `VariantId` | Integer | Unique tree identifier |
| `Height_m` | Float | Tree height in meters |
| `Longitude` | Float | X coordinate (from position.coordinates[0]) |
| `Latitude` | Float | Y coordinate (from position.coordinates[1]) |
| `SpeciesName` | String | Common name of species |
| `DBH_cm` | Float | Diameter at breast height in cm |

### Step 3: Create the Fetcher Blueprint

1. **Right-click** in Content Browser → **Blueprint Class → Actor**
2. Name it `BP_DigitalTwinFetcher`

#### Add Variables

| Variable | Type | Default Value |
|----------|------|---------------|
| `ApiBaseUrl` | String | `http://localhost:8000/rest/v1` |
| `ApiKey` | String | (paste ANON_KEY from above) |
| `FetchedTrees` | Array of ST_TreeRow | (empty) |

#### Add Event Dispatchers

1. In the **My Blueprint** panel, click **+ Event Dispatcher**
2. Create `OnFetchSuccess` with parameter:
   - `Trees` (Array of ST_TreeRow)
3. Create `OnFetchError` with parameter:
   - `ErrorMessage` (String)

### Step 4: Build the Fetch Function

Create a function called `FetchTrees`:

#### Node Graph (simplified)

```
[BeginPlay or Custom Event: FetchTrees]
    │
    ▼
[Construct Http Request]
    │
    ├─► Set URL: ApiBaseUrl + "/trees?select=variantid,height_m,position,species(commonname),stems(dbh_cm)&limit=1000&apikey=" + ApiKey
    ├─► Set Verb: "GET"
    ├─► Set Header: "Accept" = "application/json"
    │
    ▼
[Bind Event to OnProcessRequestComplete]
    │
    ▼
[Process Request]
```

#### Detailed Blueprint Steps

1. **Construct Http Request** node
   - Returns a `HttpRequest` object

2. **Set URL** on the request:

   ```
   Append strings:
   ApiBaseUrl + "/trees?select=variantid,height_m,position,species(commonname),stems(dbh_cm)&limit=1000&apikey=" + ApiKey
   ```

3. **Set Verb** → `"GET"`

4. **Set Header**:
   - Header Name: `Accept`
   - Header Value: `application/json`

5. **Bind Event to OnProcessRequestComplete**:
   - Create a custom event `OnHttpComplete`
   - Bind it to the request's completion delegate

6. **Process Request** → Sends the HTTP request

### Step 5: Handle the Response

In the `OnHttpComplete` event:

```
[OnHttpComplete] (Request, Response, bWasSuccessful)
    │
    ▼
[Branch: bWasSuccessful]
    │
    ├─► FALSE: Call OnFetchError("Request failed")
    │
    ▼ TRUE
[Get Response Code]
    │
    ▼
[Branch: ResponseCode == 200]
    │
    ├─► FALSE: Call OnFetchError("HTTP " + ResponseCode)
    │
    ▼ TRUE
[Get Content As String] → JsonString
    │
    ▼
[Parse JSON Array] → JsonArray
    │
    ▼
[ForEachLoop: JsonArray]
    │
    ├─► Get Field "variantid" → VariantId
    ├─► Get Field "height_m" → Height_m
    ├─► Get Object "position" → Get Array "coordinates" → [0]=Lon, [1]=Lat
    ├─► Get Object "species" → Get Field "commonname" → SpeciesName
    ├─► Get Array "stems" → [0] → Get Field "dbh_cm" → DBH_cm
    │
    ▼
[Make ST_TreeRow] → Add to LocalTrees array
    │
    ▼ (after loop completes)
[Set FetchedTrees = LocalTrees]
    │
    ▼
[Call OnFetchSuccess(FetchedTrees)]
```

### Step 6: Parse JSON to Struct (Detailed)

For each JSON object in the array:

```blueprint
// Get simple fields
Get Number Field (JsonObject, "variantid") → VariantId (as Integer)
Get Number Field (JsonObject, "height_m") → Height_m (as Float)

// Get nested position coordinates
Get Object Field (JsonObject, "position") → PositionObject
Get Array Field (PositionObject, "coordinates") → CoordsArray
Get [0] from CoordsArray → Longitude
Get [1] from CoordsArray → Latitude

// Get nested species name
Get Object Field (JsonObject, "species") → SpeciesObject
Get String Field (SpeciesObject, "commonname") → SpeciesName

// Get nested stem diameter (first stem)
Get Array Field (JsonObject, "stems") → StemsArray
Get [0] from StemsArray → FirstStem
Get Number Field (FirstStem, "dbh_cm") → DBH_cm

// Build the struct
Make ST_TreeRow (VariantId, Height_m, Longitude, Latitude, SpeciesName, DBH_cm)
```

### Step 7: Use the Data

Place `BP_DigitalTwinFetcher` in your level.

#### Option A: Direct Access

```blueprint
// In any other blueprint
Get Reference to BP_DigitalTwinFetcher
    → Get FetchedTrees
    → ForEachLoop
        → Use tree data for spawning, PCG, etc.
```

#### Option B: Event-Driven

```blueprint
// In your game controller or PCG manager
Bind Event to OnFetchSuccess (on BP_DigitalTwinFetcher)
    → Custom Event: HandleTreesLoaded(Trees)
        → Store Trees
        → Trigger PCG regeneration
        → Spawn tree meshes at positions
```

---

## Part 3: PCG Integration

If using Procedural Content Generation (PCG) graphs:

### Convert Tree Data to PCG Points

1. Create a function `ConvertTreesToPCGPoints`
2. For each `ST_TreeRow`:
   - Create a point at `(Longitude, Latitude, 0)` or transform to your world coordinates
   - Store `SpeciesName`, `DBH_cm`, `Height_m` as point attributes

### Example: Spawn Trees Based on Data

```blueprint
[ForEachLoop: FetchedTrees]
    │
    ▼
[Get Tree Position] → WorldLocation
    │
    ▼
[Select Mesh by SpeciesName]
    │ (use Switch on String or Map lookup)
    ▼
[Spawn Actor / Add Instance to HISM]
    │
    ▼
[Set Scale based on DBH_cm or Height_m]
```

---

## Part 4: Coordinate Transformation

The database stores coordinates in **WGS84 (EPSG:4326)** - longitude/latitude in degrees.

For Unreal Engine world coordinates, you need to:

1. **Define an origin point** (e.g., center of your forest plot)
2. **Convert lat/lon to meters** relative to origin
3. **Apply any necessary rotation** for your scene orientation

### Simple Conversion Formula

```blueprint
// Approximate meters per degree at 48°N latitude
MetersPerDegreeLat = 111320
MetersPerDegreeLon = 111320 * cos(OriginLatitude * PI / 180)

// Convert to local coordinates
LocalX = (Longitude - OriginLongitude) * MetersPerDegreeLon * 100  // cm
LocalY = (Latitude - OriginLatitude) * MetersPerDegreeLat * 100    // cm
```

For the EcoSense plot (approximate center):

- **Origin Longitude:** 7.878
- **Origin Latitude:** 48.268

---

## Part 5: Production Considerations

### For Packaged Games

1. **Use HTTPS** in production (not localhost)
2. **Deploy the API** to a public server or cloud
3. **Use only the `anon` key** - never ship `service_role`
4. **Enable Row Level Security (RLS)** in Supabase to restrict data access

### Performance

- Use `limit` parameter to paginate large datasets
- Consider spatial filtering (bounding box) for very large forests
- Cache fetched data locally if it doesn't change often

### Error Handling

- Check for network connectivity before requests
- Implement retry logic for transient failures
- Show user-friendly error messages

---

## Quick Reference

### Minimal Browser URL (copy-paste ready)

```
http://localhost:8000/rest/v1/trees?select=variantid,height_m,position,species(commonname),stems(dbh_cm)&limit=100&apikey=eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJyb2xlIjogImFub24iLCAiaXNzIjogInN1cGFiYXNlIiwgImlhdCI6IDE3MDQwNjcyMDAsICJleHAiOiAxODkzNDU2MDAwfQ.5QXqD_LbVJmY9x4M5aWeeP8kbjiKFyt-PztkzrDovYY
```

### Key Blueprint Nodes

| Node | Purpose |
|------|---------|
| `Construct Http Request` | Create HTTP request object |
| `Set URL` | Set the request URL |
| `Set Verb` | Set to "GET" |
| `Set Header` | Add headers (Accept: application/json) |
| `Process Request` | Send the request |
| `On Process Request Complete` | Callback when done |
| `Get Content As String` | Get JSON response body |
| `Deserialize Json` | Parse JSON string |
| `Get Object Field` | Access nested JSON object |
| `Get Number Field` | Get numeric value from JSON |
| `Get String Field` | Get string value from JSON |
| `Make ST_TreeRow` | Create struct instance |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Invalid authentication credentials" | Check API key is correct and not expired |
| Empty response | Verify database has data, check query syntax |
| CORS errors (in browser) | Use Unreal HTTP, not browser fetch |
| JSON parse errors | Log raw response string to verify format |
| Wrong coordinates | Check coordinate transformation formula |

---

## See Also

- [API Quick Reference](api-quick-reference.md) - More API query examples
- [Database Schema](database-schema.md) - Full table and column documentation
- [Epic Games: Working with Data Tables](https://dev.epicgames.com/community/learning/tutorials/Gp9j/)
- [VaRest Plugin Documentation](https://github.com/ufna/VaRest)
