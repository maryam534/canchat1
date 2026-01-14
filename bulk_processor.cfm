<cfmodule template="layout.cfm" title="Bulk Data Processor" currentPage="bulk_processor">

<div class="fade-in">
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            ⚡ <span class="ml-3">Bulk Data Processor</span>
        </h1>
        <p class="text-gray-600 mt-2">Advanced bulk processing with real-time monitoring and detailed logging.</p>
    </div>

    <!-- Real-time Monitoring Dashboard (for Scraper Jobs) -->
    <div id="monitoringDashboard" class="bg-white rounded-xl shadow-sm p-6 mb-6" style="display: none;">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center justify-between">
            <span>📊 <span class="ml-2">Real-time Scraping Monitor</span></span>
            <button onclick="toggleMonitoring()" class="text-sm text-gray-500 hover:text-gray-700">Hide</button>
        </h2>
        
        <!-- Current Status -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <div class="bg-blue-50 rounded-lg p-4">
                <div class="text-sm text-blue-600 font-medium mb-1">Current Event ID</div>
                <div id="currentEventId" class="text-2xl font-bold text-blue-800">-</div>
            </div>
            <div class="bg-green-50 rounded-lg p-4">
                <div class="text-sm text-green-600 font-medium mb-1">Lots Scraped</div>
                <div id="lotsScraped" class="text-2xl font-bold text-green-800">0</div>
            </div>
            <div class="bg-purple-50 rounded-lg p-4">
                <div class="text-sm text-purple-600 font-medium mb-1">Lots Inserted</div>
                <div id="lotsInserted" class="text-2xl font-bold text-purple-800">0</div>
            </div>
            <div class="bg-orange-50 rounded-lg p-4">
                <div class="text-sm text-orange-600 font-medium mb-1">Current Lot</div>
                <div id="currentLotNumber" class="text-2xl font-bold text-orange-800">-</div>
            </div>
        </div>
        
        <!-- Progress Bars -->
        <div class="mb-6">
            <div class="mb-2 flex justify-between text-sm">
                <span class="font-medium text-gray-700">Event Progress</span>
                <span id="eventProgressText" class="text-gray-600">0 / 0</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-3">
                <div id="eventProgressBar" class="bg-blue-600 h-3 rounded-full transition-all duration-300" style="width: 0%"></div>
            </div>
        </div>
        
        <div class="mb-6">
            <div class="mb-2 flex justify-between text-sm">
                <span class="font-medium text-gray-700">Overall Progress</span>
                <span id="overallProgressText" class="text-gray-600">0%</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-3">
                <div id="overallProgressBar" class="bg-green-600 h-3 rounded-full transition-all duration-300" style="width: 0%"></div>
            </div>
        </div>
        
        <!-- Control Buttons -->
        <div class="flex space-x-3 mb-4">
            <button id="pauseBtn" onclick="pauseJob()" class="px-4 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700 transition-colors" style="display: none;">
                ⏸️ Pause
            </button>
            <button id="resumeBtn" onclick="resumeJob()" class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors" style="display: none;">
                ▶️ Resume
            </button>
            <button id="stopBtn" onclick="stopJob()" class="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors" style="display: none;">
                ⏹️ Stop
            </button>
        </div>
        
        <!-- Activity Log -->
        <div class="bg-gray-50 rounded-lg p-4">
            <h3 class="text-sm font-semibold text-gray-700 mb-2">Recent Activity</h3>
            <div id="activityLog" class="text-xs text-gray-600 space-y-1 max-h-32 overflow-y-auto">
                <div>Waiting for activity...</div>
            </div>
        </div>
    </div>

    <!-- Existing Job Alert -->
    <div id="existingJobAlert" class="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-6" style="display: none;">
        <div class="flex items-center justify-between">
            <div class="flex items-center">
                <div class="flex-shrink-0">
                    <span class="text-yellow-400 text-xl">⚠️</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm text-yellow-700">
                        <strong>Existing job detected:</strong> <span id="existingJobInfo"></span>
                    </p>
                </div>
            </div>
            <div class="flex space-x-2">
                <button onclick="resumeExistingJob()" id="resumeExistingBtn" class="px-3 py-1 bg-green-600 text-white text-sm rounded hover:bg-green-700" style="display: none;">
                    ▶️ Resume
                </button>
                <button onclick="stopExistingJob()" class="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700">
                    ⏹️ Stop
                </button>
                <button onclick="forceStartNewJob()" class="px-3 py-1 bg-blue-600 text-white text-sm rounded hover:bg-blue-700">
                    🚀 Force Start New
                </button>
            </div>
        </div>
    </div>

    <!-- Start Bulk Scraping Section -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4">🚀 Start Bulk Scraping</h2>
        <p class="text-gray-600 mb-4">Start scraping auction lots from NumisBids with real-time monitoring</p>
        
        <form id="startScrapingForm" class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">Run Mode</label>
                    <select id="runMode" name="runMode" class="w-full border border-gray-300 rounded px-3 py-2 text-sm">
                        <option value="all">All Available Events</option>
                        <option value="max">Limited Count</option>
                        <option value="one">Specific Event ID</option>
                    </select>
                </div>
                <div id="maxSalesDiv" style="display: none;">
                    <label class="block text-sm font-medium text-gray-700 mb-1">Max Sales</label>
                    <input type="number" id="maxSales" name="maxSales" placeholder="e.g., 5" class="w-full border border-gray-300 rounded px-3 py-2 text-sm">
                </div>
                <div id="eventIdDiv" style="display: none;">
                    <label class="block text-sm font-medium text-gray-700 mb-1">Event ID</label>
                    <input type="text" id="eventId" name="eventId" placeholder="e.g., 9537" class="w-full border border-gray-300 rounded px-3 py-2 text-sm">
                </div>
            </div>
            
            <div class="flex space-x-3">
                <button type="button" onclick="startBulkScraping()" class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-medium">
                    ▶️ Start Bulk Scraping
                </button>
                <button type="button" onclick="toggleMonitoring()" class="px-6 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors font-medium">
                    📊 Show Monitoring
                </button>
            </div>
        </form>
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
    </cfscript>
    
    <cfif action == "process_selected">
        <cfset selectedFiles = url.selectedFiles ?: "" />
        <cfif len(selectedFiles)>
            <cfset fileList = listToArray(selectedFiles) />
            
            <!--- Process each selected file --->
            <cfset results = [] />
            <cfloop array="#fileList#" index="file">
                <cftry>
                    <cfset outTxt = "" />
                    <cfset errTxt = "" />
                    <cfexecute
                        name="#nodeExe#"
                        arguments='"#inserterScript#"'
                        timeout="900"
                        variable="outTxt"
                        errorVariable="errTxt" />
                    <cfset result = {
                        file: file,
                        success: true,
                        stdout: outTxt,
                        stderr: errTxt,
                        timestamp: now()
                    } />
                <cfcatch type="any">
                    <cfset result = {
                        file: file,
                        success: false,
                        error: cfcatch.message,
                        timestamp: now()
                    } />
                </cfcatch>
                </cftry>
                <cfset arrayAppend(results, result) />
            </cfloop>
            
            <cfset session.bulkProcessResults = results />
            <cflocation url="bulk_processor.cfm?action=results" addtoken="false" />
        </cfif>
    </cfif>
    
    <cfif action == "process_all">
        <!--- Process all files --->
        <cfset results = [] />
        <cfloop array="#allFiles#" index="file">
            <cftry>
                <cfset outTxt = "" />
                <cfset errTxt = "" />
                <cfexecute
                    name="#nodeExe#"
                    arguments='"#inserterScript#"'
                    timeout="900"
                    variable="outTxt"
                    errorVariable="errTxt" />
                <cfset result = {
                    file: file.name,
                    success: true,
                    stdout: outTxt,
                    stderr: errTxt,
                    timestamp: now()
                } />
            <cfcatch type="any">
                <cfset result = {
                    file: file.name,
                    success: false,
                    error: cfcatch.message,
                    timestamp: now()
                } />
            </cfcatch>
            </cftry>
            <cfset arrayAppend(results, result) />
        </cfloop>
        
        <cfset session.bulkProcessResults = results />
        <cflocation url="bulk_processor.cfm?action=results" addtoken="false" />
    </cfif>

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
let monitoringInterval = null;
let isMonitoringVisible = false;

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

