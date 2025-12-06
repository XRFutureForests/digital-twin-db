import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { validateServiceRoleKey } from '../_shared/validators.ts'
import { getSupabaseClient } from '../_shared/database.ts'

/**
 * Submits Galaxy workflow jobs (awaiting Galaxy integration)
 *
 * This function creates pending job records in the database. Galaxy API integration
 * is currently stubbed and pending implementation.
 *
 * @route POST /functions/v1/galaxy-submit
 *
 * @param {Request} req - HTTP request with JSON body
 * @param {string} req.headers['content-type'] - Must be 'application/json'
 * @param {string} req.headers['authorization'] - Bearer token with SERVICE_ROLE_KEY
 * @param {Object} req.body - Workflow submission details
 * @param {string} req.body.workflow_name - Name/ID of Galaxy workflow (required)
 * @param {string} [req.body.workflow_version='latest'] - Workflow version
 * @param {Object} [req.body.input_data] - Input parameters for workflow
 *
 * @returns {Response} JSON response with job details
 * @returns {Response.body.success} boolean - Whether job was created
 * @returns {Response.body.job_id} number - Internal job ID
 * @returns {Response.body.message} string - Status message
 *
 * @error 401 Unauthorized - Missing or invalid SERVICE_ROLE_KEY
 * @error 400 Bad Request - Missing workflow_name
 * @error 415 Unsupported Media Type - Content-Type is not application/json
 * @error 500 Internal Server Error - Database insertion failed
 *
 * @example
 * curl -X POST "http://localhost:54321/functions/v1/galaxy-submit" \
 *   -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
 *   -H "Content-Type: application/json" \
 *   -d '{
 *     "workflow_name": "tree_detection",
 *     "workflow_version": "v2",
 *     "input_data": {"point_cloud_id": 123}
 *   }'
 *
 * // Response (200 OK)
 * {
 *   "success": true,
 *   "job_id": 456,
 *   "message": "Job created (Galaxy integration pending implementation)"
 * }
 */
console.log('galaxy-submit function started')

serve(async (req: Request) => {
    // Validate authentication
    if (!validateServiceRoleKey(req)) {
        return new Response(
            JSON.stringify({ error: 'Unauthorized' }),
            { status: 401, headers: { 'Content-Type': 'application/json' } }
        )
    }

    try {
        // Validate Content-Type
        const contentType = req.headers.get('content-type')?.toLowerCase() || ''
        if (!contentType.includes('application/json')) {
            return new Response(
                JSON.stringify({ error: 'Invalid Content-Type', code: 'INVALID_CONTENT_TYPE', message: 'Content-Type must be application/json' }),
                { status: 415, headers: { 'Content-Type': 'application/json' } }
            )
        }

        // Parse request body
        const body = await req.json()
        const { workflow_name, workflow_version, input_data } = body

        if (!workflow_name) {
            return new Response(
                JSON.stringify({ error: 'workflow_name is required', code: 'MISSING_WORKFLOW_NAME' }),
                { status: 400, headers: { 'Content-Type': 'application/json' } }
            )
        }

        // TODO: Implement Galaxy API integration
        // const galaxyApiUrl = Deno.env.get('GALAXY_API_URL')
        // const galaxyApiKey = Deno.env.get('GALAXY_API_KEY')

        // For now, create a pending job record
        const supabase = getSupabaseClient()

        const { data, error } = await supabase
            .from('ProcessingJobs')
            .insert({
                WorkflowName: workflow_name,
                WorkflowVersion: workflow_version || 'latest',
                Status: 'pending',
                InputData: input_data,
                SubmittedBy: 'galaxy-submit-function',
            })
            .select('JobID')
            .single()

        if (error) {
            throw error
        }

        console.log(`Created pending job: ${data.JobID}`)

        // TODO: Submit to Galaxy API and update ExternalJobID
        // const galaxyResponse = await fetch(`${galaxyApiUrl}/workflows`, {
        //   method: 'POST',
        //   headers: {
        //     'X-API-KEY': galaxyApiKey,
        //     'Content-Type': 'application/json',
        //   },
        //   body: JSON.stringify({
        //     workflow_id: workflow_name,
        //     inputs: input_data,
        //   }),
        // })

        return new Response(
            JSON.stringify({
                success: true,
                job_id: data.JobID,
                message: 'Job created (Galaxy integration pending implementation)',
            }),
            { status: 200, headers: { 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        console.error('Error in galaxy-submit:', error)
        return new Response(
            JSON.stringify({ error: 'Job submission failed' }),
            { status: 500, headers: { 'Content-Type': 'application/json' } }
        )
    }
})
