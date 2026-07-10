-- XR Future Forests Lab - Processing Jobs Schema
-- This migration creates tables for tracking external processing jobs and workflows

-- Set search path
SET search_path TO shared, public;

-- =============================================================================
-- PROCESSING JOBS TABLE
-- =============================================================================

CREATE TABLE shared.ProcessingJobs (
    processing_job_id SERIAL PRIMARY KEY,
    external_job_id VARCHAR(200) UNIQUE,
    workflow_name VARCHAR(200) NOT NULL,
    workflow_version VARCHAR(50),
    Status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (Status IN ('pending', 'running', 'completed', 'failed')),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    input_data JSONB,
    output_data JSONB,
    error_message TEXT,
    submitted_by VARCHAR(200),
    CONSTRAINT chk_completed_date CHECK (completed_at IS NULL OR completed_at >= submitted_at)
);

COMMENT ON TABLE shared.ProcessingJobs IS 'Tracks external processing jobs and compute workflows';
COMMENT ON COLUMN shared.ProcessingJobs.external_job_id IS 'Unique identifier from external processing system';
COMMENT ON COLUMN shared.ProcessingJobs.Status IS 'Job status: pending, running, completed, failed';
COMMENT ON COLUMN shared.ProcessingJobs.input_data IS 'JSON representation of input parameters and data references';
COMMENT ON COLUMN shared.ProcessingJobs.output_data IS 'JSON representation of output data references and results';

-- Create indexes
CREATE INDEX idx_processing_jobs_status ON shared.ProcessingJobs(Status);
CREATE INDEX idx_processing_jobs_external_id ON shared.ProcessingJobs(external_job_id);
CREATE INDEX idx_processing_jobs_workflow ON shared.ProcessingJobs(workflow_name);
CREATE INDEX idx_processing_jobs_submitted_at ON shared.ProcessingJobs(submitted_at DESC);
CREATE INDEX idx_processing_jobs_submitted_by ON shared.ProcessingJobs(submitted_by);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE shared.ProcessingJobs ENABLE ROW LEVEL SECURITY;

-- Allow service_role full access
CREATE POLICY "Enable all for service_role" ON shared.ProcessingJobs
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Allow authenticated users to view all jobs
CREATE POLICY "Enable read for authenticated users" ON shared.ProcessingJobs
    FOR SELECT
    TO authenticated
    USING (true);

-- =============================================================================
-- GRANTS
-- =============================================================================

GRANT ALL ON shared.ProcessingJobs TO service_role;
GRANT SELECT ON shared.ProcessingJobs TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE shared.processingjobs_processing_job_id_seq TO service_role, authenticated;

-- =============================================================================
-- SUMMARY
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Processing Jobs Schema Created';
    RAISE NOTICE '=======================================================';
    RAISE NOTICE 'Table: shared.ProcessingJobs - Ready for external workflow integration';
    RAISE NOTICE '=======================================================';
END $$;
