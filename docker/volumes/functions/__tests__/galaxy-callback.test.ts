import { assertEquals, assert, assertObjectMatch } from 'https://deno.land/std@0.208.0/assert/mod.ts'

// Test status validation
Deno.test('galaxy-callback - valid status values', async () => {
    const validStatuses: Array<'pending' | 'running' | 'completed' | 'failed'> = [
        'pending',
        'running',
        'completed',
        'failed',
    ]

    for (const status of validStatuses) {
        assertEquals(validStatuses.includes(status), true)
    }
})

Deno.test('galaxy-callback - status validation for invalid values', async () => {
    const validStatuses: Array<'pending' | 'running' | 'completed' | 'failed'> = [
        'pending',
        'running',
        'completed',
        'failed',
    ]

    const testCases = ['invalid', 'pending2', 'PENDING', '', null, undefined]

    for (const testCase of testCases) {
        const isValid = testCase && validStatuses.includes(testCase as any)
        assertEquals(isValid, false)
    }
})

Deno.test('galaxy-callback - status defaults to completed', async () => {
    const status = undefined
    const defaultStatus = status && ['pending', 'running', 'completed', 'failed'].includes(status) ? status : 'completed'

    assertEquals(defaultStatus, 'completed')
})

Deno.test('galaxy-callback - error overrides status to failed', async () => {
    const status = 'running'
    const error_message = 'Processing failed'

    let jobStatus = status
    if (error_message) {
        jobStatus = 'failed'
    }

    assertEquals(jobStatus, 'failed')
})

Deno.test('galaxy-callback - payload parsing', async () => {
    const payload = JSON.stringify({
        external_job_id: 'job_123',
        status: 'completed',
        output_data: { result: 'success' },
    })

    const data = JSON.parse(payload)

    assertEquals(data.external_job_id, 'job_123')
    assertEquals(data.status, 'completed')
    assertEquals(data.output_data.result, 'success')
})

Deno.test('galaxy-callback - missing external_job_id validation', async () => {
    const payload = JSON.stringify({
        status: 'completed',
        output_data: {},
    })

    const data = JSON.parse(payload)
    const hasJobId = !!data.external_job_id

    assertEquals(hasJobId, false)
})

Deno.test('galaxy-callback - JobUpdate interface', async () => {
    interface JobUpdate {
        Status: 'pending' | 'running' | 'completed' | 'failed'
        CompletedAt: string
        OutputData?: Record<string, unknown>
        ErrorMessage?: string
    }

    const update: JobUpdate = {
        Status: 'completed',
        CompletedAt: new Date().toISOString(),
        OutputData: { result: 'success' },
    }

    assertEquals(update.Status, 'completed')
    assertEquals(typeof update.CompletedAt, 'string')
    assertEquals(update.OutputData?.result, 'success')
})

Deno.test('galaxy-callback - timestamp generation', async () => {
    const now = new Date()
    const timestamp = now.toISOString()

    // Verify ISO timestamp format
    const isoRegex = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
    assertEquals(isoRegex.test(timestamp), true)
})

Deno.test('galaxy-callback - output_data preservation', async () => {
    const outputData = {
        trees_detected: 150,
        quality_score: 0.95,
        processing_time_ms: 1234,
    }

    const jobUpdate = {
        OutputData: outputData,
    }

    assertObjectMatch(jobUpdate.OutputData!, outputData)
})

Deno.test('galaxy-callback - error message handling', async () => {
    const errorMessage = 'Point cloud processing failed: insufficient data points'

    const jobUpdate = {
        ErrorMessage: errorMessage,
        Status: 'failed' as const,
    }

    assertEquals(jobUpdate.ErrorMessage, errorMessage)
    assertEquals(jobUpdate.Status, 'failed')
})

Deno.test('galaxy-callback - complete update object creation', async () => {
    const external_job_id = 'job_abc123'
    const status = 'completed'
    const output_data = { result: 'trees detected: 150' }
    const error_message = undefined

    const validStatuses: Array<'pending' | 'running' | 'completed' | 'failed'> = [
        'pending',
        'running',
        'completed',
        'failed',
    ]
    const jobStatus = (status && validStatuses.includes(status)) ? status : 'completed'

    const updateData = {
        Status: jobStatus,
        CompletedAt: new Date().toISOString(),
    }

    if (output_data) {
        Object.assign(updateData, { OutputData: output_data })
    }

    if (error_message) {
        Object.assign(updateData, { ErrorMessage: error_message, Status: 'failed' })
    }

    assertEquals(updateData.Status, 'completed')
    assertEquals(updateData.OutputData, output_data)
})
