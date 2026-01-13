
<!---
    Main Layout with Top Navigation
    Unified interface for all RAG modules
--->

<cfparam name="attributes.title" default="RAG System" />
<cfparam name="attributes.currentPage" default="" />
<cfparam name="attributes.showBackButton" default="false" />

<cfif thisTag.executionMode EQ "start">

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><cfoutput>#attributes.title# - RAG System</cfoutput></title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
    <style>
        .nav-item.active { background: ##3b82f6; color: white; }
        .nav-item:hover { background: ##e5e7eb; }
        .nav-item.active:hover { background: ##2563eb; }
        .fade-in { animation: fadeIn 0.3s ease-in; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .step-card { transition: all 0.2s ease; }
        .step-card:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(0,0,0,0.1); }
    </style>
</head>
<body class="bg-gray-50 min-h-screen">

    <!-- Top Navigation -->
    <nav class="bg-white shadow-lg border-b">
        <div class="max-w-7xl mx-auto px-4">
            <div class="flex justify-between items-center h-16">
                <!-- Logo/Brand -->
                <div class="flex items-center space-x-3">
                    <div class="w-10 h-10 bg-gradient-to-r from-blue-500 to-indigo-600 rounded-lg flex items-center justify-center">
                        <span class="text-white font-bold text-lg">R</span>
                    </div>
                    <h1 class="text-xl font-bold text-gray-800">RAG System</h1>
                </div>
                
                <!-- Navigation Menu -->
                <div class="flex space-x-1">
                    <cfoutput>
                    <a href="chatbox.cfm" class="nav-item px-4 py-2 rounded-lg text-sm font-medium transition-colors #attributes.currentPage == 'chatbox' ? 'active' : ''#">
                        🗣️ ChatBox
                    </a>
                    <a href="file_manager.cfm" class="nav-item px-4 py-2 rounded-lg text-sm font-medium transition-colors #attributes.currentPage == 'files' ? 'active' : ''#">
                        📁 File Manager
                    </a>
                    <a href="feeds.cfm" class="nav-item px-4 py-2 rounded-lg text-sm font-medium transition-colors #attributes.currentPage == 'feeds' ? 'active' : ''#">
                        📡 Feeds
                    </a>
                    <a href="single_event_run.cfm" class="nav-item px-4 py-2 rounded-lg text-sm font-medium transition-colors #attributes.currentPage == 'single' ? 'active' : ''#">
                        🎯 Single Event
                    </a>
                    <a href="data_processor.cfm" class="nav-item px-4 py-2 rounded-lg text-sm font-medium transition-colors #attributes.currentPage == 'data_processor' ? 'active' : ''#">
                        🔄 Data Processor
                    </a>
                    <a href="bulk_processor.cfm" class="nav-item px-4 py-2 rounded-lg text-sm font-medium transition-colors #attributes.currentPage == 'bulk_processor' ? 'active' : ''#">
                        ⚡ Bulk Processor
                    </a>
                    </cfoutput>
                </div>
                
                <!-- Settings/Admin -->
                <div class="flex items-center space-x-2">
                    <cfif attributes.showBackButton>
                        <a href="javascript:history.back()" class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded">
                            ← Back
                        </a>
                    </cfif>
                    <a href="admin.cfm" class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded">
                        ⚙️ Admin
                    </a>
                </div>
            </div>
        </div>
    </nav>

    <!-- Main Content Area -->
    <main class="max-w-7xl mx-auto px-4 py-6">
        <cfif thisTag.executionMode EQ "end">
            <cfoutput>#thisTag.generatedContent#</cfoutput>
        </cfif>
    </main>

    <!-- Footer -->
    <footer class="bg-white border-t mt-auto">
        <div class="max-w-7xl mx-auto px-4 py-4">
            <div class="flex justify-between items-center text-sm text-gray-500">
                <div>
                    <span>RAG System v2.0</span>
                    <span class="mx-2">•</span>
                    <span>Unified Content Processing</span>
                </div>
                <div class="flex items-center space-x-4">
                    <cftry>
                        <cfquery name="contentStats" datasource="#application.db.dsn#">
                            SELECT 
                                COUNT(*) as total_chunks,
                                COUNT(DISTINCT source_type) as content_types,
                                COUNT(DISTINCT source_name) as unique_sources
                            FROM chunks
                        </cfquery>
                        <cfoutput>
                        <span>📊 #contentStats.total_chunks# chunks</span>
                        <span>📂 #contentStats.content_types# types</span>
                        <span>📄 #contentStats.unique_sources# sources</span>
                        </cfoutput>
                        
                        <cfcatch>
                            <span>📊 Database loading...</span>
                        </cfcatch>
                    </cftry>
                </div>
            </div>
        </div>
    </footer>

</body>
</html>

</cfif>
