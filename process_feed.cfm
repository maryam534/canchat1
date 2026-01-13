<!---
    RSS/Atom Feed Processor
    Processes feeds and stores articles in unified chunks table
--->

<cfparam name="form.feedUrl" default="" />
<cfparam name="form.category" default="" />
<cfparam name="form.frequency" default="manual" />

<!DOCTYPE html>
<html>
<head>
    <title>Feed Processing</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">

<div class="max-w-4xl mx-auto">
    <div class="bg-white rounded-xl shadow-sm p-6">
        <h1 class="text-2xl font-bold text-gray-800 mb-4">📡 Feed Processing</h1>

<cfif NOT len(form.feedUrl)>
    <div class="bg-yellow-50 p-4 rounded">
        <p class="text-yellow-800">No feed URL provided. <a href="feeds.cfm" class="text-blue-600 underline">Go back</a></p>
    </div>
<cfelse>
    <cfscript>
        // Configuration
        embedModel = application.ai.embedModel;
        openaiKey = replace(application.ai.openaiKey, '"', "", "all");
        apiBaseUrl = application.ai.apiBaseUrl;
        chunkSize = application.processing.chunkSize;
        category = len(form.category) ? form.category : "feed";
        
        processedCount = 0;
        successCount = 0;
        errorCount = 0;
        
        writeOutput("<div class='space-y-4'>");
        writeOutput("<p class='font-medium'>Processing feed: " & form.feedUrl & "</p>");
    </cfscript>

    <cftry>
        <!--- Fetch the RSS/Atom feed --->
        <cfhttp url="#form.feedUrl#" method="get" timeout="30" />
        
        <cfif cfhttp.statusCode EQ "200 OK">
            <cfscript>
                // Parse XML feed
                try {
                    feedXML = xmlParse(cfhttp.fileContent);
                    
                    // Determine feed type (RSS or Atom)
                    if (structKeyExists(feedXML, "rss")) {
                        // RSS feed
                        feedType = "RSS";
                        items = xmlSearch(feedXML, "//item");
                    } else if (structKeyExists(feedXML, "feed")) {
                        // Atom feed
                        feedType = "Atom";
                        items = xmlSearch(feedXML, "//entry");
                    } else {
                        throw(message="Unknown feed format");
                    }
                    
                    writeOutput("<p class='text-green-600'>✅ " & feedType & " feed parsed - " & arrayLen(items) & " items found</p>");
                    
                    // Process each feed item
                    for (item in items) {
                        if (processedCount >= val(form.maxPages)) break;
                        
                        try {
                            // Extract item data based on feed type
                            if (feedType == "RSS") {
                                itemTitle = xmlSearch(item, "title")[1].xmlText ?: "";
                                itemLink = xmlSearch(item, "link")[1].xmlText ?: "";
                                itemDescription = xmlSearch(item, "description")[1].xmlText ?: "";
                                itemDate = xmlSearch(item, "pubDate")[1].xmlText ?: "";
                            } else {
                                // Atom
                                itemTitle = xmlSearch(item, "title")[1].xmlText ?: "";
                                linkNodes = xmlSearch(item, "link[@href]");
                                itemLink = arrayLen(linkNodes) ? linkNodes[1].xmlAttributes.href : "";
                                summaryNodes = xmlSearch(item, "summary");
                                itemDescription = arrayLen(summaryNodes) ? summaryNodes[1].xmlText : "";
                                itemDate = xmlSearch(item, "updated")[1].xmlText ?: "";
                            }
                            
                            // Skip if no meaningful content
                            if (!len(itemTitle) AND !len(itemDescription)) continue;
                            
                            // Combine title and description for chunking
                            fullText = itemTitle;
                            if (len(itemDescription)) {
                                fullText &= chr(10) & chr(10) & itemDescription;
                            }
                            
                            // Create chunks from the article content
                            wordArray = listToArray(htmlEditFormat(fullText), " ");
                            if (arrayLen(wordArray) < 50) continue; // Skip very short content
                            
                            articleChunks = [];
                            for (i = 1; i LTE arrayLen(wordArray); i += chunkSize) {
                                thisChunkSize = min(chunkSize, arrayLen(wordArray) - i + 1);
                                chunk = arraySlice(wordArray, i, thisChunkSize);
                                arrayAppend(articleChunks, arrayToList(chunk, " "));
                            }
                            
                            writeOutput("<div class='ml-4 p-3 bg-gray-50 rounded'>");
                            writeOutput("<p class='font-medium text-gray-800'>" & encodeForHtml(itemTitle) & "</p>");
                            writeOutput("<p class='text-sm text-gray-600'>" & arrayLen(articleChunks) & " chunks created</p>");
                            
                            // Process embeddings for each chunk
                            chunkSuccessCount = 0;
                            for (chunkIndex = 1; chunkIndex LTE arrayLen(articleChunks); chunkIndex++) {
                                chunkText = articleChunks[chunkIndex];
                                
                                try {
                                    // Create embedding
                                    bodyStruct = {
                                        "model": embedModel,
                                        "input": chunkText
                                    };
                                    
                                    cfhttp(url=apiBaseUrl & "/embeddings", method="post", timeout=30) {
                                        cfhttpparam(type="header", name="Authorization", value="Bearer " & openaiKey);
                                        cfhttpparam(type="header", name="Content-Type", value="application/json");
                                        cfhttpparam(type="body", value=serializeJSON(bodyStruct));
                                    }
                                    
                                    embedResult = deserializeJSON(cfhttp.filecontent);
                                    
                                    if (structKeyExists(embedResult, "data") AND arrayLen(embedResult.data) GT 0) {
                                        embedding = "[" & arrayToList(embedResult.data[1].embedding, ",") & "]";
                                        
                                        // Insert into chunks table
                                        queryExecute("
                                            INSERT INTO chunks (
                                                chunk_text, embedding, source_type, source_name, source_id,
                                                chunk_index, chunk_size, content_type, title, category,
                                                embedding_model, metadata
                                            )
                                            VALUES (?, ?::vector, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb)
                                        ", [
                                            chunkText,
                                            embedding,
                                            'feed',
                                            form.feedUrl,
                                            itemLink & "_" & chunkIndex,
                                            chunkIndex,
                                            len(chunkText),
                                            'application/rss+xml',
                                            itemTitle,
                                            category,
                                            embedModel,
                                            serializeJSON({
                                                'feedUrl': form.feedUrl,
                                                'articleUrl': itemLink,
                                                'title': itemTitle,
                                                'pubDate': itemDate,
                                                'scrapedAt': now()
                                            })
                                        ], {datasource: application.db.dsn});
                                        
                                        chunkSuccessCount++;
                                    }
                                } catch (any chunkError) {
                                    writeOutput("<p class='text-red-600 text-xs'>❌ Chunk " & chunkIndex & " failed</p>");
                                }
                            }
                            
                            writeOutput("<p class='text-blue-600 text-sm'>📊 " & chunkSuccessCount & "/" & arrayLen(articleChunks) & " chunks stored</p>");
                            writeOutput("</div>");
                            
                            successCount++;
                            
                        } catch (any itemError) {
                            writeOutput("<div class='ml-4 p-3 bg-red-50 rounded'>");
                            writeOutput("<p class='text-red-600'>❌ Failed to process item: " & itemError.message & "</p>");
                            writeOutput("</div>");
                            errorCount++;
                        }
                        
                        processedCount++;
                    }
                    
                } catch (any parseError) {
                    writeOutput("<p class='text-red-600'>❌ Feed parsing failed: " & parseError.message & "</p>");
                    errorCount++;
                }
            </cfscript>
        <cfelse>
            <cfoutput>
                <p class="text-red-600">❌ Failed to fetch feed (HTTP #cfhttp.statusCode#)</p>
            </cfoutput>
            <cfset errorCount++ />
        </cfif>
        
        <cfcatch type="any">
            <cfoutput>
                <p class="text-red-600">❌ Feed processing error: #cfcatch.message#</p>
            </cfoutput>
            <cfset errorCount++ />
        </cfcatch>
    </cftry>

    <cfscript>
        writeOutput("<div class='mt-6 bg-green-50 border border-green-200 rounded-lg p-4'>");
        writeOutput("<h3 class='text-green-800 font-semibold'>📡 Feed Processing Complete!</h3>");
        writeOutput("<div class='mt-3 space-y-2'>");
        writeOutput("<p class='text-green-700'><strong>Articles Processed:</strong> " & processedCount & "</p>");
        writeOutput("<p class='text-green-700'><strong>Successful:</strong> " & successCount & "</p>");
        writeOutput("<p class='text-green-700'><strong>Failed:</strong> " & errorCount & "</p>");
        writeOutput("<p class='text-green-700'><strong>Category:</strong> " & category & "</p>");
        writeOutput("</div>");
        
        writeOutput("<div class='mt-4 space-x-3'>");
        writeOutput("<a href='chatbox.cfm?q=" & urlEncodedFormat('articles about ' & category) & "' class='inline-block bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors'>🗣️ Chat with Feed Content</a>");
        writeOutput("<a href='feeds.cfm' class='inline-block bg-gray-600 text-white px-4 py-2 rounded hover:bg-gray-700 transition-colors'>← Back to Feeds</a>");
        writeOutput("</div>");
        writeOutput("</div>");
        writeOutput("</div>");
    </cfscript>
</cfif>

    </div>
</div>

</body>
</html>
