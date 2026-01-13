<cfscript>
    // Get system status data
    action = url.action ?: "";
    
    if (action == "data") {
        // Return JSON data for AJAX requests
        statusData = {
            timestamp: now(),
            scraper: {
                isRunning: false,
                processId: "",
                startTime: "",
                lastActivity: "",
                currentJob: {},
                progress: {}
            },
            files: {
                inProgress: [],
                completed: [],
                totalSize: 0
            },
            database: {
                totalFiles: 0,
                completedFiles: 0,
                processingFiles: 0,
                errorFiles: 0,
                lastUpdate: "",
                jobs: {
                    total: 0,
                    running: 0,
                    completed: 0,
                    failed: 0
                }
            },
            rag: {
                processedJobs: 0,
                pendingJobs: 0,
                totalLotsProcessed: 0
            },
            system: {
                diskSpace: 0,
                memoryUsage: 0,
                uptime: 0
            },
            performance: {
                averageScrapingTime: 0,
                successRate: 0,
                totalLotsScraped: 0
            }
        };
        
        try {
            // Check scraper process
            try {
                cfexecute(
                    name = "wmic",
                    arguments = "process where ""name='node.exe'"" get ProcessId,CommandLine,StartTime /format:list",
                    timeout = 10,
                    variable = "processList"
                );
                
                if (findNoCase("scrap_all_auctions_lots_data.js", processList) > 0) {
                    statusData.scraper.isRunning = true;
                    
                    // Extract process details
                    lines = listToArray(processList, chr(13) & chr(10));
                    for (line in lines) {
                        if (findNoCase("scrap_all_auctions_lots_data.js", line) > 0) {
                            // Find the process ID for this line
                            for (i = 1; i <= arrayLen(lines); i++) {
                                if (findNoCase("ProcessId=", lines[i]) > 0 && i > arrayFind(lines, line)) {
                                    pidStart = findNoCase("ProcessId=", lines[i]) + 10;
                                    pidEnd = findNoCase(chr(13), lines[i], pidStart);
                                    if (pidEnd == 0) pidEnd = len(lines[i]) + 1;
                                    statusData.scraper.processId = trim(mid(lines[i], pidStart, pidEnd - pidStart));
                                    break;
                                }
                            }
                            break;
                        }
                    }
                }
            } catch (err) {
                statusData.scraper.isRunning = false;
            }
            
            // Check file status using application configuration
            inProgressFolder = application.paths.inProgressDir;
            finalFolder = application.paths.finalDir;
            
            if (directoryExists(inProgressFolder)) {
                inProgressFiles = directoryList(inProgressFolder, false, "name", "*.jsonl");
                for (file in inProgressFiles) {
                    filePath = inProgressFolder & "/" & file;
                    if (fileExists(filePath)) {
                        fileInfo = getFileInfo(filePath);
                        arrayAppend(statusData.files.inProgress, {
                            name: file,
                            size: numberFormat(fileInfo.size/1024, "999.9"),
                            lastModified: fileInfo.lastModified,
                            lineCount: arrayLen(listToArray(fileRead(filePath), chr(10)))
                        });
                        statusData.files.totalSize += fileInfo.size;
                    }
                }
            }
            
            if (directoryExists(finalFolder)) {
                finalFiles = directoryList(finalFolder, false, "name", "*.json");
                for (file in finalFiles) {
                    filePath = finalFolder & "/" & file;
                    if (fileExists(filePath)) {
                        fileInfo = getFileInfo(filePath);
                        arrayAppend(statusData.files.completed, {
                            name: file,
                            size: numberFormat(fileInfo.size/1024, "999.9"),
                            lastModified: fileInfo.lastModified
                        });
                        statusData.files.totalSize += fileInfo.size;
                    }
                }
            }
            
            // Get database status - scraper jobs
            try {
                // Get current running job
                currentJob = queryExecute(
                    "SELECT id, job_name, status, created_at, started_at, completed_at, error_message 
                     FROM scraper_jobs 
                     WHERE status IN ('running', 'queued', 'paused')
                     ORDER BY created_at DESC LIMIT 1",
                    [],
                    {datasource = application.db.dsn}
                );
                
                if (currentJob.recordCount > 0) {
                    statusData.scraper.isRunning = (currentJob.status == "running");
                    statusData.scraper.currentJob = {
                        id: currentJob.id,
                        name: currentJob.job_name,
                        status: currentJob.status,
                        created: currentJob.created_at,
                        started: currentJob.started_at,
                        completed: currentJob.completed_at
                    };
                    
                    // Get job statistics
                    jobStats = queryExecute(
                        "SELECT total_events, processed_events, total_lots, processed_lots, 
                                files_created, files_completed, last_update
                         FROM job_statistics 
                         WHERE job_id = ? 
                         ORDER BY id DESC LIMIT 1",
                        [{value = currentJob.id, cfsqltype = "cf_sql_integer"}],
                        {datasource = application.db.dsn}
                    );
                    
                    if (jobStats.recordCount > 0) {
                        statusData.scraper.progress = {
                            events: {
                                total: jobStats.total_events,
                                processed: jobStats.processed_events
                            },
                            lots: {
                                total: jobStats.total_lots,
                                processed: jobStats.processed_lots
                            },
                            files: {
                                created: jobStats.files_created,
                                completed: jobStats.files_completed
                            }
                        };
                    }
                    
                    // Get recent logs
                    recentLogs = queryExecute(
                        "SELECT message, timestamp, log_level 
                         FROM scrape_logs 
                         WHERE job_id = ? 
                         ORDER BY timestamp DESC 
                         LIMIT 10",
                        [{value = currentJob.id, cfsqltype = "cf_sql_integer"}],
                        {datasource = application.db.dsn}
                    );
                    
                    if (recentLogs.recordCount > 0) {
                        statusData.scraper.lastActivity = recentLogs.timestamp[1];
                    }
                }
                
                // Get job counts
                jobCounts = queryExecute(
                    "SELECT 
                        COUNT(*) as total,
                        SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) as running,
                        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
                        SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) as failed
                     FROM scraper_jobs",
                    [],
                    {datasource = application.db.dsn}
                );
                
                if (jobCounts.recordCount > 0) {
                    statusData.database.jobs = {
                        total: jobCounts.total,
                        running: jobCounts.running,
                        completed: jobCounts.completed,
                        failed: jobCounts.failed
                    };
                }
                
                // Get RAG processing status
                ragStatus = queryExecute(
                    "SELECT 
                        COUNT(*) as total_completed,
                        SUM(CASE WHEN rag_processed_at IS NOT NULL THEN 1 ELSE 0 END) as processed,
                        SUM(CASE WHEN rag_processed_at IS NULL THEN 1 ELSE 0 END) as pending
                     FROM scraper_jobs
                     WHERE status = 'completed'",
                    [],
                    {datasource = application.db.dsn}
                );
                
                if (ragStatus.recordCount > 0) {
                    statusData.rag.processedJobs = ragStatus.processed;
                    statusData.rag.pendingJobs = ragStatus.pending;
                }
                
                // Get uploaded files stats (existing)
                query name="dbStats" datasource="#application.db.dsn#" {
                    "SELECT 
                        COUNT(*) as total_files,
                        SUM(CASE WHEN status = 'Done' THEN 1 ELSE 0 END) as completed_files,
                        SUM(CASE WHEN status = 'Processing' THEN 1 ELSE 0 END) as processing_files,
                        SUM(CASE WHEN status = 'Error' THEN 1 ELSE 0 END) as error_files,
                        MAX(processed_at) as last_update
                    FROM uploaded_files";
                };
                
                statusData.database.totalFiles = dbStats.total_files;
                statusData.database.completedFiles = dbStats.completed_files;
                statusData.database.processingFiles = dbStats.processing_files;
                statusData.database.errorFiles = dbStats.error_files;
                statusData.database.lastUpdate = dbStats.last_update;
                
                // Get performance metrics
                query name="perfStats" datasource="#application.db.dsn#" {
                    "SELECT 
                        AVG(EXTRACT(EPOCH FROM (processed_at - created_at))) as avg_processing_time,
                        COUNT(*) as total_processed
                    FROM uploaded_files 
                    WHERE status = 'Done' AND processed_at IS NOT NULL";
                };
                
                statusData.performance.averageScrapingTime = numberFormat(perfStats.avg_processing_time/60, "999.9");
                statusData.performance.successRate = dbStats.total_files > 0 ? 
                    numberFormat((dbStats.completed_files / dbStats.total_files) * 100, "99.9") : 0;
                
            } catch (err) {
                statusData.database.error = err.message;
            }
            
            // Get system info
            try {
                // Get disk space
                cfexecute(
                    name = "wmic",
                    arguments = "logicaldisk where ""DeviceID='C:'"" get Size,FreeSpace /format:list",
                    timeout = 10,
                    variable = "diskInfo"
                );
                
                if (findNoCase("FreeSpace=", diskInfo) > 0) {
                    freeSpaceMatch = reFind("FreeSpace=(\d+)", diskInfo, 1, true);
                    if (freeSpaceMatch.pos[1] > 0) {
                        freeSpace = mid(diskInfo, freeSpaceMatch.pos[1], freeSpaceMatch.len[1]);
                        statusData.system.diskSpace = numberFormat(freeSpace/1024/1024/1024, "999.9");
                    }
                }
                
                // Get memory usage
                cfexecute(
                    name = "wmic",
                    arguments = "OS get TotalVisibleMemorySize,FreePhysicalMemory /format:list",
                    timeout = 10,
                    variable = "memInfo"
                );
                
                if (findNoCase("FreePhysicalMemory=", memInfo) > 0) {
                    freeMemMatch = reFind("FreePhysicalMemory=(\d+)", memInfo, 1, true);
                    if (freeMemMatch.pos[1] > 0) {
                        freeMem = mid(memInfo, freeMemMatch.pos[1], freeMemMatch.len[1]);
                        statusData.system.memoryUsage = numberFormat(freeMem/1024, "999.9");
                    }
                }
                
            } catch (err) {
                statusData.system.error = err.message;
            }
            
        } catch (err) {
            statusData.error = err.message;
        }
        
        writeOutput(serializeJSON(statusData));
        abort;
    }
