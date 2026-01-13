<!---
    RAG Processing Pipeline
    Processes scraped lots into RAG embeddings automatically
    
    Usage:
    - ?action=process&jobId=X - Process specific job
    - ?action=process_completed - Process all completed jobs that haven't been processed
    - ?action=status - Get processing status
--->
<cfsetting showdebugoutput="false" />
<cfparam name="url.action" default="" />
<cfparam name="url.jobId" default="" />
<cfparam name="form.action" default="#url.action#" />
<cfparam name="form.jobId" default="#url.jobId#" />

<cfscript>
    action = url.action ?: form.action ?: "";
    jobIdParam = url.jobId ?: form.jobId ?: "";
    
    // Include RAG processor component
    include "lib/rag_processor.cfm";
    
    if (action == "process" && len(jobIdParam)) {
        jobId = val(jobIdParam);
        
        // Process the job
        result = processJobLotsForRAG(jobId);
        
        cfheader(name="Content-Type", value="application/json; charset=utf-8");
        writeOutput(serializeJSON(result));
        abort;
        
    } else if (action == "process_completed") {
        // Process all completed jobs that haven't been processed yet
        completedJobs = queryExecute(
            "SELECT id, job_name, completed_at 
             FROM scraper_jobs 
             WHERE status = 'completed' 
             AND (rag_processed_at IS NULL OR rag_processed_at < completed_at)
             ORDER BY completed_at DESC
             LIMIT 10",
            [],
            {datasource = application.db.dsn}
        );
        
        results = [];
        totalProcessed = 0;
        totalFailed = 0;
        
        if (completedJobs.recordCount > 0) {
            for (row in completedJobs) {
                result = processJobLotsForRAG(row.id);
                result.jobId = row.id;
                result.jobName = row.job_name;
                arrayAppend(results, result);
                
                if (result.success) {
                    totalProcessed += result.processed ?: 0;
                    totalFailed += result.failed ?: 0;
                }
            }
        }
        
        cfheader(name="Content-Type", value="application/json; charset=utf-8");
        writeOutput(serializeJSON({
            success: true,
            jobsProcessed: completedJobs.recordCount,
            totalLotsProcessed: totalProcessed,
            totalLotsFailed: totalFailed,
            results: results
        }));
        abort;
        
    } else if (action == "status") {
        // Get processing status
        status = queryExecute(
            "SELECT 
                COUNT(*) as total_jobs,
                SUM(CASE WHEN rag_processed_at IS NOT NULL THEN 1 ELSE 0 END) as processed_jobs,
                SUM(CASE WHEN status = 'completed' AND rag_processed_at IS NULL THEN 1 ELSE 0 END) as pending_jobs
             FROM scraper_jobs
             WHERE status = 'completed'",
            [],
            {datasource = application.db.dsn}
        );
        
        cfheader(name="Content-Type", value="application/json; charset=utf-8");
        writeOutput(serializeJSON({
            totalJobs: status.total_jobs[1],
            processedJobs: status.processed_jobs[1],
            pendingJobs: status.pending_jobs[1]
        }));
        abort;
        
    } else {
        // Default: show simple status page
        cfheader(name="Content-Type", value="text/html; charset=utf-8");
    }
</cfscript>

<!DOCTYPE html>
<html>
<head>
    <title>RAG Processing Pipeline</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">
<div class="max-w-4xl mx-auto">
    <h1 class="text-2xl font-bold mb-4">RAG Processing Pipeline</h1>
    
    <div class="bg-white rounded-lg shadow p-6 mb-4">
        <h2 class="text-xl font-semibold mb-4">Actions</h2>
        <div class="space-y-2">
            <a href="?action=process_completed" class="inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
                Process All Completed Jobs
            </a>
            <a href="?action=status" class="inline-block bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700">
                Check Status
            </a>
        </div>
    </div>
    
    <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-xl font-semibold mb-4">Usage</h2>
        <ul class="list-disc list-inside space-y-2">
            <li><strong>Process specific job:</strong> ?action=process&jobId=X</li>
            <li><strong>Process all completed:</strong> ?action=process_completed</li>
            <li><strong>Check status:</strong> ?action=status</li>
        </ul>
    </div>
</div>
</body>
</html>