// Show/hide monitoring dashboard
function toggleMonitoring() {
    const dashboard = document.getElementById('monitoringDashboard');
    if (dashboard.style.display === 'none') {
        dashboard.style.display = 'block';
        isMonitoringVisible = true;
        startMonitoring();
    } else {
        dashboard.style.display = 'none';
        isMonitoringVisible = false;
        stopMonitoring();
    }
}

// Start monitoring updates
function startMonitoring() {
    if (monitoringInterval) clearInterval(monitoringInterval);
    updateMonitoring(); // Initial update
    monitoringInterval = setInterval(updateMonitoring, 2500); // Update every 2.5 seconds
}

// Stop monitoring updates
function stopMonitoring() {
    if (monitoringInterval) {
        clearInterval(monitoringInterval);
        monitoringInterval = null;
    }
}

// Update monitoring data
function updateMonitoring() {
    fetch('tasks/run_scraper.cfm?action=status&ajax=1')
        .then(response => {
            const contentType = response.headers.get('content-type');
            if (contentType && contentType.includes('application/json')) {
                return response.json();
            }
            return response.text().then(text => {
                // Check if response is HTML (error page)
                if (text.trim().startsWith('<!') || text.trim().startsWith('<!--')) {
                    console.error('Server returned HTML instead of JSON. This usually indicates a server error.');
                    return null;
                }
                try {
                    return JSON.parse(text);
                } catch (e) {
                    console.error('Failed to parse JSON:', text.substring(0, 200));
                    return null;
                }
            });
        })
        .then(data => {
            if (!data) return;
            
            console.log('Monitoring data:', data);
            console.log('Logs in response:', data.logs || data.LOGS);
            console.log('Current job:', data.currentJob || data.CURRENTJOB);
            
            // Handle ColdFusion's uppercase JSON keys
            // Format 1: {currentJob/CURRENTJOB: {...}, logs/LOGS: [...]} (AJAX endpoint)
            // Format 2: {STATUS: "running", JOBID: 8, NEWLOGS: [...]} (non-AJAX endpoint)
            
            let job = null;
            let jobStatus = null;
            let logs = [];
            
            // Handle both camelCase and UPPERCASE keys
            const currentJob = data.currentJob || data.CURRENTJOB;
            const logsArray = data.logs || data.LOGS || [];
            
            if (currentJob && (currentJob.id || currentJob.ID)) {
                // Format 1: AJAX endpoint response
                job = currentJob;
                jobStatus = job.status || job.STATUS;
                // Get logs from logs array (handle both cases)
                if (logsArray && Array.isArray(logsArray) && logsArray.length > 0) {
                    logs = logsArray;
                } else if (data.NEWLOGS && Array.isArray(data.NEWLOGS) && data.NEWLOGS.length > 0) {
                    logs = data.NEWLOGS.map(log => typeof log === 'string' ? log : (log.message || log));
                }
            } else if (data.STATUS || data.status) {
                // Format 2: Non-AJAX endpoint response - fetch AJAX data for full details
                jobStatus = data.STATUS || data.status;
                if (data.NEWLOGS && Array.isArray(data.NEWLOGS)) {
                    logs = data.NEWLOGS.map(log => typeof log === 'string' ? {message: log, timestamp: new Date().toLocaleTimeString()} : log);
                }
                // Always fetch from AJAX endpoint for complete data including logs
                return fetch('tasks/run_scraper.cfm?action=status&ajax=1')
                    .then(r => {
                        const contentType = r.headers.get('content-type');
                        if (contentType && contentType.includes('application/json')) {
                            return r.json();
                        }
                        return r.text().then(text => {
                            if (text.trim().startsWith('<!') || text.trim().startsWith('<!--')) {
                                console.error('Server returned HTML instead of JSON.');
                                return {currentJob: null, logs: logs || []};
                            }
                            try {
                                return JSON.parse(text);
                            } catch (e) {
                                console.error('Failed to parse AJAX response:', text.substring(0, 200));
                                return {currentJob: null, logs: logs || []};
                            }
                        });
                    })
                    .then(ajaxData => {
                        console.log('AJAX data received:', ajaxData);
                        // Handle uppercase keys from ColdFusion serializeJSON
                        const ajaxJob = ajaxData.currentJob || ajaxData.CURRENTJOB;
                        const ajaxLogs = ajaxData.logs || ajaxData.LOGS || [];
                        // Use AJAX data if available, otherwise use non-AJAX data
                        if (ajaxJob && (ajaxJob.id || ajaxJob.ID)) {
                            // Combine logs from both sources, prefer AJAX logs
                            const allLogs = (ajaxLogs.length > 0) ? ajaxLogs : logs;
                            return {job: ajaxJob, status: ajaxJob.status || ajaxJob.STATUS || jobStatus, logs: allLogs};
                        }
                        // Fallback to non-AJAX data
                        return {job: null, status: jobStatus, logs: logs || []};
                    })
                    .catch(err => {
                        console.error('Error fetching AJAX data:', err);
                        return {job: null, status: jobStatus, logs: logs || []};
                    });
            }
            
            return {job: job, status: jobStatus, logs: logs || []};
        })
        .then(result => {
            if (!result) return;
            
            const {job, status, logs} = result;
            // Handle uppercase status keys
            const jobStatus = job && (job.status || job.STATUS);
            const statusLower = (status || '').toLowerCase();
            const jobStatusLower = (jobStatus || '').toLowerCase();
            const hasActiveJob = (statusLower === 'running' || statusLower === 'paused') || 
                                 (jobStatusLower === 'running' || jobStatusLower === 'paused');
            
            // Auto-show dashboard if job is running or paused
            if (hasActiveJob && !isMonitoringVisible) {
                document.getElementById('monitoringDashboard').style.display = 'block';
                isMonitoringVisible = true;
                if (!monitoringInterval) {
                    startMonitoring();
                }
            }
            
            // Handle both camelCase and UPPERCASE keys from ColdFusion
            const jobId = job && (job.id || job.ID);
            if (jobId) {
                // Update status fields - handle uppercase keys
                const currentEventId = job.currentEventId || job.CURRENTEVENTID || job.targetEventId || job.TARGETEVENTID || '-';
                const currentLotNumber = job.currentLotNumber || job.CURRENTLOTNUMBER || '-';
                document.getElementById('currentEventId').textContent = currentEventId;
                document.getElementById('currentLotNumber').textContent = currentLotNumber;
                
                // Update statistics - show even if 0 initially - handle uppercase keys
                const stats = job.statistics || job.STATISTICS;
                if (stats) {
                    const lotsScraped = stats.processedLots || stats.PROCESSEDLOTS || 0;
                    // For now, lotsInserted = lotsScraped (in real-time mode, they're inserted immediately)
                    const lotsInserted = lotsScraped; // In real-time mode, scraped = inserted
                    console.log('Updating statistics:', {lotsScraped, lotsInserted, stats});
                    document.getElementById('lotsScraped').textContent = lotsScraped;
                    document.getElementById('lotsInserted').textContent = lotsInserted;
                    
                    // Update progress bars - handle uppercase keys
                    const totalEvents = job.totalEvents || job.TOTALEVENTS || 0;
                    const currentEventIndex = job.currentEventIndex || job.CURRENTEVENTINDEX || 0;
                    if (totalEvents > 0) {
                        const eventProgress = ((currentEventIndex + 1) / totalEvents) * 100;
                        document.getElementById('eventProgressBar').style.width = eventProgress + '%';
                        document.getElementById('eventProgressText').textContent = 
                            (currentEventIndex + 1) + ' / ' + totalEvents;
                    }
                    
                    // Handle uppercase keys for stats
                    const statsTotalEvents = stats.totalEvents || stats.TOTALEVENTS || 0;
                    const statsProcessedEvents = stats.processedEvents || stats.PROCESSEDEVENTS || 0;
                    const statsTotalLots = stats.totalLots || stats.TOTALLOTS || 0;
                    if (statsTotalEvents > 0) {
                        const overallProgress = (statsProcessedEvents / statsTotalEvents) * 100;
                        document.getElementById('overallProgressBar').style.width = overallProgress + '%';
                        document.getElementById('overallProgressText').textContent = Math.round(overallProgress) + '%';
                    } else if (statsTotalLots > 0) {
                        // For single event, use lots progress
                        const lotsProgress = (lotsScraped / statsTotalLots) * 100;
                        document.getElementById('overallProgressBar').style.width = lotsProgress + '%';
                        document.getElementById('overallProgressText').textContent = Math.round(lotsProgress) + '%';
                    }
                } else {
                    // If no statistics yet, show basic info
                    document.getElementById('lotsScraped').textContent = '0';
                    document.getElementById('lotsInserted').textContent = '0';
                }
                
                // Update button states - handle uppercase keys
                const currentJobStatus = (job.status || job.STATUS || '').toLowerCase();
                if (currentJobStatus === 'running') {
                    document.getElementById('pauseBtn').style.display = 'inline-block';
                    document.getElementById('resumeBtn').style.display = 'none';
                    document.getElementById('stopBtn').style.display = 'inline-block';
                } else if (currentJobStatus === 'paused') {
                    document.getElementById('pauseBtn').style.display = 'none';
                    document.getElementById('resumeBtn').style.display = 'inline-block';
                    document.getElementById('stopBtn').style.display = 'inline-block';
                } else {
                    document.getElementById('pauseBtn').style.display = 'none';
                    document.getElementById('resumeBtn').style.display = 'none';
                    document.getElementById('stopBtn').style.display = 'none';
                }
            } else {
                // Job exists but details not loaded yet - use status from response
                const statusLower = (status || '').toLowerCase();
                if (statusLower === 'running') {
                    document.getElementById('pauseBtn').style.display = 'inline-block';
                    document.getElementById('resumeBtn').style.display = 'none';
                    document.getElementById('stopBtn').style.display = 'inline-block';
                } else if (statusLower === 'paused') {
                    document.getElementById('pauseBtn').style.display = 'none';
                    document.getElementById('resumeBtn').style.display = 'inline-block';
                    document.getElementById('stopBtn').style.display = 'inline-block';
                } else {
                    // No active job
                    document.getElementById('pauseBtn').style.display = 'none';
                    document.getElementById('resumeBtn').style.display = 'none';
                    document.getElementById('stopBtn').style.display = 'none';
                }
            }
            
            // Update activity log (filter out process detection warnings)
            if (logs && logs.length > 0) {
                const logDiv = document.getElementById('activityLog');
                // Filter out process detection messages (they're not critical)
                const filteredLogs = logs.filter(log => {
                    const logText = typeof log === 'string' ? log : (log.message || log);
                    // Hide process detection warnings - they're normal for background execution
                    return !logText.toLowerCase().includes('process not found') && 
                           !logText.toLowerCase().includes('process check') &&
                           !logText.toLowerCase().includes('process detection') &&
                           !logText.toLowerCase().includes('checking debug log');
                });
                // Show most recent logs (keep last 20 for better visibility)
                const recentLogs = filteredLogs.slice(-20);
                // Clear and rebuild log display
                logDiv.innerHTML = '';
                recentLogs.forEach(log => {
                    const logEntry = document.createElement('div');
                    logEntry.className = 'text-sm text-gray-700 py-1 border-b border-gray-100';
                    if (typeof log === 'string') {
                        // Log already has timestamp format [HH:mm:ss] message
                        logEntry.textContent = log;
                    } else {
                        const timestamp = log.timestamp || new Date().toLocaleTimeString();
                        const message = log.message || log;
                        logEntry.textContent = `[${timestamp}] ${message}`;
                    }
                    logDiv.appendChild(logEntry);
                });
                // Keep only last 25 entries
                while (logDiv.children.length > 25) {
                    logDiv.removeChild(logDiv.firstChild);
                }
                
                // Scroll to bottom to show latest logs
                if (logDiv.scrollHeight > logDiv.clientHeight) {
                    logDiv.scrollTop = logDiv.scrollHeight;
                }
            }
            
            // Also show current lot info in activity if available
            if (job && job.currentLotNumber && job.currentLotNumber !== '-') {
                const logDiv = document.getElementById('activityLog');
                const currentInfo = `Processing Lot ${job.currentLotNumber} from Event ${job.currentEventId || job.targetEventId || 'N/A'}`;
                // Only add if not already shown
                if (!logDiv.innerHTML.includes(`Lot ${job.currentLotNumber}`)) {
                    const infoDiv = document.createElement('div');
                    infoDiv.className = 'text-blue-600 font-medium';
                    infoDiv.textContent = `[${new Date().toLocaleTimeString()}] ${currentInfo}`;
                    logDiv.insertBefore(infoDiv, logDiv.firstChild);
                    // Keep only last 10 entries
                    while (logDiv.children.length > 10) {
                        logDiv.removeChild(logDiv.lastChild);
                    }
                }
            }
        })
        .catch(error => {
            console.error('Error fetching monitoring data:', error);
        });
}

