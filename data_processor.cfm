<cfmodule template="layout.cfm" title="Data Processor" currentPage="data_processor">

<div class="fade-in">
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            🔄 <span class="ml-3">Data Processor</span>
        </h1>
        <p class="text-gray-600 mt-2">Manage and process auction data files with database insertion and embedding generation.</p>
    </div>

    <cfscript>
    // Helper function for file size formatting
    function formatFileSize(size) {
        if (size LT 1024) {
            return size & " B";
        } else if (size LT 1048576) {
            return round(size / 1024) & " KB";
        } else if (size LT 1073741824) {
            return round(size / 1048576) & " MB";
        } else {
            return round(size / 1073741824) & " GB";
        }
    }
    
    // Get paths from application
    paths = application.paths ?: {};
    finalDir = paths.finalDir ?: expandPath("./allAuctionLotsData_final");
    inProgressDir = paths.inProgressDir ?: expandPath("./allAuctionLotsData_inprogress");
    
    // Get all JSON files from both directories
    finalFiles = [];
    inProgressFiles = [];
    
    if (directoryExists(finalDir)) {
        finalDirContents = directoryList(finalDir, false, "name", "*.json");
        if (isArray(finalDirContents)) {
            for (i = 1; i <= arrayLen(finalDirContents); i++) {
                fileName = finalDirContents[i];
                filePath = finalDir & "\" & fileName;
                fileInfo = {
                    name: fileName,
                    path: filePath,
                    size: getFileInfo(filePath).size,
                    modified: getFileInfo(filePath).lastModified,
                    directory: "Final"
                };
                arrayAppend(finalFiles, fileInfo);
            }
        } else {
            for (i = 1; i <= finalDirContents.recordCount; i++) {
                fileName = finalDirContents.name[i];
                filePath = finalDir & "\" & fileName;
                fileInfo = {
                    name: fileName,
                    path: filePath,
                    size: getFileInfo(filePath).size,
                    modified: getFileInfo(filePath).lastModified,
                    directory: "Final"
                };
                arrayAppend(finalFiles, fileInfo);
            }
        }
    }
    
    if (directoryExists(inProgressDir)) {
        inProgressDirContents = directoryList(inProgressDir, false, "name", "*.json*");
        if (isArray(inProgressDirContents)) {
            for (i = 1; i <= arrayLen(inProgressDirContents); i++) {
                fileName = inProgressDirContents[i];
                filePath = inProgressDir & "\" & fileName;
                fileInfo = {
                    name: fileName,
                    path: filePath,
                    size: getFileInfo(filePath).size,
                    modified: getFileInfo(filePath).lastModified,
                    directory: "In Progress"
                };
                arrayAppend(inProgressFiles, fileInfo);
            }
        } else {
            for (i = 1; i <= inProgressDirContents.recordCount; i++) {
                fileName = inProgressDirContents.name[i];
                filePath = inProgressDir & "\" & fileName;
                fileInfo = {
                    name: fileName,
                    path: filePath,
                    size: getFileInfo(filePath).size,
                    modified: getFileInfo(filePath).lastModified,
                    directory: "In Progress"
                };
                arrayAppend(inProgressFiles, fileInfo);
            }
        }
    }
    
    // Sort by modification date (newest first)
    // Custom sort function for struct arrays
    function sortByModified(a, b) {
        return dateCompare(b.modified, a.modified);
    }
    arraySort(finalFiles, sortByModified);
    arraySort(inProgressFiles, sortByModified);
    
    // Check if we have any action to perform
    action = url.action ?: "";
    selectedFile = url.file ?: "";
    
    if (action == "process" && len(selectedFile)) {
        // Process the selected file
        nodeExe = paths.nodeBinary ?: "node.exe";
        inserterScript = expandPath("./insert_lots_into_db.js");
        
        // Run the inserter
        outTxt = ""; errTxt = "";
        cfexecute(
            name = nodeExe,
            arguments = '"' & inserterScript & '"',
            timeout = 900,
            variable = "outTxt",
            errorVariable = "errTxt"
        );
        
        // Store results in session for display
        session.processOutput = {
            stdout: outTxt,
            stderr: errTxt,
            timestamp: now()
        };
        
        // Redirect to avoid resubmission
        location("data_processor.cfm?action=results", false);
    }
    </cfscript>

    <cfif action == "results" AND structKeyExists(session, "processOutput")>
        <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Processing Results</h2>
            <div class="space-y-4">
                <div>
                    <h3 class="text-lg font-medium text-gray-700 mb-2">STDOUT</h3>
                    <pre class="bg-gray-900 text-green-400 p-4 rounded-lg text-sm overflow-x-auto whitespace-pre-wrap">#encodeForHtml(session.processOutput.stdout)#</pre>
                </div>
                <div>
                    <h3 class="text-lg font-medium text-gray-700 mb-2">STDERR</h3>
                    <pre class="bg-gray-900 text-red-400 p-4 rounded-lg text-sm overflow-x-auto whitespace-pre-wrap">#encodeForHtml(session.processOutput.stderr)#</pre>
                </div>
            </div>
            <div class="mt-4">
                <a href="data_processor.cfm" class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                    ← Back to File List
                </a>
            </div>
        </div>
        
        <cfset structDelete(session, "processOutput")>
    <cfelse>
        <!-- File Lists -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <!-- Final Directory Files -->
            <div class="bg-white rounded-xl shadow-sm p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                    📁 <span class="ml-2">Final Directory Files</span>
                    <span class="ml-2 text-sm text-gray-500">(#arrayLen(finalFiles)# files)</span>
                </h2>
                
                <cfif arrayLen(finalFiles) GT 0>
                    <div class="space-y-2 max-h-96 overflow-y-auto">
                        <cfloop array="#finalFiles#" index="file">
                            <div class="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 transition-colors">
                                <div class="flex items-center justify-between">
                                    <div class="flex-1 min-w-0">
                                        <p class="text-sm font-medium text-gray-900 truncate">#encodeForHtml(file.name)#</p>
                                        <p class="text-xs text-gray-500">
                                            #formatFileSize(file.size)# • #dateFormat(file.modified, "mm/dd/yyyy")# #timeFormat(file.modified, "HH:mm")#
                                        </p>
                                    </div>
                                    <div class="flex space-x-2 ml-2">
                                        <a href="data_processor.cfm?action=process&file=#encodeForUrl(file.name)#" 
                                           class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                                           onclick="return confirm('Process this file for database insertion and embedding?')">
                                            🔄 Process
                                        </a>
                                        <a href="file:///#file.path#" 
                                           class="inline-flex items-center px-3 py-1 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                                            👁️ View
                                        </a>
                                    </div>
                                </div>
                            </div>
                        </cfloop>
                    </div>
                <cfelse>
                    <p class="text-gray-500 text-sm">No JSON files found in final directory.</p>
                </cfif>
            </div>

            <!-- In Progress Directory Files -->
            <div class="bg-white rounded-xl shadow-sm p-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                    ⏳ <span class="ml-2">In Progress Directory Files</span>
                    <span class="ml-2 text-sm text-gray-500">(#arrayLen(inProgressFiles)# files)</span>
                </h2>
                
                <cfif arrayLen(inProgressFiles) GT 0>
                    <div class="space-y-2 max-h-96 overflow-y-auto">
                        <cfloop array="#inProgressFiles#" index="file">
                            <div class="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 transition-colors">
                                <div class="flex items-center justify-between">
                                    <div class="flex-1 min-w-0">
                                        <p class="text-sm font-medium text-gray-900 truncate">#encodeForHtml(file.name)#</p>
                                        <p class="text-xs text-gray-500">
                                            #formatFileSize(file.size)# • #dateFormat(file.modified, "mm/dd/yyyy")# #timeFormat(file.modified, "HH:mm")#
                                        </p>
                                    </div>
                                    <div class="flex space-x-2 ml-2">
                                        <a href="data_processor.cfm?action=process&file=#encodeForUrl(file.name)#" 
                                           class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                                           onclick="return confirm('Process this file for database insertion and embedding?')">
                                            🔄 Process
                                        </a>
                                        <a href="file:///#file.path#" 
                                           class="inline-flex items-center px-3 py-1 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                                            👁️ View
                                        </a>
                                    </div>
                                </div>
                            </div>
                        </cfloop>
                    </div>
                <cfelse>
                    <p class="text-gray-500 text-sm">No JSON files found in in-progress directory.</p>
                </cfif>
            </div>
        </div>

        <!-- Bulk Actions -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Bulk Actions</h2>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <a href="data_processor.cfm?action=process&file=all" 
                   class="inline-flex items-center justify-center px-4 py-3 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                   onclick="return confirm('Process ALL files for database insertion and embedding? This may take a while.')">
                    🔄 Process All Files
                </a>
                <a href="data_processor.cfm?action=refresh" 
                   class="inline-flex items-center justify-center px-4 py-3 border border-gray-300 text-sm font-medium rounded-md shadow-sm text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                    🔄 Refresh File List
                </a>
                <a href="system_status.cfm" 
                   class="inline-flex items-center justify-center px-4 py-3 border border-gray-300 text-sm font-medium rounded-md shadow-sm text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                    📊 System Status
                </a>
            </div>
        </div>

        <!-- Database Status -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Database Status</h2>
            <cfscript>
            try {
                // Get counts from database
                qAuctionHouses = queryExecute("SELECT COUNT(*) as count FROM auction_houses", {}, {datasource=application.db.dsn});
                qSales = queryExecute("SELECT COUNT(*) as count FROM sales", {}, {datasource=application.db.dsn});
                qLots = queryExecute("SELECT COUNT(*) as count FROM lots", {}, {datasource=application.db.dsn});
                qChunks = queryExecute("SELECT COUNT(*) as count FROM chunks", {}, {datasource=application.db.dsn});
                
                auctionHousesCount = qAuctionHouses.count[1];
                salesCount = qSales.count[1];
                lotsCount = qLots.count[1];
                chunksCount = qChunks.count[1];
            } catch (any e) {
                auctionHousesCount = "Error";
                salesCount = "Error";
                lotsCount = "Error";
                chunksCount = "Error";
            }
            </cfscript>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div class="text-center">
                    <div class="text-2xl font-bold text-blue-600">#auctionHousesCount#</div>
                    <div class="text-sm text-gray-500">Auction Houses</div>
                </div>
                <div class="text-center">
                    <div class="text-2xl font-bold text-green-600">#salesCount#</div>
                    <div class="text-sm text-gray-500">Sales</div>
                </div>
                <div class="text-center">
                    <div class="text-2xl font-bold text-purple-600">#lotsCount#</div>
                    <div class="text-sm text-gray-500">Lots</div>
                </div>
                <div class="text-center">
                    <div class="text-2xl font-bold text-orange-600">#chunksCount#</div>
                    <div class="text-sm text-gray-500">Chunks (Embeddings)</div>
                </div>
            </div>
        </div>
    </cfif>
</div>


</cfmodule>
