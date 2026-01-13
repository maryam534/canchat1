-- =====================================================================
-- Schema Updates for Document-Based RAG System
-- Adds support for file upload processing and document chunking
-- =====================================================================

-- Update uploaded_files table to support new RAG processing fields
ALTER TABLE uploaded_files 
ADD COLUMN IF NOT EXISTS content_type VARCHAR(100),
ADD COLUMN IF NOT EXISTS file_size INTEGER,
ADD COLUMN IF NOT EXISTS chunks_created INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS processing_time_seconds INTEGER;

-- Create stamp_chunks table for document-based RAG (separate from lot_chunks)
-- This table stores text chunks from uploaded documents with their embeddings
CREATE TABLE IF NOT EXISTS stamp_chunks (
    id BIGSERIAL PRIMARY KEY,
    chunk_text TEXT NOT NULL,
    embedding VECTOR(1536),
    source_type VARCHAR(50) NOT NULL DEFAULT 'document', -- document, web, pdf, etc.
    source_name VARCHAR(255), -- original filename or source identifier
    chunk_index INTEGER, -- position of chunk in original document
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB -- additional metadata like page numbers, sections, etc.
);

-- Indexes for stamp_chunks table
CREATE INDEX IF NOT EXISTS stamp_chunks_embedding_idx
    ON stamp_chunks USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

CREATE INDEX IF NOT EXISTS idx_stamp_chunks_source_name ON stamp_chunks(source_name);
CREATE INDEX IF NOT EXISTS idx_stamp_chunks_source_type ON stamp_chunks(source_type);
CREATE INDEX IF NOT EXISTS idx_stamp_chunks_created_at ON stamp_chunks(created_at);

-- Update indexes on uploaded_files
CREATE INDEX IF NOT EXISTS idx_uploaded_files_status ON uploaded_files(status);
CREATE INDEX IF NOT EXISTS idx_uploaded_files_processed_at ON uploaded_files(processed_at);
CREATE INDEX IF NOT EXISTS idx_uploaded_files_content_type ON uploaded_files(content_type);

-- Optional: Add a view for easy querying of processed documents
CREATE OR REPLACE VIEW processed_documents AS
SELECT 
    uf.id,
    uf.file_name,
    uf.content_type,
    uf.file_size,
    uf.chunks_created,
    uf.status,
    uf.created_at,
    uf.processed_at,
    COUNT(sc.id) as actual_chunks_in_db,
    AVG(LENGTH(sc.chunk_text)) as avg_chunk_length
FROM uploaded_files uf
LEFT JOIN stamp_chunks sc ON sc.source_name = uf.file_name
WHERE uf.status = 'Completed'
GROUP BY uf.id, uf.file_name, uf.content_type, uf.file_size, uf.chunks_created, uf.status, uf.created_at, uf.processed_at
ORDER BY uf.processed_at DESC;

-- Insert some sample data to verify the schema works
INSERT INTO uploaded_files (file_name, file_path, status, content_type, file_size, chunks_created)
VALUES ('sample_document.pdf', '/uploads/sample_document.pdf', 'Completed', 'application/pdf', 102400, 5)
ON CONFLICT (file_name) DO NOTHING;

-- Verify the tables exist and have the right structure
SELECT 'uploaded_files columns:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'uploaded_files' 
ORDER BY ordinal_position;

SELECT 'stamp_chunks columns:' as info;
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'stamp_chunks' 
ORDER BY ordinal_position;
