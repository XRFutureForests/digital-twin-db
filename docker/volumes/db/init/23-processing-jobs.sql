-- XR Future Forests Lab - Processing Jobs Schema
-- This migration creates tables for tracking external processing jobs and workflows

-- Set search path
SET search_path TO shared, public;

-- =============================================================================
-- PROCESSING JOBS TABLE
-- =============================================================================

CREATE TABLE shared.ProcessingJobs (
    ProcessingJobID SERIAL PRIMARY KEY,
    ExternalJobID VARCHAR(200) UNIQUE,
    WorkflowName VARCHAR(200) NOT NULL,
    WorkflowVersion VARCHAR(50),
    Status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (Status IN ('pending', 'running', 'completed', 'failed')),
    SubmittedAt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CompletedAt TIMESTAMPTZ,
    InputData JSONB,
    OutputData JSONB,
    ErrorMessage TEXT,
    SubmittedBy VARCHAR(200),
    CONSTRAINT chk_completed_date CHECK (CompletedAt IS NULL OR CompletedAt >= SubmittedAt)
);

COMMENT ON TABLE shared.ProcessingJobs IS 'Tracks external processing jobs and compute workflows';
COMMENT ON COLUMN shared.ProcessingJobs.ExternalJobID IS 'Unique identifier from external processing system';
COMMENT ON COLUMN shared.ProcessingJobs.Status IS 'Job status: pending, running, completed, failed';
COMMENT ON COLUMN shared.ProcessingJobs.InputData IS 'JSON representation of input parameters and data references';
COMMENT ON COLUMN shared.ProcessingJobs.OutputData IS 'JSON representation of output data references and results';

-- Create indexes
CREATE INDEX idx_processing_jobs_status ON shared.ProcessingJobs(Status);
CREATE INDEX idx_processing_jobs_external_id ON shared.ProcessingJobs(ExternalJobID);
CREATE INDEX idx_processing_jobs_workflow ON shared.ProcessingJobs(WorkflowName);
CREATE INDEX idx_processing_jobs_submitted_at ON shared.ProcessingJobs(SubmittedAt DESC);
CREATE INDEX idx_processing_jobs_submitted_by ON shared.ProcessingJobs(SubmittedBy);

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
GRANT USAGE, SELECT ON SEQUENCE shared.ProcessingJobs_ProcessingJobID_seq TO service_role, authenticated;

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
