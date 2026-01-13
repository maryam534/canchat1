<cfmodule template="layout.cfm" title="Bulk Data Processor" currentPage="bulk_processor">

<div class="fade-in">
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            ⚡ <span class="ml-3">Bulk Data Processor</span>
        </h1>
        <p class="text-gray-600 mt-2">Advanced bulk processing with real-time monitoring and detailed logging.</p>
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
    nodeExe = paths.nodeBinary ?: "node.exe";
    inserterScript = expandPath("./insert_lots_into_db.js");
    
    // Get all JSON files
    allFiles = [];
    
    // Debug output
    writeOutput("<!-- Debug: finalDir = " & finalDir & " -->");
    writeOutput("<!-- Debug: inProgressDir = " & inProgressDir & " -->");
    writeOutput("<!-- Debug: directoryExists(finalDir) = " & directoryExists(finalDir) & " -->");
    
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
                    directory: "Final",
                    selected: false
                };
                arrayAppend(allFiles, fileInfo);
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
                    directory: "Final",
                    selected: false
                };
                arrayAppend(allFiles, fileInfo);
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
                    directory: "In Progress",
                    selected: false
                };
                arrayAppend(allFiles, fileInfo);
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
                    directory: "In Progress",
                    selected: false
                };
                arrayAppend(allFiles, fileInfo);
            }
        }
    }
    
    // Sort by modification date (newest first)
    // Custom sort function for struct arrays
    function sortByModified(a, b) {
        return dateCompare(b.modified, a.modified);
    }
    arraySort(allFiles, sortByModified);
    
    // Debug output
    writeOutput("<!-- Debug: allFiles length = " & arrayLen(allFiles) & " -->");
    
    // Calculate stats
    finalCount = 0;
    inProgressCount = 0;
    totalSize = 0;
    
    for (i = 1; i <= arrayLen(allFiles); i++) {
        file = allFiles[i];
        if (file.directory == "Final") {
            finalCount++;
        } else if (file.directory == "In Progress") {
            inProgressCount++;
        }
        totalSize += file.size;
    }
    
    // Handle actions
    action = url.action ?: "";
    
    if (action == "process_selected") {
        selectedFiles = url.selectedFiles ?: "";
        if (len(selectedFiles)) {
            fileList = listToArray(selectedFiles);
            
            // Process each selected file
            results = [];
            for (file in fileList) {
                try {
                    outTxt = ""; errTxt = "";
                    cfexecute(
                        name = nodeExe,
                        arguments = '"' & inserterScript & '"',
                        timeout = 900,
                        variable = "outTxt",
                        errorVariable = "errTxt"
                    );
                    
                    result = {
                        file: file,
                        success: true,
                        stdout: outTxt,
                        stderr: errTxt,
                        timestamp: now()
                    };
                } catch (any e) {
                    result = {
                        file: file,
                        success: false,
                        error: e.message,
                        timestamp: now()
                    };
                }
                arrayAppend(results, result);
            }
            
            // Store results in session
            session.bulkProcessResults = results;
            location("bulk_processor.cfm?action=results", false);
        }
    }
    
    if (action == "process_all") {
        // Process all files
        results = [];
        for (i = 1; i <= arrayLen(allFiles); i++) {
            file = allFiles[i];
            try {
                outTxt = ""; errTxt = "";
                cfexecute(
                    name = nodeExe,
                    arguments = '"' & inserterScript & '"',
                    timeout = 900,
                    variable = "outTxt",
                    errorVariable = "errTxt"
                );
                
                result = {
                    file: file.name,
                    success: true,
                    stdout: outTxt,
                    stderr: errTxt,
                    timestamp: now()
                };
            } catch (any e) {
                result = {
                    file: file.name,
                    success: false,
                    error: e.message,
                    timestamp: now()
                };
            }
            arrayAppend(results, result);
        }
        
        session.bulkProcessResults = results;
        location("bulk_processor.cfm?action=results", false);
    }
    </cfscript>

    <cfif action == "results" AND structKeyExists(session, "bulkProcessResults")>
        <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Bulk Processing Results</h2>
            <div class="space-y-4">
                <cfloop array="#session.bulkProcessResults#" index="result">
                    <div class="border border-gray-200 rounded-lg p-4">
                        <div class="flex items-center justify-between mb-2">
                            <h3 class="text-lg font-medium text-gray-900">#encodeForHtml(result.file)#</h3>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #result.success ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'#">
                                #result.success ? '✅ Success' : '❌ Failed'#
                            </span>
                        </div>
                        
                        <cfif result.success>
                            <div class="space-y-2">
                                <div>
                                    <h4 class="text-sm font-medium text-gray-700">STDOUT</h4>
                                    <pre class="bg-gray-900 text-green-400 p-2 rounded text-xs overflow-x-auto whitespace-pre-wrap max-h-32">#encodeForHtml(result.stdout)#</pre>
                                </div>
                                <cfif len(result.stderr)>
                                    <div>
                                        <h4 class="text-sm font-medium text-gray-700">STDERR</h4>
                                        <pre class="bg-gray-900 text-red-400 p-2 rounded text-xs overflow-x-auto whitespace-pre-wrap max-h-32">#encodeForHtml(result.stderr)#</pre>
                                    </div>
                                </cfif>
                            </div>
                        <cfelse>
                            <div class="text-red-600">
                                <strong>Error:</strong> #encodeForHtml(result.error)#
                            </div>
                        </cfif>
                        
                        <div class="text-xs text-gray-500 mt-2">
                            Processed: #dateFormat(result.timestamp, "mm/dd/yyyy")# #timeFormat(result.timestamp, "HH:mm:ss")#
                        </div>
                    </div>
                </cfloop>
            </div>
            
            <div class="mt-6">
                <a href="bulk_processor.cfm" class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                    ← Back to File List
                </a>
            </div>
        </div>
        
        <cfset structDelete(session, "bulkProcessResults")>
    <cfelse>
        <!-- File Selection Interface -->
        <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
            <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold text-gray-800">Select Files to Process</h2>
                <div class="flex space-x-2">
                    <button onclick="selectAll()" class="px-3 py-1 text-sm bg-gray-100 text-gray-700 rounded hover:bg-gray-200">
                        Select All
                    </button>
                    <button onclick="selectNone()" class="px-3 py-1 text-sm bg-gray-100 text-gray-700 rounded hover:bg-gray-200">
                        Select None
                    </button>
                </div>
            </div>
            
            <form id="bulkForm" action="bulk_processor.cfm" method="get">
                <input type="hidden" name="action" value="process_selected">
                
                <div class="space-y-2 max-h-96 overflow-y-auto">
                    <cfloop array="#allFiles#" index="file">
                        <div class="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 transition-colors">
                            <label class="flex items-center space-x-3 cursor-pointer">
                                <input type="checkbox" name="selectedFiles" value="#encodeForHtml(file.name)#" class="file-checkbox rounded border-gray-300 text-blue-600 focus:ring-blue-500">
                                <div class="flex-1 min-w-0">
                                    <p class="text-sm font-medium text-gray-900 truncate">#encodeForHtml(file.name)#</p>
                                    <p class="text-xs text-gray-500">
                                        #formatFileSize(file.size)# • #dateFormat(file.modified, "mm/dd/yyyy")# #timeFormat(file.modified, "HH:mm")# • #file.directory#
                                    </p>
                                </div>
                                <div class="flex space-x-2">
                                    <a href="file:///#file.path#" 
                                       class="inline-flex items-center px-2 py-1 border border-gray-300 text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50">
                                        👁️ View
                                    </a>
                                </div>
                            </label>
                        </div>
                    </cfloop>
                </div>
                
                <div class="mt-6 flex space-x-4">
                    <button type="submit" 
                            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                            onclick="return confirm('Process selected files? This may take a while.')">
                        🔄 Process Selected Files
                    </button>
                    <a href="bulk_processor.cfm?action=process_all" 
                       class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                       onclick="return confirm('Process ALL files? This may take a very long time.')">
                        ⚡ Process All Files
                    </a>
                </div>
            </form>
        </div>

        <!-- Quick Stats -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Quick Stats</h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <div class="text-center">
                    <div class="text-2xl font-bold text-blue-600">#arrayLen(allFiles)#</div>
                    <div class="text-sm text-gray-500">Total Files</div>
                </div>
                <div class="text-center">
                    <div class="text-2xl font-bold text-green-600">#finalCount#</div>
                    <div class="text-sm text-gray-500">Final Directory</div>
                </div>
                <div class="text-center">
                    <div class="text-2xl font-bold text-orange-600">#inProgressCount#</div>
                    <div class="text-sm text-gray-500">In Progress</div>
                </div>
                <div class="text-center">
                    <div class="text-2xl font-bold text-purple-600">#formatFileSize(totalSize)#</div>
                    <div class="text-sm text-gray-500">Total Size</div>
                </div>
            </div>
        </div>
    </cfif>
</div>

<script>
function selectAll() {
    document.querySelectorAll('.file-checkbox').forEach(checkbox => {
        checkbox.checked = true;
    });
}

function selectNone() {
    document.querySelectorAll('.file-checkbox').forEach(checkbox => {
        checkbox.checked = false;
    });
}

// Auto-refresh every 30 seconds if no action
if (window.location.search.indexOf('action=') === -1) {
    setTimeout(() => {
        window.location.reload();
    }, 30000);
}
</script>


</cfmodule>