// Check for existing jobs
function checkExistingJobs() {
    fetch('tasks/run_scraper.cfm?action=status&ajax=1')
        .then(response => response.json())
        .then(data => {
            if (data.currentJob && data.currentJob.id) {
                const job = data.currentJob;
                const jobInfo = `Job #${job.id} - ${job.name} (${job.status})`;
                document.getElementById('existingJobInfo').textContent = jobInfo;
                document.getElementById('existingJobAlert').style.display = 'block';
                
                // Show resume button if paused
                if (job.status === 'paused') {
                    document.getElementById('resumeExistingBtn').style.display = 'inline-block';
                } else {
                    document.getElementById('resumeExistingBtn').style.display = 'none';
                }
                
                // Auto-show monitoring if job exists
                if (!isMonitoringVisible) {
                    document.getElementById('monitoringDashboard').style.display = 'block';
                    isMonitoringVisible = true;
                    startMonitoring();
                }
            } else {
                document.getElementById('existingJobAlert').style.display = 'none';
            }
        })
        .catch(error => {
            console.error('Error checking existing jobs:', error);
        });
}

// Stop existing job
function stopExistingJob() {
    if (confirm('Are you sure you want to stop the existing job?')) {
        fetch('tasks/run_scraper.cfm?action=stop&ajax=1', { method: 'POST' })
            .then(response => {
                if (!response.ok) {
                    throw new Error('HTTP error! status: ' + response.status);
                }
                return response.text().then(text => {
                    try {
                        return JSON.parse(text);
                    } catch (e) {
                        console.error('Response text:', text);
                        throw new Error('Invalid JSON response: ' + text.substring(0, 200));
                    }
                });
            })
            .then(data => {
                console.log('Stop response:', data);
                if (data.success === true || data.SUCCESS === true) {
                    addActivityLog('Existing job stopped successfully');
                    document.getElementById('existingJobAlert').style.display = 'none';
                    updateMonitoring();
                } else {
                    const errorMsg = data.error || data.ERROR || data.message || data.MESSAGE || 'Unknown error';
                    alert('Error stopping job: ' + errorMsg);
                    addActivityLog('Error stopping job: ' + errorMsg);
                }
            })
            .catch(error => {
                console.error('Error stopping job:', error);
                alert('Error stopping job: ' + error.message);
                addActivityLog('Error stopping job: ' + error.message);
            });
    }
}

