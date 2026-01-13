<!---
    Web Scraping Processor
    Handles URL scraping and stores content in unified chunks table
--->

<cfparam name="form.urls" default="" />
<cfparam name="form.category" default="" />
<cfparam name="form.maxPages" default="10" />
<cfsetting requesttimeout="900" />

<!DOCTYPE html>
<html>
<head>
    <title>Web Scraping Processing</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">

<div class="max-w-4xl mx-auto">
    <div class="bg-white rounded-xl shadow-sm p-6">
        <h1 class="text-2xl font-bold text-gray-800 mb-4">🌐 Web Scraping Processing</h1>

<cfif NOT len(form.urls)>
    <div class="bg-yellow-50 p-4 rounded">
        <p class="text-yellow-800">No URLs provided. <a href="web_scraping.cfm" class="text-blue-600 underline">Go back</a></p>
    </div>
<cfelse>
    <cfscript>
        // Configuration
        jsoupClass = application.processing.jsoupClass;
        embedModel = application.ai.embedModel;
        openaiKey = replace(application.ai.openaiKey, '"', "", "all");
        apiBaseUrl = application.ai.apiBaseUrl;
        chunkSize = application.processing.chunkSize;
        maxPages = val(form.maxPages);
        category = len(form.category) ? form.category : "web";
        
        // Parse URLs
        urlList = listToArray(form.urls, chr(10));
        processedCount = 0;
        successCount = 0;
        errorCount = 0;
        
        writeOutput("<div class='space-y-4'>");
        writeOutput("<p class='font-medium'>Processing " & arrayLen(urlList) & " URLs...</p>");
    </cfscript>

    <cfloop array="#urlList#" index="currentUrl">
        <cfset currentUrl = trim(currentUrl) />
        <cfif len(currentUrl) AND processedCount LT maxPages>
            
            <cfoutput>
                <div class="bg-blue-50 p-4 rounded-lg">
                    <h3 class="font-semibold text-blue-800">Processing: #currentUrl#</h3>
            </cfoutput>
            
            <cftry>
                <cfscript>
                    // Create JSoup object
                    jsoup = createObject("java", jsoupClass);
                    
                    // Connect and get document
                    doc = jsoup.connect(currentUrl).get();
                    pageTitle = doc.title().toString();
                    bodyText = doc.select("body").text();
                    
                    // Skip if content too short
                    if (len(bodyText) LTE 200) {
                        writeOutput("<p class='text-yellow-600'>⚠️ Skipped - content too short</p>");
                        errorCount++;
                        writeOutput("</div>");
                        continue;
                    }
                    
                    // Create chunks
                    wordArray = listToArray(bodyText, " ");
                    chunks = [];
                    
                    for (i = 1; i LTE arrayLen(wordArray); i += chunkSize) {
                        thisChunkSize = min(chunkSize, arrayLen(wordArray) - i + 1);
                        chunk = arraySlice(wordArray, i, thisChunkSize);
                        arrayAppend(chunks, arrayToList(chunk, " "));
                    }
                    
                    writeOutput("<p class='text-green-600'>✅ Extracted " & len(bodyText) & " characters, " & arrayLen(chunks) & " chunks</p>");
                    
                    // Process each chunk
                    chunkSuccessCount = 0;
                    for (chunkIndex = 1; chunkIndex LTE arrayLen(chunks); chunkIndex++) {
                        chunkText = chunks[chunkIndex];
                        
                        // Create embedding
                        try {
                            bodyStruct = {
                                "model": embedModel,
                                "input": chunkText
                            };
                            
                            cfhttp(url=apiBaseUrl & "/embeddings", method="post", timeout=application.ai.timeout) {
                                cfhttpparam(type="header", name="Authorization", value="Bearer " & openaiKey);
                                cfhttpparam(type="header", name="Content-Type", value="application/json");
                                cfhttpparam(type="body", value=serializeJSON(bodyStruct));
                            }
                            
                            embedResult = deserializeJSON(cfhttp.filecontent);
                            
                            if (structKeyExists(embedResult, "data") AND arrayLen(embedResult.data) GT 0) {
                                embedding = "[" & arrayToList(embedResult.data[1].embedding, ",") & "]";
                                
                                // Insert into unified chunks table
                                queryExecute("
                                    INSERT INTO chunks (
                                        chunk_text, embedding, source_type, source_name, source_id,
                                        chunk_index, chunk_size, content_type, title, category,
                                        embedding_model, metadata
                                    )
                                    VALUES (?, ?::vector, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb)
                                    ON CONFLICT (source_type, source_id, chunk_index) DO NOTHING
                                ", [
                                    { value: chunkText, cfsqltype: "cf_sql_longvarchar" },
                                    { value: embedding, cfsqltype: "cf_sql_varchar" },
                                    { value: 'web', cfsqltype: "cf_sql_varchar" },
                                    { value: left(currentUrl, 255), cfsqltype: "cf_sql_varchar" },
                                    { value: hash(currentUrl, "MD5"), cfsqltype: "cf_sql_varchar" },
                                    { value: chunkIndex, cfsqltype: "cf_sql_integer" },
                                    { value: len(chunkText), cfsqltype: "cf_sql_integer" },
                                    { value: 'text/html', cfsqltype: "cf_sql_varchar" },
                                    { value: pageTitle, cfsqltype: "cf_sql_varchar" },
                                    { value: category, cfsqltype: "cf_sql_varchar" },
                                    { value: embedModel, cfsqltype: "cf_sql_varchar" },
                                    { value: serializeJSON({
                                        'url': currentUrl,
                                        'title': pageTitle,
                                        'scrapedAt': now(),
                                        'wordCount': arrayLen(wordArray)
                                    }), cfsqltype: "cf_sql_longvarchar" }
                                ], {datasource: application.db.dsn});
                                
                                chunkSuccessCount++;
                            }
                            if (chunkIndex % 8 EQ 0) sleep(250);
                        } catch (any chunkError) {
                            writeOutput("<p class='text-red-600 text-xs'>❌ Chunk " & chunkIndex & " failed: " & chunkError.message & "</p>");
                            writedump(chunkError);
                        }
                    }
                    
                    writeOutput("<p class='text-blue-600'>📊 Stored " & chunkSuccessCount & "/" & arrayLen(chunks) & " chunks successfully</p>");
                    successCount++;
                </cfscript>
                
                <cfcatch type="any">
                    <cfoutput>
                        <p class="text-red-600">❌ Failed: #cfcatch.message#</p>
                    </cfoutput>
                    <cfset errorCount++ />
                </cfcatch>
            </cftry>
            
            <cfoutput></div></cfoutput>
            <cfset processedCount++ />
        </cfif>
    </cfloop>

    <cfscript>
        writeOutput("<div class='mt-6 bg-green-50 border border-green-200 rounded-lg p-4'>");
        writeOutput("<h3 class='text-green-800 font-semibold'>🎉 Web Scraping Complete!</h3>");
        writeOutput("<div class='mt-3 space-y-2'>");
        writeOutput("<p class='text-green-700'><strong>URLs Processed:</strong> " & processedCount & "</p>");
        writeOutput("<p class='text-green-700'><strong>Successful:</strong> " & successCount & "</p>");
        writeOutput("<p class='text-green-700'><strong>Failed:</strong> " & errorCount & "</p>");
        writeOutput("<p class='text-green-700'><strong>Category:</strong> " & category & "</p>");
        writeOutput("</div>");
        
        writeOutput("<div class='mt-4 space-x-3'>");
        writeOutput("<a href='chatbox.cfm?q=" & urlEncodedFormat('web content about ' & category) & "' class='inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors'>🗣️ Chat with Scraped Content</a>");
        writeOutput("<a href='web_scraping.cfm' class='inline-block bg-gray-600 text-white px-4 py-2 rounded hover:bg-gray-700 transition-colors'>← Back to Web Scraping</a>");
        writeOutput("</div>");
        writeOutput("</div>");
        writeOutput("</div>");
    </cfscript>
</cfif>

    </div>
</div>

</body>
</html>
