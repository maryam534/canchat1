<!---
    Advanced File-Based RAG Upload System
    Complete pipeline: Upload → Extract → Chunk → Embed → Store
--->

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Document Upload & RAG Processing</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <style>
        .step-indicator { transition: all 0.3s ease; }
        .step-active { background: ##3b82f6; color: white; }
        .step-completed { background: ##10b981; color: white; }
        .step-pending { background: ##e5e7eb; color: ##6b7280; }
        .progress-bar { transition: width 0.5s ease; }
        .fade-in { animation: fadeIn 0.5s ease-in; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
        .spinner { animation: spin 1s linear infinite; }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
    </style>
</head>
<body class="bg-gradient-to-br from-blue-50 to-indigo-100 min-h-screen">

<!-- cfif structKeyExists(form, "catalogFile") removed: processing moved to process_upload.cfm -->
    <!--- PROCESSING PIPELINE STARTS HERE --->
    <div class="container mx-auto px-4 py-8 max-w-4xl">
        <div class="bg-white rounded-xl shadow-lg overflow-hidden">
            <!-- Header -->
            <div class="bg-gradient-to-r from-blue-600 to-indigo-600 px-8 py-6">
                <h1 class="text-3xl font-bold text-white flex items-center">
                    <svg class="w-8 h-8 mr-3" fill="currentColor" viewBox="0 0 20 20">
                        <path d="M4 3a2 2 0 100 4h12a2 2 0 100-4H4z"/>
                        <path fill-rule="evenodd" d="M3 8h14v7a2 2 0 01-2 2H5a2 2 0 01-2-2V8zm5 3a1 1 0 011-1h2a1 1 0 110 2H9a1 1 0 01-1-1z" clip-rule="evenodd"/>
                    </svg>
                    Document RAG Processing Pipeline
                </h1>
                <p class="text-blue-100 mt-2">Complete file processing from upload to AI embedding</p>
            </div>

            <!-- Progress Steps -->
            <div class="px-8 py-6 bg-gray-50">
                <div class="flex items-center justify-between mb-6">
                    <div class="flex items-center space-x-4">
                        <div class="step-indicator step-active rounded-full w-10 h-10 flex items-center justify-center font-bold">1</div>
                        <span class="text-sm font-medium text-gray-700">Upload File</span>
                    </div>
                    <div class="flex-1 h-1 bg-gray-200 mx-4">
                        <div class="progress-bar h-full bg-blue-500" style="width: 20%;"></div>
                    </div>
                    <div class="flex items-center space-x-4">
                        <div class="step-indicator step-pending rounded-full w-10 h-10 flex items-center justify-center font-bold">2</div>
                        <span class="text-sm font-medium text-gray-700">Extract Text</span>
                    </div>
                    <div class="flex-1 h-1 bg-gray-200 mx-4">
                        <div class="progress-bar h-full bg-gray-300" style="width: 0%;"></div>
                    </div>
                    <div class="flex items-center space-x-4">
                        <div class="step-indicator step-pending rounded-full w-10 h-10 flex items-center justify-center font-bold">3</div>
                        <span class="text-sm font-medium text-gray-700">Create Chunks</span>
                    </div>
                    <div class="flex-1 h-1 bg-gray-200 mx-4">
                        <div class="progress-bar h-full bg-gray-300" style="width: 0%;"></div>
                    </div>
                    <div class="flex items-center space-x-4">
                        <div class="step-indicator step-pending rounded-full w-10 h-10 flex items-center justify-center font-bold">4</div>
                        <span class="text-sm font-medium text-gray-700">AI Embedding</span>
                    </div>
                    <div class="flex-1 h-1 bg-gray-200 mx-4">
                        <div class="progress-bar h-full bg-gray-300" style="width: 0%;"></div>
                    </div>
                    <div class="flex items-center space-x-4">
                        <div class="step-indicator step-pending rounded-full w-10 h-10 flex items-center justify-center font-bold">5</div>
                        <span class="text-sm font-medium text-gray-700">Store Database</span>
                    </div>
                </div>
            </div>

            <!-- Processing Content -->
            <div class="px-8 py-6">

    <cfscript>
        // Initialize processing variables
        processingSteps = [];
        currentStep = 1;
        totalSteps = 5;
        
        // Step 1: File Upload
        arrayAppend(processingSteps, {
            step: 1,
            title: "📁 File Upload",
            status: "processing",
            message: "Uploading and validating file...",
            details: []
        });
    </cfscript>

    <cftry>
    <cfset uploadDir = application.paths.uploadsDir />
    
    <!--- Ensure upload directory exists --->
    <cfif NOT directoryExists(uploadDir)>
        <cfdirectory action="create" directory="#uploadDir#" />
    </cfif>
    
        <!--- Upload file --->
    <cffile action="upload"
            fileField="catalogFile"
            destination="#uploadDir#"
            nameConflict="makeunique"
            result="uploadResult" />

        <cfset uploadedFile = uploadDir & "/" & uploadResult.serverFile />
        
        <!--- Redirect to unified processor to avoid duplicate business logic --->
        <cflocation url="process_upload.cfm?filePath=#URLEncodedFormat(uploadedFile)#&debug=#application.ui.showDebugLogs#" addToken="false">
        <cfabort>
        
        <cfcatch type="any">
            <cfoutput>
                <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-4">
                    <h3 class="text-red-800 font-semibold">Upload Error</h3>
                    <p class="text-red-700">Error: #cfcatch.message#</p>
                    <p class="text-red-700">Detail: #cfcatch.detail#</p>
                </div>
                <p class="mt-4">
                    <a href="index.cfm" class="text-blue-600 hover:text-blue-800 underline">← Back to Chat</a>
                </p>
            </cfoutput>
        </cfcatch>
    </cftry>

        <!--- Unreached content removed --->

        <!--- Step 2: Text Extraction with Apache Tika --->
        <!--- LEGACY IN-PAGE PROCESS DISABLED. Processing moved to process_upload.cfm. --->
        <!---
        <cfscript>
            arrayAppend(processingSteps, {
                step: 2,
                title: "🔍 Text Extraction (Apache Tika)",
                status: "processing",
                message: "Extracting text content from document...",
                details: []
            });
        </cfscript>

        <cfscript>
            // JavaLoader-based text extraction
            fileExtension = lcase(listLast(uploadResult.serverFile, "."));
            contentType = uploadResult.contentType;
            extractedText = "";
            
            writeLog(file="tika_processing", text="File extension: " & fileExtension, type="information");
            writeLog(file="tika_processing", text="Content type: " & contentType, type="information");
            
            // Method 1: JavaLoader approach (if available)
            if (isObject(application.javaLoader)) {
                try {
                    // If Tika needs the context classloader, set it temporarily
                    originalCL = "";
                    try {
                        if (structKeyExists(application, "tikaClassLoader") && isObject(application.tikaClassLoader)) {
                            currentThread = createObject("java", "java.lang.Thread").currentThread();
                            originalCL = currentThread.getContextClassLoader();
                            currentThread.setContextClassLoader(application.tikaClassLoader);
                        }
                    } catch (any ignoreSetCL) {}
                    writeLog(file="tika_processing", text="Using JavaLoader for Tika AutoDetectParser", type="information");
                    
                    // Use AutoDetectParser approach (more reliable than Tika facade)
                    parser = application.javaLoader.create("org.apache.tika.parser.AutoDetectParser").init();
                    metadata = application.javaLoader.create("org.apache.tika.metadata.Metadata").init();
                    contentHandler = application.javaLoader.create("org.apache.tika.sax.BodyContentHandler").init();
                    parseContext = application.javaLoader.create("org.apache.tika.parser.ParseContext").init();
                    
                    // Create file input stream
                    javaFile = createObject("java", "java.io.File").init(uploadedFile);
                    fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
                    
                    // Parse the document
                    parser.parse(fileInputStream, contentHandler, metadata, parseContext);
                    extractedText = contentHandler.toString();
                    
                    // Get content type from metadata
                    contentType = metadata.get("Content-Type");
                    if (!len(contentType)) {
                        contentType = "application/octet-stream";
                    }
                    
                    fileInputStream.close();
                    
                    // Restore original context classloader
                    try {
                        if (isObject(originalCL)) {
                            currentThread.setContextClassLoader(originalCL);
                        }
                    } catch (any ignoreRestoreCL) {}
                    
                    writeLog(file="tika_processing", text="JavaLoader AutoDetectParser extraction successful", type="information");
                    writeLog(file="tika_processing", text="Detected content type: " & contentType, type="information");
                    
                } catch (any jlError) {
                    writeLog(file="tika_processing", text="JavaLoader Tika failed: " & jlError.message, type="warning");
                    writeLog(file="tika_processing", text="Error detail: " & jlError.detail, type="warning");
                    // Fallback to command-line approach
                    try {
                        tikaJarPath = application.processing.tikaPath;
                        writeLog(file="tika_processing", text="Falling back to command-line Tika", type="information");
                        cfexecute(
                            name = "java",
                            arguments = '-jar "' & tikaJarPath & '" --text "' & uploadedFile & '"',
                            variable = "extractedText",
                            errorVariable = "tikaError",
                            timeout = 60
                        );
                        if (len(tikaError)) {
                            writeLog(file="tika_processing", text="Tika stderr: " & tikaError, type="warning");
                        }
                        switch (fileExtension) {
                            case "pdf": contentType = "application/pdf"; break;
                            case "doc": contentType = "application/msword"; break;
                            case "docx": contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"; break;
                            case "txt": contentType = "text/plain"; break;
                            default: contentType = "application/octet-stream";
                        }
                        writeLog(file="tika_processing", text="Command-line Tika extraction completed", type="information");
                    } catch (any cmdError) {
                        writeLog(file="tika_processing", text="Command-line Tika also failed: " & cmdError.message, type="error");
                        extractedText = "Error: Could not extract text using any method.";
                    }
                }
            } else {
                // Method 2: Direct file reading for simple types
                if (fileExtension == "txt") {
                    try {
                        extractedText = fileRead(uploadedFile, "utf-8");
                        contentType = "text/plain";
                        writeLog(file="tika_processing", text="Text file read directly", type="information");
                    } catch (any e) {
                        extractedText = fileRead(uploadedFile);
                        writeLog(file="tika_processing", text="Text file read with default encoding", type="information");
                    }
                } else {
                    // Method 3: Command-line Tika for complex documents
                    try {
                        tikaJarPath = application.processing.tikaPath;
                        
                        cfexecute(
                            name = "java",
                            arguments = '-jar "' & tikaJarPath & '" --text "' & uploadedFile & '"',
                            variable = "extractedText",
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
                        
                        writeLog(file="tika_processing", text="Command-line Tika extraction completed", type="information");
                        
                    } catch (any cmdError) {
                        writeLog(file="tika_processing", text="All extraction methods failed: " & cmdError.message, type="error");
                        extractedText = "Error: Could not extract text from this document.";
                        contentType = "application/octet-stream";
                    }
                }
            }
            
            // Validate extracted text
            if (!len(extractedText) || len(extractedText) < 10) {
                writeLog(file="tika_processing", text="No valid text content extracted", type="warning");
                extractedText = "Warning: Very little or no text content found in the document.";
            }
            
            // Save extracted text to temp file
            tempFolder = expandPath("./temp");
            if (!directoryExists(tempFolder)) {
                directoryCreate(tempFolder);
            }
            
            timestamp = dateFormat(now(), "yyyymmdd") & "_" & timeFormat(now(), "HHMMSS");
            tempFileName = "extracted_" & timestamp & "_" & uploadResult.serverFile & ".txt";
            tempFilePath = tempFolder & "/" & tempFileName;
            fileWrite(tempFilePath, extractedText);
            
            // Update step 2
            processingSteps[2].status = "completed";
            processingSteps[2].message = "Text extracted successfully using Apache Tika!";
            arrayAppend(processingSteps[2].details, "Content type detected: " & contentType);
            arrayAppend(processingSteps[2].details, "Extracted text length: " & len(extractedText) & " characters");
            arrayAppend(processingSteps[2].details, "Text preview: " & left(extractedText, 150) & "...");
            arrayAppend(processingSteps[2].details, "Saved to: " & tempFileName);
            
            currentStep = 3;
        </cfscript>

        <!--- Step 3: Text Chunking --->
        <cfscript>
            arrayAppend(processingSteps, {
                step: 3,
                title: "✂️ Text Chunking",
                status: "processing",
                message: "Breaking text into manageable chunks...",
                details: []
            });
            
            // Create chunks
            chunkSize = application.processing.chunkSize;
            wordArray = listToArray(htmlEditFormat(extractedText), " ");
            chunks = [];
            
            for (i = 1; i LTE arrayLen(wordArray); i += chunkSize) {
                thisChunkSize = min(chunkSize, arrayLen(wordArray) - i + 1);
                chunk = arraySlice(wordArray, i, thisChunkSize);
                arrayAppend(chunks, arrayToList(chunk, " "));
            }
            
            // Update step 3
            processingSteps[3].status = "completed";
            processingSteps[3].message = "Text chunked successfully!";
            arrayAppend(processingSteps[3].details, "Total words: " & arrayLen(wordArray));
            arrayAppend(processingSteps[3].details, "Chunk size: " & chunkSize & " words per chunk");
            arrayAppend(processingSteps[3].details, "Number of chunks created: " & arrayLen(chunks));
            arrayAppend(processingSteps[3].details, "Average chunk length: " & numberFormat(len(extractedText)/arrayLen(chunks), "999") & " characters");
            
            currentStep = 4;
        </cfscript>

        <!--- Step 4: AI Embeddings --->
        <cfscript>
            arrayAppend(processingSteps, {
                step: 4,
                title: "🤖 AI Embeddings (OpenAI)",
                status: "processing",
                message: "Creating AI embeddings for each chunk...",
                details: []
            });
            
            // Process embeddings
            embedModel = application.ai.embedModel;
            openaiKey = replace(application.ai.openaiKey, '"', "", "all");
            apiBaseUrl = application.ai.apiBaseUrl;
            timeout = application.processing.defaultTimeout;
            
            successfulEmbeddings = 0;
            failedEmbeddings = 0;
        </cfscript>

        <cfloop array="#chunks#" index="chunkIndex" item="chunkText">
            <cftry>
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
                    
                    <!--- Store in database --->
    <cfquery datasource="#application.db.dsn#">
                        INSERT INTO stamp_chunks (chunk_text, embedding, source_type, source_name, chunk_index)
        VALUES (
                            <cfqueryparam value="#chunkText#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#embedding#" cfsqltype="cf_sql_varchar">::vector,
                            'document',
                            <cfqueryparam value="#uploadResult.clientFile#" cfsqltype="cf_sql_varchar">,
                            <cfqueryparam value="#chunkIndex#" cfsqltype="cf_sql_integer">
        )
    </cfquery>

                    <cfset successfulEmbeddings++ />
                <cfelse>
                    <cfset failedEmbeddings++ />
    </cfif>
    
                <cfcatch>
                    <cfset failedEmbeddings++ />
                    <cfif application.ui.showDebugLogs>
                        <cfdump var="#cfcatch#" label="Embedding Error (cfcatch)" expand="false">
                    </cfif>
                </cfcatch>
            </cftry>
        </cfloop>

        <!--- Step 5: Database Storage --->
        <cfscript>
            arrayAppend(processingSteps, {
                step: 5,
                title: "💾 Database Storage",
                status: "processing",
                message: "Storing processed data in database...",
                details: []
            });
            
            // Store file record
            try {
                queryExecute("
                    INSERT INTO uploaded_files (file_name, file_path, status, processed_at, content_type, file_size, chunks_created)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ", [
                    uploadResult.serverFile,
                    uploadedFile,
                    'Completed',
                    now(),
                    contentType,
                    uploadResult.fileSize,
                    arrayLen(chunks)
                ], {datasource: application.db.dsn});
                
                // Update steps 4 and 5
                processingSteps[4].status = "completed";
                processingSteps[4].message = "AI embeddings created successfully!";
                arrayAppend(processingSteps[4].details, "Embedding model: " & embedModel);
                arrayAppend(processingSteps[4].details, "Successful embeddings: " & successfulEmbeddings);
                arrayAppend(processingSteps[4].details, "Failed embeddings: " & failedEmbeddings);
                arrayAppend(processingSteps[4].details, "Success rate: " & numberFormat((successfulEmbeddings/arrayLen(chunks))*100, "99.9") & "%");
                
                processingSteps[5].status = "completed";
                processingSteps[5].message = "All data stored successfully in database!";
                arrayAppend(processingSteps[5].details, "File record created in uploaded_files table");
                arrayAppend(processingSteps[5].details, "Chunks stored in stamp_chunks table");
                arrayAppend(processingSteps[5].details, "Vector embeddings ready for similarity search");
                arrayAppend(processingSteps[5].details, "Document is now searchable via RAG chat interface");
                
                currentStep = 6; // All completed
                
            } catch (any e) {
                processingSteps[5].status = "error";
                processingSteps[5].message = "Database storage failed: " & e.message;
                <!--- Debug dumps to diagnose DB failure --->
                <cfif application.ui.showDebugLogs>
                    <cfdump var="#e#" label="DB Error (e)" expand="false">
                    <cfdump var="#application.db#" label="DB Config (application.db)" expand="false">
                    <cfdump var="#uploadResult#" label="Upload Result (for context)" expand="false">
                </cfif>
            }
        </cfscript>

        <cfcatch type="any">
            <cfscript>
                // Handle any processing errors
                if (currentStep <= arrayLen(processingSteps)) {
                    processingSteps[currentStep].status = "error";
                    processingSteps[currentStep].message = "Error: " & cfcatch.message;
                    arrayAppend(processingSteps[currentStep].details, "Error type: " & cfcatch.type);
                    arrayAppend(processingSteps[currentStep].details, "Error detail: " & cfcatch.detail);
                }
            </cfscript>
        </cfcatch>
    </cftry>

    --->
    <!--- Display Processing Results (legacy UI placeholder) --->
    <cfoutput>
        <cfloop array="#processingSteps#" index="step">
            <div class="fade-in mb-6 p-6 rounded-lg border-2 
                <cfif step.status == 'completed'>border-green-200 bg-green-50
                <cfelseif step.status == 'error'>border-red-200 bg-red-50
                <cfelse>border-blue-200 bg-blue-50</cfif>">
                
                <div class="flex items-center mb-4">
                    <div class="
                        <cfif step.status == 'completed'>step-completed
                        <cfelseif step.status == 'error'>bg-red-500 text-white
                        <cfelse>step-active</cfif>
                        rounded-full w-8 h-8 flex items-center justify-center font-bold text-sm mr-4">
                        <cfif step.status == 'completed'>✓
                        <cfelseif step.status == 'error'>✗
                        <cfelse><div class="spinner w-4 h-4 border-2 border-white border-t-transparent rounded-full"></div></cfif>
                    </div>
                    <h3 class="text-lg font-semibold 
                        <cfif step.status == 'completed'>text-green-800
                        <cfelseif step.status == 'error'>text-red-800
                        <cfelse>text-blue-800</cfif>">
                        #step.title#
                    </h3>
                </div>
                
                <p class="text-gray-700 mb-3 ml-12">#step.message#</p>
                
                <cfif arrayLen(step.details) GT 0>
                    <div class="ml-12">
                        <ul class="text-sm text-gray-600 space-y-1">
                            <cfloop array="#step.details#" index="detail">
                                <li class="flex items-center">
                                    <span class="w-2 h-2 bg-gray-400 rounded-full mr-2"></span>
                                    #detail#
                                </li>
                            </cfloop>
                        </ul>
                    </div>
                </cfif>
            </div>
        </cfloop>
        
        <!--- Final Success Message --->
        <cfif currentStep GT 5>
            <div class="fade-in mt-8 p-8 bg-gradient-to-r from-green-500 to-emerald-500 rounded-xl text-white text-center">
                <div class="text-6xl mb-4">🎉</div>
                <h2 class="text-3xl font-bold mb-4">RAG Processing Complete!</h2>
                <p class="text-xl mb-6">Your document has been successfully processed through the entire RAG pipeline:</p>
                <div class="grid grid-cols-1 md:grid-cols-5 gap-4 text-sm">
                    <div class="bg-white bg-opacity-20 rounded-lg p-3">
                        <div class="font-semibold">📁 Uploaded</div>
                        <div>File stored safely</div>
                    </div>
                    <div class="bg-white bg-opacity-20 rounded-lg p-3">
                        <div class="font-semibold">🔍 Extracted</div>
                        <div>Text via Apache Tika</div>
                    </div>
                    <div class="bg-white bg-opacity-20 rounded-lg p-3">
                        <div class="font-semibold">✂️ Chunked</div>
                        <div>#arrayLen(chunks)# pieces created</div>
                    </div>
                    <div class="bg-white bg-opacity-20 rounded-lg p-3">
                        <div class="font-semibold">🤖 Embedded</div>
                        <div>AI vectors generated</div>
                    </div>
                    <div class="bg-white bg-opacity-20 rounded-lg p-3">
                        <div class="font-semibold">💾 Stored</div>
                        <div>Database ready</div>
                    </div>
                </div>
                
                <div class="mt-8 space-x-4">
                    <a href="index.cfm" class="inline-block bg-white text-green-600 px-6 py-3 rounded-lg font-semibold hover:bg-gray-100 transition-colors">
                        🗣️ Start Chatting with Your Document
                    </a>
                    <a href="dashboard.cfm" class="inline-block bg-white bg-opacity-20 text-white px-6 py-3 rounded-lg font-semibold hover:bg-opacity-30 transition-colors">
                        📊 View Dashboard
                    </a>
                </div>
        </div>
        </cfif>
    </cfoutput>

            </div>
        </div>
    </div>

<!-- cfelse removed -->
    <!--- UPLOAD FORM --->
    <div class="container mx-auto px-4 py-8 max-w-2xl">
        <div class="bg-white rounded-xl shadow-lg overflow-hidden">
            <div class="bg-gradient-to-r from-blue-600 to-indigo-600 px-8 py-6">
                <h1 class="text-3xl font-bold text-white">📁 Document Upload</h1>
                <p class="text-blue-100 mt-2">Upload PDF, DOC, or TXT files for AI-powered RAG processing</p>
            </div>
            
            <div class="px-8 py-8">
                <form action="upload.cfm" method="post" enctype="multipart/form-data" class="space-y-6">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Select Document</label>
                        <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-blue-400 transition-colors">
                            <input type="file" name="catalogFile" accept=".pdf,.doc,.docx,.txt" required
                                   class="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100">
                            <p class="mt-2 text-sm text-gray-500">Supported formats: PDF, DOC, DOCX, TXT</p>
                        </div>
                    </div>
                    
                    <button type="submit" class="w-full bg-gradient-to-r from-blue-600 to-indigo-600 text-white py-3 px-6 rounded-lg font-semibold hover:from-blue-700 hover:to-indigo-700 transition-colors">
                        🚀 Upload & Process Document
                    </button>
                </form>
                
                <div class="mt-8 text-center">
                    <a href="index.cfm" class="text-blue-600 hover:text-blue-800 underline">← Back to Chat Interface</a>
                </div>
            </div>
        </div>
    </div>
<!-- /cfif removed -->

</body>
</html>