<cfscript>
    // Get form parameters
    startDate = form.startDate ?: "";
    endDate = form.endDate ?: "";
    sourceType = form.sourceType ?: "";
    
    // Build the query based on filters
    whereClause = "WHERE 1=1";
    params = [];
    paramIndex = 1;
    
    if (len(startDate)) {
        whereClause &= " AND created_at >= ?";
        arrayAppend(params, startDate & " 00:00:00");
        paramIndex++;
    }
    
    if (len(endDate)) {
        whereClause &= " AND created_at <= ?";
        arrayAppend(params, endDate & " 23:59:59");
        paramIndex++;
    }
    
    if (len(sourceType)) {
        whereClause &= " AND file_name LIKE ?";
        arrayAppend(params, "%" & sourceType & "%");
        paramIndex++;
    }
    
    // Query the database
    sql = "SELECT file_name, status, created_at, processed_at FROM uploaded_files " & whereClause & " ORDER BY created_at DESC";
    
    try {
        cfquery(name="exportData" datasource="#application.db.dsn#">
            #preserveSingleQuotes(sql)#
            <cfloop array="#params#" index="param">
                <cfqueryparam value="#param#" cfsqltype="cf_sql_varchar">
            </cfloop>
        </cfquery>
        
        // Set response headers for CSV download
        filename = "export_" & dateFormat(now(), "yyyy-mm-dd") & "_" & timeFormat(now(), "HH-mm-ss") & ".csv";
        
        response.setHeader("Content-Disposition", "attachment; filename=" & filename);
        response.setHeader("Content-Type", "text/csv");
        
        // Output CSV header
        writeOutput("File Name,Status,Created At,Processed At" & chr(13) & chr(10));
        
        // Output data rows
        cfloop query="exportData">
            writeOutput('"#replace(exportData.file_name, '"', '""', 'all')#","#exportData.status#","#dateFormat(exportData.created_at, 'yyyy-mm-dd HH:mm:ss')#","#dateFormat(exportData.processed_at, 'yyyy-mm-dd HH:mm:ss')#"#chr(13)##chr(10)#');
        </cfloop>
        
    } catch (any e) {
        // If there's an error, redirect back to dashboard with error message
        location(url="dashboard.cfm?error=" & urlEncodedFormat("Export failed: " & e.message), addToken=false);
    }
</cfscript>
