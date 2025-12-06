/**
 * Implements exponential backoff retry logic for transient failures
 *
 * Useful for handling temporary network issues, database timeouts, and
 * external API unavailability. Includes jitter to prevent thundering herd.
 *
 * @example
 * const result = await withRetry(
 *   () => fetchFromUnstableAPI(),
 *   { maxRetries: 3, baseDelayMs: 1000 }
 * )
 */

/**
 * Retry configuration options
 */
export interface RetryOptions {
    /** Maximum number of retry attempts (default: 3) */
    maxRetries?: number
    /** Base delay in milliseconds for first retry (default: 1000) */
    baseDelayMs?: number
    /** Maximum delay in milliseconds (prevents unbounded exponential growth) (default: 30000) */
    maxDelayMs?: number
    /** Whether to add jitter to delays (default: true) */
    useJitter?: boolean
}

/**
 * Retryable error class to distinguish from non-retryable errors
 */
export class RetryableError extends Error {
    /**
     * @param {string} message - Error message
     * @param {number} [statusCode] - HTTP status code (if applicable)
     */
    constructor(message: string, public statusCode?: number) {
        super(message)
        this.name = 'RetryableError'
    }
}

/**
 * Determines if an error is worth retrying
 *
 * Retries on network timeouts, 429 (rate limit), and 5xx errors.
 * Does not retry on 4xx errors (except 429) or authorization failures.
 *
 * @param {Error} error - Error to evaluate
 * @returns {boolean} True if error should trigger a retry
 */
function isRetryable(error: unknown): boolean {
    // Network errors (AbortError = timeout)
    if (error instanceof Error && error.name === 'AbortError') {
        return true
    }

    // Check for HTTP status codes in error
    if (error instanceof RetryableError) {
        const code = error.statusCode || 0
        // Retry on rate limit (429) and server errors (5xx)
        if (code === 429 || (code >= 500 && code < 600)) {
            return true
        }
        // Don't retry client errors (4xx) except 429
        if (code >= 400 && code < 500) {
            return false
        }
    }

    // Default to retrying unknown errors (network issues, etc)
    return true
}

/**
 * Calculates delay for next retry with exponential backoff and optional jitter
 *
 * Formula: baseDelay * (2 ^ attemptNumber) + random jitter
 *
 * @param {number} attempt - Retry attempt number (0-indexed)
 * @param {RetryOptions} options - Retry configuration
 * @returns {number} Delay in milliseconds
 */
function calculateDelay(attempt: number, options: RetryOptions): number {
    const baseDelay = options.baseDelayMs || 1000
    const maxDelay = options.maxDelayMs || 30000
    const useJitter = options.useJitter !== false

    // Exponential backoff: 2^attempt * baseDelay
    let delay = baseDelay * Math.pow(2, attempt)

    // Cap at maxDelay
    delay = Math.min(delay, maxDelay)

    // Add jitter (±10% of delay)
    if (useJitter) {
        const jitter = delay * 0.1 * (Math.random() * 2 - 1)
        delay = Math.max(100, delay + jitter) // Minimum 100ms
    }

    return Math.floor(delay)
}

/**
 * Executes a function with exponential backoff retry on transient failures
 *
 * @template T - Return type of the function
 * @param {() => Promise<T>} fn - Async function to execute with retries
 * @param {RetryOptions} [options] - Retry configuration
 * @returns {Promise<T>} Result from successful execution
 * @throws {Error} Final error if all retries exhausted
 *
 * @example
 * // Retry database operation
 * const data = await withRetry(
 *   () => supabase.from('Users').select('*'),
 *   { maxRetries: 5, baseDelayMs: 500 }
 * )
 *
 * @example
 * // Retry external API call
 * const response = await withRetry(
 *   () => fetch('https://api.example.com/data'),
 *   { maxRetries: 3 }
 * )
 */
export async function withRetry<T>(
    fn: () => Promise<T>,
    options: RetryOptions = {}
): Promise<T> {
    const maxRetries = options.maxRetries || 3
    let lastError: Error | unknown = new Error('Unknown error')

    for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
            return await fn()
        } catch (error) {
            lastError = error

            // Don't retry on last attempt
            if (attempt === maxRetries) {
                break
            }

            // Check if error is retryable
            if (!isRetryable(error)) {
                throw error
            }

            // Calculate and wait for backoff delay
            const delay = calculateDelay(attempt, options)
            console.log(
                `Retry attempt ${attempt + 1}/${maxRetries} in ${delay}ms. Error: ${
                    error instanceof Error ? error.message : String(error)
                }`
            )

            await new Promise(resolve => setTimeout(resolve, delay))
        }
    }

    // All retries exhausted
    if (lastError instanceof Error) {
        throw lastError
    }
    throw new Error(`Operation failed after ${maxRetries} retries`)
}

/**
 * Creates a retry-enabled wrapper for an async function
 *
 * Useful for functions that will be called multiple times.
 *
 * @template T - Return type of wrapped function
 * @param {() => Promise<T>} fn - Function to wrap
 * @param {RetryOptions} [options] - Retry configuration
 * @returns {() => Promise<T>} Wrapped function with retry logic
 *
 * @example
 * const fetchWithRetry = createRetryWrapper(
 *   () => fetch('https://api.example.com/data'),
 *   { maxRetries: 3 }
 * )
 * const result = await fetchWithRetry()
 */
export function createRetryWrapper<T>(
    fn: () => Promise<T>,
    options: RetryOptions = {}
): () => Promise<T> {
    return () => withRetry(fn, options)
}
