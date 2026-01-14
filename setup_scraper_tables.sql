-- Complete Setup Script for Scraper Job Management System
-- Run this script to create all necessary tables and columns
-- Safe to run multiple times (uses IF NOT EXISTS)

-- =====================================================================
-- Step 1: Create scraper_jobs table (if it doesn't exist)
-- =====================================================================
CREATE TABLE IF NOT EXISTS scraper_jobs (
    id SERIAL PRIMARY KEY,
    job_name VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'queued', -- queued, running, paused, stopped, completed, error
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP NULL,
    paused_at TIMESTAMP NULL,
    stopped_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    process_id VARCHAR(50) NULL,
    max_sales INTEGER NULL,
    target_event_id VARCHAR(50) NULL,
    run_mode VARCHAR(20) DEFAULT 'all', -- all, one, max
    parameters JSONB NULL,
    error_message TEXT NULL,
    created_by VARCHAR(100) DEFAULT 'system',
    rag_processed_at TIMESTAMP NULL -- Track when RAG processing completed
);

-- =====================================================================
-- Step 2: Add resume state columns (if they don't exist)
-- =====================================================================
DO $$ 
BEGIN
    -- Add resume_state JSONB column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'scraper_jobs' AND column_name = 'resume_state') THEN
        ALTER TABLE scraper_jobs ADD COLUMN resume_state JSONB NULL;
    END IF;
    
    -- Add current_event_id column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'scraper_jobs' AND column_name = 'current_event_id') THEN
        ALTER TABLE scraper_jobs ADD COLUMN current_event_id VARCHAR(50) NULL;
    END IF;
    
    -- Add current_lot_number column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'scraper_jobs' AND column_name = 'current_lot_number') THEN
        ALTER TABLE scraper_jobs ADD COLUMN current_lot_number VARCHAR(50) NULL;
    END IF;
    
    -- Add total_events column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'scraper_jobs' AND column_name = 'total_events') THEN
        ALTER TABLE scraper_jobs ADD COLUMN total_events INTEGER NULL;
    END IF;
    
    -- Add current_event_index column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'scraper_jobs' AND column_name = 'current_event_index') THEN
        ALTER TABLE scraper_jobs ADD COLUMN current_event_index INTEGER NULL;
    END IF;
END $$;

-- =====================================================================
-- Step 3: Create scrape_logs table (if it doesn't exist)
-- =====================================================================
CREATE TABLE IF NOT EXISTS scrape_logs (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES scraper_jobs(id) ON DELETE CASCADE,
    log_level VARCHAR(20) NOT NULL, -- info, warning, error, debug
    message TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(100) DEFAULT 'scraper', -- scraper, system, user
    metadata JSONB NULL
);

-- =====================================================================
-- Step 4: Create job_statistics table (if it doesn't exist)
-- =====================================================================
CREATE TABLE IF NOT EXISTS job_statistics (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES scraper_jobs(id) ON DELETE CASCADE,
    total_events INTEGER DEFAULT 0,
    processed_events INTEGER DEFAULT 0,
    total_lots INTEGER DEFAULT 0,
    processed_lots INTEGER DEFAULT 0,
    files_created INTEGER DEFAULT 0,
    files_completed INTEGER DEFAULT 0,
    start_time TIMESTAMP NULL,
    end_time TIMESTAMP NULL,
    duration_seconds INTEGER DEFAULT 0,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- Step 5: Create indexes for better performance
-- =====================================================================
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_status ON scraper_jobs(status);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_created_at ON scraper_jobs(created_at);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_status_created ON scraper_jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_current_event ON scraper_jobs(current_event_id);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_resume_state ON scraper_jobs USING GIN(resume_state);
CREATE INDEX IF NOT EXISTS idx_scrape_logs_job_id ON scrape_logs(job_id);
CREATE INDEX IF NOT EXISTS idx_scrape_logs_timestamp ON scrape_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_job_statistics_job_id ON job_statistics(job_id);

-- =====================================================================
-- Step 6: Insert initial system job (if needed)
-- =====================================================================
INSERT INTO scraper_jobs (job_name, status, created_by) 
VALUES ('System Initialization', 'completed', 'system')
ON CONFLICT DO NOTHING;

-- =====================================================================
-- Verification: Check if tables were created successfully
-- =====================================================================
DO $$
BEGIN
    RAISE NOTICE 'Setup completed!';
    RAISE NOTICE 'Tables created: scraper_jobs, scrape_logs, job_statistics';
    RAISE NOTICE 'Resume state columns added to scraper_jobs';
END $$;
