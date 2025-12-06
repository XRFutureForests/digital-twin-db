import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { validateHMACSignature } from '../_shared/validators.ts'
import { getSupabaseClient } from '../_shared/database.ts'

/**
 * Webhook receiver for Galaxy workflow completion callbacks
 *
 * This function receives workflow completion notifications from Galaxy. It validates
 * the HMAC signature to ensure authenticity, updates the job status in the database,
 * and prepares for result processing (currently a TODO).
 *
 * @route POST /functions/v1/galaxy-callback
 *
 * @param {Request} req - HTTP request with HMAC signature header
 * @param {string} req.headers['x-galaxy-signature'] - HMAC-SHA256 signature of request body
 * @param {Object} req.body - JSON payload with Galaxy workflow results
 * @param {string} req.body.external_job_id - Galaxy job ID (required)
 * @param {string} [req.body.status] - Job status (pending|running|completed|failed, defaults to completed)
 * @param {Object} [req.body.output_data] - Workflow output data (varies by workflow type)
 * @param {string} [req.body.error_message] - Error message if job failed
 *
 * @returns {Response} JSON response confirming callback receipt
 * @returns {Response.body.success} boolean - Whether the callback was processed successfully
 *
 * @error 401 Unauthorized - Invalid HMAC signature
 * @error 400 Bad Request - Missing external_job_id
 * @error 500 Internal Server Error - Database update or processing errors
 *
 * @example
 * // Galaxy sends this webhook:
 * curl -X POST "http://localhost:54321/functions/v1/galaxy-callback" \
 *   -H "x-galaxy-signature: abc123def456..." \
 *   -H "Content-Type: application/json" \
 *   -d '{
 *     "external_job_id": "workflow_123",
 *     "status": "completed",
 *     "output_data": {...}
 *   }'
 */
console.log('galaxy-callback function started')

interface JobUpdate {
    Status: 'pending' | 'running' | 'completed' | 'failed'
    CompletedAt: string
    OutputData?: Record<string, unknown>
    ErrorMessage?: string
}

serve(async (req: Request) => {
    try {
        // Get webhook secret
        const webhookSecret = Deno.env.get('GALAXY_WEBHOOK_SECRET')
        if (!webhookSecret) {
            throw new Error('GALAXY_WEBHOOK_SECRET not configured')
        }

        // Get signature from header
        const signature = req.headers.get('x-galaxy-signature')
        const body = await req.text()

        // Validate HMAC signature
        const isValid = await validateHMACSignature(body, signature, webhookSecret)
        if (!isValid) {
            return new Response(
                JSON.stringify({ error: 'Invalid signature' }),
                { status: 401, headers: { 'Content-Type': 'application/json' } }
            )
        }

        // Parse callback data
        const data = JSON.parse(body)
        const { external_job_id, status, output_data, error_message } = data

        if (!external_job_id) {
            return new Response(
                JSON.stringify({ error: 'external_job_id is required' }),
                { status: 400, headers: { 'Content-Type': 'application/json' } }
            )
        }

        // TODO: Implement result processing and data insertion
        // For now, just update job status
        const supabase = getSupabaseClient()

        const validStatuses: Array<'pending' | 'running' | 'completed' | 'failed'> = ['pending', 'running', 'completed', 'failed']
        const jobStatus = (status && validStatuses.includes(status)) ? status : 'completed'

        const updateData: JobUpdate = {
            Status: jobStatus,
            CompletedAt: new Date().toISOString(),
        }

        if (output_data) {
            updateData.OutputData = output_data
        }

        if (error_message) {
            updateData.ErrorMessage = error_message
            updateData.Status = 'failed'
        }

        const { error: updateError } = await supabase
            .from('ProcessingJobs')
            .update(updateData)
            .eq('ExternalJobID', external_job_id)

        if (updateError) {
            throw updateError
        }

        console.log(`Updated job ${external_job_id}: ${status}`)

        // TODO: Parse output_data and insert results into appropriate tables
        // - If tree detection results → insert into Trees table
        // - If environmental processing → insert into Environments table
        // - etc.

        return new Response(
            JSON.stringify({ success: true }),
            { status: 200, headers: { 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('Error in galaxy-callback:', error)
        return new Response(
            JSON.stringify({ error: 'Callback processing failed' }),
            { status: 500, headers: { 'Content-Type': 'application/json' } }
        )
    }
})
