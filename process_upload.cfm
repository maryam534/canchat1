<!---
    Document Processing Handler
    Extracts text from uploaded documents and creates embeddings
    ColdFusion 2023 Compatible
--->

<cfparam name="url.filePath" default="" />
<cfparam name="url.debug" default="false" />

<!DOCTYPE html>
<html>
<head>
    <title>Document Processing</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">

<div class="max-w-4xl mx-auto">
    <h1 class="text-2xl font-bold mb-4">📄 Document Processing</h1>

<cfscript>
    // Validate file path
    if (!len(url.filePath)) {
        writeOutput("<div class='bg-yellow-50 p-4 rounded'><h3 class='text-yellow-800'>No File Specified</h3><p>Please upload a file first. <a href='file_manager.cfm' class='text-blue-600 underline'>Go to File Manager</a></p></div>");
        writeOutput("</div></body></html>");
        abort;
    }
    
    if (NOT fileExists(url.filePath)) {
        writeLog(file="process_upload_errors", text="File not found: " & url.filePath, type="error");
        writeOutput("<div class='bg-red-50 p-4 rounded'><h3 class='text-red-800'>Error</h3><p>Invalid file path: " & url.filePath & "</p></div>");
        writeOutput("</div></body></html>");
        abort;
    }
    
    // Get configuration
    tikaPath = application.processing.tikaPath;
    chunkSize = application.processing.chunkSize;
    embedModel = application.ai.embedModel;
    openaiKey = replace(application.ai.openaiKey, '"', "", "all");
    apiBaseUrl = application.ai.apiBaseUrl;
    timeout = application.processing.defaultTimeout;
    showDebug = (application.ui.showDebugLogs OR url.debug EQ "true");
    
    writeOutput("<p class='mb-4'><strong>File:</strong> " & getFileFromPath(url.filePath) & "</p>");
    
    if (showDebug) {
        writeOutput("<div class='bg-blue-50 p-4 rounded mb-4'>");
        writeOutput("<h3 class='text-blue-800 font-semibold'>Debug Mode Enabled</h3>");
        writeOutput("<p><strong>File Path:</strong> " & url.filePath & "</p>");
        writeOutput("<p><strong>Tika JAR:</strong> " & tikaPath & "</p>");
        writeOutput("<p><strong>JAR Exists:</strong> " & fileExists(tikaPath) & "</p>");
        writeOutput("</div>");
    }
</cfscript>

<!-- Step 1: Text Extraction -->
<div class="bg-white p-6 rounded-lg shadow mb-4">
    <h2 class="text-lg font-semibold mb-2">🔍 Step 1: Text Extraction</h2>

