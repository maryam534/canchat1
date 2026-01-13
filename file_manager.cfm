<!---
    File Manager Module - Document Upload & Management
    Handles PDF, DOC, TXT uploads with step-by-step processing
--->

<cfmodule template="layout.cfm" title="File Manager" currentPage="files">

<div class="fade-in">
    <!-- Header -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            📁 <span class="ml-3">File Manager</span>
        </h1>
        <p class="text-gray-600 mt-2">Upload and manage documents for RAG processing</p>
    </div>

    <!-- Upload Section -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Upload Form -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                ⬆️ <span class="ml-2">Upload New Document</span>
            </h2>
            
            <form action="upload.cfm" method="post" enctype="multipart/form-data" class="space-y-4">
                <div>
                    <label class="block text-sm font-medium text-gray-700 mb-2">Select Document</label>
                    <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-blue-400 transition-colors">
                        <input 
                            type="file" 
                            name="catalogFile" 
                            accept=".pdf,.doc,.docx,.txt,.rtf,.odt"
                            required
                            class="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100"
                        />
                        <p class="mt-2 text-sm text-gray-500">
                            Supported: PDF, DOC, DOCX, TXT, RTF, ODT
                        </p>
                    </div>
                </div>
                
                <input type="hidden" name="source_type" value="document" />
                <input type="hidden" name="debug" value="true" />
                
                <button 
                    type="submit" 
                    class="w-full bg-gradient-to-r from-blue-600 to-indigo-600 text-white py-3 px-6 rounded-lg font-semibold hover:from-blue-700 hover:to-indigo-700 transition-colors"
                >
                    🚀 Upload & Process Document
                </button>
            </form>
        </div>

        <!-- Processing Steps -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                ⚙️ <span class="ml-2">Processing Pipeline</span>
            </h2>
            
            <div class="space-y-3">
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-blue-500 text-white rounded-full flex items-center justify-center text-sm font-bold">1</div>
                    <div>
                        <p class="font-medium text-gray-800">File Upload</p>
                        <p class="text-sm text-gray-600">Save file to secure uploads directory</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-green-500 text-white rounded-full flex items-center justify-center text-sm font-bold">2</div>
                    <div>
                        <p class="font-medium text-gray-800">Text Extraction</p>
                        <p class="text-sm text-gray-600">Extract text using Apache Tika</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-purple-500 text-white rounded-full flex items-center justify-center text-sm font-bold">3</div>
                    <div>
                        <p class="font-medium text-gray-800">Text Chunking</p>
                        <p class="text-sm text-gray-600">Split into manageable pieces</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-orange-500 text-white rounded-full flex items-center justify-center text-sm font-bold">4</div>
                    <div>
                        <p class="font-medium text-gray-800">AI Embeddings</p>
                        <p class="text-sm text-gray-600">Generate vector embeddings</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-indigo-500 text-white rounded-full flex items-center justify-center text-sm font-bold">5</div>
                    <div>
                        <p class="font-medium text-gray-800">Store in Database</p>
                        <p class="text-sm text-gray-600">Save to unified chunks table</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- File Management -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
            📂 <span class="ml-2">Document Library</span>
        </h2>
        
        <cfquery name="documents" datasource="#application.db.dsn#">
            SELECT 
                source_name,
                title,
                content_type,
                COUNT(*) as chunk_count,
                MAX(created_at) as last_updated,
                SUM(chunk_size) as total_characters,
                STRING_AGG(DISTINCT category, ', ') as categories
            FROM chunks 
            WHERE source_type = 'document'
            GROUP BY source_name, title, content_type
            ORDER BY last_updated DESC
        </cfquery>
        
        <cfif documents.recordCount GT 0>
            <div class="overflow-x-auto">
                <table class="w-full table-auto">
                    <thead class="bg-gray-50">
                        <tr>
                            <th class="text-left p-3 font-medium text-gray-700">Document</th>
                            <th class="text-left p-3 font-medium text-gray-700">Type</th>
                            <th class="text-left p-3 font-medium text-gray-700">Chunks</th>
                            <th class="text-left p-3 font-medium text-gray-700">Size</th>
                            <th class="text-left p-3 font-medium text-gray-700">Updated</th>
                            <th class="text-left p-3 font-medium text-gray-700">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <cfoutput>
                        <cfloop query="documents">
                            <tr class="border-t border-gray-200 hover:bg-gray-50">
                                <td class="p-3">
                                    <div class="font-medium text-gray-900">#source_name#</div>
                                    <cfif len(title) AND title NEQ source_name>
                                        <div class="text-sm text-gray-500">#title#</div>
                                    </cfif>
                                </td>
                                <td class="p-3">
                                    <span class="inline-block bg-blue-100 text-blue-800 px-2 py-1 rounded text-xs">
                                        #listLast(source_name, ".")#
                                    </span>
                                </td>
                                <td class="p-3 text-gray-600">#chunk_count#</td>
                                <td class="p-3 text-gray-600">
                                    <cfif isNumeric(total_characters) AND total_characters GT 0>
                                        #numberFormat(total_characters/1024, "999.9")# KB
                                    <cfelse>
                                        0 KB
                                    </cfif>
                                </td>
                                <td class="p-3 text-gray-600">#dateFormat(last_updated, "mm/dd/yy")#</td>
                                <td class="p-3">
                                    <div class="flex space-x-2">
                                        <a href="chatbox.cfm?q=#urlEncodedFormat('content from ' & source_name)#" 
                                           class="text-blue-600 hover:text-blue-800 text-sm">
                                            Search
                                        </a>
                                        <a href="view_chunks.cfm?source=#urlEncodedFormat(source_name)#" 
                                           class="text-green-600 hover:text-green-800 text-sm">
                                            View
                                        </a>
                                        <a href="delete_source.cfm?source=#urlEncodedFormat(source_name)#&type=document" 
                                           class="text-red-600 hover:text-red-800 text-sm"
                                           onclick="return confirm('Delete all chunks for this document?')">
                                            Delete
                                        </a>
                                    </div>
                                </td>
                            </tr>
                        </cfloop>
                        </cfoutput>
                    </tbody>
                </table>
            </div>
        <cfelse>
            <div class="text-center py-8 text-gray-500">
                <div class="text-4xl mb-4">📄</div>
                <p class="text-lg font-medium">No documents uploaded yet</p>
                <p class="text-sm">Upload your first document to get started!</p>
            </div>
        </cfif>
    </div>

    <!-- Recent Activity -->
    <div class="bg-white rounded-xl shadow-sm p-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
            🕐 <span class="ml-2">Recent Activity</span>
        </h2>
        
        <cfquery name="recentActivity" datasource="#application.db.dsn#">
            SELECT 
                source_type,
                source_name,
                title,
                chunk_text,
                created_at,
                category
            FROM chunks 
            ORDER BY created_at DESC
            LIMIT 10
        </cfquery>
        
        <cfif recentActivity.recordCount GT 0>
            <div class="space-y-3">
                <cfoutput>
                <cfloop query="recentActivity">
                    <div class="flex items-start space-x-3 p-3 bg-gray-50 rounded-lg">
                        <div class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold
                            <cfif source_type == 'document'>bg-blue-100 text-blue-600
                            <cfelseif source_type == 'lot'>bg-purple-100 text-purple-600
                            <cfelseif source_type == 'web'>bg-green-100 text-green-600
                            <cfelse>bg-gray-100 text-gray-600</cfif>">
                            <cfif source_type == 'document'>📄
                            <cfelseif source_type == 'lot'>🏷️
                            <cfelseif source_type == 'web'>🌐
                            <cfelse>📝</cfif>
                        </div>
                        <div class="flex-1 min-w-0">
                            <div class="flex items-center justify-between">
                                <p class="font-medium text-gray-900 truncate">#source_name#</p>
                                <span class="text-xs text-gray-500">#timeFormat(created_at, "h:mm tt")#</span>
                            </div>
                            <p class="text-sm text-gray-600 truncate">#left(chunk_text, 100)#...</p>
                            <cfif len(category)>
                                <span class="inline-block bg-gray-200 text-gray-700 px-2 py-1 rounded text-xs mt-1">
                                    #category#
                                </span>
                            </cfif>
                        </div>
                    </div>
                </cfloop>
                </cfoutput>
            </div>
        <cfelse>
            <p class="text-gray-500 text-center py-4">No recent activity</p>
        </cfif>
    </div>
</div>

</cfmodule>