// Resume existing job
function resumeExistingJob() {
    fetch('tasks/run_scraper.cfm?action=resume&ajax=1', { method: 'POST' })
        .then(response => {
            if (!response.ok) {
                throw new Error('HTTP error! status: ' + response.status);
            }
            return response.text().then(text => {
                try {
                    return JSON.parse(text);
                } catch (e) {
                    console.error('Response text:', text);
                    throw new Error('Invalid JSON response: ' + text.substring(0, 200));
                }
            });
        })
        .then(data => {
            console.log('Resume response:', data);
            if (data.success === true || data.SUCCESS === true) {
                addActivityLog('Job resumed successfully');
                document.getElementById('existingJobAlert').style.display = 'none';
                updateMonitoring();
            } else {
                const errorMsg = data.error || data.ERROR || data.message || data.MESSAGE || 'Unknown error';
                alert('Error resuming job: ' + errorMsg);
                addActivityLog('Error resuming job: ' + errorMsg);
            }
        })
        .catch(error => {
            console.error('Error resuming job:', error);
            alert('Error resuming job: ' + error.message);
            addActivityLog('Error resuming job: ' + error.message);
        });
}

// Force start new job (stops existing first)
function forceStartNewJob() {
    if (confirm('This will stop the existing job and start a new one. Continue?')) {
        stopExistingJob();
        // Wait a moment for job to stop, then start new one
        setTimeout(() => {
            startBulkScraping(true); // Pass force flag
        }, 1000);
    }
}