<cftry>
    <cfscript>
        // Get file extension
        fileExtension = lcase(listLast(getFileFromPath(url.filePath), "."));
        writeLog(file="tika_processing", text="Processing file extension: " & fileExtension, type="information");
        
        if (fileExtension == "txt") {
            // Direct text file reading
            pdfText = fileRead(url.filePath, "utf-8");
            contentType = "text/plain";
            writeLog(file="tika_processing", text="Text file read directly", type="information");
            
        } else {
            // Command-line Tika for other formats
            writeLog(file="tika_processing", text="Using command-line Tika for: " & fileExtension, type="information");
            
            cfexecute(
                name = "java",
                arguments = '-jar "' & tikaPath & '" --text "' & url.filePath & '"',
                variable = "pdfText",
                errorVariable = "tikaError",
                timeout = 60
            );
            
            if (len(tikaError)) {
                writeLog(file="tika_processing", text="Tika stderr: " & tikaError, type="warning");
            }
            
            // Set content type
            switch (fileExtension) {
                case "pdf": contentType = "application/pdf"; break;
                case "doc": contentType = "application/msword"; break;
                case "docx": contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"; break;
                default: contentType = "application/octet-stream";
            }
        }
        
        writeLog(file="tika_processing", text="Text extraction completed", type="information");
        writeLog(file="tika_processing", text="Extracted text length: " & len(pdfText) & " characters", type="information");
    </cfscript>
    
    <cfoutput>
        <p class="text-green-600">✅ Text extracted successfully!</p>
        <p><strong>Content Type:</strong> #contentType#</p>
        <p><strong>Text Length:</strong> #len(pdfText)# characters</p>
        <p><strong>Preview:</strong> #left(pdfText, 150)#...</p>
    </cfoutput>
    
    <cfif showDebug>
        <cfdump var="#pdfText#" label="Extracted Text (Full)" expand="false">
    </cfif>
    
    <cfcatch type="any">
        <cfoutput>
            <p class="text-red-600">❌ Text extraction failed!</p>
            <p><strong>Error:</strong> #cfcatch.message#</p>
            <p><strong>Type:</strong> #cfcatch.type#</p>
            <p><strong>Detail:</strong> #cfcatch.detail#</p>
        </cfoutput>
        
        <cfif showDebug>
            <cfdump var="#cfcatch#" label="Text Extraction Error (Full)" expand="true">
        </cfif>
        
        <cfoutput>
            <div class="mt-4 p-4 bg-yellow-50 rounded">
                <h4 class="text-yellow-800 font-semibold">Diagnostic Information:</h4>
                <p><strong>File Path:</strong> #url.filePath#</p>
                <p><strong>File Exists:</strong> #fileExists(url.filePath)#</p>
                <p><strong>Tika JAR Path:</strong> #tikaPath#</p>
                <p><strong>Tika JAR Exists:</strong> #fileExists(tikaPath)#</p>
                <p><strong>File Extension:</strong> #fileExtension#</p>
            </div>
        </cfoutput>
        <cfabort>
    </cfcatch>
</cftry>

</div>

<!-- Step 2: Save Extracted Text -->
<div class="bg-white p-6 rounded-lg shadow mb-4">
    <h2 class="text-lg font-semibold mb-2">💾 Step 2: Save Extracted Text</h2>

<cftry>
    <cfscript>
        // Store extracted text in temp folder
        tempFolder = expandPath("./temp");
        if (!directoryExists(tempFolder)) {
            directoryCreate(tempFolder);
        }
        
        // Create unique filename
        originalFileName = getFileFromPath(url.filePath);
        timestamp = dateFormat(now(), "yyyymmdd") & "_" & timeFormat(now(), "HHMMSS");
        tempFileName = "extracted_" & timestamp & "_" & originalFileName & ".txt";
        tempFilePath = tempFolder & "/" & tempFileName;
        
        // Write extracted text
        fileWrite(tempFilePath, pdfText);
        
        writeLog(file="tika_commands", text="Extracted text saved to: " & tempFilePath, type="information");
    </cfscript>
    
    <cfoutput>
        <p class="text-green-600">✅ Text saved to temp folder!</p>
        <p><strong>Saved as:</strong> #tempFileName#</p>
        <p><strong>File Size:</strong> #numberFormat(len(pdfText)/1024, "999.9")# KB</p>
    </cfoutput>
    
    <cfcatch type="any">
        <cfoutput>
            <p class="text-red-600">❌ Failed to save text file!</p>
            <p><strong>Error:</strong> #cfcatch.message#</p>
        </cfoutput>
        <cfif showDebug>
            <cfdump var="#cfcatch#" label="File Save Error" expand="false">
        </cfif>
    </cfcatch>
</cftry>

</div>

<!-- Step 3: Create Chunks -->
<div class="bg-white p-6 rounded-lg shadow mb-4">
    <h2 class="text-lg font-semibold mb-2">✂️ Step 3: Create Text Chunks</h2>

