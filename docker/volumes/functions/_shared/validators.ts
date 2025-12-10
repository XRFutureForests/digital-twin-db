/**
 * Validates the Service Role Key from the Authorization header
 *
 * Performs constant-time comparison to prevent timing attacks on token verification.
 * The Service Role Key is a sensitive credential that grants full database access.
 *
 * @param {Request} req - HTTP request with Authorization header
 * @param {string} [req.headers['authorization']] - Bearer token to validate
 *
 * @returns {boolean} True if the provided token matches SUPABASE_SERVICE_ROLE_KEY
 *
 * @example
 * if (!validateServiceRoleKey(req)) {
 *   return new Response('Unauthorized', { status: 401 })
 * }
 */
export function validateServiceRoleKey(req: Request): boolean {
    const authHeader = req.headers.get('authorization')

    if (!authHeader || !authHeader.toLowerCase().startsWith('bearer ')) {
        return false
    }

    const token = authHeader.slice(7) // Extract token after "Bearer "
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!serviceRoleKey) {
        console.error('SUPABASE_SERVICE_ROLE_KEY not configured')
        return false
    }

    // Use constant-time comparison to prevent timing attacks
    return constantTimeEqual(token, serviceRoleKey)
}

/**
 * Constant-time string comparison to prevent timing attacks
 *
 * Uses bitwise operations to ensure comparison time is independent of
 * where strings differ, preventing attackers from learning information
 * through response time analysis.
 *
 * @param {string} a - First string to compare
 * @param {string} b - Second string to compare
 * @returns {boolean} True if strings are equal
 */
function constantTimeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) {
        return false
    }

    let result = 0
    for (let i = 0; i < a.length; i++) {
        result |= a.charCodeAt(i) ^ b.charCodeAt(i)
    }

    return result === 0
}
