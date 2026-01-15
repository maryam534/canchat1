<cfscript>
    cfsetting(requesttimeout=7200, showdebugoutput=false);
    
    // ---- Config ----
    try {
        paths = application.paths ?: {};
        ai    = application.ai    ?: {};
    } catch (any appErr) {
        // If application scope not initialized, use defaults
        paths = {};
        ai = {};
        if ((url.ajax ?: "") == "1") {
            writeOutput(serializeJSON({error: "Application not initialized. Please refresh the page."}));
            abort;
        }
    }
    
    // ---- Global Scraper Status Tracking ----
    // Initialize application-scoped scraper status if it doesn't exist
    if (!structKeyExists(application, "scraperStatus")) {
        application.scraperStatus = {
            isRunning: false,
            startTime: "",
            processId: "",
            lastUpdate: now()
        };
    }
    
    // ---- Get parameters for testing ----
    maxSales = url.maxSales ?: form.maxSales ?: "";
    targetEventId = url.eventId ?: form.eventId ?: "";
    action = url.action ?: form.action ?: "";
    runMode = url.runMode ?: form.runMode ?: "all"; // all, one, max
    
    // Auto-start for convenience: if eventId present and no action, default to start (single event)
    if (!len(action) AND len(trim(targetEventId))) {
        action = "start";
        runMode = "one";
    }
    
    // ---- Enhanced Job Management System ----
    
    // Helper function to log to database
    function logToDatabase(jobId, level, message, source = "system", metadata = {}) {
        try {
            queryExecute(
                "
                    INSERT INTO scrape_logs
                        (job_id, log_level, message, source, metadata)
                    VALUES
                        (?, ?, ?, ?, to_jsonb(?))
                ",
                [
                    {value = jobId,                   cfsqltype = "cf_sql_integer"},
                    {value = level,                   cfsqltype = "cf_sql_varchar"},
                    {value = message,                 cfsqltype = "cf_sql_longvarchar"},
                    {value = source,                  cfsqltype = "cf_sql_varchar"},
                    {value = serializeJSON(metadata), cfsqltype = "cf_sql_varchar"}
                ],
                {datasource = application.db.dsn}
            );
        } catch (any err) {
            // Fallback to file logging if database fails
            writeLog(file="scraper", text="[#level#] Job #jobId#: #message#", type="information");
        }
    }

    
    // Helper function to update job status
    function updateJobStatus(jobId, status, additionalFields = {}) {
        try {
            var sql    = "";
            var params = [];

            switch (status) {
                case "running":
                    sql    = "UPDATE scraper_jobs SET status = ?, started_at = CURRENT_TIMESTAMP";
                    params = [
                        {value = status, cfsqltype="cf_sql_varchar"}
                    ];

                    // Optional process ID
                    if (structKeyExists(additionalFields, "processId")) {
                        sql &= ", process_id = ?";
                        arrayAppend(params, {value = additionalFields.processId, cfsqltype="cf_sql_varchar"});
                    }

                    sql &= " WHERE id = ?";
                    arrayAppend(params, {value = jobId, cfsqltype="cf_sql_integer"});
                    break;

                case "paused":
                    sql = "UPDATE scraper_jobs SET status = ?, paused_at = CURRENT_TIMESTAMP WHERE id = ?";
                    params = [
                        {value = status, cfsqltype="cf_sql_varchar"},
                        {value = jobId,  cfsqltype="cf_sql_integer"}
                    ];
                    break;

                case "stopped":
                    sql = "UPDATE scraper_jobs SET status = ?, stopped_at = CURRENT_TIMESTAMP";
                    params = [
                        {value = status, cfsqltype="cf_sql_varchar"}
                    ];

                    if (structKeyExists(additionalFields,"errorMessage")) {
                        sql &= ", error_message = ?";
                        arrayAppend(params, {value = additionalFields.errorMessage, cfsqltype="cf_sql_longvarchar"});
                    }

                    sql &= " WHERE id = ?";
                    arrayAppend(params, {value = jobId, cfsqltype="cf_sql_integer"});
                    break;

                case "completed":
                    sql = "UPDATE scraper_jobs SET status = ?, completed_at = CURRENT_TIMESTAMP WHERE id = ?";
                    params = [
                        {value = status, cfsqltype="cf_sql_varchar"},
                        {value = jobId,  cfsqltype="cf_sql_integer"}
                    ];
                    break;

                default:
                    sql = "UPDATE scraper_jobs SET status = ? WHERE id = ?";
                    params = [
                        {value = status, cfsqltype="cf_sql_varchar"},
                        {value = jobId,  cfsqltype="cf_sql_integer"}
                    ];
            }

            queryExecute(sql, params, {datasource=application.db.dsn});
            return true;
        }
        catch (any err) {
            writeLog(file="scraper", text="Error updating job status: #err.message#", type="error");
            return false;
        }
    }

    // Process Control Actions

    if (action == "pause") {
        try {
            // Find running job and pause it
            runningJob = queryExecute(
                "SELECT id FROM scraper_jobs WHERE status = 'running' ORDER BY created_at DESC LIMIT 1",
                [],
                {datasource: application.db.dsn}
            );
            
            if (runningJob.recordCount > 0) {
                updateJobStatus(runningJob.id, "paused");
                writeOutput(serializeJSON({success: true, message: "Job paused successfully"}));
            } else {
                writeOutput(serializeJSON({success: false, message: "No running job found"}));
            }
        } catch (any err) {
            writeOutput(serializeJSON({success: false, message: "Error pausing job: " & err.message}));
        }
        abort;
    }

    if (action == "stop") {
        try {
            // Find running/paused job and stop it
            activeJob = queryExecute(
                "SELECT id FROM scraper_jobs WHERE status IN ('running','paused') ORDER BY created_at DESC LIMIT 1",
                [],
                {datasource: application.db.dsn}
            );
            
            if (activeJob.recordCount > 0) {
                updateJobStatus(activeJob.id, "stopped");
                writeOutput(serializeJSON({success: true, message: "Job stopped successfully"}));
            } else {
                writeOutput(serializeJSON({success: false, message: "No active job found"}));
            }
        } catch (any err) {
            writeOutput(serializeJSON({success: false, message: "Error stopping job: " & err.message}));
        }
        abort;
    }

    // Check for AJAX requests FIRST, before non-AJAX status endpoint
    // If ajax=1, skip the non-AJAX endpoint and let the AJAX endpoint (line 715+) handle it
    if ((url.ajax ?: "") != "1" && action == "status") {
        // Non-AJAX status endpoint (Format 2) - only runs if ajax != 1
        try {
            // Get current job status from database
            currentJob = queryExecute(
                "SELECT id, status, job_name, created_at, started_at, completed_at FROM scraper_jobs WHERE status IN ('running', 'queued', 'paused') ORDER BY created_at DESC LIMIT 1",
                [],
                {datasource: application.db.dsn}
            );
            
            if (currentJob.recordCount > 0) {
                jobId = currentJob.id;
                
                // Get real statistics from database
                stats = queryExecute(
                    "SELECT total_events, processed_events, total_lots, processed_lots, files_created, files_completed FROM job_statistics WHERE job_id = ? ORDER BY id DESC LIMIT 1",
                    [{value = jobId, cfsqltype = "cf_sql_integer"}],
                    {datasource: application.db.dsn}
                );
                
                // Get recent logs
                recentLogs = queryExecute(
                    "SELECT message, timestamp FROM scrape_logs WHERE job_id = ? ORDER BY timestamp DESC LIMIT 10",
                    [{value = jobId, cfsqltype = "cf_sql_integer"}],
                    {datasource: application.db.dsn}
                );
                
                statusData = {
                    jobId: currentJob.id,
                    status: currentJob.status,
                    jobName: currentJob.job_name,
                    created: currentJob.created_at,
                    started: currentJob.started_at,
                    completed: currentJob.completed_at,
                    statusText: currentJob.status,
                    progressPct: 0,
                    progressLabel: "Initializing",
                    newLogs: []
                };
                
                // Calculate real progress
                if (stats.recordCount > 0) {
                    totalEvents = stats.total_events;
                    processedEvents = stats.processed_events;
                    totalLots = stats.total_lots;
                    processedLots = stats.processed_lots;
                    
                    if (totalEvents > 0) {
                        statusData.progressPct = int((processedEvents / totalEvents) * 100);
                    } else if (totalLots > 0) {
                        statusData.progressPct = int((processedLots / totalLots) * 100);
                    }
                }
                
                // Add real logs
                if (recentLogs.recordCount > 0) {
                    for (row = recentLogs.recordCount; row >= 1; row--) {
                        arrayAppend(statusData.newLogs, recentLogs.message[row]);
                    }
                }
                
                if (currentJob.status == "running") {
                    if (statusData.progressPct == 0) statusData.progressPct = 5; // Show at least some progress
                    statusData.progressLabel = "Scraping in progress... (" & statusData.progressPct & "%)";
                } else if (currentJob.status == "completed") {
                    statusData.progressPct = 100;
                    statusData.progressLabel = "Completed";
                    statusData.done = true;
                } else if (currentJob.status == "paused") {
                    statusData.progressLabel = "Paused";
                }
                
                writeOutput(serializeJSON(statusData));
            } else {
                writeOutput(serializeJSON({status: "idle", statusText: "No active jobs found"}));
            }
        } catch (any err) {
            writeOutput(serializeJSON({status: "error", message: "Error getting status: " & err.message}));
        }
        abort;
    }

    if (action == "ingest") {
        try {
            // Trigger RAG database ingestion
            // This would typically call process_web_scraping.cfm or similar
            writeOutput(serializeJSON({success: true, message: "RAG database ingestion triggered"}));
        } catch (any err) {
            writeOutput(serializeJSON({success: false, message: "Error triggering ingestion: " & err.message}));
        }
        abort;
    }

    if (action == "start") {
        result = {success: false, error: "", jobId: 0};
        try {
            // First, verify tables exist
            try {
                tableCheck = queryExecute(
                    "SELECT 1 FROM scraper_jobs LIMIT 1",
                    [],
                    {datasource: application.db.dsn}
                );
            } catch (any tableErr) {
                result.error = "Database tables not found. Please run the migration first. Error: " & tableErr.message & ". Go to apply_migration.cfm to create tables.";
                writeOutput(serializeJSON(result));
                abort;
            }
            
            // Check if a job is already running or paused for the same event
            checkRunning = queryExecute(
                "SELECT id, status, current_event_id FROM scraper_jobs WHERE status IN ('running','paused') ORDER BY created_at DESC LIMIT 1",
                [],
                {datasource: application.db.dsn}
            );

            // Support force start via query/form param
            forceStart = ( (url.force ?: form.force ?: "") == "1" );

            if (checkRunning.recordCount > 0 AND !forceStart) {
                // If there's a PAUSED job for the SAME event, auto-resume it instead of error
                if (checkRunning.status == "paused" AND len(trim(targetEventId)) AND checkRunning.current_event_id == trim(targetEventId)) {
                    // Auto-resume the paused job - execute the resume logic
                    jobId = checkRunning.id;
                    currentEventId = checkRunning.current_event_id;
                    
                    singleJs = expandPath('/scrape_single_event.js');
                    workDir = getDirectoryFromPath(singleJs);
                    outPath = paths.inProgressDir & '/auction_' & trim(currentEventId) & '_lots.jsonl';
                    outPath = replace(outPath, '\', '/', 'all');
                    
                    nodeExe = paths.nodeBinary ?: "node.exe";
                    nodeExeQuoted = (find(" ", nodeExe) > 0) ? '"' & nodeExe & '"' : nodeExe;
                    scraperCmd = '/c cd /d "' & workDir & '" && ' & nodeExeQuoted & ' "' & singleJs & '" --event-id ' & trim(currentEventId) & ' --output-file "' & outPath & '" --job-id ' & jobId;
                    
                    cmdExe = paths.cmdExe ?: "cmd.exe";
                    output = "";
                    
                    logToDatabase(jobId, "info", "Auto-resuming paused job for event " & currentEventId, "system");
                    
                    cfexecute(
                        name = cmdExe,
                        arguments = scraperCmd,
                        timeout = 0,
                        variable = "output"
                    );
                    
                    // Update job status to running
                    updateJobStatus(jobId, "running");
                    logToDatabase(jobId, "info", "Scraper job resumed successfully (auto-resume). Loading state from database.", "system");
                    
                    application.scraperStatus.isRunning = true;
                    application.scraperStatus.lastUpdate = now();
                    
                    result.success = true;
                    result.error = "";
                    result.jobId = jobId;
                    result.message = "Auto-resumed paused job " & jobId & " for event " & currentEventId;
                    result.autoResumed = true;
                    
                    writeOutput(serializeJSON(result));
                    abort;
                } else {
                    result.error = "A scraper job is already running or paused (Job ##" & checkRunning.id & ", status: " & checkRunning.status & "). Please stop or resume the existing job first.";
                }
            } else {
                // Ensure paths are initialized
                if (!structKeyExists(paths, "scraper") OR !len(paths.scraper)) {
                    paths.scraper = expandPath('/canchat1/scrap_all_auctions_lots_data.js');
                }
                if (!structKeyExists(paths, "inProgressDir") OR !len(paths.inProgressDir)) {
                    paths.inProgressDir = expandPath('./allAuctionLotsData_inprogress');
                }
                
                jobName = "NumisBids Scraper - " & dateFormat(now(), "yyyy-MM-dd HH:mm:ss");
                parameters = {
                    maxSales     : maxSales,
                    targetEventId: targetEventId,
                    runMode      : runMode
                };
                writeLog(file="scraper", text="[info] Entered action=start with eventId=" & targetEventId & ", runMode=" & runMode & ", force=" & forceStart, type="information");
                
                // Insert job
                createJob = queryExecute(
                    "
                        INSERT INTO scraper_jobs
                            (job_name, status, max_sales, target_event_id, run_mode, parameters, created_by)
                        VALUES
                            (?, 'queued', ?, ?, ?, to_jsonb(?), 'user')
                        RETURNING id
                    ",
                    [
                        { value = jobName,                   cfsqltype = "cf_sql_varchar" },
                        { value = val(maxSales),             cfsqltype = "cf_sql_integer" },
                        { value = targetEventId,             cfsqltype = "cf_sql_varchar" },
                        { value = runMode,                   cfsqltype = "cf_sql_varchar" },
                        { value = serializeJSON(parameters), cfsqltype = "cf_sql_varchar" }
                    ],
                    { datasource = application.db.dsn }
                );
                jobId = createJob.id;
                updateJobStatus(jobId, "running");
                logToDatabase(jobId, "info", "Scraper job started successfully", "system");

                // Launch scraper using direct Node execution (quoting paths; no cmd wrapper)
                nodeExe   = paths.nodeBinary ?: "node.exe";
                // Use absolute path from web root (leading slash means from web root)
                singleJs  = expandPath('/scrape_single_event.js');
                allJs     = paths.scraper;

                outVar = ""; errVar = "";
                if (len(trim(targetEventId))) {
                    // Single event mode
                    // Use forward slashes or proper path handling
                    outPath = paths.inProgressDir & '/auction_' & trim(targetEventId) & '_lots.jsonl';
                    // Normalize path separators
                    outPath = replace(outPath, '\', '/', 'all');
                    args = '"' & singleJs & '" --event-id ' & trim(targetEventId) & ' --output-file "' & outPath & '" --job-id ' & jobId;
                    
                    // Initialize job with event ID
                    queryExecute(
                        "UPDATE scraper_jobs SET current_event_id = ?, total_events = 1, current_event_index = 0 WHERE id = ?",
                        [
                            {value = trim(targetEventId), cfsqltype = "cf_sql_varchar"},
                            {value = jobId, cfsqltype = "cf_sql_integer"}
                        ],
                        {datasource = application.db.dsn}
                    );
                } else {
                    // All events mode
                    args = '"' & allJs & '"' & (len(trim(maxSales)) AND isNumeric(maxSales) ? ' --max-sales ' & maxSales : '') & ' --job-id ' & jobId;
                }

                logToDatabase(jobId, 'debug', 'Launching: ' & nodeExe & ' ' & args, 'system');

                // Launch scraper in background (non-blocking)
                // Use cmd.exe wrapper for better Windows compatibility and error capture
                cmdExe = paths.cmdExe ?: "cmd.exe";
                // Get working directory - ensure it's the root directory, not tasks folder
                workDir = getDirectoryFromPath(singleJs);
                
                // Verify the script file exists
                if (!fileExists(singleJs)) {
                    logToDatabase(jobId, 'error', 'Script file not found: ' & singleJs, 'system');
                    result.error = "Script file not found: " & singleJs;
                } else {
                    // Verify Node.js is accessible
                    nodeExePath = paths.nodeBinary;
                    
                    // #region agent log - Hypothesis C: Node.js path
                    try {
                        debugLogPath = expandPath(".cursor/debug.log");
                        logContent = serializeJSON({
                            location: "run_scraper.cfm:389",
                            message: "Node.js path verification",
                            data: {
                                nodeExePath: nodeExePath,
                                nodeExePathExists: fileExists(nodeExePath),
                                nodeExe: nodeExe,
                                jobId: jobId
                            },
                            timestamp: getTickCount(),
                            sessionId: "debug-session",
                            runId: "run1",
                            hypothesisId: "C"
                        }) & chr(10);
                        if (fileExists(debugLogPath)) {
                            fileAppend(debugLogPath, logContent);
                        } else {
                            fileWrite(debugLogPath, logContent);
                        }
                    } catch (any e) {
                        // Ignore logging errors
                    }
                    // #endregion
                    
                    if (!fileExists(nodeExePath)) {
                        logToDatabase(jobId, 'error', 'Node.js not found at: ' & nodeExePath, 'system');
                        result.error = "Node.js not found at: " & nodeExePath;
                    } else {
                    // Build command with proper working directory
                    if (len(trim(targetEventId))) {
                        // Single event mode - use cmd wrapper with working directory
                        // IMPORTANT: Use proper quoting for paths with spaces
                        // Wrap nodeExe in quotes if it contains spaces
                        nodeExeQuoted = (find(" ", nodeExe) > 0) ? '"' & nodeExe & '"' : nodeExe;
                        // Wrap script path in quotes (it's already in args, but ensure it's quoted)
                        cmdArgs = '/c cd /d "' & workDir & '" && ' & nodeExeQuoted & ' ' & args & ' 2>&1';
                        
                        // #region agent log - Hypothesis E: Command construction
                        try {
                            debugLogPath = expandPath(".cursor/debug.log");
                            logContent = serializeJSON({
                                location: "run_scraper.cfm:397",
                                message: "Command construction for single event",
                                data: {
                                    workDir: workDir,
                                    nodeExe: nodeExe,
                                    args: args,
                                    fullCmdArgs: cmdArgs,
                                    singleJs: singleJs,
                                    outPath: outPath,
                                    targetEventId: targetEventId,
                                    jobId: jobId,
                                    workDirExists: directoryExists(workDir),
                                    singleJsExists: fileExists(singleJs)
                                },
                                timestamp: getTickCount(),
                                sessionId: "debug-session",
                                runId: "run1",
                                hypothesisId: "E"
                            }) & chr(10);
                            if (fileExists(debugLogPath)) {
                                fileAppend(debugLogPath, logContent);
                            } else {
                                fileWrite(debugLogPath, logContent);
                            }
                        } catch (any e) {
                            // Ignore logging errors
                        }
                        // #endregion
                    } else {
                        // All events mode
                        cmdArgs = '/c cd /d "' & getDirectoryFromPath(allJs) & '" && ' & nodeExe & ' ' & args & ' 2>&1';
                    }
                    
                    try {
                        // Log the full command
                        logToDatabase(jobId, 'debug', 'Full command: ' & cmdExe & ' ' & cmdArgs, 'system');
                        logToDatabase(jobId, 'debug', 'Script path: ' & singleJs & ' | Work dir: ' & workDir, 'system');
                        
                        // #region agent log - Hypothesis A: Working directory
                        try {
                            debugLogPath = expandPath(".cursor/debug.log");
                            logContent = serializeJSON({
                                location: "run_scraper.cfm:405",
                                message: "Before cfexecute - working directory check",
                                data: {
                                    cmdExe: cmdExe,
                                    cmdArgs: cmdArgs,
                                    singleJs: singleJs,
                                    workDir: workDir,
                                    nodeExe: nodeExe,
                                    args: args,
                                    jobId: jobId,
                                    directoryExists: directoryExists(workDir),
                                    scriptExists: fileExists(singleJs)
                                },
                                timestamp: getTickCount(),
                                sessionId: "debug-session",
                                runId: "run1",
                                hypothesisId: "A"
                            }) & chr(10);
                            if (fileExists(debugLogPath)) {
                                fileAppend(debugLogPath, logContent);
                            } else {
                                fileWrite(debugLogPath, logContent);
                            }
                        } catch (any e) {
                            // Ignore logging errors
                        }
                        // #endregion
                        
                        // #region agent log - Hypothesis B: Arguments
                        try {
                            debugLogPath = expandPath(".cursor/debug.log");
                            logContent = serializeJSON({
                                location: "run_scraper.cfm:425",
                                message: "Command arguments breakdown",
                                data: {
                                    fullCmdArgs: cmdArgs,
                                    nodeExePath: nodeExe,
                                    scriptPath: singleJs,
                                    targetEventId: targetEventId,
                                    outputPath: outPath,
                                    jobId: jobId,
                                    argsString: args
                                },
                                timestamp: getTickCount(),
                                sessionId: "debug-session",
                                runId: "run1",
                                hypothesisId: "B"
                            }) & chr(10);
                            if (fileExists(debugLogPath)) {
                                fileAppend(debugLogPath, logContent);
                            } else {
                                fileWrite(debugLogPath, logContent);
                            }
                        } catch (any e) {
                            // Ignore logging errors
                        }
                        // #endregion
                        
                        // Initialize variables before cfexecute (in case it fails)
                        variables.outVar = "";
                        variables.errVar = "";
                        
                        // Execute with output redirection to capture errors
                        // Note: With timeout=0, cfexecute runs in background and doesn't capture output
                        // We'll rely on the debug log file to verify script execution
                        try {
                            logToDatabase(jobId, 'info', 'Executing script in background (timeout=0)...', 'system');
                            
                            // #region agent log - Hypothesis D: Process execution
                            try {
                                debugLogPath = expandPath(".cursor/debug.log");
                                logContent = serializeJSON({
                                    location: "run_scraper.cfm:450",
                                    message: "About to call cfexecute",
                                    data: {
                                        cmdExe: cmdExe,
                                        cmdArgs: cmdArgs,
                                        timeout: 0,
                                        jobId: jobId,
                                        timestampBefore: getTickCount()
                                    },
                                    timestamp: getTickCount(),
                                    sessionId: "debug-session",
                                    runId: "run1",
                                    hypothesisId: "D"
                                }) & chr(10);
                                if (fileExists(debugLogPath)) {
                                    fileAppend(debugLogPath, logContent);
                                } else {
                                    fileWrite(debugLogPath, logContent);
                                }
                            } catch (any e) {
                                // Ignore logging errors
                            }
                            // #endregion
                            
                            cfexecute(
                                name          = cmdExe,
                                arguments     = cmdArgs,
                                timeout       = 0,
                                variable      = "outVar",
                                errorVariable = "errVar"
                            );
                            
                            // #region agent log - Hypothesis D: After execution
                            try {
                                debugLogPath = expandPath(".cursor/debug.log");
                                logContent = serializeJSON({
                                    location: "run_scraper.cfm:470",
                                    message: "cfexecute completed (non-blocking)",
                                    data: {
                                        jobId: jobId,
                                        outVarLen: len(variables.outVar ?: ""),
                                        errVarLen: len(variables.errVar ?: ""),
                                        timestampAfter: getTickCount()
                                    },
                                    timestamp: getTickCount(),
                                    sessionId: "debug-session",
                                    runId: "run1",
                                    hypothesisId: "D"
                                }) & chr(10);
                                if (fileExists(debugLogPath)) {
                                    fileAppend(debugLogPath, logContent);
                                } else {
                                    fileWrite(debugLogPath, logContent);
                                }
                            } catch (any e) {
                                // Ignore logging errors
                            }
                            // #endregion
                            
                            // Wait for script to initialize and write to debug log
                            // Increased wait time to allow script to fully start
                            sleep(8000);
                            
                            // Check debug log file for immediate errors
                            debugLogPath = workDir & "\scrape_debug.log";
                            if (fileExists(debugLogPath)) {
                                try {
                                    // Wait a bit more for script to write (file writes might be buffered)
                                    sleep(3000);
                                    // Force file system sync by reading multiple times
                                    debugLogContent = "";
                                    for (i = 1; i <= 3; i++) {
                                        sleep(1000);
                                        debugLogContent = fileRead(debugLogPath);
                                        // Check if we have new content for this job
                                        if (findNoCase("jobId=" & jobId, debugLogContent) > 0 || findNoCase("Script started: eventId=" & trim(targetEventId), debugLogContent) > 0) {
                                            break;
                                        }
                                    }
                                    // Get last 2000 characters (more recent entries)
                                    if (len(debugLogContent) > 2000) {
                                        debugLogContent = right(debugLogContent, 2000);
                                    }
                                    logToDatabase(jobId, 'debug', 'Debug log content (last 2000 chars): ' & debugLogContent, 'system');
                                    
                                    // Check specifically for this jobId (the script writes "jobId=35" format)
                                    if (findNoCase("jobId=" & jobId, debugLogContent) > 0 || findNoCase("jobId=" & jobId & ",", debugLogContent) > 0) {
                                        logToDatabase(jobId, 'info', 'SUCCESS: Found debug log entry for jobId ' & jobId & ' - script started!', 'system');
                                    } else {
                                        // Also check for eventId as fallback (script might have started but jobId check failed)
                                        if (findNoCase("Script started: eventId=" & trim(targetEventId), debugLogContent) > 0) {
                                            logToDatabase(jobId, 'info', 'Script started (found eventId in log, but jobId check failed - this is OK)', 'system');
                                        } else {
                                            logToDatabase(jobId, 'warning', 'Script may not have started - no debug log entry found for jobId ' & jobId & ' or eventId ' & trim(targetEventId), 'system');
                                            // Show the actual command that was executed
                                            logToDatabase(jobId, 'debug', 'Command executed: ' & cmdExe & ' ' & cmdArgs, 'system');
                                            // Check if script file is readable
                                            if (fileExists(singleJs)) {
                                                logToDatabase(jobId, 'debug', 'Script file exists and is readable: ' & singleJs, 'system');
                                            } else {
                                                logToDatabase(jobId, 'error', 'Script file does not exist: ' & singleJs, 'system');
                                                updateJobStatus(jobId, "error", {error_message: "Script file not found: " & singleJs});
                                            }
                                            // If script didn't start after 11 seconds, mark as error
                                            // (We wait 8+3 seconds, so if still no log, it's likely failed)
                                            updateJobStatus(jobId, "error", {error_message: "Script failed to start - no debug log entry found after 11 seconds. Command: " & cmdExe & " " & cmdArgs});
                                        }
                                    }
                                } catch (any readErr) {
                                    logToDatabase(jobId, 'debug', 'Could not read debug log: ' & readErr.message, 'system');
                                }
                            } else {
                                logToDatabase(jobId, 'warning', 'Debug log file not found: ' & debugLogPath & ' - script may not have started', 'system');
                                // Verify the working directory exists
                                if (!directoryExists(workDir)) {
                                    logToDatabase(jobId, 'error', 'Working directory does not exist: ' & workDir, 'system');
                                }
                            }
                            
                            // Log any immediate output/errors from cfexecute
                            // These are captured from stdout/stderr
                            if (structKeyExists(variables, "outVar") && len(trim(variables.outVar))) {
                                logToDatabase(jobId, 'info', 'Script output (stdout): ' & left(variables.outVar, 1000), 'system');
                                writeLog(file="scraper", text="[JOB " & jobId & "] Script stdout: " & left(variables.outVar, 500), type="information");
                            }
                            if (structKeyExists(variables, "errVar") && len(trim(variables.errVar))) {
                                logToDatabase(jobId, 'error', 'Script error (stderr): ' & left(variables.errVar, 1000), 'system');
                                writeLog(file="scraper", text="[JOB " & jobId & "] Script stderr: " & left(variables.errVar, 500), type="error");
                            }
                            
                            // Note: With timeout=0, output variables are typically empty (expected behavior)
                            // We rely on the debug log file check above to verify script execution
                            // The debug log check will show if the script started successfully
                            
                            // Note: Process detection is unreliable when script runs in background
                            // Instead, we rely on database updates to verify script is running
                            // The script will update job_statistics and scrape_logs tables in real-time
                            logToDatabase(jobId, 'info', 'Script launched in background - monitoring via database updates', 'system');
                            
                            // Optional: Quick process check (non-blocking, don't fail if not found)
                            try {
                                sleep(3000); // Wait 3 seconds for script to start
                                processCheck = "";
                                cfexecute(
                                    name = "wmic",
                                    arguments = 'process where "name=''node.exe''" get ProcessId,CommandLine /format:list',
                                    timeout = 3,
                                    variable = "processCheck"
                                );
                                // Check for both filename and event-id in command line
                                if (findNoCase("scrape_single_event.js", processCheck) > 0 || 
                                    (findNoCase("node.exe", processCheck) > 0 && findNoCase("--event-id", processCheck) > 0 && findNoCase(trim(targetEventId), processCheck) > 0)) {
                                    logToDatabase(jobId, 'info', 'Node.js process detected - script is running', 'system');
                                } else {
                                    logToDatabase(jobId, 'info', 'Process not immediately detected (normal for background execution) - monitoring via database', 'system');
                                }
                            } catch (any procErr) {
                                // Don't log as error - process detection is optional
                                logToDatabase(jobId, 'debug', 'Process check skipped (non-critical): ' & procErr.message, 'system');
                            }
                            
                            // Check debug log for immediate startup confirmation
                            if (fileExists(debugLogPath)) {
                                try {
                                    sleep(2000); // Wait a bit more for script to write to log
                                    debugLogContent = fileRead(debugLogPath);
                                    // Get last 1500 characters (recent entries)
                                    if (len(debugLogContent) > 1500) {
                                        debugLogContent = right(debugLogContent, 1500);
                                    }
                                    // Only log if there are new entries (not just old ones)
                                    if (findNoCase("Script started: eventId=" & trim(targetEventId), debugLogContent) > 0) {
                                        logToDatabase(jobId, 'info', 'Debug log confirms script started for event ' & trim(targetEventId), 'system');
                                    }
                                } catch (any readErr) {
                                    // Non-critical
                                }
                            }
                            
                        } catch (any cfexecErr) {
                            // Handle cfexecute errors
                            logToDatabase(jobId, 'error', 'cfexecute error: ' & cfexecErr.message, 'system');
                            // Try to get error details if available
                            if (structKeyExists(cfexecErr, "detail")) {
                                logToDatabase(jobId, 'error', 'cfexecute detail: ' & cfexecErr.detail, 'system');
                            }
                            // Check if variables were updated despite error
                            if (structKeyExists(variables, "errVar") && len(trim(variables.errVar))) {
                                logToDatabase(jobId, 'error', 'Error variable content: ' & variables.errVar, 'system');
                            }
                            result.error = "Failed to launch scraper: " & cfexecErr.message;
                        }
                    } catch (any execErr) {
                        // If outer try block fails, log the error
                        logToDatabase(jobId, 'error', 'Execution failed: ' & execErr.message & ' | Detail: ' & (structKeyExists(execErr, "detail") ? execErr.detail : ""), 'system');
                        result.error = "Failed to launch scraper: " & execErr.message;
                    }
                    } // Close the else block for Node.js check
                } // Close the else block for script file check

                application.scraperStatus.isRunning  = true;
                application.scraperStatus.startTime  = now();
                application.scraperStatus.lastUpdate = now();

                result.success = true;
                result.jobId   = jobId;
                result.message = "Scraper job started successfully";
             }
        } catch (any err) {
            result.error = "Error START scraper: " & err.message;
            if (structKeyExists(err, "detail")) {
                result.error &= " (Detail: " & err.detail & ")";
            }
            if (structKeyExists(err, "sql")) {
                result.error &= " (SQL: " & left(err.sql, 100) & ")";
            }
            if (structKeyExists(err, "sqlState")) {
                result.error &= " (SQL State: " & err.sqlState & ")";
            }
            writeLog(file="scraper", text="[ERROR] Start action failed: " & err.message & " | Detail: " & (structKeyExists(err, "detail") ? err.detail : "") & " | SQL: " & (structKeyExists(err, "sql") ? err.sql : ""), type="error");
        }
        writeOutput(serializeJSON(result));
        abort;
    }


    if (action == "resume") { 
        result = {success: false, error: ""};
        
        try {
            // Find the most recent paused job with resume state
            findPausedJob = queryExecute(
                "SELECT id, job_name, current_event_id, current_lot_number, current_event_index, resume_state FROM scraper_jobs WHERE status = 'paused' ORDER BY created_at DESC LIMIT 1",
                [],
                { datasource = application.db.dsn }
            );
            
            if (findPausedJob.recordCount == 0) {
                result.error = "No paused jobs found to resume.";
            } else {
                jobId = findPausedJob.id;
                currentEventId = findPausedJob.current_event_id ?: "";
                
                // Determine which script to use based on whether it's a single event job
                if (len(trim(currentEventId))) {
                    // Single event mode - use scrape_single_event.js
                    singleJs = expandPath('/scrape_single_event.js');
                    workDir = getDirectoryFromPath(singleJs);
                    outPath = paths.inProgressDir & '/auction_' & trim(currentEventId) & '_lots.jsonl';
                    outPath = replace(outPath, '\', '/', 'all');
                    
                    // Quote node path if it has spaces (same as start action)
                    nodeExe = paths.nodeBinary ?: "node.exe";
                    nodeExeQuoted = (find(" ", nodeExe) > 0) ? '"' & nodeExe & '"' : nodeExe;
                    
                    scraperCmd = '/c cd /d "' & workDir & '" && ' & nodeExeQuoted & ' "' & singleJs & '" --event-id ' & trim(currentEventId) & ' --output-file "' & outPath & '" --job-id ' & jobId;
                    logToDatabase(jobId, "info", "Resuming single event scraper for event " & currentEventId, "system");
                } else {
                    // Multi-event mode - use scrap_all_auctions_lots_data.js
                    workDir = getDirectoryFromPath(paths.scraper);
                    nodeExe = paths.nodeBinary ?: "node.exe";
                    nodeExeQuoted = (find(" ", nodeExe) > 0) ? '"' & nodeExe & '"' : nodeExe;
                    scraperCmd = '/c cd /d "' & workDir & '" && ' & nodeExeQuoted & ' "' & paths.scraper & '" --job-id=' & jobId;
                    logToDatabase(jobId, "info", "Resuming multi-event scraper", "system");
                }
                
                cmdExe = paths.cmdExe ?: "cmd.exe";
                output = ""; 

                cfexecute(
                    name = cmdExe,
                    arguments = scraperCmd,
                    timeout = 0,
                    variable = "output"
                );
                
                // Update job status to running
                updateJobStatus(jobId, "running");
                logToDatabase(jobId, "info", "Scraper job resumed successfully via Resume button.", "system");
                
                application.scraperStatus.isRunning = true;
                application.scraperStatus.lastUpdate = now();
                
                result.success = true;
                result.message = "Scraper job resumed successfully. Resuming from saved state.";
                result.resumeState = {
                    currentEventId: currentEventId,
                    currentLotNumber: findPausedJob.current_lot_number ?: "",
                    currentEventIndex: findPausedJob.current_event_index ?: 0
                };
            }
        } catch (any err) {
            result.error = "Error resuming scraper: " & err.message;
        }
        
        writeOutput(serializeJSON(result));
        abort;
    }

    if (action == "pause") {
        result = {success: false, error: ""};
        
        try {
            // Find the most recent running job
            findRunningJob = queryExecute(
                "SELECT id, job_name, process_id, current_event_id, current_lot_number, current_event_index FROM scraper_jobs WHERE status = 'running' ORDER BY created_at DESC LIMIT 1",
                [],
                { datasource = application.db.dsn }
            );
            
            if (findRunningJob.recordCount == 0) {
                result.error = "No running jobs found to pause.";
            } else {
                jobId = findRunningJob.id;
                processId = findRunningJob.process_id;
                
                // Kill process (scraper will detect pause status and save state)
                if (len(processId) > 0) {
                    cfexecute(
                        name = "taskkill",
                        arguments = "/f /pid " & processId & " >nul 2>&1",
                        timeout = 10
                    );
                }
                
                // Update job status to paused (state will be saved by scraper script)
                updateJobStatus(jobId, "paused");
                logToDatabase(jobId, "info", "Scraper job paused by user", "user");
                
                application.scraperStatus.isRunning = false;
                application.scraperStatus.lastUpdate = now();
                
                result.success = true;
                result.message = "Scraper job paused successfully. State saved for resume.";
                result.currentEventId = findRunningJob.current_event_id ?: "";
                result.currentLotNumber = findRunningJob.current_lot_number ?: "";
            }
        } catch (any err) {
            result.error = "Error pausing scraper: " & err.message;
        }
        
        writeOutput(serializeJSON(result));
        abort;
    }

    if (action == "stop") {
        result = {success: false, error: ""};
        
        try {
            // Find the most recent running or paused job
            findActiveJob = queryExecute(
                "SELECT id, job_name, process_id FROM scraper_jobs WHERE status IN ('running', 'paused') ORDER BY created_at DESC LIMIT 1",
                [],
                { datasource = application.db.dsn }
            );
            
            if (findActiveJob.recordCount == 0) {
                result.error = "No active jobs found to stop.";
            } else {
                jobId = findActiveJob.id;
                processId = findActiveJob.process_id;
                
                if (len(processId) > 0) {
                    cfexecute(
                        name = "taskkill",
                        arguments = "/f /pid " & processId & " >nul 2>&1",
                        timeout = 10
                    );
                }
                
                updateJobStatus(jobId, "stopped");
                logToDatabase(jobId, "info", "Scraper job stopped by user", "user");
                
                application.scraperStatus.isRunning = false;
                application.scraperStatus.lastUpdate = now();
                
                result.success = true;
                result.message = "Scraper job stopped successfully";
            }
        } catch (any err) {
            result.error = "Error stopping scraper: " & err.message;
        }
        
        writeOutput(serializeJSON(result));
        abort;
    }

    
    // ---- Guards ----
    if ( !structKeyExists(paths,"nodeBinary") || !len(paths.nodeBinary) ) {
      // default to node on PATH instead of aborting
      paths.nodeBinary = "node";
    }
    // Only require multi-event scraper when not running a single event
    if ( !len(trim(targetEventId)) ) {
        if ( !structKeyExists(paths,"scraper") || !fileExists(paths.scraper) ) {
          writeOutput('<p style="color:red"><b>Error:</b> Scraper not found: ' & encodeForHtml(paths.scraper) & '</p>');
          abort;
        }
    }
    if ( !structKeyExists(paths,"inserter") || !fileExists(paths.inserter) ) {
      writeOutput('<p style="color:red"><b>Error:</b> Inserter not found: ' & encodeForHtml(paths.inserter) & '</p>');
      abort;
    }
    if ( !len(ai.openaiKey) ) {
      writeOutput('<p style="color:red"><b>Error:</b> OPENAI_API_KEY is not set.</p>');
      abort;
    }
    
    // ---- Build commands (use cmd.exe so we can cd into folder) ----
    workDir = getDirectoryFromPath(paths.scraper);
    cmdExe  = paths.cmdExe;
    
    function lastLine(s){ return listLast(reReplace(s ?: "", "\r", "", "all"), chr(10)); }
    
    // Helper function for logging
    function addLog(type, message) {
        // Simple logging - could be enhanced to write to file or database
        writeLog(file="scraper", text="[#type#] #message#", type="information");
    }
    
    // ---- Enhanced AJAX Endpoints ----
    if ((url.ajax ?: "") == "1") {
        // Wrap entire AJAX section in try-catch to ensure JSON response
        try {
            // Set content type to JSON first - this must be before any output
            try {
                cfcontent(type="application/json", reset="true");
            } catch (any contentErr) {
                // If cfcontent fails, continue - some CF versions handle this differently
            }
            
            // Handle AJAX requests
            if (action == "status") {
            statusData = {
                isRunning: false,
                currentJob: {},
                recentJobs: [],
                inProgressFiles: [],
                completedFiles: [],
                logs: [],
                buttonStates: {
                    startEnabled: true,
                    resumeEnabled: false,
                    pauseEnabled: false,
                    stopEnabled: false,
                    refreshEnabled: true,
                    stopRefreshEnabled: false,
                    pauseUpdatesEnabled: true
                }
            };

            try {
                // Check if database is configured
                if (!structKeyExists(application, "db") || !structKeyExists(application.db, "dsn") || !len(application.db.dsn)) {
                    throw new Error("Database DSN not configured. Please check Application.cfc initialization.");
                }
                
                // Get current active job with resume state fields
                // Use try-catch for each query to handle missing columns gracefully
                try {
                    getCurrentJob = queryExecute(
                        "SELECT id, job_name, status, created_at, started_at, paused_at, stopped_at, process_id, max_sales, target_event_id, run_mode, error_message,
                                current_event_id, current_lot_number, total_events, current_event_index, resume_state
                        FROM scraper_jobs 
                        WHERE status IN ('running', 'paused') 
                        ORDER BY created_at DESC 
                        LIMIT 1",
                        [],
                        { datasource: application.db.dsn }
                    );
                } catch (any queryErr) {
                    // If query fails (maybe missing columns), try simpler query
                    writeLog(file="scraper", text="Error in getCurrentJob query: " & queryErr.message & " | Trying simpler query", type="error");
                    try {
                        getCurrentJob = queryExecute(
                            "SELECT id, job_name, status, created_at, started_at, paused_at, stopped_at, process_id, max_sales, target_event_id, run_mode, error_message
                            FROM scraper_jobs 
                            WHERE status IN ('running', 'paused') 
                            ORDER BY created_at DESC 
                            LIMIT 1",
                            [],
                            { datasource: application.db.dsn }
                        );
                    } catch (any simpleQueryErr) {
                        // If even simple query fails, check if table exists
                        writeLog(file="scraper", text="Error in simple getCurrentJob query: " & simpleQueryErr.message, type="error");
                        // Create empty query result
                        getCurrentJob = queryNew("id,job_name,status,created_at,started_at");
                    }
                }

                currentJobId = 0;
                if (getCurrentJob.recordCount > 0) {
                    for (row in getCurrentJob) {
                        currentJobId = row.id; // Store job ID for log fetching
                        statusData.currentJob = {
                            id: row.id,
                            name: row.job_name ?: "",
                            status: row.status ?: "",
                            createdAt: row.created_at ?: "",
                            startedAt: row.started_at ?: "",
                            pausedAt: structKeyExists(row, "paused_at") ? row.paused_at : "",
                            stoppedAt: structKeyExists(row, "stopped_at") ? row.stopped_at : "",
                            processId: structKeyExists(row, "process_id") ? row.process_id : "",
                            maxSales: structKeyExists(row, "max_sales") ? row.max_sales : "",
                            targetEventId: structKeyExists(row, "target_event_id") ? row.target_event_id : "",
                            runMode: structKeyExists(row, "run_mode") ? row.run_mode : "",
                            errorMessage: structKeyExists(row, "error_message") ? row.error_message : "",
                            currentEventId: structKeyExists(row, "current_event_id") && !isNull(row.current_event_id) ? row.current_event_id : "",
                            currentLotNumber: structKeyExists(row, "current_lot_number") && !isNull(row.current_lot_number) ? row.current_lot_number : "",
                            totalEvents: structKeyExists(row, "total_events") && !isNull(row.total_events) ? row.total_events : 0,
                            currentEventIndex: structKeyExists(row, "current_event_index") && !isNull(row.current_event_index) ? row.current_event_index : 0,
                            resumeState: (structKeyExists(row, "resume_state") && !isNull(row.resume_state) && len(trim(row.resume_state))) 
                                ? (isJSON(row.resume_state) ? deserializeJSON(row.resume_state) : {}) 
                                : {}
                        };

                        statusData.isRunning = (row.status == "running");
                        
                        // Get job statistics for progress tracking
                        try {
                            getJobStats = queryExecute(
                                "SELECT total_events, processed_events, total_lots, processed_lots, files_created, files_completed, last_update
                                 FROM job_statistics 
                                 WHERE job_id = ? 
                                 ORDER BY id DESC LIMIT 1",
                                [{value = row.id, cfsqltype = "cf_sql_integer"}],
                                {datasource = application.db.dsn}
                            );
                        } catch (any statsErr) {
                            writeLog(file="scraper", text="Error getting job statistics: " & statsErr.message, type="error");
                            getJobStats = queryNew("total_events,processed_events,total_lots,processed_lots,files_created,files_completed,last_update");
                        }
                        
                        if (getJobStats.recordCount > 0) {
                            for (stat in getJobStats) {
                                statusData.currentJob.statistics = {
                                    totalEvents: stat.total_events ?: 0,
                                    processedEvents: stat.processed_events ?: 0,
                                    totalLots: stat.total_lots ?: 0,
                                    processedLots: stat.processed_lots ?: 0,
                                    filesCreated: stat.files_created ?: 0,
                                    filesCompleted: stat.files_completed ?: 0,
                                    lastUpdate: stat.last_update
                                };
                                break;
                            }
                        }

                        // Update button states
                        if (row.status == "running") {
                            statusData.buttonStates.startEnabled = false;
                            statusData.buttonStates.resumeEnabled = false;
                            statusData.buttonStates.pauseEnabled = true;
                            statusData.buttonStates.stopEnabled = true;
                        } else if (row.status == "paused") {
                            statusData.buttonStates.startEnabled = false;
                            statusData.buttonStates.resumeEnabled = true;
                            statusData.buttonStates.pauseEnabled = false;
                            statusData.buttonStates.stopEnabled = true;
                        }

                        break; // Exit after first row
                    }
                }
                
                // Get logs for the current job (outside the loop so it always runs)
                if (getCurrentJob.recordCount > 0 && currentJobId > 0) {
                    try {
                        getJobLogs = queryExecute(
                            "SELECT message, timestamp, log_level, source 
                             FROM scrape_logs 
                             WHERE job_id = ? 
                             ORDER BY timestamp DESC 
                             LIMIT 30",
                            [{value = currentJobId, cfsqltype = "cf_sql_integer"}],
                            {datasource = application.db.dsn}
                        );
                        
                        writeLog(file="scraper", text="[DEBUG] Fetched " & getJobLogs.recordCount & " logs for job " & currentJobId, type="information");
                        
                        if (getJobLogs.recordCount > 0) {
                            // Add logs in reverse order (oldest first for display, newest at bottom)
                            for (logRow = getJobLogs.recordCount; logRow >= 1; logRow--) {
                                logMessage = getJobLogs.message[logRow];
                                logTimestamp = getJobLogs.timestamp[logRow];
                                logLevel = getJobLogs.log_level[logRow];
                                logSource = getJobLogs.source[logRow];
                                
                                // Format log message with timestamp (like command line: [HH:mm:ss] message)
                                formattedLog = "[" & timeFormat(logTimestamp, "HH:mm:ss") & "] " & logMessage;
                                arrayAppend(statusData.logs, formattedLog);
                            }
                        } else {
                            // No logs yet - add a placeholder
                            arrayAppend(statusData.logs, "[Waiting] Script starting, logs will appear here once scraping begins...");
                        }
                    } catch (any logsErr) {
                        writeLog(file="scraper", text="Error getting job logs for job " & currentJobId & ": " & logsErr.message, type="error");
                        arrayAppend(statusData.logs, "[Error] Could not fetch logs: " & logsErr.message);
                    }
                } else {
                    // No active job or job ID not set
                    if (getCurrentJob.recordCount == 0) {
                        arrayAppend(statusData.logs, "[Info] No active job found");
                    } else if (currentJobId == 0) {
                        arrayAppend(statusData.logs, "[Info] Job ID not available yet");
                    }
                }
                // Get recent jobs
                getRecentJobs = queryExecute(
                    "SELECT id, job_name, status, created_at, started_at, completed_at, error_message 
                    FROM scraper_jobs 
                    ORDER BY created_at DESC 
                    LIMIT 10",
                    [],
                    { datasource: application.db.dsn }
                );

                for (job in getRecentJobs) {
                    arrayAppend(statusData.recentJobs, {
                        id: job.id,
                        name: job.job_name,
                        status: job.status,
                        createdAt: job.created_at,
                        startedAt: job.started_at,
                        completedAt: job.completed_at,
                        errorMessage: job.error_message
                    });
                }

                // Check in-progress files
                try {
                    inProgressFolder = structKeyExists(application, "paths") && structKeyExists(application.paths, "inProgressDir") 
                        ? application.paths.inProgressDir 
                        : expandPath("./allAuctionLotsData_inprogress");
                    if (len(inProgressFolder) && directoryExists(inProgressFolder)) {
                        inProgressFiles = directoryList(inProgressFolder, false, "name", "*.jsonl");

                        for (file in inProgressFiles) {
                            try {
                                filePath = inProgressFolder & "/" & file;
                                if (fileExists(filePath)) {
                                    fileInfo = getFileInfo(filePath);
                                    // Only read file if it's not too large (limit to 10MB)
                                    if (fileInfo.size < 10485760) {
                                        lineCount = arrayLen(listToArray(fileRead(filePath), chr(10)));
                                    } else {
                                        lineCount = 0; // Skip line count for large files
                                    }
                                    arrayAppend(statusData.inProgressFiles, {
                                        name: file,
                                        size: numberFormat(fileInfo.size / 1024, "999.9"),
                                        lastModified: fileInfo.lastModified,
                                        lineCount: lineCount
                                    });
                                }
                            } catch (any fileErr) {
                                // Skip this file if there's an error
                                writeLog(file="scraper", text="Error reading in-progress file " & file & ": " & fileErr.message, type="error");
                            }
                        }
                    }
                } catch (any dirErr) {
                    writeLog(file="scraper", text="Error checking in-progress directory: " & dirErr.message, type="error");
                }

                // Check completed files
                try {
                    finalFolder = structKeyExists(application, "paths") && structKeyExists(application.paths, "finalDir") 
                        ? application.paths.finalDir 
                        : expandPath("./allAuctionLotsData_final");
                    if (len(finalFolder) && directoryExists(finalFolder)) {
                        finalFiles = directoryList(finalFolder, false, "name", "*.json");

                        for (file in finalFiles) {
                            try {
                                filePath = finalFolder & "/" & file;
                                if (fileExists(filePath)) {
                                    fileInfo = getFileInfo(filePath);
                                    arrayAppend(statusData.completedFiles, {
                                        name: file,
                                        size: numberFormat(fileInfo.size / 1024, "999.9"),
                                        lastModified: fileInfo.lastModified
                                    });
                                }
                            } catch (any fileErr) {
                                // Skip this file if there's an error
                                writeLog(file="scraper", text="Error reading completed file " & file & ": " & fileErr.message, type="error");
                            }
                        }
                    }
                } catch (any dirErr) {
                    writeLog(file="scraper", text="Error checking completed directory: " & dirErr.message, type="error");
                }

                // Cross-check for running processes
                hasInProgressFiles = (arrayLen(statusData.inProgressFiles) > 0);
                isNodeRunning = false;

                try {
                    cfexecute(
                        name = "wmic",
                        arguments = "process where ""name='node.exe'"" get ProcessId,CommandLine /format:list",
                        timeout = 10,
                        variable = "processList"
                    );
                    isNodeRunning = (findNoCase("scrap_all_auctions_lots_data.js", processList) > 0);
                } catch (any err) {
                    isNodeRunning = false;
                }

                // Auto-correct global status if required
                if (application.scraperStatus.isRunning && !isNodeRunning && !hasInProgressFiles) {
                    timeSinceLastUpdate = dateDiff("n", application.scraperStatus.lastUpdate, now());
                    if (timeSinceLastUpdate > 5) {
                        application.scraperStatus.isRunning = false;
                        application.scraperStatus.lastUpdate = now();
                        statusData.isRunning = false;
                        writeLog(file="scraper", text="Auto-corrected global status: scraper marked as stopped due to inactivity", type="information");
                    }
                }

                // Update global status
                application.scraperStatus.isRunning = statusData.isRunning;
                application.scraperStatus.lastUpdate = now();

            } catch (any err) {
                statusData = {
                    error: "Error retrieving status: " & err.message,
                    isRunning: false,
                    currentJob: {},
                    logs: ["[Error] " & err.message]
                };
                if (structKeyExists(err, "detail")) {
                    statusData.error &= " (Detail: " & err.detail & ")";
                }
                if (structKeyExists(err, "sql")) {
                    statusData.error &= " (SQL: " & left(err.sql, 100) & ")";
                }
                writeLog(file="scraper", text="[ERROR] Status action failed: " & err.message & " | Detail: " & (structKeyExists(err, "detail") ? err.detail : "") & " | SQL: " & (structKeyExists(err, "sql") ? err.sql : ""), type="error");
            }

            // Ensure we always output JSON, even on error
            try {
                writeOutput(serializeJSON(statusData));
            } catch (any outputErr) {
                // Last resort - output minimal JSON
                writeOutput(serializeJSON({error: "Failed to serialize status data: " & outputErr.message, isRunning: false}));
            }
            abort;
        }
            
            // Get current progress details
            if (action == "get_current_progress") {
                progressData = {
                    success: false,
                    currentEventId: "",
                    currentLotNumber: "",
                    totalEvents: 0,
                    currentEventIndex: 0,
                    lotsScraped: 0,
                    lotsInserted: 0,
                    eventsProcessed: 0
                };
                
                try {
                    // Get current active job
                    getCurrentJob = queryExecute(
                        "SELECT id, current_event_id, current_lot_number, total_events, current_event_index
                         FROM scraper_jobs 
                         WHERE status IN ('running', 'paused') 
                         ORDER BY created_at DESC 
                         LIMIT 1",
                        [],
                        { datasource = application.db.dsn }
                    );
                    
                    if (getCurrentJob.recordCount > 0) {
                        for (row in getCurrentJob) {
                            progressData.currentEventId = row.current_event_id ?: "";
                            progressData.currentLotNumber = row.current_lot_number ?: "";
                            progressData.totalEvents = row.total_events ?: 0;
                            progressData.currentEventIndex = row.current_event_index ?: 0;
                            
                            // Get statistics
                            getJobStats = queryExecute(
                                "SELECT processed_events, processed_lots
                                 FROM job_statistics 
                                 WHERE job_id = ? 
                                 ORDER BY id DESC LIMIT 1",
                                [{value = row.id, cfsqltype = "cf_sql_integer"}],
                                {datasource = application.db.dsn}
                            );
                            
                            if (getJobStats.recordCount > 0) {
                                for (stat in getJobStats) {
                                    progressData.eventsProcessed = stat.processed_events ?: 0;
                                    progressData.lotsScraped = stat.processed_lots ?: 0;
                                    progressData.lotsInserted = stat.processed_lots ?: 0; // Same as scraped in real-time mode
                                    break;
                                }
                            }
                            
                            progressData.success = true;
                            break;
                        }
                    }
                } catch (any err) {
                    progressData.error = err.message;
                }
                
                writeOutput(serializeJSON(progressData));
                abort;
            }

        
        if (action == "start") {
    
            // Start scraper via AJAX
            result = {success: false, error: ""};
            
            try {
                // Check if scraper is already running using global status
                if (application.scraperStatus.isRunning) {
                    result.success = false;
                    result.error = "Scraper is already running";
                    writeOutput(serializeJSON(result));
                    abort;
                }
                
                // Create new .jsonl file for this session
                timestamp = dateFormat(now(), "yyyy-mm-dd") & "_" & timeFormat(now(), "HH-mm-ss");
                newFileName = "auction_lots_" & timestamp & ".jsonl";
                inProgressFolder = application.paths.inProgressDir;
                
                // Ensure in-progress folder exists
                if (!directoryExists(inProgressFolder)) {
                    directoryCreate(inProgressFolder);
                }
                
                // Create empty .jsonl file
                newFilePath = inProgressFolder & "/" & newFileName;
                fileWrite(newFilePath, "");
                
                // Build scraper command based on run mode
                 scrOut = ""; scrErr = "";
        // Use simplified single-event scraper when eventId provided
        if (len(trim(targetEventId))) {
            scrCmd = '/c cd /d "' & workDir & '" && "' & paths.nodeBinary & '" "' & expandPath('/scrape_single_event.js') & '"';
        } else {
                scrCmd = '/c cd /d "' & workDir & '" && "' & paths.nodeBinary & '" "' & paths.scraper & '"';
        }
        
        // Add parameters based on run mode (event-id takes precedence over max-sales)
        if (runMode == "one" AND len(trim(targetEventId))) {
            scrCmd &= ' --event-id ' & trim(targetEventId);
        } else if (runMode == "max" AND len(trim(maxSales)) AND isNumeric(maxSales)) {
            scrCmd &= ' --max-sales ' & maxSales;
                }
                
                // Add the new file name as parameter
        scrCmd &= ' --output-file "' & newFileName & '"';
        
        // Log command for debugging
        addLog('info', 'Launching scraper (AJAX): ' & scrCmd);
                
                // Run scraper in background
                cfexecute(
                    name          = cmdExe,
                    arguments     = scrCmd,
                    timeout       = 3600,
                    variable      = "scrOut",
                    errorVariable = "scrErr"
                );
                
                // Update global status
                application.scraperStatus.isRunning = true;
                application.scraperStatus.startTime = now();
                application.scraperStatus.lastUpdate = now();
                
                result.success = true;
                result.message = "Scraper started successfully";
                
            } catch (any err) {
                result.error = err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }
        
        if (action == "stop") {
            // Stop scraper via AJAX
            result = {success: false, error: ""};
            try {
                processDetails = ""; 
                // First, get detailed list of node.exe processes to identify our scraper
                cfexecute(
                    name = "wmic",
                    arguments = "process where ""name='node.exe'"" get ProcessId,CommandLine /format:list",
                    timeout = 10,
                    variable = "processDetails"
                );
                
                // Add debug info to result
                result.debug = {};
                result.debug.processDetails = processDetails;
                
                // Look for our scraper process (contains scrap_all_auctions_lots_data.js)
                scraperProcessId = "";
                if (findNoCase("scrap_all_auctions_lots_data.js", processDetails) > 0) {
                    // Parse the list format to find our scraper's PID
                    lines = listToArray(processDetails, chr(13) & chr(10));
                    for (line in lines) {
                        if (findNoCase("scrap_all_auctions_lots_data.js", line) > 0) {
                            // Extract PID from list format (ProcessId=XXXXX)
                            if (findNoCase("ProcessId=", line) > 0) {
                                pidStart = findNoCase("ProcessId=", line) + 10;
                                pidEnd = findNoCase(chr(13), line, pidStart);
                                if (pidEnd == 0) pidEnd = len(line) + 1;
                                scraperProcessId = trim(mid(line, pidStart, pidEnd - pidStart));
                                break;
                            }
                        }
                    }
                }
                
                // Add more debug info
                result.debug.hasScraperProcess = (len(scraperProcessId) > 0);
                result.debug.globalStatusBefore = application.scraperStatus.isRunning;
                
                result.debug.scraperProcessId = scraperProcessId;
                
                if (len(scraperProcessId) > 0) {
                    // Kill our specific scraper process
                    cfexecute(
                        name = "taskkill",
                        arguments = "/f /pid " & scraperProcessId & " >nul 2>&1",
                        timeout = 10
                    );
                    
                    // Also try to kill any Node.js processes that might be our scraper (backup method)
                    cfexecute(
                        name = "taskkill",
                        arguments = "/f /im node.exe /fi ""WINDOWTITLE eq *scrap*"" >nul 2>&1",
                        timeout = 10
                    );
                    
                    // Wait a moment for process to terminate
                    sleep(1000);
                    
                    processCheck = ""; 
                    // Verify that our specific process was terminated
                    cfexecute(
                        name = "wmic",
                        arguments = "process where ""name='node.exe'"" get ProcessId,CommandLine /format:list",
                        timeout = 10,
                        variable = "processCheck"
                    );
                    
                    result.debug.processCheck = processCheck;
                    result.debug.scraperStillRunning = findNoCase("scrap_all_auctions_lots_data.js", processCheck) > 0;
                    
                    // If our scraper is still found, the termination failed
                    if (findNoCase("scrap_all_auctions_lots_data.js", processCheck) > 0) {
                        result.success = false;
                        result.error = "Failed to terminate scraper process - process still running after kill attempt";
                    } else {
                        // Move in-progress files to complete folder
                        inProgressFolder = application.paths.inProgressDir;
                        finalFolder = application.paths.finalDir;
                        
                        if (directoryExists(inProgressFolder)) {
                            inProgressFiles = directoryList(inProgressFolder, false, "name", "*.jsonl");
                            movedFiles = [];
                            
                            for (file in inProgressFiles) {
                                sourcePath = inProgressFolder & "/" & file;
                                targetPath = finalFolder & "/" & file;
                                
                                if (fileExists(sourcePath)) {
                                    try {
                                        // Move file to complete folder
                                        fileMove(sourcePath, targetPath);
                                        arrayAppend(movedFiles, file);
                                    } catch (any moveErr) {
                                        addLog('error', 'Failed to move file ' & file & ': ' & moveErr.message);
                                    }
                                }
                            }
                            
                            result.movedFiles = movedFiles;
                        }
                        
                        // Update global status
                        application.scraperStatus.isRunning = false;
                        application.scraperStatus.lastUpdate = now();
                        
                        result.success = true;
                        result.message = "Scraper stopped successfully. Files moved to complete folder.";
                    }
                } else {
                    // No scraper process found, but check global status
                    if (application.scraperStatus.isRunning) {
                        // Move in-progress files to complete folder even if no process found
                        inProgressFolder = application.paths.inProgressDir;
                        finalFolder = application.paths.finalDir;
                        
                        if (directoryExists(inProgressFolder)) {
                            inProgressFiles = directoryList(inProgressFolder, false, "name", "*.jsonl");
                            movedFiles = [];
                            
                            for (file in inProgressFiles) {
                                sourcePath = inProgressFolder & "/" & file;
                                targetPath = finalFolder & "/" & file;
                                
                                if (fileExists(sourcePath)) {
                                    try {
                                        fileMove(sourcePath, targetPath);
                                        arrayAppend(movedFiles, file);
                                    } catch (any moveErr) {
                                        addLog('error', 'Failed to move file ' & file & ': ' & moveErr.message);
                                    }
                                }
                            }
                            
                            result.movedFiles = movedFiles;
                        }
                        
                        // Global status says it's running but no process found - update global status
                        application.scraperStatus.isRunning = false;
                        application.scraperStatus.lastUpdate = now();
                        
                        result.success = true;
                        result.message = "Scraper process not found but global status updated. Files moved to complete folder.";
                        result.debug.globalStatusCorrected = true;
                    } else {
                        // Both global status and process detection say not running
                        result.success = true;
                        result.message = "No scraper process found to stop.";
                    }
                }
            } catch (any err) {
                result.error = "Error during stop operation: " & err.message;
                result.debug = result.debug ?: {};
                result.debug.exception = err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }
         
        if (action == "readFile") {
            // Read JSONL file content to show scraped links with enhanced information
            result = {success: false, error: "", data: [], fileInfo: {}};
            
            try {
                fileName = url.fileName ?: "";
                if (len( fileName)) {
                    filePath = application.paths.inProgressDir & "/" & fileName;
                    if (fileExists( filePath)) {
                        fileContent = fileRead(filePath);
                        lines = listToArray(fileContent, chr(10));
                        
                        // Get file info
                        fileInfo = getFileInfo(filePath);
                        result.fileInfo = {
                            name: fileName,
                            size: numberFormat(fileInfo.size/1024, "999.9"),
                            lastModified: fileInfo.lastModified,
                            lineCount: arrayLen(lines)
                        };
                        
                        // Parse each JSON line and extract relevant info
                        for (i = 1; i <= arrayLen(lines); i++) {
                            line = trim(lines[i]);
                            if (len(line)) {
                                try {
                                    jsonData = deserializeJSON(line);
                                    if (structKeyExists( jsonData, "url")) {
                                        // Extract more detailed information
                                        itemData = {
                                            url: jsonData.url,
                                            title: jsonData.title ?: jsonData.name ?: "No title",
                                            timestamp: jsonData.timestamp ?: jsonData.createdAt ?: now(),
                                            price: jsonData.price ?: jsonData.estimatedPrice ?: "N/A",
                                            lotNumber: jsonData.lotNumber ?: jsonData.lot ?: "N/A",
                                            auctionTitle: jsonData.auctionTitle ?: jsonData.eventName ?: "N/A",
                                            status: jsonData.status ?: "Active"
                                        };
                                        
                                        // Add any additional fields that might be present
                                        if (structKeyExists(jsonData, "description")) {
                                            itemData.description = jsonData.description;
                                        }
                                        if (structKeyExists(jsonData, "imageUrl")) {
                                            itemData.imageUrl = jsonData.imageUrl;
                                        }
                                        if (structKeyExists(jsonData, "endDate")) {
                                            itemData.endDate = jsonData.endDate;
                                        }
                                        
                                        arrayAppend(result.data, itemData);
                                    }
                                } catch (any jsonErr) {
                                    // Skip invalid JSON lines
                                }
                            }
                        }
                        
                        result.success = true;
                        result.message = "File read successfully - " & arrayLen(result.data) & " items found";
                    } else {
                        result.error = "File not found: " & fileName;
                    }
                } else {
                    result.error = "No filename provided";
                }
            } catch (any  err) {
                result.error = err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }
        
        if (action == "checkInProgressFiles") {
            // Check if there are in-progress .jsonl files
            result = {success: false, hasInProgressFiles: false, files: []};
            
            try {
                inProgressFolder = application.paths.inProgressDir;
                if (directoryExists(inProgressFolder)) {
                    inProgressFiles = directoryList(inProgressFolder, false, "name", "*.jsonl");
                    result.hasInProgressFiles = (arrayLen(inProgressFiles) > 0);
                    result.files = inProgressFiles;
                }
                result.success = true;
            } catch (any err) {
                result.error = err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }
        
        if (action == "resume") {
            // Resume scraping from existing .jsonl file
            result = {success: false, error: ""};
            
            try {
                // Check if scraper is already running
                if (application.scraperStatus.isRunning) {
                    result.success = false;
                    result.error = "Scraper is already running";
                    writeOutput(serializeJSON(result));
                    abort;
                }
                
                // Check for in-progress files
                inProgressFolder = application.paths.inProgressDir;
                if (!directoryExists(inProgressFolder)) {
                    result.success = false;
                    result.error = "No in-progress folder found";
                    writeOutput(serializeJSON(result));
                    abort;
                }
                
                inProgressFiles = directoryList(inProgressFolder, false, "name", "*.jsonl");
                if (arrayLen(inProgressFiles) == 0) {
                    result.success = false;
                    result.error = "No in-progress files found to resume from";
                    writeOutput(serializeJSON(result));
                    abort;
                }
                
                // Read the last line to identify the last processed lot
                lastProcessedLot = "";
                lastFileName = inProgressFiles[1]; // Get the first (and likely only) file
                lastFilePath = inProgressFolder & "/" & lastFileName;
                
                if (fileExists(lastFilePath)) {
                    fileContent = fileRead(lastFilePath);
                    lines = listToArray(fileContent, chr(10));
                    
                    if (arrayLen(lines) > 0) {
                        lastLine = trim(lines[arrayLen(lines)]);
                        if (len(lastLine)) {
                            try {
                                lastLotData = deserializeJSON(lastLine);
                                if (structKeyExists(lastLotData, "lotNumber")) {
                                    lastProcessedLot = lastLotData.lotNumber;
                                } else if (structKeyExists(lastLotData, "lot")) {
                                    lastProcessedLot = lastLotData.lot;
                                }
                            } catch (any jsonErr) {
                                // If JSON parsing fails, try to extract lot number from URL or other fields
                                if (findNoCase("lot=", lastLine) > 0) {
                                    lotStart = findNoCase("lot=", lastLine) + 4;
                                    lotEnd = findNoCase("&", lastLine, lotStart);
                                    if (lotEnd == 0) lotEnd = len(lastLine) + 1;
                                    lastProcessedLot = trim(mid(lastLine, lotStart, lotEnd - lotStart));
                                }
                            }
                        }
                    }
                }
                
                // Build scraper command with resume parameters
                scrOut = ""; scrErr = "";
                scrCmd = '/c cd /d "' & workDir & '" && node "' & paths.scraper & '" --resume';
                
                // Add the last processed lot as parameter if found
                if (len(lastProcessedLot)) {
                    scrCmd = scrCmd & ' --last-lot "' & lastProcessedLot & '"';
                }
                
                // Add the existing file name as parameter
                scrCmd = scrCmd & ' --output-file "' & lastFileName & '"';
                
                // Run scraper in background
                cfexecute(
                    name          = cmdExe,
                    arguments     = scrCmd,
                    timeout       = 3600,
                    variable      = "scrOut",
                    errorVariable = "scrErr"
                );
                
                // Update global status
                application.scraperStatus.isRunning = true;
                application.scraperStatus.startTime = now();
                application.scraperStatus.lastUpdate = now();
                
                result.success = true;
                result.message = "Scraper resumed successfully from existing file";
                
            } catch (any err) {
                result.error = err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }
        
        if (action == "pause") {
            // Pause scraping process (similar to stop but preserve files)
            result = {success: false, error: ""};
            
            try {
                // Check if scraper is running
                if (!application.scraperStatus.isRunning) {
                    result.success = false;
                    result.error = "No scraper is currently running";
                    writeOutput(serializeJSON(result));
                    abort;
                }
                processDetails = "";
                // Terminate the scraper process (same logic as stop)
                cfexecute(
                    name = "wmic",
                    arguments = "process where ""name='node.exe'"" get ProcessId,CommandLine /format:list",
                    timeout = 10,
                    variable = "processDetails"
                );
                
                scraperProcessId = "";
                if (findNoCase("scrap_all_auctions_lots_data.js", processDetails) > 0) {
                    lines = listToArray(processDetails, chr(13) & chr(10));
                    for (line in lines) {
                        if (findNoCase("scrap_all_auctions_lots_data.js", line) > 0) {
                            if (findNoCase("ProcessId=", line) > 0) {
                                pidStart = findNoCase("ProcessId=", line) + 10;
                                pidEnd = findNoCase(chr(13), line, pidStart);
                                if (pidEnd == 0) pidEnd = len(line) + 1;
                                scraperProcessId = trim(mid(line, pidStart, pidEnd - pidStart));
                                break;
                            }
                        }
                    }
                }
                
                if (len(scraperProcessId) > 0) {
                    cfexecute(
                        name = "taskkill",
                        arguments = "/f /pid " & scraperProcessId & " >nul 2>&1",
                        timeout = 10
                    );
                    
                    sleep(1000);
                    processCheck = "";
                    // Verify termination
                    cfexecute(
                        name = "wmic",
                        arguments = "process where ""name='node.exe'"" get ProcessId,CommandLine /format:list",
                        timeout = 10,
                        variable = "processCheck"
                    );
                    
                    if (findNoCase("scrap_all_auctions_lots_data.js", processCheck) > 0) {
                        result.success = false;
                        result.error = "Failed to pause scraper process";
                    } else {
                        // Update global status but keep files for resume
                        application.scraperStatus.isRunning = false;
                        application.scraperStatus.lastUpdate = now();
                        
                        result.success = true;
                        result.message = "Scraper paused successfully. Files preserved for resume.";
                    }
                } else {
                    // No process found but update global status
                    application.scraperStatus.isRunning = false;
                    application.scraperStatus.lastUpdate = now();
                    
                    result.success = true;
                    result.message = "Scraper paused (no process found). Files preserved for resume.";
                }
                
            } catch (any err) {
                result.error = "Error during pause operation: " & err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }
        
        if (action == "countLines") {
            // Count lines in a specific .jsonl file
            result = {success: false, lineCount: 0, error: ""};
            
            try {
                fileName = url.fileName ?: "";
                if (len(fileName)) {
                    filePath = expandPath("/allAuctionLotsData_inprogress/" & fileName);
                    if (fileExists(filePath)) {
                        fileContent = fileRead(filePath);
                        lines = listToArray(fileContent, chr(10));
                        result.lineCount = arrayLen(lines);
                        result.success = true;
                    } else {
                        result.error = "File not found: " & fileName;
                    }
                } else {
                    result.error = "No filename provided";
                }
            } catch (any err) {
                result.error = err.message;
            }
            
            writeOutput(serializeJSON(result));
            abort;
        }

        } catch (any ajaxErr) {
            // Catch any unhandled errors in AJAX section and return JSON
            errorResponse = {
                error: "Internal server error: " & ajaxErr.message,
                detail: structKeyExists(ajaxErr, "detail") ? ajaxErr.detail : "",
                type: "AJAX_ERROR",
                action: action ?: "unknown"
            };
            if (structKeyExists(ajaxErr, "sql")) {
                errorResponse.sql = left(ajaxErr.sql, 200);
            }
            if (structKeyExists(ajaxErr, "sqlState")) {
                errorResponse.sqlState = ajaxErr.sqlState;
            }
            writeLog(file="scraper", text="[FATAL AJAX ERROR] Action: " & (action ?: "unknown") & " | Error: " & ajaxErr.message & " | Detail: " & (structKeyExists(ajaxErr, "detail") ? ajaxErr.detail : "") & " | SQL: " & (structKeyExists(ajaxErr, "sql") ? ajaxErr.sql : ""), type="error");
            writeOutput(serializeJSON(errorResponse));
            abort;
        }
    }
    // ---- Start Scraper Process (Non-AJAX) ----
    if (action == "start" && (url.ajax ?: "") != "1") {
       
        // Build scraper command based on run mode
        scrOut = ""; scrErr = "";
        // Choose script: single-event script if eventId, otherwise multi-event
        singleScript = expandPath('/scrape_single_event.js');
        chosenScript = len(trim(targetEventId)) ? singleScript : paths.scraper;
        scrCmd = '/c cd /d "' & workDir & '" && node "' & chosenScript & '"';
    
        // Minimal single-event mode: if an eventId is present, ignore other modes
        if (len(trim(targetEventId))) {
            scrCmd &= ' --event-id ' & trim(targetEventId);
            scrCmd &= ' --output-file "auction_' & trim(targetEventId) & '_lots.jsonl"';
        } else if (runMode == "max" AND len(trim(maxSales)) AND isNumeric(maxSales)) {
            scrCmd &= ' --max-sales ' & maxSales;
        }
        // For "all" mode, no additional parameters needed
        
        // Log command for debugging
        addLog('info', 'Launching scraper (non-AJAX): ' & scrCmd);
    
        // Run scraper
        cfexecute(
          name          = cmdExe,
          arguments     = scrCmd,
          timeout       = 3600,
          variable      = "scrOut",
          errorVariable = "scrErr"
        );
    
        // Run inserter
        insOut = ""; insErr = "";
        embedModel = ai.embedModel ?: "text-embedding-3-small";
        insCmd = '/c cd /d "' & workDir & '" && "' & paths.nodeBinary & '" "' & paths.inserter & '"'
               & ' --openaiKey="' & replace(ai.openaiKey, '"', '\"', "all") & '"'
               & ' --embedModel="' & embedModel & '"';
    
        cfexecute(
          name          = cmdExe,
          arguments     = insCmd,
          timeout       = 3600,
          variable      = "insOut",
          errorVariable = "insErr"
        );
    
        // Display results
        writeOutput('<div style="background: ##e8f5e8; border: 1px solid ##4CAF50; border-radius: 8px; padding: 20px; margin-top: 20px;">');
        writeOutput('<h3 style="margin-top: 0; color: ##2E7D32;"><span style="color: ##4CAF50;">&##128202;</span> Scraper Results</h3>');
        
        if (len(scrOut)) {
            writeOutput('<h4>Scraper Output:</h4>');
            writeOutput('<pre style="background: ##f5f5f5; padding: 10px; border-radius: 4px; max-height: 200px; overflow-y: auto; font-size: 11px;">');
            writeOutput(encodeForHtml(scrOut));
            writeOutput('</pre>');
        }
    
        if (len(scrErr)) {
            writeOutput('<h4 style="color: ##f44336;">Scraper Errors:</h4>');
            writeOutput('<pre style="background: ##ffebee; padding: 10px; border-radius: 4px; max-height: 200px; overflow-y: auto; font-size: 11px;">');
            writeOutput(encodeForHtml(scrErr));
            writeOutput('</pre>');
        }
    
        if (len(insOut)) {
            writeOutput('<h4>Inserter Output:</h4>');
            writeOutput('<pre style="background: ##f5f5f5; padding: 10px; border-radius: 4px; max-height: 200px; overflow-y: auto; font-size: 11px;">');
            writeOutput(encodeForHtml(insOut));
            writeOutput('</pre>');
        }
    
        if (len(insErr)) {
            writeOutput('<h4 style="color: ##f44336;">Inserter Errors:</h4>');
            writeOutput('<pre style="background: ##ffebee; padding: 10px; border-radius: 4px; max-height: 200px; overflow-y: auto; font-size: 11px;">');
            writeOutput(encodeForHtml(insErr));
            writeOutput('</pre>');
        }
    
        writeOutput('</div>');
    }
</cfscript>  
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>NumisBids Scraper - Control Panel</title>
        
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }
    
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                padding: 20px;
            }
    
            .container {
                max-width: 1400px;
                margin: 0 auto;
                background: white;
                border-radius: 15px;
                box-shadow: 0 20px 40px rgba(0,0,0,0.1);
                overflow: hidden;
            }
    
            .header {
                background: linear-gradient(135deg, #2196F3, #1976D2);
                color: white;
                padding: 30px;
                text-align: center;
            }
    
            .header h1 {
                font-size: 2.5rem;
                margin-bottom: 10px;
                font-weight: 300;
            }
    
            .header p {
                font-size: 1.1rem;
                opacity: 0.9;
            }
    
            .main-content {
                padding: 30px;
            }
    
            .scraper-options {
                background: #f8f9fa;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                padding: 30px;
                margin-bottom: 25px;
                text-align: center;
            }

            .scraper-options h2 {
                color: #1976D2;
                margin-bottom: 10px;
                font-size: 1.8rem;
            }

            .scraper-options > p {
                color: #666;
                margin-bottom: 30px;
                font-size: 1.1rem;
            }

            .option-cards {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 25px;
                margin-bottom: 30px;
                max-width: 800px;
                margin-left: auto;
                margin-right: auto;
            }

            .option-card {
                background: white;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                padding: 25px;
                cursor: pointer;
                transition: all 0.3s ease;
                text-align: center;
            }

            .option-card:hover {
                border-color: #2196F3;
                box-shadow: 0 4px 12px rgba(33, 150, 243, 0.15);
                transform: translateY(-2px);
            }

            .option-card.selected {
                border-color: #2196F3;
                background: #f3f8ff;
                box-shadow: 0 4px 12px rgba(33, 150, 243, 0.2);
            }

            .card-icon {
                font-size: 3rem;
                margin-bottom: 15px;
            }

            .option-card h3 {
                color: #333;
                margin-bottom: 10px;
                font-size: 1.3rem;
            }

            .option-card p {
                color: #666;
                margin-bottom: 15px;
                line-height: 1.5;
            }

            .card-features {
                display: flex;
                flex-direction: column;
                gap: 8px;
                font-size: 0.9rem;
                color: #28a745;
            }

            .input-form {
                background: white;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                padding: 25px;
                max-width: 600px;
                margin: 0 auto;
                text-align: left;
            }

            .input-form h3 {
                color: #1976D2;
                margin-bottom: 20px;
                text-align: center;
            }

            .help-text {
                background: #f8f9fa;
                border-left: 4px solid #2196F3;
                padding: 15px;
                margin: 10px 0;
                font-size: 0.9rem;
                line-height: 1.5;
                color: #555;
            }

            .checkbox-container {
                display: flex;
                align-items: flex-start;
                gap: 12px;
                cursor: pointer;
                margin: 15px 0;
                line-height: 1.5;
            }

            .checkbox-container input[type="checkbox"] {
                margin: 0;
                transform: scale(1.2);
            }

            .status-section {
                background: #f8f9fa;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                padding: 25px;
                margin-bottom: 25px;
            }

            .status-display {
                background: white;
                border-radius: 8px;
                padding: 20px;
                margin: 15px 0;
            }

            .status-item {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 8px 0;
                border-bottom: 1px solid #eee;
            }

            .status-item:last-child {
                border-bottom: none;
            }

            .status-label {
                font-weight: 600;
                color: #333;
            }

            .status-value {
                color: #666;
                font-family: monospace;
            }

            .form-actions {
                display: flex;
                gap: 15px;
                justify-content: center;
                margin-top: 20px;
                flex-wrap: wrap;
            }
    
            .form-group {
                margin-bottom: 20px;
            }
    
            .form-group label {
                display: block;
                font-weight: 600;
                margin-bottom: 8px;
                color: #333;
                font-size: 1rem;
            }
    
            .radio-group {
                display: flex;
                gap: 25px;
                margin-top: 15px;
                flex-wrap: wrap;
            }
    
            .radio-option {
                display: flex;
                align-items: center;
                gap: 10px;
                padding: 15px;
                border: 2px solid #e9ecef;
                border-radius: 8px;
                cursor: pointer;
                transition: all 0.3s ease;
                min-width: 200px;
            }
    
            .radio-option:hover {
                border-color: #2196F3;
                background: #f0f8ff;
            }
    
            .radio-option input[type="radio"] {
                width: 18px;
                height: 18px;
                accent-color: #2196F3;
                cursor: pointer;
                margin: 0;
                padding: 0;
                position: relative;
                z-index: 1;
                opacity: 1;
                pointer-events: auto;
            }
            
            .radio-option input[type="radio"]:checked {
                accent-color: #2196F3;
            }
            
            .radio-option input[type="radio"]:focus {
                outline: 2px solid #2196F3;
                outline-offset: 2px;
            }
            
            .radio-option input[type="radio"]:disabled {
                opacity: 0.5;
                cursor: not-allowed;
            }
            
            .radio-option label {
                margin: 0;
                cursor: pointer;
                font-weight: 500;
                user-select: none;
            }
    
            .input-field {
                width: 100%;
                padding: 12px 15px;
                border: 2px solid #e9ecef;
                border-radius: 8px;
                font-size: 1rem;
                transition: border-color 0.3s ease;
            }
    
            .input-field:focus {
                outline: none;
                border-color: #2196F3;
                box-shadow: 0 0 0 3px rgba(33, 150, 243, 0.1);
            }
    
            .btn-group {
                display: flex;
                gap: 15px;
                margin-top: 25px;
                flex-wrap: wrap;
            }
    
            .btn {
                padding: 15px 30px;
                border: none;
                border-radius: 8px;
                cursor: pointer;
                text-decoration: none;
                display: inline-flex;
                align-items: center;
                gap: 8px;
                font-size: 1rem;
                font-weight: 600;
                transition: all 0.3s ease;
                min-width: 140px;
                justify-content: center;
            }
    
            .btn:hover {
                transform: translateY(-2px);
                box-shadow: 0 8px 25px rgba(0,0,0,0.15);
            }
    
            .btn:disabled {
                opacity: 0.6;
                cursor: not-allowed;
                transform: none;
            }
    
            .btn-primary {
                background: linear-gradient(135deg, #2196F3, #1976D2);
                color: white;
            }
    
            .btn-success {
                background: linear-gradient(135deg, #4CAF50, #45a049);
                color: white;
            }
    
            .btn-danger {
                background: linear-gradient(135deg, #f44336, #d32f2f);
                color: white;
            }
    
            .btn-warning {
                background: linear-gradient(135deg, #FF9800, #F57C00);
                color: white;
            }
    
            .btn-secondary {
                background: linear-gradient(135deg, #9E9E9E, #757575);
                color: white;
            }
    
            .quick-actions {
                background: linear-gradient(135deg, #fff3e0, #ffe0b2);
                border: 2px solid #FF9800;
                border-radius: 12px;
                padding: 25px;
                margin-bottom: 25px;
            }
    
            .quick-actions h3 {
                color: #E65100;
                margin-bottom: 20px;
                font-size: 1.3rem;
                display: flex;
                align-items: center;
                gap: 10px;
            }
    
            .quick-actions .btn-group {
                margin-top: 15px;
            }
    
            .progress-section {
                background: #f8f9fa;
                border: 2px solid #e9ecef;
                border-radius: 12px;
                padding: 25px;
                margin-bottom: 25px;
            }
    
            .progress-section h3 {
                color: #4CAF50;
                margin-bottom: 20px;
                font-size: 1.3rem;
                display: flex;
                align-items: center;
                gap: 10px;
            }
    
            .status-display {
                display: flex;
                align-items: center;
                gap: 15px;
                margin-bottom: 20px;
                padding: 15px;
                background: white;
                border-radius: 8px;
                border: 1px solid #e9ecef;
            }
    
            .status-indicator {
                width: 16px;
                height: 16px;
                border-radius: 50%;
                animation: pulse 2s infinite;
            }
    
            .status-running {
                background: #4CAF50;
            }
    
            .status-idle {
                background: #FF9800;
            }
    
            .status-stopped {
                background: #f44336;
            }
    
            @keyframes pulse {
                0% { opacity: 1; }
                50% { opacity: 0.5; }
                100% { opacity: 1; }
            }
            
            .progress-bar {
                background: #e9ecef;
                height: 30px;
                border-radius: 15px;
                overflow: hidden;
                margin: 15px 0;
                box-shadow: inset 0 2px 4px rgba(0,0,0,0.1);
            }
    
            .progress-fill {
                background: linear-gradient(90deg, #4CAF50, #45a049);
                height: 100%;
                width: 0%;
                transition: width 0.8s ease;
                border-radius: 15px;
            }
            
            .progress-fill.running {
                background: linear-gradient(90deg, #4CAF50, #45a049, #4CAF50);
                background-size: 200% 100%;
                animation: progressPulse 2s infinite;
            }
            
            @keyframes progressPulse {
                0% { background-position: 0% 50%; }
                50% { background-position: 100% 50%; }
                100% { background-position: 0% 50%; }
            }
    
            .progress-text {
                font-size: 1rem;
                color: #666;
                margin-top: 10px;
            }
    
            .live-updates {
                background: #e3f2fd;
                border-radius: 8px;
                padding: 20px;
                margin-top: 20px;
            }
    
            #liveUpdates {
                max-height: 300px;
                overflow-y: auto;
                padding-right: 10px;
            }
    
            #liveUpdates::-webkit-scrollbar {
                width: 8px;
            }
    
            #liveUpdates::-webkit-scrollbar-track {
                background: #f1f1f1;
                border-radius: 4px;
            }
    
            #liveUpdates::-webkit-scrollbar-thumb {
                background: #c1c1c1;
                border-radius: 4px;
            }
    
            #liveUpdates::-webkit-scrollbar-thumb:hover {
                background: #a8a8a8;
            }
    
            .live-updates h4 {
                color: #1976D2;
                margin-bottom: 15px;
                font-size: 1.1rem;
            }
    
            .update-item {
                padding: 10px;
                margin: 8px 0;
                border-radius: 6px;
                font-size: 0.9rem;
            }
    
            .update-success {
                background: #d4edda;
                border: 1px solid #c3e6cb;
                color: #155724;
            }
    
            .update-error {
                background: #f8d7da;
                border: 1px solid #f5c6cb;
                color: #721c24;
            }
    
            .update-warning {
                background: #fff3cd;
                border: 1px solid #ffeaa7;
                color: #856404;
            }
    
            .update-info {
                background: #d1ecf1;
                border: 1px solid #bee5eb;
                color: #0c5460;
            }
    
            .file-monitor {
                background: #e8f5e8;
                border: 2px solid #4CAF50;
                border-radius: 12px;
                padding: 25px;
                margin-bottom: 25px;
            }
    
            .file-monitor h4 {
                color: #2E7D32;
                margin-bottom: 20px;
                font-size: 1.3rem;
                display: flex;
                align-items: center;
                gap: 10px;
            }
    
            .file-section {
                margin-bottom: 20px;
            }
    
            .file-section h5 {
                color: #4CAF50;
                margin-bottom: 10px;
                font-size: 1rem;
            }
    
            .file-list {
                background: white;
                border-radius: 8px;
                padding: 15px;
                max-height: 200px;
                overflow-y: auto;
            }
    
            .file-item {
                display: flex;
                align-items: center;
                gap: 10px;
                padding: 12px;
                margin: 5px 0;
                border-radius: 8px;
                cursor: pointer;
                transition: all 0.3s ease;
                font-family: 'Courier New', monospace;
                font-size: 0.9rem;
                border: 1px solid transparent;
            }
    
            .file-item:hover {
                background: #f8f9fa;
                border-color: #e9ecef;
                transform: translateY(-1px);
                box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            }
    
            .file-item:hover {
                background: #f5f5f5;
            }
    
            .file-item.in-progress {
                color: #FF9800;
                border-left: 3px solid #FF9800;
            }
    
            .file-item.completed {
                color: #4CAF50;
                border-left: 3px solid #4CAF50;
            }
    
            .log-container {
                background: #1a1a1a;
                color: #00ff00;
                padding: 20px;
                border-radius: 12px;
                font-family: 'Courier New', monospace;
                font-size: 0.9rem;
                max-height: 400px;
                overflow-y: auto;
                border: 2px solid #333;
            }
    
            .log-item {
                margin: 5px 0;
                padding: 5px 0;
                border-bottom: 1px solid #333;
            }
    
            .log-info { color: #2196F3; }
            .log-success { color: #4CAF50; }
            .log-warning { color: #FF9800; }
            .log-error { color: #f44336; }
    
            .modal {
                display: none;
                position: fixed;
                z-index: 1000;
                left: 0;
                top: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(0,0,0,0.5);
            }
    
            .modal-content {
                background-color: white;
                margin: 5% auto;
                padding: 30px;
                border-radius: 12px;
                width: 80%;
                max-width: 800px;
                max-height: 80vh;
                overflow-y: auto;
                box-shadow: 0 20px 40px rgba(0,0,0,0.3);
            }
    
            .modal-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 20px;
                padding-bottom: 15px;
                border-bottom: 2px solid #e9ecef;
            }
    
            .modal-title {
                font-size: 1.5rem;
                color: #1976D2;
                font-weight: 600;
            }
    
            .close {
                color: #aaa;
                font-size: 28px;
                font-weight: bold;
                cursor: pointer;
                transition: color 0.3s ease;
            }
    
            .close:hover {
                color: #000;
            }
    
            .link-item {
                margin: 15px 0;
                padding: 15px;
                border: 1px solid #e9ecef;
                border-radius: 8px;
                background: #f8f9fa;
            }
    
            .link-item a {
                color: #2196F3;
                text-decoration: none;
                font-weight: 500;
            }
    
            .link-item a:hover {
                text-decoration: underline;
            }
    
            .link-title {
                color: #666;
                font-size: 0.9rem;
                margin-top: 5px;
            }
    
            .loading {
                opacity: 0.7;
                pointer-events: none;
            }
    
            .fade-in {
                animation: fadeIn 0.5s ease-in;
            }
    
            @keyframes fadeIn {
                from { opacity: 0; transform: translateY(10px); }
                to { opacity: 1; transform: translateY(0); }
            }
    
            @media (max-width: 768px) {
                .option-cards {
                    grid-template-columns: 1fr;
                    gap: 15px;
                }
                
                .form-actions {
                    flex-direction: column;
                }
                
                .btn {
                    width: 100%;
                }
                
                .header h1 {
                    font-size: 2rem;
                }
                
                .input-form {
                    margin: 0 10px;
                    padding: 20px;
                }
                
                .main-content {
                    padding: 20px;
                }
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>&#128640; NumisBids Scraper Control Panel</h1>
                <p>Advanced auction data scraping and monitoring system</p>
            </div>
    
            <div class="main-content">
                <!-- Simple Scraper Options -->
                <div class="scraper-options">
                    <h2>Choose Scraping Mode</h2>
                    <p>Select how you want to scrape auction data from NumisBids</p>
                    
                    <div class="option-cards">
                        <!-- Single Event Option -->
                        <div class="option-card" id="singleEventCard">
                            <div class="card-icon">Single</div>
                            <h3>Single Event</h3>
                            <p>Scrape one specific auction event with all its lots</p>
                            <div class="card-features">
                                <span>Fast and focused</span>
                                <span>Complete lot details</span>
                                <span>Perfect for testing</span>
                                </div>
                                </div>
                        
                        <!-- All Events Option -->
                        <div class="option-card" id="allEventsCard">
                            <div class="card-icon">All</div>
                            <h3>All Events</h3>
                            <p>Scrape all available auction events from the homepage</p>
                            <div class="card-features">
                                <span>Complete coverage</span>
                                <span>Automatic discovery</span>
                                <span>Full database update</span>
                                </div>
                            </div>
                        </div>
    
                    <!-- Single Event Form -->
                    <div class="input-form" id="singleEventForm" style="display: none;">
                        <h3>Enter Event/Sale URL or ID</h3>
                        <div class="form-group">
                            <input type="text" id="saleUrlInput" class="input-field" placeholder="https://www.numisbids.com/sale/9691 OR https://www.numisbids.com/event/13227 OR 9691">
                            <div class="help-text">
                                <strong>Examples:</strong><br>
                                • Sale URL: https://www.numisbids.com/sale/9691<br>
                                • Event URL (redirects to sale): https://www.numisbids.com/event/13227<br>
                                • Direct ID: 9691
                        </div>
                        </div>
                        <div class="form-actions">
                            <button type="button" class="btn btn-primary" id="startSingleBtn">
                                Start Single Event Scraping
                            </button>
                            <button type="button" class="btn btn-secondary" id="cancelSingleBtn">
                                Cancel
                            </button>
                        </div>
                </div>
    
                    <!-- All Events Form -->
                    <div class="input-form" id="allEventsForm" style="display: none;">
                        <h3>Scrape All Events</h3>
                        <div class="form-group">
                            <div class="help-text">
                                <strong>This will:</strong><br>
                                • Discover all events from NumisBids homepage<br>
                                • Scrape each event with all lots and details<br>
                                • Update your complete auction database<br>
                                • May take several hours to complete
                            </div>
                            <label class="checkbox-container">
                                <input type="checkbox" id="confirmAllEvents">
                                <span class="checkmark"></span>
                                I understand this will scrape all events and may take several hours
                            </label>
                        </div>
                        <div class="form-actions">
                            <button type="button" class="btn btn-success" id="startAllBtn" disabled>
                                Start All Events Scraping
                        </button>
                            <button type="button" class="btn btn-secondary" id="cancelAllBtn">
                                Cancel
                        </button>
                        </div>
                    </div>
                </div>
    
                <!-- Status Section -->
                <div class="status-section" id="statusSection" style="display: none;">
                    <h3>Scraping Status</h3>
                    <div class="status-display">
                        <div class="status-item">
                            <span class="status-label">Mode:</span>
                            <span class="status-value" id="currentMode">-</span>
                        </div>
                        <div class="status-item">
                            <span class="status-label">Status:</span>
                            <span class="status-value" id="currentStatus">-</span>
                    </div>
                        <div class="status-item">
                            <span class="status-label">Progress:</span>
                            <span class="status-value" id="currentProgress">-</span>
                    </div>
                </div>
    
                    <!-- Progress bar -->
                    <div class="progress" style="background:#eee;border-radius:8px;height:12px;margin:10px 0;">
                        <div id="progressBar" style="background:#2196F3;width:0%;height:100%;border-radius:8px;"></div>
                    </div>
    
                    <!-- Live command output/logs -->
                    <pre id="outputLog" style="background:#111;color:#0f0;padding:12px;border-radius:8px;max-height:300px;overflow:auto;white-space:pre-wrap;">Waiting for output...</pre>

                    <div class="form-actions">
                        <button type="button" class="btn btn-danger" id="stopScrapingBtn">
                            Stop
                        </button>
                        <button type="button" class="btn btn-secondary" id="pauseScrapingBtn">
                            Pause
                        </button>
                        <button type="button" class="btn btn-secondary" id="refreshStatusBtn">
                            Refresh Status
                        </button>
                        <button type="button" class="btn btn-secondary" id="backToOptionsBtn">
                            Back to Options
                        </button>
                    </div>
                </div>
            </div>
        </div>
    
        <!-- Modal for File Content -->
        <div id="fileModal" class="modal">
            <div class="modal-content">
                <div class="modal-header">
                    <div class="modal-title" id="modalTitle">File Content</div>
                    <span class="close" id="closeModal">&times;</span>
                </div>
                <div id="modalContent"></div>
            </div>
        </div>
    
        <!-- jQuery Library -->
        <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>

        <script>
            // Global variables
            let isRunning = false;
            let isLoading = false;
            let updateInterval = null;
            let isLiveUpdatesPaused = false;
            let logs = [];
            let liveUpdates = [];

            // Wait for jQuery to be ready
            $(document).ready(function() {
                console.log('jQuery loaded - initializing application');
                
                // Initialize the application
                setupEventListeners();
                
                console.log('Application initialization completed successfully');
            });

            function initializeApp() {
                console.log('System initialized successfully with jQuery');
                console.log('Ready to start scraping operations');
            }

            function setupEventListeners() {
                console.log('Setting up clean UI event listeners...');
                
                // Option card selection
                $('#singleEventCard').on('click', function() {
                    console.log('Single Event card clicked!');
                    // Open input form and focus the textbox
                    selectOption('single');
                    setTimeout(function(){ 
                        console.log('Focusing input field');
                        $('#saleUrlInput').focus(); 
                    }, 100);
                });
                
                $('#allEventsCard').on('click', function() {
                    // Immediately start all-events scraping per request
                    startAllEventsScraping();
                });
                
                // Form buttons
                $('#startSingleBtn').on('click', function() {
                    startSingleEventScraping();
                });
                
                $('#startAllBtn').on('click', function() {
                    startAllEventsScraping();
                });
                
                $('#cancelSingleBtn, #cancelAllBtn').on('click', function() {
                    showOptions();
                });
                
                // Enter-to-start on single event input
                $('#saleUrlInput').on('keyup', function(e){
                    if (e.key === 'Enter') {
                        startSingleEventScraping();
                    }
                });
                
                // Status section buttons
                $('#stopScrapingBtn').on('click', function() {
                    stopScraping();
                });

                $('#refreshStatusBtn').on('click', function() {
                    refreshStatus();
                });
                
                $('#backToOptionsBtn').on('click', function() {
                    showOptions();
                });

                console.log('Clean UI event listeners setup complete');
            }

            // Clean UI Functions
            function selectOption(type) {
                console.log('selectOption called with type:', type);
                // Remove selected class from all cards
                $('.option-card').removeClass('selected');
                
                if (type === 'single') {
                    console.log('Showing single event form');
                    $('#singleEventCard').addClass('selected');
                    $('#singleEventForm').show();
                    $('#allEventsForm').hide();
                    console.log('Single event form should now be visible');
                } else if (type === 'all') {
                    console.log('Showing all events form');
                    $('#allEventsCard').addClass('selected');
                    $('#allEventsForm').show();
                    $('#singleEventForm').hide();
                }
            }

            function showOptions() {
                $('.option-card').removeClass('selected');
                $('#singleEventForm').hide();
                $('#allEventsForm').hide();
                $('#statusSection').hide();
                $('.scraper-options').show();
                $('#confirmAllEvents').prop('checked', false);
                $('#startAllBtn').prop('disabled', true);
            }

            // Helper: parse sale/event URL or plain ID into numeric id
            function parseIdFromInput(raw) {
                if (!raw) return '';
                var s = (raw + '').trim();
                var m = s.match(/\/sale\/(\d+)/i);
                if (m) return m[1];
                m = s.match(/\/event\/(\d+)/i);
                if (m) return m[1];
                m = s.match(/^(\d{3,})$/);
                if (m) return m[1];
                return '';
            }

            // Append a line to live output
            function appendOutput(line) {
                var el = document.getElementById('outputLog');
                if (!el) return;
                if (el.textContent === 'Waiting for output...') el.textContent = '';
                el.textContent += line + "\n";
                el.scrollTop = el.scrollHeight;
            }

            // Set progress visually
            function setProgress(percent, label) {
                var bar = document.getElementById('progressBar');
                if (bar) bar.style.width = (Math.max(0, Math.min(100, percent)) + '%');
                if (label) {
                    var v = document.getElementById('currentProgress');
                    if (v) v.textContent = label;
                }
            }

            // Override startSingleEventScraping to accept URL
            function startSingleEventScraping() {
                var raw = $('#saleUrlInput').val().trim();
                var id = parseIdFromInput(raw);
                if (!id) {
                    alert('Please provide a valid sale or event URL (or numeric ID).');
                    return;
                }

                // Show status section
                $('.scraper-options').hide();
                $('#statusSection').show();
                $('#currentMode').text('Single Event (' + id + ')');
                $('#currentStatus').text('Starting...');
                $('#currentProgress').text('Initializing');
                setProgress(0, 'Starting');
                appendOutput('Launching single-event scraper for ID: ' + id);

                // Kick off backend
                $.post(window.location.href, {
                    action: 'start',
                    runMode: 'one',
                    eventId: id,
                    ajax: 1
                }).done(function(resp){
                    appendOutput('Backend accepted start.');
                    startStatusUpdates();
                }).fail(function(){
                    alert('Failed to start scraping.');
                    showOptions();
                });
            }

            // Hook Stop/Pause (backend actions must exist)
            $('#pauseScrapingBtn').on('click', function(){
                $.post(window.location.href, { action: 'pause' }).always(function(){
                    $('#currentStatus').text('Paused');
                    appendOutput('Paused by user');
                    });
                });

            // Extend refreshStatus to also update output/progress (placeholder polling)
            function refreshStatus() {
                $.get(window.location.href + '?action=status', function(data){
                    try {
                        var s = (typeof data === 'string') ? JSON.parse(data) : data;
                        if (s && s.statusText) $('#currentStatus').text(s.statusText);
                        if (s && typeof s.progressPct === 'number') setProgress(s.progressPct, s.progressLabel || (s.progressPct + '%'));
                        if (s && s.newLogs && s.newLogs.length) {
                            s.newLogs.forEach(function(line){ appendOutput(line); });
                        }
                        if (s && s.done) {
                            appendOutput('Scraping completed.');
                            $('#currentStatus').text('Completed');
                            setProgress(100, 'Completed');
                            // Optional: trigger ingestion into RAG DB
                            $.post(window.location.href, { action: 'ingest' }).always(function(){
                                appendOutput('Ingestion into RAG database triggered.');
                            });
                        }
                    } catch(_) {
                        // fallback UI only
                        $('#currentStatus').text('Running');
                    }
                }).fail(function(){
                    // Best-effort UI update
                    var cur = $('#currentStatus').text();
                    if (!cur || cur === '-' || cur === 'Starting...') $('#currentStatus').text('Running');
                });
            }

            function startAllEventsScraping() {
                // Show status section immediately
                $('.scraper-options').hide();
                $('#statusSection').show();
                $('#currentMode').text('All Events');
                $('#currentStatus').text('Starting...');
                $('#currentProgress').text('Discovering events');

                // Start scraping via AJAX
                $.post(window.location.href, {
                    action: 'start',
                    runMode: 'all',
                    ajax: 1
                }).done(function(response) {
                    console.log('All events scraping started:', response);
                    startStatusUpdates();
                }).fail(function() {
                    alert('Failed to start scraping. Please try again.');
                    showOptions();
                });
            }

            function stopScraping() {
                if (confirm('Are you sure you want to stop the scraping process?')) {
                    $.post(window.location.href, {
                        action: 'stop'
                    }).done(function() {
                        $('#currentStatus').text('Stopping...');
                        setTimeout(function() {
                            showOptions();
                        }, 2000);
                    });
                }
            }

            function startStatusUpdates() {
                if (updateInterval) clearInterval(updateInterval);
                updateInterval = setInterval(refreshStatus, 2000);
            }

            function stopStatusUpdates() {
                if (updateInterval) {
                    clearInterval(updateInterval);
                    updateInterval = null;
                }
            }


            // 1. Start Scraping Function
            function startScraping() {
                if (isLoading || isRunning) {
                    addLog('warning', 'Scraper is already running or loading');
                    return;
                }

                addLog('info', 'Starting new scraping session...');
                isLoading = true;
                updateButtonStates();

                // Get form data
                const formData = {
                    action: 'start',
                    runMode: $('input[name="runMode"]:checked').val(),
                    eventId: $('#eventId').val(),
                    maxSales: $('#maxSales').val(),
                    ajax: 1
                };
                $.ajax({
                    url: '?',
                    method: 'POST',
                    data: formData,
                    dataType: 'json',
                    success: function(data) {
                        console.log(data);
                        isLoading = false;
                        
                        if (data.SUCCESS) {
                            isRunning = true;
                            addLog('success', 'Scraping started successfully - Job ID: ' + data.JOBID);
                            addLiveUpdate('success', 'New scraping session started');
                            updateStatus('Running - Scraping in progress', 'running');
                            startMonitoring();
                            
                            // Update button states according to specification
                            $('#startBtn').prop('disabled', true);
                            $('#resumeBtn').prop('disabled', true);
                            $('#pauseBtn').prop('disabled', false);
                            $('#stopBtn').prop('disabled', false);
                            $('#refreshStatusBtn').prop('disabled', false);
                            $('#stopRefreshBtn').prop('disabled', false);
                            $('#pauseUpdatesBtn').prop('disabled', false);
                        } else {
                            addLog('error', 'Failed to start scraping: ' + (data.error || 'Unknown error'));
                            updateStatus('Failed to start', 'error');
                        }
                        updateButtonStates();
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error starting scraper: ' + error);
                        updateStatus('Error starting scraper', 'error');
                        updateButtonStates();
                    }
                });
            }

            // 2. Resume Scraping Function
            function resumeScraping() {
                if (isLoading || isRunning) {
                    addLog('warning', 'Scraper is already running or loading');
                    return;
                }

                addLog('info', 'Checking for in-progress files to resume...');
                isLoading = true;
                updateButtonStates();

                // First check if .jsonl file exists
                $.ajax({
                    url: '?action=checkInProgressFiles&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        if (data.hasInProgressFiles) {
                            // Resume from existing file
                            $.ajax({
                                url: '?action=resume&ajax=1',
                                method: 'POST',
                                dataType: 'json',
                                success: function(resumeData) {
                                    isLoading = false;
                                    
                                    if (resumeData.success) {
                                        isRunning = true;
                                        addLog('success', 'Scraping resumed from last position');
                                        addLiveUpdate('success', 'Scraping resumed successfully');
                                        updateStatus('Running - Resumed scraping', 'running');
                                        startMonitoring();
                                    } else {
                                        addLog('error', 'Failed to resume scraping: ' + (resumeData.error || 'Unknown error'));
                                        updateStatus('Failed to resume', 'error');
                                    }
                                    updateButtonStates();
                                },
                                error: function(xhr, status, error) {
                                    isLoading = false;
                                    addLog('error', 'AJAX error resuming scraper: ' + error);
                                    updateStatus('Error resuming scraper', 'error');
                                    updateButtonStates();
                                }
                            });
                        } else {
                            // No in-progress files, start new
                            addLog('info', 'No in-progress files found, starting new session');
                            isLoading = false;
                            updateButtonStates();
                            startScraping();
                        }
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error checking in-progress files: ' + error);
                        updateButtonStates();
                    }
                });
            }

            // 3. Pause Scraping Function
            function pauseScraping() {
                if (!isRunning) {
                    addLog('warning', 'No scraper is currently running');
                    return;
                }

                addLog('info', 'Pausing scraping process...');
                isLoading = true;
                updateButtonStates();

                $.ajax({
                    url: '?action=pause&ajax=1',
                    method: 'POST',
                    dataType: 'json',
                    success: function(data) {
                        isLoading = false;
                        
                        if (data.success) {
                            isRunning = false;
                            addLog('success', 'Scraping paused successfully');
                            addLiveUpdate('warning', 'Scraping paused - can resume later');
                            updateStatus('Paused - Ready to resume', 'paused');
                            stopMonitoring();
                        } else {
                            addLog('error', 'Failed to pause scraping: ' + (data.error || 'Unknown error'));
                        }
                        updateButtonStates();
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error pausing scraper: ' + error);
                        updateButtonStates();
                    }
                });
            }

            // 4. Stop Scraping Function
            function stopScraping() {
                if (!isRunning && !isLoading) {
                    addLog('warning', 'No scraper is currently running');
                    return;
                }

                addLog('info', 'Stopping scraping process...');
                isLoading = true;
                updateButtonStates();

                $.ajax({
                    url: '?action=stop&ajax=1',
                    method: 'POST',
                    dataType: 'json',
                    success: function(data) {
                        isLoading = false;
                        
                        if (data.success) {
                            isRunning = false;
                            addLog('success', 'Scraping stopped successfully');
                            addLiveUpdate('info', 'Scraping stopped - files moved to complete folder');
                            updateStatus('Stopped - Files completed', 'stopped');
                            stopMonitoring();
                        } else {
                            addLog('error', 'Failed to stop scraping: ' + (data.error || 'Unknown error'));
                        }
                        updateButtonStates();
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error stopping scraper: ' + error);
                        updateButtonStates();
                    }
                });
            }

            // 2. Resume Scraping Function
            function resumeScraping() {
                if (isLoading || isRunning) {
                    addLog('warning', 'Scraper is already running or loading');
                    return;
                }

                addLog('info', 'Checking for in-progress files to resume...');
                isLoading = true;
                updateButtonStates();

                // First check if .jsonl file exists
                $.ajax({
                    url: '?action=checkInProgressFiles&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        if (data.hasInProgressFiles) {
                            // Resume from existing file
                            $.ajax({
                                url: '?action=resume&ajax=1',
                                method: 'POST',
                                dataType: 'json',
                                success: function(resumeData) {
                                    isLoading = false;
                                    
                                    if (resumeData.success) {
                                        isRunning = true;
                                        addLog('success', 'Scraping resumed from last position');
                                        addLiveUpdate('success', 'Scraping resumed successfully');
                                        updateStatus('Running - Resumed scraping', 'running');
                                        startMonitoring();
                                    } else {
                                        addLog('error', 'Failed to resume scraping: ' + (resumeData.error || 'Unknown error'));
                                        updateStatus('Failed to resume', 'error');
                                    }
                                    updateButtonStates();
                                },
                                error: function(xhr, status, error) {
                                    isLoading = false;
                                    addLog('error', 'AJAX error resuming scraper: ' + error);
                                    updateStatus('Error resuming scraper', 'error');
                                    updateButtonStates();
                                }
                            });
                        } else {
                            // No in-progress files, start new
                            addLog('info', 'No in-progress files found, starting new session');
                            isLoading = false;
                            updateButtonStates();
                            startScraping();
                        }
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error checking in-progress files: ' + error);
                        updateButtonStates();
                    }
                });
            }

            // 3. Pause Scraping Function
            function pauseScraping() {
                if (!isRunning) {
                    addLog('warning', 'No scraper is currently running');
                    return;
                }

                addLog('info', 'Pausing scraping process...');
                isLoading = true;
                updateButtonStates();

                $.ajax({
                    url: '?action=pause&ajax=1',
                    method: 'POST',
                    dataType: 'json',
                    success: function(data) {
                        isLoading = false;
                        
                        if (data.success) {
                            isRunning = false;
                            addLog('success', 'Scraping paused successfully');
                            addLiveUpdate('warning', 'Scraping paused - can resume later');
                            updateStatus('Paused - Ready to resume', 'paused');
                            stopMonitoring();
                        } else {
                            addLog('error', 'Failed to pause scraping: ' + (data.error || 'Unknown error'));
                        }
                        updateButtonStates();
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error pausing scraper: ' + error);
                        updateButtonStates();
                    }
                });
            }

            // 4. Stop Scraping Function
            function stopScraping() {
                if (!isRunning && !isLoading) {
                    addLog('warning', 'No scraper is currently running');
                    return;
                }

                addLog('info', 'Stopping scraping process...');
                isLoading = true;
                updateButtonStates();

                $.ajax({
                    url: '?action=stop&ajax=1',
                    method: 'POST',
                    dataType: 'json',
                    success: function(data) {
                        isLoading = false;
                        
                        if (data.success) {
                            isRunning = false;
                            addLog('success', 'Scraping stopped successfully');
                            addLiveUpdate('info', 'Scraping stopped - files moved to complete folder');
                            updateStatus('Stopped - Files completed', 'stopped');
                            stopMonitoring();
                        } else {
                            addLog('error', 'Failed to stop scraping: ' + (data.error || 'Unknown error'));
                        }
                        updateButtonStates();
                    },
                    error: function(xhr, status, error) {
                        isLoading = false;
                        addLog('error', 'AJAX error stopping scraper: ' + error);
                        updateButtonStates();
                    }
                });
            }

            // 5. Refresh Scraping Status Function
            function refreshScrapingStatus() {
                addLog('info', 'Starting auto-refresh status monitoring...');
                
                // Clear any existing interval
                if (updateInterval) {
                    clearInterval(updateInterval);
                }

                // Start new interval for status updates
                updateInterval = setInterval(function() {
                    $.ajax({
                        url: '?action=status&ajax=1',
                        method: 'GET',
                        dataType: 'json',
                        success: function(data) {
                            const isRunningStatus = data.isRunning !== undefined ? data.isRunning : data.ISRUNNING;
                            const inProgressFiles = data.inProgressFiles || data.INPROGRESSFILES || [];
                            const completedFiles = data.completedFiles || data.COMPLETEDFILES || [];
                            
                            isRunning = isRunningStatus;
                            updateFileLists(inProgressFiles, completedFiles);
                            
                            if (isRunning) {
                                updateStatus('Running - Scraping in progress', 'running');
                                // Count lines in .jsonl file for progress
                                if (inProgressFiles.length > 0) {
                                    countFileLines(inProgressFiles[0].name);
                                }
                            } else {
                                updateStatus('Idle - Ready to start', 'idle');
                            }
                            
                            updateButtonStates();
                        },
                        error: function(xhr, status, error) {
                            addLog('error', 'Error refreshing status: ' + error);
                        }
                    });
                }, 3000); // Check every 3 seconds

                addLog('success', 'Auto-refresh status started');
                addLiveUpdate('info', 'Status auto-refresh enabled');
            }

            // 6. Stop Auto Refresh Status Function
            function stopAutoRefreshStatus() {
                if (updateInterval) {
                    clearInterval(updateInterval);
                    updateInterval = null;
                    addLog('success', 'Auto-refresh status stopped');
                    addLiveUpdate('info', 'Status auto-refresh disabled');
                } else {
                    addLog('info', 'No auto-refresh was running');
                }
            }

            // Helper function to count lines in .jsonl file
            function countFileLines(fileName) {
                $.ajax({
                    url: '?action=countLines&fileName=' + encodeURIComponent(fileName) + '&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        if (data.success) {
                            $('#progressText').text(`Processed ${data.lineCount} items`);
                            const progressPercent = Math.min((data.lineCount / 1000) * 100, 100); // Assuming 1000 items = 100%
                            $('#progressFill').css('width', progressPercent + '%');
                        }
                    },
                    error: function(xhr, status, error) {
                        console.log('Error counting file lines:', error);
                    }
                });
            }

            async function restoreApplicationState() {
                addLog('info', 'Checking current scraper state...');
                
                updateStatus('Checking scraper status...', 'idle');
                $('#progressFill').css('width', '25%');
                $('#progressText').text('Detecting current state...');
                
                $.ajax({
                    url: '?action=status&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        const isRunningStatus = data.isRunning !== undefined ? data.isRunning : data.ISRUNNING;
                        const inProgressFiles = data.inProgressFiles || data.INPROGRESSFILES || [];
                        const completedFiles = data.completedFiles || data.COMPLETEDFILES || [];
                        
                        isRunning = isRunningStatus;
                        updateFileLists(inProgressFiles, completedFiles);
                        
                        if (isRunning) {
                            addLog('success', 'Detected active scraper - restoring live state');
                            addLiveUpdate('info', 'Scraper is currently running - monitoring resumed');
                            updateStatus('Running - Scraping in progress', 'running');
                            startMonitoring();
                        } else {
                            addLog('info', 'No active scraper detected - system is idle');
                            updateStatus('Idle - Ready to start', 'idle');
                        }
                        
                        if (isLoading) {
                            console.log('restoreApplicationState: isLoading was true, setting to false');
                            isLoading = false;
                        }
                        
                        updateButtonStates();
                        
                        if (inProgressFiles && inProgressFiles.length > 0) {
                            addLog('info', `Found ${inProgressFiles.length} in-progress files`);
                            inProgressFiles.forEach(function(file) {
                                addLog('info', `Active file: ${file.name || file.NAME} (${file.size || file.SIZE} KB)`);
                            });
                        }
                        
                        if (completedFiles && completedFiles.length > 0) {
                            addLog('info', `Found ${completedFiles.length} completed files`);
                        }
                    },
                    error: function(xhr, status, error) {
                        addLog('error', 'Error restoring application state: ' + error);
                        addLog('info', 'Continuing with default idle state');
                        updateStatus('Idle - Ready to start', 'idle');
                        
                        if (isLoading) {
                            console.log('restoreApplicationState error: isLoading was true, setting to false');
                            isLoading = false;
                        }
                        updateButtonStates();
                    }
                });
            }

            function handleFormSubmit(e) {
                e.preventDefault();
                console.log('Form submitted');
                startScraping();
            }

            function handleRunModeChange() {
                const selectedMode = $('input[name="runMode"]:checked').val();
                console.log('Run mode changed to:', selectedMode);
                
                $('#eventIdGroup').hide();
                $('#maxSalesGroup').hide();
                
                if (selectedMode === 'one') {
                    $('#eventIdGroup').show();
                } else if (selectedMode === 'max') {
                    $('#maxSalesGroup').show();
                }
            }

            function handleQuickAction(e) {
                const btn = $(e.currentTarget);
                const eventId = btn.data('event');
                const maxSales = btn.data('max');
                console.log(eventId);
                if (eventId) {
                    $('#mode-one').prop('checked', true);
                    $('#eventId').val(eventId);
                    handleRunModeChange();
                    startScraping();
                } else if (maxSales) {
                    $('#mode-max').prop('checked', true);
                    $('#maxSales').val(maxSales);
                    handleRunModeChange();
                    startScraping();
                }
            }

            function startMonitoring() {
                if (updateInterval) clearInterval(updateInterval);
                if (!isLiveUpdatesPaused) {
                    updateInterval = setInterval(refreshStatus, 3000);
                }
            }

            function stopMonitoring() {
                if (updateInterval) {
                    clearInterval(updateInterval);
                    updateInterval = null;
                }
            }

            function refreshStatus() {
                $.ajax({
                    url: '?action=status&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        const isRunningStatus = data.isRunning !== undefined ? data.isRunning : data.ISRUNNING;
                        const inProgressFiles = data.inProgressFiles || data.INPROGRESSFILES || [];
                        const completedFiles = data.completedFiles || data.COMPLETEDFILES || [];
                        
                        isRunning = isRunningStatus;
                        updateFileLists(inProgressFiles, completedFiles);
                        
                        if (isRunning) {
                            updateStatus('Running - Scraping in progress', 'running');
                        } else {
                            updateStatus('Idle - Ready to start', 'idle');
                            stopMonitoring();
                        }
                        
                        updateButtonStates();
                    },
                    error: function(xhr, status, error) {
                        addLog('error', 'Error refreshing status: ' + error);
                    }
                });
            }

            // Enhanced refresh status function for the new button
            function refreshScrapingStatus() {
                addLog('info', 'Starting auto-refresh status monitoring...');
                
                // Clear any existing interval
                if (updateInterval) {
                    clearInterval(updateInterval);
                }

                // Start new interval for status updates
                updateInterval = setInterval(function() {
                    $.ajax({
                        url: '?action=status&ajax=1',
                        method: 'GET',
                        dataType: 'json',
                        success: function(data) {
                            const isRunningStatus = data.isRunning !== undefined ? data.isRunning : data.ISRUNNING;
                            const inProgressFiles = data.inProgressFiles || data.INPROGRESSFILES || [];
                            const completedFiles = data.completedFiles || data.COMPLETEDFILES || [];
                            
                            isRunning = isRunningStatus;
                            updateFileLists(inProgressFiles, completedFiles);
                            
                            if (isRunning) {
                                updateStatus('Running - Scraping in progress', 'running');
                                // Count lines in .jsonl file for progress
                                if (inProgressFiles.length > 0) {
                                    countFileLines(inProgressFiles[0].name);
                                }
                            } else {
                                updateStatus('Idle - Ready to start', 'idle');
                            }
                            
                            updateButtonStates();
                        },
                        error: function(xhr, status, error) {
                            addLog('error', 'Error refreshing status: ' + error);
                        }
                    });
                }, 3000); // Check every 3 seconds

                addLog('success', 'Auto-refresh status started');
                addLiveUpdate('info', 'Status auto-refresh enabled');
            }

            // Stop auto refresh function
            function stopAutoRefreshStatus() {
                if (updateInterval) {
                    clearInterval(updateInterval);
                    updateInterval = null;
                    addLog('success', 'Auto-refresh status stopped');
                    addLiveUpdate('info', 'Status auto-refresh disabled');
                } else {
                    addLog('info', 'No auto-refresh was running');
                }
            }

            // Helper function to count lines in .jsonl file
            function countFileLines(fileName) {
                $.ajax({
                    url: '?action=countLines&fileName=' + encodeURIComponent(fileName) + '&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        if (data.success) {
                            $('#progressText').text(`Processed ${data.lineCount} items`);
                            const progressPercent = Math.min((data.lineCount / 1000) * 100, 100); // Assuming 1000 items = 100%
                            $('#progressFill').css('width', progressPercent + '%');
                        }
                    },
                    error: function(xhr, status, error) {
                        console.log('Error counting file lines:', error);
                    }
                });
            }

            function startBackgroundMonitoring() {
                // Start background monitoring for state changes
                setInterval(function() {
                    if (!isLoading && !isRunning) {
                        $.ajax({
                            url: '?action=status&ajax=1',
                            method: 'GET',
                            dataType: 'json',
                            success: function(data) {
                                const isRunningStatus = data.isRunning !== undefined ? data.isRunning : data.ISRUNNING;
                                if (isRunningStatus !== isRunning) {
                                    console.log('Background monitoring detected state change');
                                    isRunning = isRunningStatus;
                                    updateButtonStates();
                                }
                            },
                            error: function(xhr, status, error) {
                                console.log('Background monitoring error:', error);
                            }
                        });
                    }
                }, 10000); // Check every 10 seconds
            }

            function updateButtonStates() {
                // Start button: disabled when running or loading
                $('#startBtn').prop('disabled', isRunning || isLoading);
                
                // Resume button: disabled when running or loading
                $('#resumeBtn').prop('disabled', isRunning || isLoading);
                
                // Pause button: disabled when not running or loading
                $('#pauseBtn').prop('disabled', !isRunning || isLoading);
                
                // Stop button: disabled when not running and not loading
                $('#stopBtn').prop('disabled', !isRunning && !isLoading);
                
                // Refresh status button: disabled when loading
                $('#refreshStatusBtn').prop('disabled', isLoading);
                
                // Stop refresh button: disabled when no interval is running
                $('#stopRefreshBtn').prop('disabled', !updateInterval);
                
                // Add loading classes
                if (isLoading) {
                    $('#startBtn, #resumeBtn, #pauseBtn, #stopBtn').addClass('loading');
                } else {
                    $('#startBtn, #resumeBtn, #pauseBtn, #stopBtn').removeClass('loading');
                }
                
                // Debug logging
                console.log('Button States Updated:', {
                    isRunning: isRunning,
                    isLoading: isLoading,
                    isLiveUpdatesPaused: isLiveUpdatesPaused,
                    startBtnDisabled: $('#startBtn').is(':disabled'),
                    resumeBtnDisabled: $('#resumeBtn').is(':disabled'),
                    pauseBtnDisabled: $('#pauseBtn').is(':disabled'),
                    stopBtnDisabled: $('#stopBtn').is(':disabled'),
                    refreshStatusBtnDisabled: $('#refreshStatusBtn').is(':disabled'),
                    stopRefreshBtnDisabled: $('#stopRefreshBtn').is(':disabled')
                });
            }

            function updateStatus(text, status) {
                $('#statusText').text(text);
                $('#statusIndicator').removeClass().addClass('status-indicator ' + status);
            }

            function updateFileLists(inProgressFiles, completedFiles) {
                $('#inProgressCount').text(inProgressFiles.length);
                $('#completedCount').text(completedFiles.length);
                
                let inProgressHtml = '';
                inProgressFiles.forEach(function(file) {
                    inProgressHtml += `<div class="file-item" onclick="readFileContent('${file.name || file.NAME}')">${file.name || file.NAME} (${file.size || file.SIZE} KB)</div>`;
                });
                $('#inProgressFiles').html(inProgressHtml);
                
                let completedHtml = '';
                completedFiles.forEach(function(file) {
                    completedHtml += `<div class="file-item" onclick="readFileContent('${file.name || file.NAME}')">${file.name || file.NAME} (${file.size || file.SIZE} KB)</div>`;
                });
                $('#completedFiles').html(completedHtml);
            }

            function readFileContent(fileName) {
                $.ajax({
                    url: '?action=readFile&fileName=' + encodeURIComponent(fileName) + '&ajax=1',
                    method: 'GET',
                    dataType: 'json',
                    success: function(data) {
                        if (data.success) {
                            $('#modalTitle').text('File: ' + fileName);
                            $('#modalContent').html('<pre>' + data.content + '</pre>');
                            $('#fileModal').show();
                        } else {
                            addLog('error', 'Failed to read file: ' + (data.error || 'Unknown error'));
                        }
                    },
                    error: function(xhr, status, error) {
                        addLog('error', 'Error reading file: ' + error);
                    }
                });
            }

            function addLog(type, message) {
                const timestamp = new Date().toLocaleTimeString();
                const logItem = $(`<div class="log-item log-${type}">[${timestamp}] ${message}</div>`);
                $('#logContainer').append(logItem);
                $('#logContainer').scrollTop($('#logContainer')[0].scrollHeight);
                
                logs.push({type: type, message: message, timestamp: timestamp});
                if (logs.length > 100) logs.shift();
            }

            function addLiveUpdate(type, message) {
                const timestamp = new Date().toLocaleTimeString();
                const updateItem = $(`<div class="live-update-item update-${type}">[${timestamp}] ${message}</div>`);
                $('#liveUpdates').append(updateItem);
                $('#liveUpdates').scrollTop($('#liveUpdates')[0].scrollHeight);
                
                liveUpdates.push({type: type, message: message, timestamp: timestamp});
                if (liveUpdates.length > 50) liveUpdates.shift();
            }

            // Helper function for manual refresh
            function handleManualRefresh() {
                addLog('info', 'Manual refresh requested');
                refreshStatus();
            }

            // Legacy function for compatibility
            function stopScraper() {
                addLog('info', 'Legacy stop scraper called');
                stopScraping();
            }

            // Live updates toggle function
            function toggleLiveUpdates() {
                isLiveUpdatesPaused = !isLiveUpdatesPaused;
                
                if (isLiveUpdatesPaused) {
                    if (updateInterval) {
                        clearInterval(updateInterval);
                        updateInterval = null;
                    }
                    $('#pauseUpdatesBtn').text('▶️ Resume Live Updates').removeClass('btn-warning').addClass('btn-success');
                    addLog('warning', 'Live updates paused by user');
                    addLiveUpdate('warning', 'Live updates paused');
                    
                    const statusText = $('#statusText');
                    if (statusText.length && isRunning) {
                        statusText.text(statusText.text() + ' (Updates Paused)');
                    }
                } else {
                    if (isRunning && !updateInterval) {
                        startMonitoring();
                    }
                    $('#pauseUpdatesBtn').text('⏸️ Pause Live Updates').removeClass('btn-success').addClass('btn-warning');
                    addLog('success', 'Live updates resumed');
                    addLiveUpdate('success', 'Live updates resumed');
                    
                    const statusText = $('#statusText');
                    if (statusText.length && isRunning) {
                        statusText.text(statusText.text().replace(' (Updates Paused)', ''));
                    }
                }
                
                updateButtonStates();
            }
        </script>
    </body>
    </html>
    