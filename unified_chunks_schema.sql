-- =====================================================================
-- Unified Chunks Table Schema
-- Single table for ALL content types: scraping, uploads, lots, etc.
-- =====================================================================

-- Drop old tables if they exist (backup data first if needed)
DROP TABLE IF EXISTS stamp_chunks CASCADE;
DROP TABLE IF EXISTS lot_chunks CASCADE;
DROP TABLE IF EXISTS rag_chunks CASCADE;

-- Create unified chunks table
CREATE TABLE IF NOT EXISTS chunks (
    id BIGSERIAL PRIMARY KEY,
    
    -- Core content
    chunk_text TEXT NOT NULL,
    embedding VECTOR(1536),
    
    -- Source identification
    source_type VARCHAR(50) NOT NULL, -- 'lot', 'document', 'web', 'scraping', 'manual'
    source_name VARCHAR(255), -- filename, URL, lot number, etc.
    source_id VARCHAR(100), -- lot_pk, file_id, event_id, etc.
    
    -- Chunk metadata
    chunk_index INTEGER DEFAULT 1, -- position in original content
    chunk_size INTEGER, -- number of characters in this chunk
    
    -- Content metadata
    content_type VARCHAR(100), -- application/pdf, text/html, etc.
    title VARCHAR(500), -- document title, lot title, page title
    category VARCHAR(100), -- lot category, document type, etc.
    
    -- Processing metadata
    created_at TIMESTAMPTZ DEFAULT now(),
    processed_at TIMESTAMPTZ,
    embedding_model VARCHAR(100) DEFAULT 'text-embedding-3-small',
    processing_version VARCHAR(20) DEFAULT '1.0',
    
    -- Additional structured data
    metadata JSONB, -- prices, dates, URLs, etc.
    
    -- Search optimization
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english', chunk_text)) STORED,
    
    -- Ensure uniqueness per source
    CONSTRAINT unique_chunk_per_source UNIQUE (source_type, source_id, chunk_index)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS chunks_embedding_idx
    ON chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_chunks_source_type ON chunks(source_type);
CREATE INDEX IF NOT EXISTS idx_chunks_source_name ON chunks(source_name);
CREATE INDEX IF NOT EXISTS idx_chunks_source_id ON chunks(source_id);
CREATE INDEX IF NOT EXISTS idx_chunks_created_at ON chunks(created_at);
CREATE INDEX IF NOT EXISTS idx_chunks_category ON chunks(category);
CREATE INDEX IF NOT EXISTS idx_chunks_search_vector ON chunks USING gin(search_vector);

-- Create a view for easy content browsing
CREATE OR REPLACE VIEW content_summary AS
SELECT 
    source_type,
    source_name,
    COUNT(*) as chunk_count,
    SUM(chunk_size) as total_characters,
    MIN(created_at) as first_created,
    MAX(created_at) as last_created,
    STRING_AGG(DISTINCT category, ', ') as categories,
    COUNT(DISTINCT embedding) FILTER (WHERE embedding IS NOT NULL) as embedded_chunks
FROM chunks
GROUP BY source_type, source_name
ORDER BY last_created DESC;

-- Insert sample data to verify schema
INSERT INTO chunks (chunk_text, source_type, source_name, category, title, metadata)
VALUES 
    ('Sample lot description for testing', 'lot', 'lot-12345', 'stamps', 'Sample Stamp Lot', '{"price": 100, "currency": "USD"}'),
    ('Sample document content for testing', 'document', 'test.pdf', 'manual', 'Test Document', '{"pages": 1, "size": 1024}'),
    ('Sample web content for testing', 'web', 'example.com', 'information', 'Web Page Title', '{"url": "https://example.com"}')
ON CONFLICT DO NOTHING;

-- Verify the table structure
SELECT 'Chunks table created successfully' as status;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'chunks' 
ORDER BY ordinal_position;