<cftry>
    <cfscript>
        // Create chunks
        wordArray = listToArray(htmlEditFormat(pdfText), " ");
        chunks = [];
        
        for (i = 1; i LTE arrayLen(wordArray); i += chunkSize) {
            thisChunkSize = min(chunkSize, arrayLen(wordArray) - i + 1);
            chunk = arraySlice(wordArray, i, thisChunkSize);
            arrayAppend(chunks, arrayToList(chunk, " "));
        }
    </cfscript>
    
    <cfoutput>
        <p class="text-green-600">✅ Text chunked successfully!</p>
        <p><strong>Total Words:</strong> #arrayLen(wordArray)#</p>
        <p><strong>Chunk Size:</strong> #chunkSize# words per chunk</p>
        <p><strong>Chunks Created:</strong> #arrayLen(chunks)#</p>
        <p><strong>Average Chunk Length:</strong> #numberFormat(len(pdfText)/arrayLen(chunks), "999")# characters</p>
    </cfoutput>
    
    <cfcatch type="any">
        <cfoutput>
            <p class="text-red-600">❌ Chunking failed!</p>
            <p><strong>Error:</strong> #cfcatch.message#</p>
        </cfoutput>
        <cfif showDebug>
            <cfdump var="#cfcatch#" label="Chunking Error" expand="false">
        </cfif>
        <cfabort>
    </cfcatch>
</cftry>

</div>

<!-- Step 4: Create Embeddings and Store -->
<div class="bg-white p-6 rounded-lg shadow mb-4">
    <h2 class="text-lg font-semibold mb-2">🤖 Step 4: AI Embeddings & Database Storage</h2>

