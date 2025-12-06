/**
 * Aquarius API configuration from environment variables
 */
interface AquariusConfig {
    hostname: string
    username: string
    password: string
}

/**
 * Aquarius time series description metadata
 */
interface TimeSeriesDescription {
    UniqueId: string
    LocationIdentifier: string
    Parameter: string
    Label: string
    Unit: string
}

/**
 * Single data point from Aquarius time series
 */
interface DataPoint {
    Timestamp: string
    Value: {
        Numeric: number | null
    }
}

/**
 * Custom error class for Aquarius API errors
 *
 * Includes error code and optional HTTP status code for proper error handling.
 */
export class AquariusError extends Error {
    /**
     * @param {string} code - Error code (e.g., 'AUTH_FAILED', 'TIMEOUT')
     * @param {string} message - Human-readable error message
     * @param {number} [statusCode] - HTTP status code (401, 408, 500, etc.)
     */
    constructor(
        public code: string,
        message: string,
        public statusCode?: number
    ) {
        super(message)
        this.name = 'AquariusError'
    }
}

/**
 * Client for Aquarius TSDB API
 *
 * Handles authentication, time series discovery, and data retrieval from Aquarius.
 * All requests include 30-second timeout and automatic connection cleanup.
 *
 * @example
 * const aquarius = new AquariusClient()
 * await aquarius.connect()
 * const descriptions = await aquarius.getTimeSeriesDescriptions()
 * const data = await aquarius.getData(uniqueId, startDate, endDate)
 * await aquarius.disconnect()
 */
export class AquariusClient {
    private config: AquariusConfig
    private token: string | null = null
    private baseUrl: string
    private requestTimeout = 30000 // 30 seconds

    /**
     * Initializes Aquarius client with environment configuration
     * @throws {AquariusError} If required environment variables are missing
     */
    constructor() {
        this.config = {
            hostname: Deno.env.get('AQUARIUS_HOSTNAME') || '',
            username: Deno.env.get('AQUARIUS_USERNAME') || '',
            password: Deno.env.get('AQUARIUS_PASSWORD') || '',
        }

        if (!this.config.hostname || !this.config.username || !this.config.password) {
            throw new AquariusError(
                'MISSING_CONFIG',
                'Aquarius configuration incomplete: AQUARIUS_HOSTNAME, AQUARIUS_USERNAME, and AQUARIUS_PASSWORD must be set'
            )
        }

        const hostname = this.config.hostname.replace(/\/$/, '')
        this.baseUrl = hostname.includes('/AQUARIUS')
            ? `${hostname}/Publish/v2`
            : `${hostname}/AQUARIUS/Publish/v2`
    }

    /**
     * Fetch with automatic timeout (30 seconds)
     * @private
     */
    private async fetchWithTimeout(url: string, options: RequestInit): Promise<Response> {
        const controller = new AbortController()
        const timeoutId = setTimeout(() => controller.abort(), this.requestTimeout)

        try {
            return await fetch(url, {
                ...options,
                signal: controller.signal,
            })
        } finally {
            clearTimeout(timeoutId)
        }
    }

