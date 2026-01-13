<!---
    Database Setup - Create Unified Chunks Table
--->

<!DOCTYPE html>
<html>
<head>
    <title>Database Setup</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">

<div class="max-w-4xl mx-auto">
    <div class="bg-white rounded-xl shadow-sm p-6">
        <h1 class="text-2xl font-bold text-gray-800 mb-4">🗄️ Database Setup</h1>
        <p class="text-gray-600 mb-6">Create the unified chunks table for your RAG system</p>

        <cfif structKeyExists(url, "action") AND url.action EQ "setup">
            <div class="bg-blue-50 p-4 rounded-lg mb-6">
                <h3 class="text-blue-800 font-semibold mb-2">Setting up database...</h3>
            </div>

            <cftry>
                <!--- Create the unified chunks table --->
                <cfquery datasource="#application.db.dsn#">
                    CREATE EXTENSION IF NOT EXISTS vector
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    DROP TABLE IF EXISTS stamp_chunks CASCADE
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    DROP TABLE IF EXISTS lot_chunks CASCADE
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE TABLE IF NOT EXISTS chunks (
                        id BIGSERIAL PRIMARY KEY,
                        chunk_text TEXT NOT NULL,
                        embedding VECTOR(1536),
                        source_type VARCHAR(50) NOT NULL,
                        source_name VARCHAR(255),
                        source_id VARCHAR(100),
                        chunk_index INTEGER DEFAULT 1,
                        chunk_size INTEGER,
                        content_type VARCHAR(100),
                        title VARCHAR(500),
                        category VARCHAR(100),
                        created_at TIMESTAMPTZ DEFAULT now(),
                        processed_at TIMESTAMPTZ,
                        embedding_model VARCHAR(100) DEFAULT 'text-embedding-3-small',
                        processing_version VARCHAR(20) DEFAULT '1.0',
                        metadata JSONB,
                        search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english', chunk_text)) STORED,
                        CONSTRAINT unique_chunk_per_source UNIQUE (source_type, source_id, chunk_index)
                    )
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX IF NOT EXISTS chunks_embedding_idx
                        ON chunks USING ivfflat (embedding vector_cosine_ops)
                        WITH (lists = 100)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX IF NOT EXISTS idx_chunks_source_type ON chunks(source_type)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX IF NOT EXISTS idx_chunks_source_name ON chunks(source_name)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX IF NOT EXISTS idx_chunks_created_at ON chunks(created_at)
                </cfquery>
                
                <!--- Update uploaded_files table --->
                <cfquery datasource="#application.db.dsn#">
                    ALTER TABLE uploaded_files 
                    ADD COLUMN IF NOT EXISTS content_type VARCHAR(100),
                    ADD COLUMN IF NOT EXISTS file_size INTEGER,
                    ADD COLUMN IF NOT EXISTS chunks_created INTEGER DEFAULT 0
                </cfquery>
                
                <!--- Test insert with proper JSONB casting --->
                <cfquery datasource="#application.db.dsn#">
                    INSERT INTO chunks (chunk_text, source_type, source_name, category, title, metadata)
                    VALUES (
                        'Database setup test chunk', 
                        'system', 
                        'setup_test', 
                        'system', 
                        'Setup Test', 
                        <cfqueryparam value='{"setup": true, "timestamp": "#now()#"}' cfsqltype="cf_sql_varchar">::jsonb
                    )
                    ON CONFLICT (source_type, source_id, chunk_index) DO NOTHING
                </cfquery>
                
                <cfoutput>
                    <div class="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
                        <h3 class="text-green-800 font-semibold">✅ Database Setup Complete!</h3>
                        <div class="mt-3 space-y-2">
                            <p class="text-green-700">• pgvector extension enabled</p>
                            <p class="text-green-700">• Old tables removed (stamp_chunks, lot_chunks)</p>
                            <p class="text-green-700">• Unified chunks table created</p>
                            <p class="text-green-700">• Vector indexes created</p>
                            <p class="text-green-700">• uploaded_files table updated</p>
                            <p class="text-green-700">• Test chunk inserted successfully</p>
                        </div>
                        
                        <div class="mt-4 space-x-3">
                            <a href="chatbox.cfm" class="inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors">
                                🗣️ Go to ChatBox
                            </a>
                            <a href="file_manager.cfm" class="inline-block bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 transition-colors">
                                📁 Upload Documents
                            </a>
                        </div>
                    </div>
                </cfoutput>
                
                <cfcatch type="any">
                    <cfoutput>
                        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
                            <h3 class="text-red-800 font-semibold">❌ Database Setup Failed</h3>
                            <p class="text-red-700"><strong>Error:</strong> #cfcatch.message#</p>
                            <p class="text-red-700"><strong>Detail:</strong> #cfcatch.detail#</p>
                            
                            <div class="mt-4">
                                <h4 class="font-semibold text-red-800">Possible Solutions:</h4>
                                <ul class="list-disc list-inside text-red-700 mt-2">
                                    <li>Ensure pgvector extension is installed</li>
                                    <li>Check database connection (DSN: #application.db.dsn#)</li>
                                    <li>Verify database user has CREATE permissions</li>
                                    <li>Run the SQL manually: unified_chunks_schema.sql</li>
                                </ul>
                            </div>
                        </div>
                    </cfoutput>
                </cfcatch>
            </cftry>

        <cfelse>
            <!--- Setup Form --->
            <div class="space-y-6">
                <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                    <h3 class="text-yellow-800 font-semibold mb-2">⚠️ Database Setup Required</h3>
                    <p class="text-yellow-700">
                        The unified chunks table needs to be created before you can use the RAG system.
                        This will create the new table and remove old conflicting tables.
                    </p>
                </div>

                <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                    <h3 class="text-blue-800 font-semibold mb-2">📋 What This Will Do:</h3>
                    <ul class="list-disc list-inside text-blue-700 space-y-1">
                        <li>Enable pgvector extension</li>
                        <li>Remove old tables: stamp_chunks, lot_chunks</li>
                        <li>Create unified chunks table</li>
                        <li>Add vector similarity indexes</li>
                        <li>Update uploaded_files table</li>
                        <li>Insert test data</li>
                    </ul>
                </div>

                <div class="text-center">
                    <a href="?action=setup" 
                       class="inline-block bg-gradient-to-r from-blue-600 to-indigo-600 text-white px-8 py-3 rounded-lg font-semibold hover:from-blue-700 hover:to-indigo-700 transition-colors"
                       onclick="return confirm('This will modify your database structure. Continue?')">
                        🚀 Setup Database Now
                    </a>
                </div>

                <div class="text-center text-sm text-gray-500">
                    <p>Alternative: Run <code>unified_chunks_schema.sql</code> manually in PostgreSQL</p>
                </div>
            </div>
        </cfif>
    </div>
</div>

</body>
</html>