// Start bulk scraping
function startBulkScraping(forceStart = false) {
    const runMode = document.getElementById('runMode').value;
    const maxSales = document.getElementById('maxSales').value;
    const eventId = document.getElementById('eventId').value;
    
    // Validate inputs
    if (runMode === 'max' && !maxSales) {
        alert('Please enter Max Sales');
        return;
    }
    if (runMode === 'one' && !eventId) {
        alert('Please enter Event ID');
        return;
    }
    
    // Build form data
    const formData = new FormData();
    formData.append('action', 'start');
    formData.append('runMode', runMode);
    if (maxSales) formData.append('maxSales', maxSales);
    if (eventId) formData.append('eventId', eventId);
    if (forceStart) formData.append('force', '1');
    formData.append('ajax', '1');
    
    // Show monitoring dashboard
    document.getElementById('monitoringDashboard').style.display = 'block';
    isMonitoringVisible = true;
    startMonitoring();
    addActivityLog('Starting bulk scraping...');
    
    // Start scraping
    fetch('tasks/run_scraper.cfm', {
        method: 'POST',
        body: formData
    })
    .then(response => {
        // Check if response is OK
        if (!response.ok) {
            throw new Error('HTTP error! status: ' + response.status);
        }
        // Try to parse as JSON
        return response.text().then(text => {
            try {
                return JSON.parse(text);
            } catch (e) {
                console.error('Response text:', text);
                throw new Error('Invalid JSON response: ' + text.substring(0, 200));
            }
        });
    })
    .then(data => {
        console.log('Start response:', data);
        
        // Handle different response formats
        // Format 1: {success: true, jobId: 8}
        // Format 2: {SUCCESS: true, JOBID: 8, MESSAGE: '...'}
        // Format 3: {STATUS: "running", JOBID: 8}
        const hasSuccessFlag = data.success === true || 
                              data.SUCCESS === true ||
                              data.SUCCESS === "true" ||
                              data.success === "true";
        
        const hasStatusRunning = (data.STATUS && (data.STATUS === "running" || data.STATUS === "queued")) ||
                                (data.status && (data.status === "running" || data.status === "queued"));
        
        const hasJobId = data.jobId || data.JOBID || data.job_id;
        const noError = (!data.error || data.error === '') && (!data.ERROR || data.ERROR === '');
        
        // Success if: has success flag, OR has running status, OR has jobId with no error
        const isSuccess = hasSuccessFlag || hasStatusRunning || (hasJobId && noError && data.SUCCESS !== false);
        
        if (isSuccess) {
            const jobId = data.jobId || data.JOBID || data.job_id || 'N/A';
            const successMsg = data.MESSAGE || data.message || 'Bulk scraping started successfully!';
            addActivityLog(successMsg + ' Job ID: ' + jobId);
            
            // Hide existing job alert if shown
            document.getElementById('existingJobAlert').style.display = 'none';
            
            // If response has logs, show them
            if (data.NEWLOGS && Array.isArray(data.NEWLOGS)) {
                data.NEWLOGS.forEach(log => {
                    if (typeof log === 'string') {
                        addActivityLog(log);
                    }
                });
            }
            
            updateMonitoring();
        } else {
            // Only treat as error if SUCCESS is explicitly false or we have an error field
            const hasExplicitError = data.SUCCESS === false || 
                                    data.success === false ||
                                    (data.error && data.error !== '') ||
                                    (data.ERROR && data.ERROR !== '');
            
            if (!hasExplicitError && hasJobId) {
                // Actually a success, just with different format
                const jobId = data.jobId || data.JOBID || data.job_id || 'N/A';
                const successMsg = data.MESSAGE || data.message || 'Bulk scraping started successfully!';
                addActivityLog(successMsg + ' Job ID: ' + jobId);
                document.getElementById('existingJobAlert').style.display = 'none';
                updateMonitoring();
                return; // Exit early, it's actually a success
            }
            
            // Try multiple possible error field names
            const errorMsg = data.error || data.ERROR || data.message || data.MESSAGE || 
                           (data.SUCCESS === false ? 'Operation failed' : 'Unknown error');
            
            console.error('Start failed with error:', errorMsg, 'Full response:', data);
            
            // Check if error is about existing job
            if (errorMsg.indexOf('already running') > -1 || errorMsg.indexOf('paused') > -1) {
                // Show existing job alert and check for existing jobs
                checkExistingJobs();
            }
            
            // Check if error is about missing tables
            if (errorMsg.indexOf('does not exist') > -1 || 
                errorMsg.indexOf('not found') > -1 || 
                errorMsg.indexOf('migration') > -1 ||
                errorMsg.indexOf('scraper_jobs') > -1) {
                alert('Database tables not found!\n\nPlease run the migration first:\n1. Go to: apply_migration.cfm\n2. Click the page to run migration\n3. Then try starting again.\n\nError: ' + errorMsg);
                addActivityLog('Error: Database tables missing. Please run migration at apply_migration.cfm');
            } else {
                alert('Error starting scraping: ' + errorMsg);
                addActivityLog('Error: ' + errorMsg);
            }
        }
    })
    .catch(error => {
        console.error('Error starting scraping:', error);
        alert('Error starting scraping: ' + error.message);
        addActivityLog('Error: ' + error.message);
    });
}

