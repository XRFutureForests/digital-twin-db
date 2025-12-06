import { assertEquals, assertFalse } from 'https://deno.land/std@0.208.0/assert/mod.ts'
import { validateServiceRoleKey, validateHMACSignature } from '../_shared/validators.ts'

Deno.test('validateServiceRoleKey - valid token', () => {
    const validToken = 'test-secret-key-12345'
    Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', validToken)

    const req = new Request('http://localhost:8000', {
        headers: {
            'authorization': `Bearer ${validToken}`,
        },
    })

    assertEquals(validateServiceRoleKey(req), true)
})

Deno.test('validateServiceRoleKey - invalid token', () => {
    Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'valid-secret')

    const req = new Request('http://localhost:8000', {
        headers: {
            'authorization': 'Bearer wrong-secret',
        },
    })

    assertEquals(validateServiceRoleKey(req), false)
})

Deno.test('validateServiceRoleKey - missing authorization header', () => {
    Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'valid-secret')

    const req = new Request('http://localhost:8000', {
        headers: {},
    })

    assertEquals(validateServiceRoleKey(req), false)
})

Deno.test('validateServiceRoleKey - invalid bearer format', () => {
    Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'valid-secret')

    const req = new Request('http://localhost:8000', {
        headers: {
            'authorization': 'Basic dXNlcjpwYXNz',
        },
    })

    assertEquals(validateServiceRoleKey(req), false)
})

Deno.test('validateServiceRoleKey - missing env variable', () => {
    Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY')

    const req = new Request('http://localhost:8000', {
        headers: {
            'authorization': 'Bearer some-token',
        },
    })

    assertEquals(validateServiceRoleKey(req), false)
})

Deno.test('validateHMACSignature - valid signature', async () => {
    const payload = '{"message":"test"}'
    const secret = 'shared-secret'

    // Generate valid HMAC-SHA256 signature
    const encoder = new TextEncoder()
    const keyData = encoder.encode(secret)
    const key = await crypto.subtle.importKey(
        'raw',
        keyData,
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
    )

    const data = encoder.encode(payload)
    const signatureBytes = await crypto.subtle.sign('HMAC', key, data)
    const signature = Array.from(new Uint8Array(signatureBytes))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('')

    const isValid = await validateHMACSignature(payload, signature, secret)
    assertEquals(isValid, true)
})

Deno.test('validateHMACSignature - invalid signature', async () => {
    const payload = '{"message":"test"}'
    const secret = 'shared-secret'
    const invalidSignature = 'invalid0000000000000000000000000000000000000000000000000000000000'

    const isValid = await validateHMACSignature(payload, invalidSignature, secret)
    assertEquals(isValid, false)
})

Deno.test('validateHMACSignature - missing signature', async () => {
    const payload = '{"message":"test"}'
    const secret = 'shared-secret'

    const isValid = await validateHMACSignature(payload, null, secret)
    assertEquals(isValid, false)
})

Deno.test('validateHMACSignature - missing secret', async () => {
    const payload = '{"message":"test"}'
    const signature = 'abc123def456'

    const isValid = await validateHMACSignature(payload, signature, '')
    assertEquals(isValid, false)
})

Deno.test('validateHMACSignature - invalid hex in signature', async () => {
    const payload = '{"message":"test"}'
    const secret = 'shared-secret'
    const invalidHexSignature = 'xyz000' // Invalid hex characters

    const isValid = await validateHMACSignature(payload, invalidHexSignature, secret)
    assertEquals(isValid, false)
})