    /**
     * Authenticates with Aquarius API and obtains session token
     * @throws {AquariusError} If authentication fails or timeout occurs
     */
    async connect(): Promise<void> {
        try {
            const response = await this.fetchWithTimeout(`${this.baseUrl}/session`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    Username: this.config.username,
                    EncryptedPassword: this.config.password,
                }),
            })

            if (!response.ok) {
                throw new AquariusError(
                    'AUTH_FAILED',
                    `Aquarius authentication failed: ${response.statusText}`,
                    response.status
                )
            }

            const tokenText = await response.text()
            this.token = tokenText.replace(/"/g, '')

            if (!this.token) {
                throw new AquariusError(
                    'EMPTY_TOKEN',
                    'Aquarius returned empty authentication token'
                )
            }

            console.log('Connected to Aquarius API')
        } catch (error) {
            if (error instanceof AquariusError) {
                throw error
            }

            if (error instanceof Error && error.name === 'AbortError') {
                throw new AquariusError(
                    'TIMEOUT',
                    `Aquarius connection timeout (${this.requestTimeout}ms)`
                )
            }

            throw new AquariusError(
                'CONNECTION_ERROR',
                `Failed to connect to Aquarius: ${error instanceof Error ? error.message : String(error)}`
            )
        }
    }

    /**
     * Closes Aquarius session (cleanup operation)
     * Does not throw errors - logs warnings if disconnect fails
     */
    async disconnect(): Promise<void> {
        if (this.token) {
            try {
                await this.fetchWithTimeout(`${this.baseUrl}/session`, {
                    method: 'DELETE',
                    headers: { 'X-Authentication-Token': this.token },
                })
            } catch (error) {
                // Log but don't throw on disconnect errors - cleanup should not fail the request
                console.warn(
                    `Aquarius disconnect warning: ${error instanceof Error ? error.message : String(error)}`
                )
            }
        }

        this.token = null
    }

    /**
     * Fetches all time series descriptions from Aquarius
     * @returns {Promise<TimeSeriesDescription[]>} Array of available time series
     * @throws {AquariusError} If not connected or API error occurs
     */
    async getTimeSeriesDescriptions(): Promise<TimeSeriesDescription[]> {
        if (!this.token) {
            throw new AquariusError(
                'NOT_CONNECTED',
                'Not connected to Aquarius. Call connect() first.'
            )
        }

        try {
            const response = await this.fetchWithTimeout(
                `${this.baseUrl}/GetTimeSeriesDescriptionList`,
                {
                    headers: { 'X-Authentication-Token': this.token },
                }
            )

            if (!response.ok) {
                throw new AquariusError(
                    'API_ERROR',
                    `Failed to fetch time series descriptions: ${response.statusText}`,
                    response.status
                )
            }

            const data = await response.json()
            const descriptions = data.TimeSeriesDescriptions

            if (!Array.isArray(descriptions)) {
                throw new AquariusError(
                    'INVALID_RESPONSE',
                    'Aquarius API returned invalid response format (expected TimeSeriesDescriptions array)'
                )
            }

            console.log(`Fetched ${descriptions.length} time series descriptions`)
            return descriptions
        } catch (error) {
            if (error instanceof AquariusError) {
                throw error
            }

            if (error instanceof Error && error.name === 'AbortError') {
                throw new AquariusError(
                    'TIMEOUT',
                    `Aquarius API timeout (${this.requestTimeout}ms) fetching time series descriptions`
                )
            }

            throw new AquariusError(
                'REQUEST_ERROR',
                `Error fetching time series descriptions: ${error instanceof Error ? error.message : String(error)}`
            )
        }
    }

    /**
     * Fetches corrected time series data for a specific sensor
     *
     * @param {string} uniqueId - Time series unique ID from Aquarius
     * @param {Date} startTime - Start of data range (inclusive)
     * @param {Date} endTime - End of data range (inclusive)
     * @returns {Promise<DataPoint[]>} Array of data points (empty if not found)
     * @throws {AquariusError} If not connected or API error occurs
     *
     * @example
     * const data = await client.getData(
     *   'sensor_123_UniqueID',
     *   new Date('2024-01-01'),
     *   new Date('2024-01-31')
     * )
     */
    async getData(
        uniqueId: string,
        startTime: Date,
        endTime: Date
    ): Promise<DataPoint[]> {
        if (!this.token) {
            throw new AquariusError(
                'NOT_CONNECTED',
                'Not connected to Aquarius. Call connect() first.'
            )
        }

        try {
            const startStr = startTime.toISOString().replace(/\.\d+Z$/, 'Z')
            const endStr = endTime.toISOString().replace(/\.\d+Z$/, 'Z')

            const params = new URLSearchParams({
                TimeSeriesUniqueId: uniqueId,
                QueryFrom: startStr,
                QueryTo: endStr,
            })

            const response = await this.fetchWithTimeout(
                `${this.baseUrl}/GetTimeSeriesCorrectedData?${params}`,
                {
                    headers: { 'X-Authentication-Token': this.token },
                }
            )

            if (!response.ok) {
                // Don't throw for not found (common case) - return empty array
                if (response.status === 404) {
                    console.warn(
                        `Time series not found: ${uniqueId} (${startStr} to ${endStr})`
                    )
                    return []
                }

                throw new AquariusError(
                    'API_ERROR',
                    `Failed to fetch data for ${uniqueId}: ${response.statusText}`,
                    response.status
                )
            }

            const data = await response.json()
            const points = data.Points

            if (!Array.isArray(points)) {
                throw new AquariusError(
                    'INVALID_RESPONSE',
                    `Invalid response format for ${uniqueId} (expected Points array)`
                )
            }

            return points
        } catch (error) {
            if (error instanceof AquariusError) {
                throw error
            }

            if (error instanceof Error && error.name === 'AbortError') {
                throw new AquariusError(
                    'TIMEOUT',
                    `Aquarius API timeout (${this.requestTimeout}ms) fetching data for ${uniqueId}`
                )
            }

            throw new AquariusError(
                'REQUEST_ERROR',
                `Error fetching data for ${uniqueId}: ${error instanceof Error ? error.message : String(error)}`
            )
        }
    }
}
