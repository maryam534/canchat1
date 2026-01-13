<!---
    Direct Tika Test - Minimal debugging
--->

<h1>Direct Tika Command Test</h1>

<cfscript>
    // Test parameters
    testFilePath = "C:\inetpub\wwwroot\canchat1\uploads\The 23 Rules of Storytelling for VCs3.pdf";
    tikaJarPath = application.processing.tikaPath;
    
    writeOutput("<p><strong>Test File:</strong> " & testFilePath & "</p>");
    writeOutput("<p><strong>File Exists:</strong> " & fileExists(testFilePath) & "</p>");
    writeOutput("<p><strong>Tika JAR:</strong> " & tikaJarPath & "</p>");
    writeOutput("<p><strong>JAR Exists:</strong> " & fileExists(tikaJarPath) & "</p>");
</cfscript>

<h2>Test 1: Java Version</h2>
<cftry>
    <cfexecute name="java" arguments="-version" variable="javaVer" errorVariable="javaErr" timeout="10">
    <cfoutput>
        <p>✅ Java available</p>
        <pre style="background: ##f5f5f5; padding: 10px;">#javaErr#</pre>
    </cfoutput>
    
    <cfcatch>
        <cfoutput>
            <p>❌ Java not available: #cfcatch.message#</p>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 2: Tika Help</h2>
<cftry>
    <cfexecute name="java" arguments='-jar "#tikaJarPath#" --help' variable="tikaHelp" errorVariable="tikaHelpErr" timeout="15">
    <cfoutput>
        <p>✅ Tika JAR executable</p>
        <pre style="background: ##f5f5f5; padding: 10px; max-height: 150px; overflow-y: auto;">#left(tikaHelp, 500)#</pre>
    </cfoutput>
    
    <cfcatch>
        <cfoutput>
            <p>❌ Tika JAR failed: #cfcatch.message#</p>
            <cfif isDefined("tikaHelpErr") AND len(tikaHelpErr)>
                <p><strong>Error output:</strong> #tikaHelpErr#</p>
            </cfif>
        </cfoutput>
    </cfcatch>
</cftry>

<cfif fileExists(testFilePath)>
    <h2>Test 3: Extract Text from Your PDF</h2>
    <cftry>
        <cfexecute name="java" arguments='-jar "#tikaJarPath#" --text "#testFilePath#"' variable="extractedText" errorVariable="extractErr" timeout="30">
        <cfoutput>
            <p>✅ Text extraction successful!</p>
            <p><strong>Text Length:</strong> #len(extractedText)# characters</p>
            <p><strong>Preview:</strong></p>
            <div style="background: ##f9f9f9; padding: 10px; border: 1px solid ##ddd; max-height: 200px; overflow-y: auto;">
                #left(extractedText, 500)#...
            </div>
        </cfoutput>
        
        <cfcatch>
            <cfoutput>
                <p>❌ Text extraction failed: #cfcatch.message#</p>
                <p><strong>Type:</strong> #cfcatch.type#</p>
                <p><strong>Detail:</strong> #cfcatch.detail#</p>
                <cfif isDefined("extractErr") AND len(extractErr)>
                    <p><strong>Tika Error Output:</strong></p>
                    <pre style="background: ##ffe6e6; padding: 10px;">#extractErr#</pre>
                </cfif>
            </cfoutput>
        </cfcatch>
    </cftry>
<cfelse>
    <div style="background: ##fff3cd; padding: 15px; border-radius: 5px;">
        <p><strong>File not found:</strong> #testFilePath#</p>
        <p>Please upload a file first or check the file path.</p>
    </div>
</cfif>

<h2>Alternative File Paths to Try</h2>
<cfscript>
    uploadsDir = application.paths.uploadsDir;
    writeOutput("<p><strong>Uploads Directory:</strong> " & uploadsDir & "</p>");
    
    if (directoryExists(uploadsDir)) {
        files = directoryList(uploadsDir, false, "name", "*.pdf");
        if (arrayLen(files) > 0) {
            writeOutput("<p><strong>PDF files found:</strong></p><ul>");
            for (file in files) {
                fullPath = uploadsDir & "/" & file;
                writeOutput("<li><a href='?testFile=" & urlEncodedFormat(fullPath) & "'>" & file & "</a></li>");
            }
            writeOutput("</ul>");
        } else {
            writeOutput("<p>No PDF files found in uploads directory.</p>");
        }
    }
</cfscript>

<cfif structKeyExists(url, "testFile") AND fileExists(url.testFile)>
    <h2>Test with Selected File: <cfoutput>#getFileFromPath(url.testFile)#</cfoutput></h2>
    <cftry>
        <cfexecute name="java" arguments='-jar "#tikaJarPath#" --text "#url.testFile#"' variable="selectedText" errorVariable="selectedErr" timeout="30">
        <cfoutput>
            <p>✅ Extraction successful for selected file!</p>
            <p><strong>Length:</strong> #len(selectedText)# characters</p>
            <div style="background: ##f0f8ff; padding: 10px; border: 1px solid ##ccc; max-height: 200px; overflow-y: auto;">
                #left(selectedText, 500)#...
            </div>
        </cfoutput>
        
        <cfcatch>
            <cfoutput>
                <p>❌ Failed: #cfcatch.message#</p>
                <cfif isDefined("selectedErr")>
                    <p><strong>Error:</strong> #selectedErr#</p>
                </cfif>
            </cfoutput>
        </cfcatch>
    </cftry>
</cfif>

<p><a href="upload.cfm">← Back to Upload</a></p>
