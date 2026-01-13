<!---
    Simple Upload Test - Minimal debugging
--->

<cfif structKeyExists(form, "testFile")>
    <cfoutput>
        <h2>Form Data Received:</h2>
        <p><strong>Form keys:</strong> #structKeyList(form)#</p>
        <p><strong>testFile exists:</strong> #structKeyExists(form, "testFile")#</p>
        
        <cfif structKeyExists(form, "testFile") AND len(form.testFile)>
            <p><strong>File field has value:</strong> Yes</p>
        <cfelse>
            <p><strong>File field has value:</strong> No - this is the problem!</p>
        </cfif>
    </cfoutput>
    
    <cftry>
        <cfset uploadDir = expandPath("./uploads") />
        <cfoutput><p><strong>Upload Directory:</strong> #uploadDir#</p></cfoutput>
        
        <cfif NOT directoryExists(uploadDir)>
            <cfdirectory action="create" directory="#uploadDir#" />
            <cfoutput><p><strong>Created directory:</strong> #uploadDir#</p></cfoutput>
        </cfif>
        
        <cffile action="upload"
                fileField="testFile"
                destination="#uploadDir#"
                nameConflict="makeunique"
                result="uploadResult" />
        
        <cfoutput>
            <h2>Upload Success!</h2>
            <p><strong>Server File:</strong> #uploadResult.serverFile#</p>
            <p><strong>Client File:</strong> #uploadResult.clientFile#</p>
            <p><strong>File Size:</strong> #uploadResult.fileSize# bytes</p>
            <p><strong>Content Type:</strong> #uploadResult.contentType#</p>
            <p><strong>File Written To:</strong> #uploadDir#/#uploadResult.serverFile#</p>
            
            <cfset fullPath = uploadDir & "/" & uploadResult.serverFile />
            <p><strong>File Exists on Disk:</strong> #fileExists(fullPath)#</p>
        </cfoutput>
        
        <cfcatch type="any">
            <cfoutput>
                <h2>Upload Failed!</h2>
                <p><strong>Error:</strong> #cfcatch.message#</p>
                <p><strong>Detail:</strong> #cfcatch.detail#</p>
                <p><strong>Type:</strong> #cfcatch.type#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
<cfelse>
    <!--- Show upload form --->
    <h1>Simple Upload Test</h1>
    <form action="simple_upload_test.cfm" method="post" enctype="multipart/form-data">
        <p>
            <label>Select any file to test:</label><br>
            <input type="file" name="testFile" required>
        </p>
        <p>
            <button type="submit">Test Upload</button>
        </p>
    </form>
    
    <hr>
    <h2>Current Configuration:</h2>
    <cfoutput>
        <p><strong>Application Upload Dir:</strong> #application.paths.uploadsDir#</p>
        <p><strong>Upload Dir Exists:</strong> #directoryExists(application.paths.uploadsDir)#</p>
        <p><strong>Temp Dir:</strong> #expandPath('./temp')#</p>
        <p><strong>Temp Dir Exists:</strong> #directoryExists(expandPath('./temp'))#</p>
    </cfoutput>
</cfif>

<p><a href="index.cfm">← Back to main page</a></p>