<cftry>
    <cfscript>
        successfulEmbeddings = 0;
        failedEmbeddings = 0;
        fileName = getFileFromPath(url.filePath);
    </cfscript>
    
    <cfloop array="#chunks#" index="chunkIndex" item="chunkText">
        <cftry>
            <!--- Create embedding via OpenAI --->
            <cfset bodyStruct = {
                "model": embedModel,
                "input": chunkText
            } />
            
            <cfhttp url="#apiBaseUrl#/embeddings" 
                    method="post" 
                    timeout="#timeout#">
                <cfhttpparam type="header" 
                             name="Authorization" 
                             value="Bearer #openaiKey#" />
                <cfhttpparam type="header" 
                             name="Content-Type" 
                             value="application/json" />
                <cfhttpparam type="body" 
                             value="#serializeJSON(bodyStruct)#" />
            </cfhttp>

            <cfset embedResult = DeserializeJSON(cfhttp.filecontent) />
            
            <cfif structKeyExists(embedResult, "data") AND arrayLen(embedResult.data) GT 0>
                <cfset embedding = "[" & ArrayToList(embedResult.data[1].embedding, ",") & "]" />
                
                <!--- Insert into unified chunks table --->
                <cftry>
                    <cfquery datasource="#application.db.dsn#">
                        INSERT INTO chunks (
                            chunk_text, 
                            embedding, 
                            source_type, 
                            source_name, 
                            source_id,
                            chunk_index,
                            chunk_size,
                            content_type,
                            title,
                            embedding_model,
                            metadata
                        )
                        VALUES (
                            <cfqueryparam value="#chunkText#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#embedding#" cfsqltype="cf_sql_varchar">::vector,
                            'document',
                            <cfqueryparam value="#fileName#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#fileName#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#chunkIndex#" cfsqltype="cf_sql_integer">,
                            <cfqueryparam value="#len(chunkText)#" cfsqltype="cf_sql_integer">,
                            <cfqueryparam value="#contentType#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#fileName#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#embedModel#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#serializeJSON({
                                'originalFile': fileName,
                                'fileSize': getFileInfo(url.filePath).size,
                                'uploadDate': now()
                            })#" cfsqltype="cf_sql_varchar">::jsonb
                        )
                    </cfquery>
                    
                    <cfset successfulEmbeddings++ />
                    
                    <cfcatch type="any">
                        <cfset failedEmbeddings++ />
                        <cfif showDebug>
                            <cfdump var="#cfcatch#" label="DB Insert Error - Chunk #chunkIndex#" expand="false">
                        </cfif>
                    </cfcatch>
                </cftry>
                
            <cfelse>
                <cfset failedEmbeddings++ />
                <cfif showDebug>
                    <cfdump var="#embedResult#" label="OpenAI API Error - Chunk #chunkIndex#" expand="false">
                </cfif>
            </cfif>
            
            <cfcatch type="any">
                <cfset failedEmbeddings++ />
                <cfif showDebug>
                    <cfdump var="#cfcatch#" label="Embedding Error - Chunk #chunkIndex#" expand="false">
                </cfif>
            </cfcatch>
        </cftry>
    </cfloop>
    
    <!--- Update file status --->
    <cftry>
        <cfquery datasource="#application.db.dsn#">
            UPDATE uploaded_files 
            SET status = 'Completed', processed_at = CURRENT_TIMESTAMP 
            WHERE file_path = <cfqueryparam value="#url.filePath#" cfsqltype="cf_sql_varchar">
        </cfquery>
        
        <cfcatch type="any">
            <cfif showDebug>
                <cfdump var="#cfcatch#" label="File Status Update Error" expand="false">
            </cfif>
        </cfcatch>
    </cftry>
    
    <!--- Display Results --->
    <cfoutput>
        <div class="bg-green-50 border border-green-200 rounded-lg p-4">
            <h3 class="text-green-800 font-semibold">🎉 Processing Complete!</h3>
            <div class="mt-3 space-y-2">
                <p class="text-green-700"><strong>File:</strong> #fileName#</p>
                <p class="text-green-700"><strong>Chunks Created:</strong> #arrayLen(chunks)#</p>
                <p class="text-green-700"><strong>Successful Embeddings:</strong> #successfulEmbeddings#</p>
                <p class="text-green-700"><strong>Failed Embeddings:</strong> #failedEmbeddings#</p>
                <p class="text-green-700"><strong>Success Rate:</strong> #numberFormat((successfulEmbeddings/arrayLen(chunks))*100, "99.9")#%</p>
            </div>
            
            <div class="mt-4 space-x-3">
                <a href="chatbox.cfm?q=#urlEncodedFormat('content from ' & fileName)#" 
                   class="inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors">
                    🗣️ Chat with Document
                </a>
                <a href="file_manager.cfm" 
                   class="inline-block bg-gray-600 text-white px-4 py-2 rounded hover:bg-gray-700 transition-colors">
                    📁 Back to File Manager
                </a>
            </div>
        </div>
    </cfoutput>
    
    <cfcatch type="any">
        <!--- Handle any overall processing errors --->
        <cftry>
            <cfquery datasource="#application.db.dsn#">
                UPDATE uploaded_files 
                SET status = 'Error', processed_at = CURRENT_TIMESTAMP 
                WHERE file_path = <cfqueryparam value="#url.filePath#" cfsqltype="cf_sql_varchar">
            </cfquery>
            
            <cfcatch type="any">
                <!--- Ignore file status update errors --->
            </cfcatch>
        </cftry>
        
        <cfoutput>
            <div class="bg-red-50 border border-red-200 rounded-lg p-4">
                <h3 class="text-red-800 font-semibold">❌ Processing Error</h3>
                <p class="text-red-700"><strong>Error:</strong> #cfcatch.message#</p>
                <p class="text-red-700"><strong>Type:</strong> #cfcatch.type#</p>
                
                <cfif showDebug>
                    <div class="mt-4">
                        <cfdump var="#cfcatch#" label="Processing Error (Full)" expand="true">
                    </div>
                </cfif>
                
                <div class="mt-4">
                    <a href="file_manager.cfm" 
                       class="inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors">
                        ← Back to File Manager
                    </a>
                </div>
            </div>
        </cfoutput>
    </cfcatch>
</cftry>

</div>

</div>
</body>
</html>