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

/**
 * Validates HMAC-SHA256 signature from webhook requests
 *
 * Used by Galaxy webhook callbacks to verify authenticity of messages.
 * Compares provided signature against computed HMAC of payload.
 *
 * @param {string} payload - Request body as string (typically JSON)
 * @param {string | null} signature - HMAC-SHA256 signature as hex string
 * @param {string} secret - Shared secret (GALAXY_WEBHOOK_SECRET)
 *
 * @returns {Promise<boolean>} True if signature is valid
 *
 * @example
 * const isValid = await validateHMACSignature(
 *   requestBody,
 *   req.headers.get('x-galaxy-signature'),
 *   Deno.env.get('GALAXY_WEBHOOK_SECRET')
 * )
 */
export async function validateHMACSignature(
    payload: string,
    signature: string | null,
    secret: string
): Promise<boolean> {
    if (!signature) {
        console.error('HMAC validation: no signature provided')
        return false
    }

    if (!secret) {
        console.error('HMAC validation: no secret configured')
        return false
    }

    try {
        const encoder = new TextEncoder()
        const keyData = encoder.encode(secret)

        const key = await crypto.subtle.importKey(
            'raw',
            keyData,
            { name: 'HMAC', hash: 'SHA-256' },
            false,
            ['verify']
        )

        const data = encoder.encode(payload)
        const signatureBytes = hexToBytes(signature)

        return await crypto.subtle.verify('HMAC', key, signatureBytes, data)
    } catch (error) {
        console.error('HMAC validation error:', error)
        return false
    }
}

/**
 * Converts a hex string to a Uint8Array
 *
 * @param {string} hex - Hex string (even length, valid hex characters)
 * @returns {Uint8Array} Decoded bytes
 * @throws {Error} If hex string is invalid
 *
 * @example
 * const bytes = hexToBytes('48656c6c6f')  // "Hello"
 */
function hexToBytes(hex: string): Uint8Array {
    // Validate hex string format (even length, valid hex characters)
    if (hex.length % 2 !== 0) {
        throw new Error('Invalid hex string: odd length')
    }

    if (!/^[0-9a-fA-F]*$/.test(hex)) {
        throw new Error('Invalid hex string: contains non-hex characters')
    }

    const bytes = new Uint8Array(hex.length / 2)
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16)
    }
    return bytes
}