</cfscript>

<!DOCTYPE html>
<html>
<head>
    <title>System Status - NumisBids Scraper</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <style>
        .status-card {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            margin-bottom: 1.5rem;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .metric {
            text-align: center;
            padding: 1rem;
            border-radius: 8px;
        }
        .metric-value {
            font-size: 2rem;
            font-weight: bold;
            margin-bottom: 0.5rem;
        }
        .metric-label {
            font-size: 0.875rem;
            color: #6b7280;
        }
        .status-indicator {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
            margin-right: 8px;
        }
        .status-running { background: ##10b981; }
        .status-stopped { background: ##ef4444; }
        .status-warning { background: ##f59e0b; }
        .progress-bar {
            background: #e5e7eb;
            height: 8px;
            border-radius: 4px;
            overflow: hidden;
            margin-top: 0.5rem;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, ##3b82f6, ##1d4ed8);
            transition: width 0.3s ease;
        }
    </style>
</head>
<body class="bg-gray-50">
    <div class="max-w-7xl mx-auto p-6">
        <div class="mb-6">
            <h1 class="text-3xl font-bold text-gray-900">System Status Dashboard</h1>
            <p class="text-gray-600">Real-time monitoring of the NumisBids scraper system</p>
        </div>
        
        <!-- Scraper Status -->
        <div class="status-card">
            <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold text-gray-800">&#128260; Scraper Status</h2>
                <button onclick="refreshStatus()" class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 transition-colors">
                    Refresh
                </button>
            </div>
            
            <div id="scraperStatus" class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div class="metric bg-blue-50">
                    <div class="metric-value text-blue-600" id="scraperState">Loading...</div>
                    <div class="metric-label">Status</div>
                </div>
                <div class="metric bg-green-50">
                    <div class="metric-value text-green-600" id="processId">-</div>
                    <div class="metric-label">Process ID</div>
                </div>
                <div class="metric bg-purple-50">
                    <div class="metric-value text-purple-600" id="uptime">-</div>
                    <div class="metric-label">Uptime</div>
                </div>
            </div>
        </div>
        
        <!-- File Management -->
        <div class="status-card">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">&#128193; File Management</h2>
            
            <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
                <div class="metric bg-yellow-50">
                    <div class="metric-value text-yellow-600" id="inProgressCount">0</div>
                    <div class="metric-label">In Progress</div>
                </div>
                <div class="metric bg-green-50">
                    <div class="metric-value text-green-600" id="completedCount">0</div>
                    <div class="metric-label">Completed</div>
                </div>
                <div class="metric bg-blue-50">
                    <div class="metric-value text-blue-600" id="totalSize">0 MB</div>
                    <div class="metric-label">Total Size</div>
                </div>
                <div class="metric bg-purple-50">
                    <div class="metric-value text-purple-600" id="totalLots">0</div>
                    <div class="metric-label">Total Lots</div>
                </div>
            </div>
            
            <div id="fileDetails" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                    <h3 class="font-semibold text-gray-700 mb-2">&#128203; In Progress Files</h3>
                    <div id="inProgressFiles" class="bg-gray-50 p-3 rounded-lg max-h-40 overflow-y-auto"></div>
                </div>
                <div>
                    <h3 class="font-semibold text-gray-700 mb-2">&#9989; Recent Completed Files</h3>
                    <div id="completedFiles" class="bg-gray-50 p-3 rounded-lg max-h-40 overflow-y-auto"></div>
                </div>
            </div>
        </div>
        
        <!-- Database Status -->
        <div class="status-card">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">&#128224; Database Status</h2>
            
            <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
                <div class="metric bg-blue-50">
                    <div class="metric-value text-blue-600" id="dbTotalFiles">0</div>
                    <div class="metric-label">Total Files</div>
                </div>
                <div class="metric bg-green-50">
                    <div class="metric-value text-green-600" id="dbCompletedFiles">0</div>
                    <div class="metric-label">Completed</div>
                </div>
                <div class="metric bg-yellow-50">
                    <div class="metric-value text-yellow-600" id="dbProcessingFiles">0</div>
                    <div class="metric-label">Processing</div>
                </div>
                <div class="metric bg-red-50">
                    <div class="metric-value text-red-600" id="dbErrorFiles">0</div>
                    <div class="metric-label">Errors</div>
                </div>
            </div>
            
            <div class="bg-gray-50 p-4 rounded-lg">
                <div class="flex justify-between items-center mb-2">
                    <span class="text-sm font-medium text-gray-700">Success Rate</span>
                    <span class="text-sm font-medium text-gray-700" id="successRate">0%</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" id="successRateBar" style="width: 0%"></div>
                </div>
            </div>
        </div>
        
        <!-- Performance Metrics -->
        <div class="status-card">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">&#128202; Performance Metrics</h2>
            
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div class="metric bg-indigo-50">
                    <div class="metric-value text-indigo-600" id="avgScrapingTime">0 min</div>
                    <div class="metric-label">Avg Scraping Time</div>
                </div>
                <div class="metric bg-emerald-50">
                    <div class="metric-value text-emerald-600" id="totalLotsScraped">0</div>
                    <div class="metric-label">Total Lots Scraped</div>
                </div>
                <div class="metric bg-rose-50">
                    <div class="metric-value text-rose-600" id="errorRate">0%</div>
                    <div class="metric-label">Error Rate</div>
                </div>
            </div>
        </div>
        
        <!-- System Resources -->
        <div class="status-card">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">&#128187; System Resources</h2>
            
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                    <h3 class="font-semibold text-gray-700 mb-2">Disk Space</h3>
                    <div class="bg-gray-50 p-4 rounded-lg">
                        <div class="flex justify-between items-center mb-2">
                            <span class="text-sm font-medium text-gray-700">Free Space</span>
                            <span class="text-sm font-medium text-gray-700" id="diskSpace">0 GB</span>
                        </div>
                        <div class="progress-bar">
                            <div class="progress-fill bg-green-500" id="diskBar" style="width: 80%"></div>
                        </div>
                    </div>
                </div>
                <div>
                    <h3 class="font-semibold text-gray-700 mb-2">Memory Usage</h3>
                    <div class="bg-gray-50 p-4 rounded-lg">
                        <div class="flex justify-between items-center mb-2">
                            <span class="text-sm font-medium text-gray-700">Available Memory</span>
                            <span class="text-sm font-medium text-gray-700" id="memoryUsage">0 GB</span>
                        </div>
                        <div class="progress-bar">
                            <div class="progress-fill bg-blue-500" id="memoryBar" style="width: 60%"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="text-center mt-6">
            <a href="dashboard.cfm" class="text-blue-600 hover:text-blue-800 underline">&#8592; Back to Dashboard</a>
        </div>
    </div>

    <script>
        function refreshStatus() {
            fetch('?action=data')
                .then(response => response.json())
                .then(data => {
                    updateStatusDisplay(data);
                })
                .catch(error => {
                    console.error('Error fetching status:', error);
                });
        }
        
        function updateStatusDisplay(data) {
            // Update scraper status
            const scraperState = document.getElementById('scraperState');
            const processId = document.getElementById('processId');
            const uptime = document.getElementById('uptime');
            
            if (data.scraper.isRunning) {
                scraperState.innerHTML = '<span class="status-indicator status-running"></span>Running';
                processId.textContent = data.scraper.processId || 'N/A';
                uptime.textContent = 'Active';
            } else {
                scraperState.innerHTML = '<span class="status-indicator status-stopped"></span>Stopped';
                processId.textContent = '-';
                uptime.textContent = '-';
            }
            
            // Update file management
            document.getElementById('inProgressCount').textContent = data.files.inProgress.length;
            document.getElementById('completedCount').textContent = data.files.completed.length;
            document.getElementById('totalSize').textContent = formatBytes(data.files.totalSize);
            
            let totalLots = 0;
            data.files.inProgress.forEach(file => {
                totalLots += file.lineCount || 0;
            });
            document.getElementById('totalLots').textContent = totalLots;
            
            // Update file lists
            updateFileList('inProgressFiles', data.files.inProgress, 'in-progress');
            updateFileList('completedFiles', data.files.completed.slice(0, 5), 'completed');
            
            // Update database status
            document.getElementById('dbTotalFiles').textContent = data.database.totalFiles;
            document.getElementById('dbCompletedFiles').textContent = data.database.completedFiles;
            document.getElementById('dbProcessingFiles').textContent = data.database.processingFiles;
            document.getElementById('dbErrorFiles').textContent = data.database.errorFiles;
            
            const successRate = data.performance.successRate;
            document.getElementById('successRate').textContent = successRate + '%';
            document.getElementById('successRateBar').style.width = successRate + '%';
            
            // Update performance metrics
            document.getElementById('avgScrapingTime').textContent = data.performance.averageScrapingTime + ' min';
            document.getElementById('totalLotsScraped').textContent = data.performance.totalLotsScraped;
            
            const errorRate = data.database.totalFiles > 0 ? 
                ((data.database.errorFiles / data.database.totalFiles) * 100).toFixed(1) : 0;
            document.getElementById('errorRate').textContent = errorRate + '%';
            
            // Update system resources
            if (data.system.diskSpace) {
                document.getElementById('diskSpace').textContent = data.system.diskSpace + ' GB';
            }
            if (data.system.memoryUsage) {
                document.getElementById('memoryUsage').textContent = data.system.memoryUsage + ' GB';
            }
        }
        
        function updateFileList(elementId, files, type) {
            const element = document.getElementById(elementId);
            if (files.length === 0) {
                element.innerHTML = '<p class="text-gray-500 text-sm">No files</p>';
                return;
            }
            
            let html = '';
            files.forEach(file => {
                const statusClass = type === 'in-progress' ? 'text-yellow-600' : 'text-green-600';
                html += `<div class="text-sm ${statusClass} mb-1">${file.name} (${file.size} KB)</div>`;
            });
            element.innerHTML = html;
        }
        
        function formatBytes(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        // Auto-refresh every 30 seconds
        setInterval(refreshStatus, 30000);
        
        // Initial load
        refreshStatus();
    </script>
</body>
</html> 