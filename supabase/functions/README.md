# Supabase Edge Functions for XR Future Forests Lab

Edge Functions provide serverless business logic for the digital twin system. These run on Deno and can be invoked via HTTP endpoints.

## Available Functions

### 1. S3 Presigned URL Generator
**Path**: `/functions/v1/s3-presigned-url`
**Method**: POST

Generates temporary presigned URLs for accessing point cloud files stored in S3 buckets.

**Request Body**:
```json
{
  "file_path": "s3://xr-forests-pointclouds/plot-a/scan.las",
  "expiration_seconds": 3600
}
```

**Response**:
```json
{
  "presigned_url": "https://s3.amazonaws.com/...",
  "expires_in": 3600,
  "file_path": "s3://...",
  "variant_id": 123
}
```

**Authentication**: Requires valid Supabase auth token

## Planned Functions

### 2. Process Point Cloud
Orchestrates point cloud processing workflows by creating processing variants and triggering external processing services.

### 3. Aggregate Sensor Data
Aggregates sensor readings into environment variants based on time ranges and location.

### 4. Audit Logger
Automatically logs data changes with user attribution for field-level audit tracking.

### 5. Growth Simulation Coordinator
Interfaces with external growth models (SILVA) and stores simulation results as tree variants.

## Local Development

### Prerequisites
- Supabase CLI installed
- Docker Compose running

### Running Functions Locally
```bash
# Start all Supabase services
docker-compose up -d

# Functions will be available at:
# http://localhost:54321/functions/v1/function-name
```

### Testing Functions
```bash
curl -X POST \
  http://localhost:54321/functions/v1/s3-presigned-url \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"file_path": "s3://bucket/file.las"}'
```

## Deploying Functions

Functions are deployed as part of the Docker Compose stack. To update:

1. Edit function code in `supabase/functions/function-name/`
2. Restart the functions container:
```bash
docker-compose restart functions
```

## Environment Variables

Edge Functions have access to these environment variables (configured in docker-compose.yml):
- `SUPABASE_URL` - Supabase API URL
- `SUPABASE_ANON_KEY` - Anonymous API key
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key
- `SUPABASE_DB_URL` - Direct database connection string
- `S3_ENDPOINT` - S3 endpoint URL
- `S3_REGION` - AWS region
- `S3_BUCKET_NAME` - Default S3 bucket
- `S3_ACCESS_KEY_ID` - S3 access key
- `S3_SECRET_ACCESS_KEY` - S3 secret key

## Security

- All functions require authentication via Supabase auth tokens
- RLS policies are enforced for database queries
- S3 credentials are server-side only and never exposed to clients
- Presigned URLs expire after configured duration (default 1 hour)

## Development Guidelines

1. **Use TypeScript** for type safety
2. **Handle CORS** for browser requests
3. **Validate Input** - never trust client data
4. **Use Supabase Client** for database queries to respect RLS
5. **Log Errors** for debugging
6. **Keep Functions Small** - single responsibility

## Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [Deno Documentation](https://deno.land/manual)
- [AWS SDK for Deno](https://github.com/aws/aws-sdk-js-v3)
