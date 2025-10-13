// Supabase Edge Function: Generate S3 Presigned URLs for Point Cloud Files
// This function generates temporary signed URLs for accessing point cloud files in S3

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// AWS S3 SDK v3
import {
  S3Client,
  GetObjectCommand,
} from 'https://esm.sh/@aws-sdk/client-s3@3'
import { getSignedUrl } from 'https://esm.sh/@aws-sdk/s3-request-presigner@3'

interface RequestBody {
  file_path: string
  expiration_seconds?: number
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  try {
    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      }
    )

    // Get user from auth header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authorization token' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const body: RequestBody = await req.json()
    const { file_path, expiration_seconds = 3600 } = body

    if (!file_path) {
      return new Response(
        JSON.stringify({ error: 'file_path is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Validate file_path format (should be s3://bucket/key)
    const s3UriMatch = file_path.match(/^s3:\/\/([^/]+)\/(.+)$/)
    if (!s3UriMatch) {
      return new Response(
        JSON.stringify({ error: 'Invalid S3 URI format. Expected: s3://bucket/key' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const bucket = s3UriMatch[1]
    const key = s3UriMatch[2]

    // Verify user has access to this point cloud in database
    const { data: pointCloud, error: dbError } = await supabaseClient
      .from('PointClouds')
      .select('VariantID, FilePath')
      .eq('FilePath', file_path)
      .single()

    if (dbError || !pointCloud) {
      return new Response(
        JSON.stringify({ error: 'Point cloud not found or access denied' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Initialize S3 client
    const s3Client = new S3Client({
      region: Deno.env.get('S3_REGION') ?? 'us-east-1',
      credentials: {
        accessKeyId: Deno.env.get('S3_ACCESS_KEY_ID') ?? '',
        secretAccessKey: Deno.env.get('S3_SECRET_ACCESS_KEY') ?? '',
      },
      endpoint: Deno.env.get('S3_ENDPOINT'),
    })

    // Generate presigned URL
    const command = new GetObjectCommand({
      Bucket: bucket,
      Key: key,
    })

    const presignedUrl = await getSignedUrl(s3Client, command, {
      expiresIn: expiration_seconds,
    })

    // Return presigned URL
    return new Response(
      JSON.stringify({
        presigned_url: presignedUrl,
        expires_in: expiration_seconds,
        file_path: file_path,
        variant_id: pointCloud.VariantID,
      }),
      {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )
  } catch (error) {
    console.error('Error generating presigned URL:', error)
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        message: error instanceof Error ? error.message : 'Unknown error',
      }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    )
  }
})
