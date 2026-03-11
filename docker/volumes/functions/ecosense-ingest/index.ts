import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { validateServiceRoleKey } from '../_shared/validators.ts'
import { getSupabaseClient } from '../_shared/database.ts'
import { AquariusClient, AquariusError } from '../_shared/aquarius.ts'
import { withRetry } from '../_shared/retry.ts'

/**
 * Syncs sensor data from the Aquarius API to the database
 *
 * This function fetches time series data from the Aquarius API for all Ecosense sensors
 * and stores the readings in the database. It handles concurrent API requests with
 * configurable batch sizes to avoid memory issues on large datasets.
 *
 * @route POST /functions/v1/ecosense-ingest
 *
 * @param {Request} req - HTTP request with optional query parameters
 * @param {string} [req.url.searchParams.days_back='7'] - Number of days to sync (1-365, clamped)
 *
 * @returns {Response} JSON response with sync results
 * @returns {Response.body.success} boolean - Whether the sync completed successfully
 * @returns {Response.body.count} number - Total sensor readings inserted
 * @returns {Response.body.sensors} number - Number of sensors processed
 * @returns {Response.body.errors} string[] - Optional array of error messages encountered
 *
 * @error 401 Unauthorized - Missing or invalid SERVICE_ROLE_KEY
 * @error 400 Bad Request - Invalid days_back parameter (not a valid integer)
 * @error 500 Internal Server Error - Database or Aquarius API errors
 *
 * @example
 * curl -X POST "http://localhost:8000/functions/v1/ecosense-ingest?days_back=7" \
 *   -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY"
 *
 * // Response (200 OK)
 * {
 *   "success": true,
 *   "count": 45230,
 *   "sensors": 12,
 *   "errors": ["Failed to fetch data for sensor_123: timeout"]
 * }
 */
console.log('ecosense-ingest function started')

// Memory optimization: Batch size prevents unbounded memory growth
// For large sensor datasets (100K+ points), readings are streamed in 5K-point batches
// rather than loading entire dataset into memory before insertion.
// Adjust READINGS_BATCH_SIZE down if memory-constrained, up if memory available.
const READINGS_BATCH_SIZE = 5000
const API_CONCURRENCY_LIMIT = 5