// Pause job
function pauseJob() {
    fetch('tasks/run_scraper.cfm?action=pause&ajax=1', { method: 'POST' })
        .then(response => {
            if (!response.ok) {
                throw new Error('HTTP error! status: ' + response.status);
            }
            return response.text().then(text => {
                try {
                    return JSON.parse(text);
                } catch (e) {
                    console.error('Response text:', text);
                    throw new Error('Invalid JSON response: ' + text.substring(0, 200));
                }
            });
        })
        .then(data => {
            console.log('Pause response:', data);
            if (data.success === true || data.SUCCESS === true) {
                addActivityLog('Job paused successfully');
                updateMonitoring();
            } else {
                const errorMsg = data.error || data.ERROR || data.message || data.MESSAGE || 'Unknown error';
                alert('Error pausing job: ' + errorMsg);
                addActivityLog('Error pausing job: ' + errorMsg);
            }
        })
        .catch(error => {
            console.error('Error pausing job:', error);
            alert('Error pausing job: ' + error.message);
            addActivityLog('Error pausing job: ' + error.message);
        });
}

// Resume job
function resumeJob() {
    fetch('tasks/run_scraper.cfm?action=resume&ajax=1', { method: 'POST' })
        .then(response => {
            if (!response.ok) {
                throw new Error('HTTP error! status: ' + response.status);
            }
            return response.text().then(text => {
                try {
                    return JSON.parse(text);
                } catch (e) {
                    console.error('Response text:', text);
                    throw new Error('Invalid JSON response: ' + text.substring(0, 200));
                }
            });
        })
        .then(data => {
            console.log('Resume response:', data);
            if (data.success === true || data.SUCCESS === true) {
                addActivityLog('Job resumed successfully');
                updateMonitoring();
            } else {
                const errorMsg = data.error || data.ERROR || data.message || data.MESSAGE || 'Unknown error';
                alert('Error resuming job: ' + errorMsg);
                addActivityLog('Error resuming job: ' + errorMsg);
            }
        })
        .catch(error => {
            console.error('Error resuming job:', error);
            alert('Error resuming job: ' + error.message);
            addActivityLog('Error resuming job: ' + error.message);
        });
}

