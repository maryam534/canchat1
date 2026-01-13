<!---
    Debug Configuration Values
--->

<h1>Configuration Debug</h1>

<h2>Application Paths:</h2>
<cfoutput>
<table border="1" cellpadding="5">
    <tr><td><strong>uploads Directory (config):</strong></td><td>#application.paths.uploadsDir#</td></tr>
    <tr><td><strong>uploads Directory exists:</strong></td><td>#directoryExists(application.paths.uploadsDir)#</td></tr>
    <tr><td><strong>Temp Directory:</strong></td><td>#expandPath('./temp')#</td></tr>
    <tr><td><strong>Temp Directory exists:</strong></td><td>#directoryExists(expandPath('./temp'))#</td></tr>
    <tr><td><strong>Current Directory:</strong></td><td>#expandPath('.')#</td></tr>
    <tr><td><strong>Tika Path:</strong></td><td>#application.processing.tikaPath#</td></tr>
    <tr><td><strong>Tika Exists:</strong></td><td>#fileExists(application.processing.tikaPath)#</td></tr>
</table>
</cfoutput>

<h2>Application Settings:</h2>
<cfoutput>
<table border="1" cellpadding="5">
    <tr><td><strong>App Name:</strong></td><td>#this.name#</td></tr>
    <tr><td><strong>Session Management:</strong></td><td>#this.sessionManagement#</td></tr>
    <tr><td><strong>File Upload Enabled:</strong></td><td>#this.enableFileUpload#</td></tr>
    <tr><td><strong>Max File Size:</strong></td><td>#this.maxFileSize# bytes (#this.maxFileSize/1024/1024# MB)</td></tr>
    <tr><td><strong>Upload Timeout:</strong></td><td>#this.uploadTimeout# seconds</td></tr>
</table>
</cfoutput>

<h2>Environment Variables:</h2>
<cfoutput>
<table border="1" cellpadding="5">
    <tr><td><strong>UPLOADS_DIR:</strong></td><td>#sys("UPLOADS_DIR", "NOT SET")#</td></tr>
    <tr><td><strong>FINAL_DIR:</strong></td><td>#sys("FINAL_DIR", "NOT SET")#</td></tr>
    <tr><td><strong>TIKA_PATH:</strong></td><td>#sys("TIKA_PATH", "NOT SET")#</td></tr>
    <tr><td><strong>OPENAI_API_KEY:</strong></td><td>#len(sys("OPENAI_API_KEY", "")) > 10 ? "SET" : "NOT SET"#</td></tr>
</table>
</cfoutput>

<h2>Directory Creation Test:</h2>
<cfscript>
    testUploadDir = expandPath("./uploads");
    testTempDir = expandPath("./temp");
</cfscript>

<cfoutput>
<p><strong>Test Upload Dir:</strong> #testUploadDir#</p>
<p><strong>Test Temp Dir:</strong> #testTempDir#</p>
</cfoutput>

<cftry>
    <cfif NOT directoryExists(testUploadDir)>
        <cfdirectory action="create" directory="#testUploadDir#" />
        <cfoutput><p><strong>Created uploads directory:</strong> #testUploadDir#</p></cfoutput>
    <cfelse>
        <cfoutput><p><strong>Uploads directory already exists:</strong> #testUploadDir#</p></cfoutput>
    </cfif>
    
    <cfif NOT directoryExists(testTempDir)>
        <cfdirectory action="create" directory="#testTempDir#" />
        <cfoutput><p><strong>Created temp directory:</strong> #testTempDir#</p></cfoutput>
    <cfelse>
        <cfoutput><p><strong>Temp directory already exists:</strong> #testTempDir#</p></cfoutput>
    </cfif>
    
    <cfcatch type="any">
        <cfoutput>
            <p><strong>Directory creation failed:</strong> #cfcatch.message#</p>
            <p><strong>Detail:</strong> #cfcatch.detail#</p>
        </cfoutput>
    </cfcatch>
</cftry>

<p><a href="simple_upload_test.cfm">→ Go to Simple Upload Test</a></p>
<p><a href="index.cfm">← Back to main page</a></p>
