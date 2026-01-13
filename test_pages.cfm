<cfsetting requesttimeout="30" showdebugoutput="false">

<h1>Page Test Results</h1>

<cfscript>
// Test bulk_processor.cfm
try {
    writeOutput("<h2>Testing bulk_processor.cfm</h2>");
    writeOutput("<p>Attempting to include bulk_processor.cfm...</p>");
    
    // Capture output
    savecontent variable="bulkOutput" {
        include "bulk_processor.cfm";
    }
    
    // Check if ColdFusion expressions are processed
    if (findNoCase("#encodeForHtml", bulkOutput)) {
        writeOutput("<p style='color: red;'>❌ ERROR: ColdFusion expressions not processed in bulk_processor.cfm</p>");
        writeOutput("<p>Raw output contains: #encodeForHtml(left(bulkOutput, 500))#...</p>");
    } else {
        writeOutput("<p style='color: green;'>✅ SUCCESS: ColdFusion expressions processed in bulk_processor.cfm</p>");
    }
    
} catch (any e) {
    writeOutput("<p style='color: red;'>❌ ERROR in bulk_processor.cfm: #encodeForHtml(e.message)#</p>");
}

// Test data_processor.cfm
try {
    writeOutput("<h2>Testing data_processor.cfm</h2>");
    writeOutput("<p>Attempting to include data_processor.cfm...</p>");
    
    // Capture output
    savecontent variable="dataOutput" {
        include "data_processor.cfm";
    }
    
    // Check if ColdFusion expressions are processed
    if (findNoCase("#encodeForHtml", dataOutput)) {
        writeOutput("<p style='color: red;'>❌ ERROR: ColdFusion expressions not processed in data_processor.cfm</p>");
        writeOutput("<p>Raw output contains: #encodeForHtml(left(dataOutput, 500))#...</p>");
    } else {
        writeOutput("<p style='color: green;'>✅ SUCCESS: ColdFusion expressions processed in data_processor.cfm</p>");
    }
    
} catch (any e) {
    writeOutput("<p style='color: red;'>❌ ERROR in data_processor.cfm: #encodeForHtml(e.message)#</p>");
}
</cfscript>

<p><a href="bulk_processor.cfm">Go to Bulk Processor</a> | <a href="data_processor.cfm">Go to Data Processor</a></p>