// Stop job
function stopJob() {
    if (confirm('Are you sure you want to stop the job?')) {
        fetch('tasks/run_scraper.cfm?action=stop&ajax=1', { method: 'POST' })
            .then(response => {
                if (!response.ok) {
                    throw new Error('HTTP error! status: ' + response.status);
                }
                return response.text().then(text => {
                    try {
                        return JSON.parse(text);
                    } catch (e) {
                        console.error('Response text:', text);
                        throw new Error('Invalid JSON response: ' + text.substring(0, 200));
                    }
                });
            })
            .then(data => {
                console.log('Stop response:', data);
                if (data.success === true || data.SUCCESS === true) {
                    addActivityLog('Job stopped successfully');
                    stopMonitoring();
                    updateMonitoring();
                } else {
                    const errorMsg = data.error || data.ERROR || data.message || data.MESSAGE || 'Unknown error';
                    alert('Error stopping job: ' + errorMsg);
                    addActivityLog('Error stopping job: ' + errorMsg);
                }
            })
            .catch(error => {
                console.error('Error stopping job:', error);
                alert('Error stopping job: ' + error.message);
                addActivityLog('Error stopping job: ' + error.message);
            });
    }
}

// Add activity log entry
function addActivityLog(message) {
    const logDiv = document.getElementById('activityLog');
    if (!logDiv) return;
    
    // Filter out process detection warnings (they're normal for background execution)
    const lowerMessage = message.toLowerCase();
    if (lowerMessage.includes('process not found') || 
        lowerMessage.includes('process check') ||
        lowerMessage.includes('process detection') ||
        lowerMessage.includes('checking debug log for errors')) {
        // Don't show these - they're not critical, script is monitored via database
        return;
    }
    
    const timestamp = new Date().toLocaleTimeString();
    const logEntry = document.createElement('div');
    logEntry.textContent = `[${timestamp}] ${message}`;
    logDiv.insertBefore(logEntry, logDiv.firstChild);
    
    // Keep only last 10 entries
    while (logDiv.children.length > 10) {
        logDiv.removeChild(logDiv.lastChild);
    }
}

