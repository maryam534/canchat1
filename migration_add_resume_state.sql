-- Migration: Add resume state tracking columns to scraper_jobs table
-- Date: 2024
-- Description: Adds columns for real-time monitoring and pause/resume functionality

-- Add resume state columns if they don't exist
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

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_current_event ON scraper_jobs(current_event_id);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_resume_state ON scraper_jobs USING GIN(resume_state);
