<!---
    Configuration Test Page
    Displays all application configuration values for verification
--->

<!DOCTYPE html>
<html>
<head>
    <title>Configuration Test - Stamp ChatBot</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">
    <div class="max-w-4xl mx-auto">
        <h1 class="text-3xl font-bold text-gray-800 mb-6">Configuration Test</h1>
        
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <!-- Paths Configuration -->
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">File Paths</h2>
                <cfoutput>
                    <div class="space-y-2 text-sm">
                        <div><strong>Node Binary:</strong> #application.paths.nodeBinary#</div>
                        <div><strong>CMD Exe:</strong> #application.paths.cmdExe#</div>
                        <div><strong>Scraper:</strong> #application.paths.scraper#</div>
                        <div><strong>Inserter:</strong> #application.paths.inserter#</div>
                        <div><strong>Uploads Dir:</strong> #application.paths.uploadsDir#</div>
                        <div><strong>In Progress Dir:</strong> #application.paths.inProgressDir#</div>
                        <div><strong>Final Dir:</strong> #application.paths.finalDir#</div>
                        <div><strong>Libs Dir:</strong> #application.paths.libsDir#</div>
                        <div><strong>CFML Dir:</strong> #application.paths.cfmlDir#</div>
                    </div>
                </cfoutput>
            </div>
            
            <!-- AI Configuration -->
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">AI Settings</h2>
                <cfoutput>
                    <div class="space-y-2 text-sm">
                        <div><strong>API Key:</strong> #left(application.ai.openaiKey, 10)#... (hidden)</div>
                        <div><strong>Embed Model:</strong> #application.ai.embedModel#</div>
                        <div><strong>Embed Dim:</strong> #application.ai.embedDim#</div>
                        <div><strong>Chat Model:</strong> #application.ai.chatModel#</div>
                        <div><strong>API Base URL:</strong> #application.ai.apiBaseUrl#</div>
                        <div><strong>Timeout:</strong> #application.ai.timeout#s</div>
                        <div><strong>Max Chars:</strong> #application.ai.maxChars#</div>
                        <div><strong>Max Items:</strong> #application.ai.maxItems#</div>
                    </div>
                </cfoutput>
            </div>
            
            <!-- Database Configuration -->
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">Database</h2>
                <cfoutput>
                    <div class="space-y-2 text-sm">
                        <div><strong>DSN:</strong> #application.db.dsn#</div>
                        <div><strong>Vector Limit:</strong> #application.db.vectorLimit#</div>
                        <div><strong>Chunk Limit:</strong> #application.db.chunkLimit#</div>
                    </div>
                </cfoutput>
            </div>
            
            <!-- Processing Configuration -->
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">Processing</h2>
                <cfoutput>
                    <div class="space-y-2 text-sm">
                        <div><strong>Chunk Size:</strong> #application.processing.chunkSize# words</div>
                        <div><strong>Tika Path:</strong> #application.processing.tikaPath#</div>
                        <div><strong>Jsoup Class:</strong> #application.processing.jsoupClass#</div>
                        <div><strong>Default Timeout:</strong> #application.processing.defaultTimeout#s</div>
                        <div><strong>Max Retries:</strong> #application.processing.maxRetries#</div>
                    </div>
                </cfoutput>
            </div>
            
            <!-- Web Configuration -->
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">Web Settings</h2>
                <cfoutput>
                    <div class="space-y-2 text-sm">
                        <div><strong>Base URL:</strong> #application.web.baseUrl#</div>
                        <div><strong>Process URL:</strong> #application.web.processUrl#</div>
                        <div><strong>Chat Version:</strong> #application.web.chatVersion#</div>
                    </div>
                </cfoutput>
            </div>
            
            <!-- UI Configuration -->
            <div class="bg-white rounded-lg shadow p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">UI Settings</h2>
                <cfoutput>
                    <div class="space-y-2 text-sm">
                        <div><strong>Max Similarity Results:</strong> #application.ui.maxSimilarityResults#</div>
                        <div><strong>Show Debug Logs:</strong> #application.ui.showDebugLogs#</div>
                        <div><strong>Default Placeholder:</strong> #application.ui.defaultPlaceholder#</div>
                    </div>
                </cfoutput>
            </div>
        </div>
        
        <div class="mt-6 text-center">
            <a href="index.cfm" class="text-blue-600 hover:text-blue-800 underline">← Back to Chat</a>
        </div>
    </div>
</body>
</html>