// Handle run mode changes
document.getElementById('runMode').addEventListener('change', function() {
    const runMode = this.value;
    document.getElementById('maxSalesDiv').style.display = (runMode === 'max') ? 'block' : 'none';
    document.getElementById('eventIdDiv').style.display = (runMode === 'one') ? 'block' : 'none';
});

// Auto-start monitoring if page loads with active job
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(function() {
        // Check for existing jobs and auto-show monitoring
        checkExistingJobs();
        
        // Also check status directly and show monitoring if job is active
        fetch('tasks/run_scraper.cfm?action=status')
            .then(response => response.text())
            .then(text => {
                try {
                    const data = JSON.parse(text);
                    // Check if job is running or paused
                    if ((data.STATUS === 'running' || data.STATUS === 'paused' || 
                         data.status === 'running' || data.status === 'paused') ||
                        (data.currentJob && (data.currentJob.status === 'running' || data.currentJob.status === 'paused'))) {
                        // Auto-show monitoring
                        if (!isMonitoringVisible) {
                            document.getElementById('monitoringDashboard').style.display = 'block';
                            isMonitoringVisible = true;
                            startMonitoring();
                        }
                    }
                } catch (e) {
                    console.error('Error parsing status:', e);
                }
            })
            .catch(error => console.error('Error checking initial status:', error));
    }, 500);
});

// Auto-refresh every 30 seconds if no action
if (window.location.search.indexOf('action=') === -1) {
    setTimeout(() => {
        window.location.reload();
    }, 30000);
}
</script>


</cfmodule>
