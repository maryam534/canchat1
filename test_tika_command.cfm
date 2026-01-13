<!---
    Test Tika Command Line Approach
--->

<h1>Tika Command Line Test</h1>

<cfscript>
    tikaJarPath = application.processing.tikaPath;
    writeOutput("<p><strong>Tika JAR Path:</strong> " & tikaJarPath & "</p>");
    writeOutput("<p><strong>Tika JAR Exists:</strong> " & fileExists(tikaJarPath) & "</p>");
</cfscript>

<h2>Test 1: Java Version Check</h2>
<cftry>
    <cfexecute name="java" arguments="-version" variable="javaVersion" errorVariable="javaError" timeout="10">
    <cfoutput>
        <p>✅ <strong>Java Available</strong></p>
        <pre style="background: ##f5f5f5; padding: 10px;">#javaError#</pre>
    </cfoutput>
    
    <cfcatch>
        <cfoutput>
            <p>❌ <strong>Java Not Available:</strong> #cfcatch.message#</p>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 2: Tika JAR Test</h2>
<cftry>
    <cfexecute name="java" arguments='-jar "#tikaJarPath#" --help' variable="tikaHelp" errorVariable="tikaHelpError" timeout="15">
    <cfoutput>
        <p>✅ <strong>Tika JAR Executable</strong></p>
        <pre style="background: ##f5f5f5; padding: 10px; max-height: 200px; overflow-y: auto;">#left(tikaHelp, 1000)#</pre>
    </cfoutput>
    
    <cfcatch>
        <cfoutput>
            <p>❌ <strong>Tika JAR Failed:</strong> #cfcatch.message#</p>
            <cfif len(tikaHelpError)>
                <p><strong>Error output:</strong> #tikaHelpError#</p>
            </cfif>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 3: Create Sample Text File and Extract</h2>
<cfscript>
    // Create a sample text file
    sampleText = "This is a sample document for testing text extraction. It contains multiple sentences to verify that our RAG system can properly extract and process text content from uploaded documents.";
    sampleFilePath = expandPath("./temp/sample_test.txt");
    
    if (!directoryExists(expandPath("./temp"))) {
        directoryCreate(expandPath("./temp"));
    }
    
    fileWrite(sampleFilePath, sampleText);
    writeOutput("<p><strong>Sample file created:</strong> " & sampleFilePath & "</p>");
</cfscript>

<cftry>
    <cfexecute name="java" arguments='-jar "#tikaJarPath#" --text "#sampleFilePath#"' variable="extractedSample" errorVariable="sampleError" timeout="15">
    <cfoutput>
        <p>✅ <strong>Sample Text Extraction Success</strong></p>
        <p><strong>Original:</strong> #sampleText#</p>
        <p><strong>Extracted:</strong> #trim(extractedSample)#</p>
        <p><strong>Match:</strong> #trim(extractedSample) == sampleText ? "Perfect!" : "Different but readable"#</p>
    </cfoutput>
    
    <cfcatch>
        <cfoutput>
            <p>❌ <strong>Sample Extraction Failed:</strong> #cfcatch.message#</p>
            <cfif len(sampleError)>
                <p><strong>Error output:</strong> #sampleError#</p>
            </cfif>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 4: Check Uploads Directory</h2>
<cfscript>
    uploadsDir = application.paths.uploadsDir;
    writeOutput("<p><strong>Uploads Directory:</strong> " & uploadsDir & "</p>");
    writeOutput("<p><strong>Directory Exists:</strong> " & directoryExists(uploadsDir) & "</p>");
    
    if (directoryExists(uploadsDir)) {
        files = directoryList(uploadsDir, false, "name");
        writeOutput("<p><strong>Files in uploads:</strong> " & arrayLen(files) & "</p>");
        
        if (arrayLen(files) > 0) {
            writeOutput("<ul>");
            for (file in files) {
                filePath = uploadsDir & "/" & file;
                fileInfo = getFileInfo(filePath);
                writeOutput("<li><strong>" & file & "</strong> (" & numberFormat(fileInfo.size/1024, "999.9") & " KB) - ");
                writeOutput('<a href="?testFile=' & urlEncodedFormat(filePath) & '">Test Extract</a></li>');
            }
            writeOutput("</ul>");
        }
    }
</cfscript>

<cfif structKeyExists(url, "testFile") AND fileExists(url.testFile)>
    <h2>Test 5: Extract from Uploaded File</h2>
    <cfscript>
        testFilePath = url.testFile;
        testFileExt = lcase(listLast(getFileFromPath(testFilePath), "."));
    </cfscript>
    
    <cfoutput>
        <p><strong>Testing file:</strong> #getFileFromPath(testFilePath)#</p>
        <p><strong>Extension:</strong> #testFileExt#</p>
    </cfoutput>
    
    <cftry>
        <cfif testFileExt == "txt">
            <cfset testExtracted = fileRead(testFilePath) />
            <cfoutput>
                <p>✅ <strong>Direct text read successful</strong></p>
                <p><strong>Length:</strong> #len(testExtracted)# characters</p>
                <p><strong>Preview:</strong> #left(testExtracted, 200)#...</p>
            </cfoutput>
        <cfelse>
            <cfexecute name="java" arguments='-jar "#tikaJarPath#" --text "#testFilePath#"' variable="testExtracted" errorVariable="testError" timeout="30">
            <cfoutput>
                <p>✅ <strong>Tika extraction successful</strong></p>
                <p><strong>Length:</strong> #len(testExtracted)# characters</p>
                <p><strong>Preview:</strong> #left(testExtracted, 200)#...</p>
                <cfif len(testError)>
                    <p><strong>Warnings:</strong> #testError#</p>
                </cfif>
            </cfoutput>
        </cfif>
        
        <cfcatch>
            <cfoutput>
                <p>❌ <strong>Extraction failed:</strong> #cfcatch.message#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
</cfif>

<cfscript>
    // Clean up sample file
    if (fileExists(expandPath("./temp/sample_test.txt"))) {
        fileDelete(expandPath("./temp/sample_test.txt"));
    }
</cfscript>

<div style="margin-top: 30px; padding: 20px; background: ##f0f8ff; border-radius: 8px;">
    <h3>📋 Recommendations:</h3>
    <cfif fileExists(tikaJarPath)>
        <p>✅ Tika JAR is available. The command-line approach should work reliably.</p>
        <p>🔄 Try uploading your document again using the new extraction method.</p>
    <cfelse>
        <p>❌ Tika JAR not found. Please ensure the JAR file exists at the configured path.</p>
    </cfif>
</div>

<p><a href="upload.cfm">← Back to Upload Page</a></p>
