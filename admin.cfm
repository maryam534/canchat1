<!---
    Admin Module - System Administration
    Manage unified chunks table and system settings
--->

<cfmodule template="layout.cfm" title="System Admin" currentPage="admin">

<cfif structKeyExists(url, "action") AND url.action EQ "reset_database">
    <div class="fade-in">
        <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
            <h1 class="text-2xl font-bold text-gray-800 mb-4">🗄️ Database Reset</h1>
            
            <cftry>
                <!--- Reset database structure --->
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
                    DROP TABLE IF EXISTS chunks CASCADE
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE TABLE chunks (
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
                    CREATE INDEX chunks_embedding_idx ON chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX idx_chunks_source_type ON chunks(source_type)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX idx_chunks_source_name ON chunks(source_name)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    CREATE INDEX idx_chunks_created_at ON chunks(created_at)
                </cfquery>
                
                <cfquery datasource="#application.db.dsn#">
                    ALTER TABLE uploaded_files 
                    ADD COLUMN IF NOT EXISTS content_type VARCHAR(100),
                    ADD COLUMN IF NOT EXISTS file_size INTEGER,
                    ADD COLUMN IF NOT EXISTS chunks_created INTEGER DEFAULT 0
                </cfquery>
                
                <!--- Test insert --->
                <cfquery datasource="#application.db.dsn#">
                    INSERT INTO chunks (chunk_text, source_type, source_name, category, title, metadata)
                    VALUES (
                        'Database reset test - system ready for RAG processing', 
                        'system', 
                        'reset_test', 
                        'system', 
                        'Database Reset Test', 
                        <cfqueryparam value='{"reset": true, "timestamp": "#now()#", "version": "2.0"}' cfsqltype="cf_sql_varchar">::jsonb
                    )
                </cfquery>
                
                <cfoutput>
                    <div class="bg-green-50 border border-green-200 rounded-lg p-4 mb-6">
                        <h3 class="text-green-800 font-semibold">✅ Database Reset Complete!</h3>
                        <div class="mt-3 space-y-2">
                            <p class="text-green-700">• pgvector extension enabled</p>
                            <p class="text-green-700">• Old tables removed (stamp_chunks, lot_chunks)</p>
                            <p class="text-green-700">• Fresh unified chunks table created</p>
                            <p class="text-green-700">• Vector indexes created for similarity search</p>
                            <p class="text-green-700">• uploaded_files table updated</p>
                            <p class="text-green-700">• Test chunk inserted with proper JSONB</p>
                        </div>
                        
                        <div class="mt-4 space-x-3">
                            <a href="chatbox.cfm" class="inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors">
                                🗣️ Go to ChatBox
                            </a>
                            <a href="file_manager.cfm" class="inline-block bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 transition-colors">
                                📁 Upload Documents
                            </a>
                            <a href="admin.cfm" class="inline-block bg-gray-600 text-white px-4 py-2 rounded hover:bg-gray-700 transition-colors">
                                ← Back to Admin
                            </a>
                        </div>
                    </div>
                </cfoutput>
                
                <cfcatch type="any">
                    <cfoutput>
                        <div class="bg-red-50 border border-red-200 rounded-lg p-4">
                            <h3 class="text-red-800 font-semibold">❌ Database Reset Failed</h3>
                            <p class="text-red-700"><strong>Error:</strong> #cfcatch.message#</p>
                            <p class="text-red-700"><strong>Detail:</strong> #cfcatch.detail#</p>
                            
                            <div class="mt-4">
                                <a href="admin.cfm" class="inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors">
                                    ← Back to Admin
                                </a>
                            </div>
                        </div>
                    </cfoutput>
                </cfcatch>
            </cftry>
        </div>
    </div>
<cfelse>

<div class="fade-in">
    <!-- Header -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            ⚙️ <span class="ml-3">System Administration</span>
        </h1>
        <p class="text-gray-600 mt-2">Manage your unified RAG system and monitor performance</p>
    </div>

    <!-- Quick Actions -->
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <a href="config_test.cfm" class="step-card bg-gradient-to-r from-blue-500 to-blue-600 text-white p-4 rounded-lg text-center hover:from-blue-600 hover:to-blue-700 transition-colors">
            <div class="text-2xl mb-2">🔧</div>
            <div class="font-semibold">Configuration</div>
            <div class="text-sm opacity-90">Test settings</div>
        </a>
        
        <a href="env_editor.cfm" class="step-card bg-gradient-to-r from-green-500 to-green-600 text-white p-4 rounded-lg text-center hover:from-green-600 hover:to-green-700 transition-colors">
            <div class="text-2xl mb-2">🌍</div>
            <div class="font-semibold">Environment</div>
            <div class="text-sm opacity-90">Edit .env vars</div>
        </a>
        
        <a href="system_status.cfm" class="step-card bg-gradient-to-r from-purple-500 to-purple-600 text-white p-4 rounded-lg text-center hover:from-purple-600 hover:to-purple-700 transition-colors">
            <div class="text-2xl mb-2">📊</div>
            <div class="font-semibold">System Status</div>
            <div class="text-sm opacity-90">Monitor health</div>
        </a>
        
        <a href="?action=reset_database" 
           onclick="return confirm('This will reset the database structure and remove all existing chunks. Continue?')"
           class="step-card bg-gradient-to-r from-orange-500 to-orange-600 text-white p-4 rounded-lg text-center hover:from-orange-600 hover:to-orange-700 transition-colors">
            <div class="text-2xl mb-2">🗄️</div>
            <div class="font-semibold">Reset Database</div>
            <div class="text-sm opacity-90">Rebuild chunks table</div>
        </a>
        
        <a href="##" onclick="return confirm('This will restart the application. Continue?') && (window.location='chatbox.cfm?appreset=1')" class="step-card bg-gradient-to-r from-red-500 to-red-600 text-white p-4 rounded-lg text-center hover:from-red-600 hover:to-red-700 transition-colors">
            <div class="text-2xl mb-2">🔄</div>
            <div class="font-semibold">Restart App</div>
            <div class="text-sm opacity-90">Reload config</div>
        </a>
    </div>

    <!-- Unified Chunks Overview -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
            🗄️ <span class="ml-2">Unified Chunks Database</span>
        </h2>
        
        <cfquery name="chunkOverview" datasource="#application.db.dsn#">
            SELECT 
                source_type,
                COUNT(*) as chunk_count,
                COUNT(DISTINCT source_name) as unique_sources,
                COUNT(*) FILTER (WHERE embedding IS NOT NULL) as embedded_count,
                AVG(chunk_size) as avg_chunk_size,
                MAX(created_at) as last_added
            FROM chunks
            GROUP BY source_type
            ORDER BY chunk_count DESC
        </cfquery>
        
        <div class="overflow-x-auto">
            <table class="w-full table-auto">
                <thead class="bg-gray-50">
                    <tr>
                        <th class="text-left p-3 font-medium text-gray-700">Content Type</th>
                        <th class="text-left p-3 font-medium text-gray-700">Chunks</th>
                        <th class="text-left p-3 font-medium text-gray-700">Sources</th>
                        <th class="text-left p-3 font-medium text-gray-700">Embedded</th>
                        <th class="text-left p-3 font-medium text-gray-700">Avg Size</th>
                        <th class="text-left p-3 font-medium text-gray-700">Last Added</th>
                        <th class="text-left p-3 font-medium text-gray-700">Actions</th>
                    </tr>
                </thead>
                <tbody>
                    <cfoutput>
                    <cfloop query="chunkOverview">
                        <tr class="border-t border-gray-200 hover:bg-gray-50">
                            <td class="p-3">
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                                    <cfif source_type == 'document'>bg-blue-100 text-blue-800
                                    <cfelseif source_type == 'lot'>bg-purple-100 text-purple-800
                                    <cfelseif source_type == 'web'>bg-green-100 text-green-800
                                    <cfelseif source_type == 'feed'>bg-orange-100 text-orange-800
                                    <cfelse>bg-gray-100 text-gray-800</cfif>">
                                    <cfif source_type == 'document'>📄 Documents
                                    <cfelseif source_type == 'lot'>🏷️ Auction Lots
                                    <cfelseif source_type == 'web'>🌐 Web Pages
                                    <cfelseif source_type == 'feed'>📡 RSS Feeds
                                    <cfelse>📝 #source_type#</cfif>
                                </span>
                            </td>
                            <td class="p-3 font-mono text-sm">#numberFormat(chunk_count, "999,999")#</td>
                            <td class="p-3 font-mono text-sm">#unique_sources#</td>
                            <td class="p-3">
                                <div class="flex items-center">
                                    <div class="w-full bg-gray-200 rounded-full h-2 mr-2">
                                        <div class="bg-green-500 h-2 rounded-full" style="width: #numberFormat((embedded_count/chunk_count)*100, "99")#%"></div>
                                    </div>
                                    <span class="text-sm text-gray-600">#numberFormat((embedded_count/chunk_count)*100, "99")#%</span>
                                </div>
                            </td>
                            <td class="p-3 text-sm text-gray-600">#numberFormat(avg_chunk_size, "999")# chars</td>
                            <td class="p-3 text-sm text-gray-600">
                                <cfif isDate(last_added)>
                                    #dateFormat(last_added, "mm/dd/yy")#
                                <cfelse>
                                    Never
                                </cfif>
                            </td>
                            <td class="p-3">
                                <div class="flex space-x-2">
                                    <a href="view_chunks.cfm?type=#source_type#" class="text-blue-600 hover:text-blue-800 text-sm">View</a>
                                    <a href="manage_chunks.cfm?type=#source_type#" class="text-green-600 hover:text-green-800 text-sm">Manage</a>
                                </div>
                            </td>
                        </tr>
                    </cfloop>
                    </cfoutput>
                </tbody>
            </table>
        </div>
    </div>

    <!-- System Statistics -->
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
        <cfquery name="systemStats" datasource="#application.db.dsn#">
            SELECT 
                COUNT(*) as total_chunks,
                COUNT(DISTINCT source_name) as total_sources,
                COUNT(*) FILTER (WHERE embedding IS NOT NULL) as embedded_chunks,
                COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') as chunks_today,
                COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') as chunks_week,
                AVG(chunk_size) as avg_chunk_size
            FROM chunks
        </cfquery>
        
        <cfoutput>
        <div class="bg-white rounded-lg shadow-sm p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">📊 Content Statistics</h3>
            <div class="space-y-3">
                <div class="flex justify-between">
                    <span class="text-gray-600">Total Chunks:</span>
                    <span class="font-semibold">#numberFormat(systemStats.total_chunks, "999,999")#</span>
                </div>
                <div class="flex justify-between">
                    <span class="text-gray-600">Unique Sources:</span>
                    <span class="font-semibold">#systemStats.total_sources#</span>
                </div>
                <div class="flex justify-between">
                    <span class="text-gray-600">Embedded:</span>
                    <span class="font-semibold">#numberFormat(systemStats.embedded_chunks, "999,999")#</span>
                </div>
                <div class="flex justify-between">
                    <span class="text-gray-600">Added Today:</span>
                    <span class="font-semibold text-green-600">#systemStats.chunks_today#</span>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">⚡ Performance</h3>
            <div class="space-y-3">
                <div class="flex justify-between">
                    <span class="text-gray-600">Avg Chunk Size:</span>
                    <span class="font-semibold">#numberFormat(systemStats.avg_chunk_size, "999")# chars</span>
                </div>
                <div class="flex justify-between">
                    <span class="text-gray-600">This Week:</span>
                    <span class="font-semibold text-blue-600">#systemStats.chunks_week#</span>
                </div>
                <div class="flex justify-between">
                    <span class="text-gray-600">Embedding Rate:</span>
                    <span class="font-semibold">
                        #numberFormat((systemStats.embedded_chunks/systemStats.total_chunks)*100, "99.9")#%
                    </span>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-6">
            <h3 class="text-lg font-semibold text-gray-800 mb-4">🛠️ Maintenance</h3>
            <div class="space-y-3">
                <a href="reindex_embeddings.cfm" class="block w-full bg-blue-600 text-white text-center py-2 rounded hover:bg-blue-700 transition-colors text-sm">
                    Rebuild Embeddings
                </a>
                <a href="cleanup_chunks.cfm" class="block w-full bg-yellow-600 text-white text-center py-2 rounded hover:bg-yellow-700 transition-colors text-sm">
                    Cleanup Old Chunks
                </a>
                <a href="export_chunks.cfm" class="block w-full bg-green-600 text-white text-center py-2 rounded hover:bg-green-700 transition-colors text-sm">
                    Export Data
                </a>
            </div>
        </div>
        </cfoutput>
    </div>
</div>

</cfif>

</cfmodule>