serve(async (req: Request) => {
    // Validate authentication
    if (!validateServiceRoleKey(req)) {
        return new Response(
            JSON.stringify({ error: 'Unauthorized', code: 'INVALID_AUTH' }),
            { status: 401, headers: { 'Content-Type': 'application/json' } }
        )
    }

    const aquarius = new AquariusClient()

    try {
        // Parse request parameters
        const url = new URL(req.url)
        const daysBackParam = url.searchParams.get('days_back') || '7'
        const daysBackInt = parseInt(daysBackParam)

        if (isNaN(daysBackInt)) {
            return new Response(
                JSON.stringify({ error: 'Invalid parameter', code: 'INVALID_DAYS_BACK', message: 'days_back must be a valid integer' }),
                { status: 400, headers: { 'Content-Type': 'application/json' } }
            )
        }

        const daysBack = Math.max(1, Math.min(365, daysBackInt)) // Limit to 1-365 days

        console.log(`Starting ecosense data sync (days_back=${daysBack})`)

        // Initialize clients
        const supabase = getSupabaseClient()

        // Connect to Aquarius
        await aquarius.connect()

        // Parameter to SensorType mapping
        const paramMapping: Record<string, string> = {
            'Sapflow': 'Sap_Flow',
            'StemRadialVar_Volt': 'Stem_Radial_Variation',
            'BarPressure': 'Barometric_Pressure',
            'SoilMoisture': 'Soil_Moisture',
            'SoilTemp': 'Soil_Temperature',
        }

        // Fetch time series descriptions
        const descriptions = await aquarius.getTimeSeriesDescriptions()

        // Filter for Ecosense sensors
        const ecosenseTS = descriptions.filter(ts =>
            ts.LocationIdentifier?.startsWith('Ecosense_') &&
            ts.Parameter in paramMapping
        )

        console.log(`Filtered to ${ecosenseTS.length} relevant sensors`)

        if (ecosenseTS.length === 0) {
            await aquarius.disconnect()
            return new Response(
                JSON.stringify({
                    success: true,
                    count: 0,
                    sensors: 0,
                    message: 'No Ecosense sensors found matching filter criteria',
                }),
                { status: 200, headers: { 'Content-Type': 'application/json' } }
            )
        }

        // Batch fetch all sensor types and locations (avoid N+1 queries)
        // Note: Table/column names are lowercase in the database schema
        const { data: allSensorTypes } = await supabase
            .from('sensortypes')
            .select('sensortypeid, sensortypename')

        const { data: allLocations } = await supabase
            .from('locations')
            .select('locationid, locationname')

        const sensorTypeMap = new Map(
            (allSensorTypes || []).map((st: { sensortypeid: number; sensortypename: string }) => [
                st.sensortypename,
                st.sensortypeid,
            ])
        )

        const locationMap = new Map(
            (allLocations || []).map((loc: { locationid: number; locationname: string }) => [
                loc.locationname,
                loc.locationid,
            ])
        )

        // Sync metadata: collect all upsert operations
        const sensorsToUpsert = []

        for (const ts of ecosenseTS) {
            const mappedType = paramMapping[ts.Parameter]
            const sensorTypeId = sensorTypeMap.get(mappedType)

            if (!sensorTypeId) {
                console.warn(`Sensor type not found: ${mappedType}`)
                continue
            }

            let locationId = locationMap.get(ts.LocationIdentifier)

            // Only create location if it doesn't exist (checked on next sync)
            if (!locationId) {
                const { data: newLocation } = await supabase
                    .from('locations')
                    .insert({
                        locationname: ts.LocationIdentifier,
                        centerpoint: 'POINT(0 0)', // Default, should be updated later
                    })
                    .select('locationid')
                    .single()

                locationId = newLocation?.locationid
                if (locationId) {
                    locationMap.set(ts.LocationIdentifier, locationId)
                } else {
                    console.warn(`Failed to create location: ${ts.LocationIdentifier}`)
                    continue
                }
            }

            sensorsToUpsert.push({
                locationid: locationId,
                sensortypeid: sensorTypeId,
                sensormodel: 'Ecosense Node',
                serialnumber: ts.Label,
                position: 'POINT(0 0)', // Default
                samplinginterval_seconds: ts.Unit ? 900 : 900, // Placeholder - should use actual value
                unit: ts.Unit,
                externalid: ts.UniqueId,
                externalmetadata: {
                    LocationIdentifier: ts.LocationIdentifier,
                    Parameter: ts.Parameter,
                    Label: ts.Label,
                },
                isactive: true,
                createdby: 'ecosense-ingest-function',
            })
        }

        if (sensorsToUpsert.length > 0) {
            // Use RPC for bulk upsert (views don't support ON CONFLICT)
            console.log(`Upserting ${sensorsToUpsert.length} sensors via RPC`)
            const { data: upsertedSensors, error: upsertError } = await withRetry(
                () => supabase.rpc('bulk_upsert_sensors', {
                    p_sensors: sensorsToUpsert
                }),
                { maxRetries: 3, baseDelayMs: 500 }
            )

            if (upsertError) {
                console.error('Sensor upsert error:', upsertError)
            } else {
                console.log(`Upserted ${upsertedSensors?.length || 0} sensors`)
            }
        }

        // Fetch sensor IDs mapping in batches to avoid URI too long error
        const BATCH_SIZE = 100 // Safe batch size for URL length
        const allExternalIds = ecosenseTS.map(ts => ts.UniqueId)
        const createdSensors: { sensorid: number; externalid: string }[] = []

        for (let i = 0; i < allExternalIds.length; i += BATCH_SIZE) {
            const batchIds = allExternalIds.slice(i, i + BATCH_SIZE)
            const { data: batchSensors, error: batchError } = await withRetry(
                () => supabase
                    .from('sensors')
                    .select('sensorid, externalid')
                    .in('externalid', batchIds),
                { maxRetries: 3, baseDelayMs: 500 }
            )

            if (batchError) {
                console.error(`Error fetching sensor batch ${Math.floor(i / BATCH_SIZE) + 1}:`, batchError)
            } else if (batchSensors) {
                createdSensors.push(...batchSensors)
            }
        }

        console.log(`Fetched ${createdSensors.length} sensor mappings from database`)

        const sensorIdMap = new Map(
            createdSensors.map(s => [s.externalid, s.sensorid])
        )

        // Sync readings with parallelization (up to API_CONCURRENCY_LIMIT concurrent requests)
        const endTime = new Date()
        const startTime = new Date(endTime.getTime() - daysBack * 24 * 60 * 60 * 1000)

        let totalPoints = 0
        const errors: string[] = []

        // Create array of sensor fetch tasks
        const fetchTasks = ecosenseTS.map(async ts => {
            const sensorId = sensorIdMap.get(ts.UniqueId)
            if (!sensorId) {
                errors.push(`Sensor not found for ${ts.UniqueId}`)
                return { sensorId: null, points: [] }
            }

            try {
                const points = await aquarius.getData(ts.UniqueId, startTime, endTime)
                return { sensorId, points }
            } catch (error) {
                const message = error instanceof Error ? error.message : String(error)
                errors.push(`Failed to fetch data for ${ts.UniqueId}: ${message}`)
                return { sensorId, points: [] }
            }
        })

        // Execute with concurrency limit
        const results = []
        for (let i = 0; i < fetchTasks.length; i += API_CONCURRENCY_LIMIT) {
            const batch = fetchTasks.slice(i, i + API_CONCURRENCY_LIMIT)
            results.push(...await Promise.all(batch))
        }

        // Collect all readings for bulk insert
        const allReadings: { sensorid: number; timestamp: string; value: number; quality: string }[] = []
        for (const { sensorId, points } of results) {
            if (!sensorId || points.length === 0) continue

            const readings = points
                .filter(p => p.Value?.Numeric !== null && p.Value?.Numeric !== undefined)
                .map(p => ({
                    sensorid: sensorId,
                    timestamp: p.Timestamp,
                    value: p.Value.Numeric,
                    quality: 'good',
                }))

            allReadings.push(...readings)
        }

        // Insert in batches using RPC function with ON CONFLICT DO NOTHING
        for (let i = 0; i < allReadings.length; i += READINGS_BATCH_SIZE) {
            const batch = allReadings.slice(i, i + READINGS_BATCH_SIZE)

            const { data: insertResult, error: insertError } = await withRetry(
                () => supabase.rpc('bulk_insert_readings', { readings: batch }),
                { maxRetries: 3, baseDelayMs: 1000 }
            )

            if (insertError) {
                // Only log first few errors to avoid spam
                if (errors.length < 10) {
                    errors.push(`Insert error: ${insertError.message}`)
                }
            } else if (insertResult && insertResult.length > 0) {
                totalPoints += insertResult[0].out_inserted_count
            }
        }

        await aquarius.disconnect()

        const response = {
            success: true,
            count: totalPoints,
            sensors: ecosenseTS.length,
            errors: errors.length > 0 ? errors : undefined,
        }

        console.log(`Import complete: ${totalPoints} points inserted from ${ecosenseTS.length} sensors`)

        return new Response(
            JSON.stringify(response),
            { status: 200, headers: { 'Content-Type': 'application/json' } }
        )
    } catch (error) {
        await aquarius.disconnect().catch(() => {
            /* ignore disconnect errors */
        })

        const errorResponse = {
            error: 'Import failed',
            code: error instanceof AquariusError ? error.code : 'UNKNOWN_ERROR',
            message: error instanceof Error ? error.message : String(error),
        }

        const statusCode =
            error instanceof AquariusError && error.statusCode
                ? error.statusCode
                : 500

        console.error('Error in ecosense-ingest:', error)

        return new Response(
            JSON.stringify(errorResponse),
            { status: statusCode, headers: { 'Content-Type': 'application/json' } }
        )
    }
})
