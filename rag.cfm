<!---
    RAG (Retrieval Augmented Generation) Handler
    Processes user questions with semantic search and OpenAI
--->
<cfsetting showdebugoutput="false" />
<cfparam name="url.question" default="" />
<cfparam name="form.question" default="#url.question#" />

<cfscript>
    userPrompt = trim(form.question);
    if (len(userPrompt) EQ 0) {
        writeOutput("<p>Please ask a valid question.</p>");
        abort;
    }
    openaiKey = replace(application.ai.openaiKey, '"', "", "all");
if (!structKeyExists(session, "chatHistory") or !isArray(session.chatHistory)) {
    session.chatHistory = [];
}

// Check if this is a counting query - if so, query database directly for accurate results
isCountingQuery = false;
categoryName = "";
lowerPrompt = lcase(userPrompt);

// Detect counting queries like "how many lots of X", "how many lots in X category", "count of X"
if (reFindNoCase("how many|count|number of", lowerPrompt)) {
    isCountingQuery = true;
    
    // Try to extract category name from the query
    // Simple extraction: look for text after "of " or "in "
    posOf = findNoCase(" of ", userPrompt);
    posIn = findNoCase(" in ", userPrompt);
    
    if (posOf GT 0) {
        startPos = posOf + 4;
        strLen = len(userPrompt);
        count = strLen - startPos + 1;
        remaining = mid(userPrompt, startPos, count);
        remaining = trim(reReplace(remaining, "(\s+category|\s+lots?|\?|\.|$)", "", "all"));
        if (len(remaining) GT 0 AND len(remaining) LT 100) {
            categoryName = remaining;
        }
    } else if (posIn GT 0) {
        startPos = posIn + 4;
        strLen = len(userPrompt);
        count = strLen - startPos + 1;
        remaining = mid(userPrompt, startPos, count);
        remaining = trim(reReplace(remaining, "(\s+category|\s+lots?|\?|\.|$)", "", "all"));
        if (len(remaining) GT 0 AND len(remaining) LT 100) {
            categoryName = remaining;
        }
    }
    
    // If we detected a counting query, query the database directly
    if (isCountingQuery) {
        try {
            if (len(categoryName) GT 0) {
                // Query for specific category count
                // Try case-insensitive exact match (trimmed) first
                catCount = queryExecute(
                    "SELECT COUNT(*) as cnt, MAX(majgroup) as actual_name FROM lots WHERE LOWER(TRIM(majgroup)) = LOWER(TRIM(?))",
                    [{value: categoryName, cfsqltype: "cf_sql_varchar"}],
                    {datasource: application.db.dsn}
                );
                
                if (catCount.recordCount GT 0 AND val(catCount.cnt) GT 0) {
                    actualCategory = catCount.actual_name[1];
                    countResult = "The total number of lots in the category of <strong>" & htmlEditFormat(actualCategory) & "</strong> is <strong>" & catCount.cnt & " lots</strong>.";
                    writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                    abort;
                }
                
                // Try partial match if exact match fails
                catCount = queryExecute(
                    "SELECT COUNT(*) as cnt FROM lots WHERE majgroup ILIKE ?",
                    [{value: "%" & categoryName & "%", cfsqltype: "cf_sql_varchar"}],
                    {datasource: application.db.dsn}
                );
                
                if (catCount.recordCount GT 0 AND val(catCount.cnt) GT 0) {
                    // Get the actual category name(s) that matched
                    catNames = queryExecute(
                        "SELECT DISTINCT majgroup, COUNT(*) as lot_count FROM lots WHERE majgroup ILIKE ? GROUP BY majgroup ORDER BY lot_count DESC LIMIT 5",
                        [{value: "%" & categoryName & "%", cfsqltype: "cf_sql_varchar"}],
                        {datasource: application.db.dsn}
                    );
                    
                    if (catNames.recordCount EQ 1) {
                        actualCategory = catNames.majgroup[1];
                        countResult = "The total number of lots in the category of <strong>" & htmlEditFormat(actualCategory) & "</strong> is <strong>" & catCount.cnt & " lots</strong>.";
                    } else {
                        countResult = "Found <strong>" & catCount.cnt & " lots</strong> matching ""<strong>" & htmlEditFormat(categoryName) & "</strong>"". ";
                        if (catNames.recordCount GT 0) {
                            countResult &= "Matching categories: ";
                            catList = [];
                            for (i = 1; i LTE catNames.recordCount; i++) {
                                arrayAppend(catList, htmlEditFormat(catNames.majgroup[i]) & " (" & catNames.lot_count[i] & " lots)");
                            }
                            countResult &= arrayToList(catList, ", ");
                        }
                    }
                    writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                    abort;
                }
            } else {
                // General count query - total lots
                totalCount = queryExecute(
                    "SELECT COUNT(*) as cnt FROM lots",
                    [],
                    {datasource: application.db.dsn}
                );
                
                if (totalCount.recordCount GT 0) {
                    countResult = "The total number of lots in the database is <strong>" & totalCount.cnt & " lots</strong>.";
                    writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                    abort;
                }
            }
        } catch (any e) {
            // If direct query fails, log error and fall through to RAG search
            // writeOutput("<p>Debug: " & htmlEditFormat(e.message) & "</p>");
            isCountingQuery = false;
        }
    }
}
</cfscript>

<!--- Step 1: Embedding --->
<cfhttp url="#application.ai.apiBaseUrl#/embeddings" method="POST" result="embedCall" timeout="#application.ai.timeout#">
    <cfhttpparam type="header" name="Authorization" value="Bearer #openaiKey#" />
    <cfhttpparam type="header" name="Content-Type" value="application/json" />
    <cfhttpparam type="body" value='{"model": "#application.ai.embedModel#", "input": "#Replace(userPrompt, '"', '""', 'all')#"}' />
</cfhttp>

<cfscript>
   
    try {
    if (findNoCase("error", embedCall.fileContent)) {
            writeOutput("<p>API Error: " & htmlEditFormat(embedCall.fileContent) & "</p>");
            abort;
        }
        embedJSON = deserializeJSON(embedCall.fileContent);
        embedding = embedJSON.data[1].embedding;
        embStr = "[" & ArrayToList(embedding, ",") & "]";
    } catch (any e) {
        writeOutput("<p>Embedding API Error: " & htmlEditFormat(e.message) & "</p>");
        abort;
    }
</cfscript>

<!--- Step 2: DB Search --->
    <cfquery name="relatedChunks" datasource="#application.db.dsn#">
        SELECT 
            l.source_type,
            l.source_name,
            l.source_id,
            l.title,
            l.category,
            l.content_type,
            l.chunk_text,
            l.metadata,
            1 - (l.embedding <-> <cfqueryparam value="#embStr#" cfsqltype="cf_sql_varchar">::vector) AS similarity
        FROM chunks l
        WHERE l.embedding IS NOT NULL
        ORDER BY l.embedding <-> <cfqueryparam value="#embStr#" cfsqltype="cf_sql_varchar">::vector ASC
    LIMIT 25
    </cfquery>

<cfscript>
    maxItems = application.ai.maxItems;
    maxChars = application.ai.maxChars;
    chunks = [];
    contextText = "";
contextCap = 20000;

    if (isQuery(relatedChunks) AND relatedChunks.recordCount GT 0) {
        for (row = 1; row LTE relatedChunks.recordCount; row++) {
            if (arrayLen(chunks) GTE maxItems) break;
            snippetTxt = relatedChunks.chunk_text[row];
            simVal = val(relatedChunks.similarity[row]);
            
            // Add metadata info (especially image URL) to context
            metaStr = "";
            if (len(relatedChunks.metadata[row])) {
                try {
                    meta = deserializeJSON(relatedChunks.metadata[row]);
                    if (structKeyExists(meta, "imageUrl") && len(meta.imageUrl)) {
                        metaStr = chr(10) & "Image URL: " & meta.imageUrl;
                    }
                    if (structKeyExists(meta, "lotUrl") && len(meta.lotUrl)) {
                        metaStr &= chr(10) & "Lot URL: " & meta.lotUrl;
                    }
                } catch (any e) {}
            }
            
            if (len(snippetTxt)) {
                arrayAppend(chunks, {"text": snippetTxt, "similarity": simVal});
                if (len(contextText) LT contextCap) {
                    remaining = contextCap - len(contextText);
                    contextText &= left(snippetTxt & metaStr, remaining) & chr(10) & "---" & chr(10);
                }
            }
        }
    }

systemRole = "You are a helpful auction lot and numismatic assistant. Use only the provided context to answer questions. " &
    "SEARCH FLEXIBILITY: When users ask about lots, they may use partial lot numbers, auction names, categories, coin types, or descriptions. Match flexibly. " &
    "For example: 'lot 23006', 'Philip II tetradrachm', 'ancient coins', 'macedonian kingdom' should all find relevant lots. " &
    "RESPONSE FORMAT: " &
    "- For lot queries: Show lot number, title, full description, category, prices (starting/realized if available), and display the image using ![Lot Image](imageUrl). " &
    "- For counting queries: Provide the exact count from statistics chunks. " &
    "- For category queries: List relevant lots with brief descriptions. " &
    "OUTPUT: Use Markdown (**, ##, -, 1.) for formatting. DO NOT use HTML tags like <ol>, <ul>, <li>, <strong>, etc. Use only Markdown syntax. " &
    "IMAGES: Always include images when available using ![Lot Image](URL) format. " &
    "If you cannot find relevant information in the context, say: I could not find information about that in the database.";

history = session.chatHistory;
priorMessages = [];
for (i = 1; i LTE arrayLen(history); i++) {
    if (structKeyExists(history[i], "role") and structKeyExists(history[i], "content")) {
        arrayAppend(priorMessages, { "role": history[i].role, "content": left(history[i].content, 800) });
    }
}
</cfscript>

<!--- Step 3: AI Call --->
<cfhttp url="#application.ai.apiBaseUrl#/chat/completions" method="POST" result="gptCall" timeout="#application.ai.timeout#">
    <cfhttpparam type="header" name="Authorization" value="Bearer #openaiKey#" />
    <cfhttpparam type="header" name="Content-Type" value="application/json; charset=utf-8" />
    <cfset messages = [
        {"role": "system", "content": systemRole},
        {"role": "system", "content": "Context:\n\n" & left(contextText, 20000)}
    ] />
    <cfloop array="#priorMessages#" index="pm">
        <cfset arrayAppend(messages, pm) />
    </cfloop>
    <cfset arrayAppend(messages, {"role": "user", "content": userPrompt}) />
    <cfset body = {"model": application.ai.chatModel, "temperature": 0, "max_tokens": 4000, "messages": messages} />
    <cfhttpparam type="body" value="#serializeJSON(body)#" />
</cfhttp>
<!--- <cfdump var="#gptCall#"> --->
<!--- Step 4: Response --->
<cfscript>
    aiAnswerText = "No response";
    
    if (len(gptCall.fileContent)) {
        try {
            gptResponse = deserializeJSON(gptCall.fileContent);
         
            if (structKeyExists(gptResponse, "choices") AND arrayLen(gptResponse.choices)) {
                assistantMarkdown = gptResponse.choices[1].message.content ?: "";
                
                // First, strip any HTML tags that AI might have generated
                assistantMarkdown = reReplace(assistantMarkdown, "<[^>]*>", "", "all");
                
                // Markdown to HTML conversion
                html = assistantMarkdown ?: "";
                lines = listToArray(html, chr(10));
                html = "";
                inList = false;
                listType = "";
        
                for (i = 1; i <= arrayLen(lines); i++) {
                    line = trim(lines[i]);
                    
                    if (len(line) EQ 0) {
                        if (inList) {
                            html &= "</" & listType & ">";
                            inList = false;
                            listType = "";
                        }
                        html &= "<br>";
                        continue;
                    }
                    
                    // Headers
                    if (left(line, 3) EQ "#### ") {
                        if (inList) { html &= "</" & listType & ">"; inList = false; listType = ""; }
                        headerText = mid(line, 3, len(line));
                        html &= "<h3>" & headerText & "</h3>";
                    }

                    else if (left(line, 2) EQ "## ") {
                        if (inList) { html &= "</" & listType & ">"; inList = false; listType = ""; }
                        headerText = mid(line, 2, len(line));
                        html &= "<h2>" & headerText & "</h2>";
                    }
                

                    // Unordered lists
                    else if (left(line, 2) EQ "- ") {
                        if (!inList OR listType NEQ "ul") {
                            if (inList) html &= "</" & listType & ">";
                            html &= "<ul>";
                            inList = true;
                            listType = "ul";
                        }
                        listText = mid(line, 3, len(line));
                        html &= "<li>" & listText & "</li>";
                    }
                    // Ordered lists
                    else if (reFind('^\d+\.', line)) {
                        if (!inList OR listType NEQ "ol") {
                            if (inList) html &= "</" & listType & ">";
                            html &= "<ol>";
                            inList = true;
                            listType = "ol";
                        }
                        listText = reReplace(line, '^\d+\.\s*', '');
                        html &= "<li>" & listText & "</li>";
                    }
                    // Paragraph
                    // else {
                    //     if (inList) { html &= "</" & listType & ">"; inList = false; listType = ""; }
                    //     html &= "<p>" & line & "</p>";
                    // }
                    else {
                        if (inList) {
                            html &= "</" & listType & ">";
                            inList = false;
                            listType = "";
                        }
                        html &=  htmlEditFormat(line) ;
                    }

                }
            
                if (inList) { html &= "</" & listType & ">"; }
            
                // Inline formatting
                html = reReplace(html, '\*\*([^*]+)\*\*', '<strong>\1</strong>', 'all'); // bold
                html = reReplace(html, '(^|[^*])\*([^*]+)\*', '\1<em>\2</em>', 'all');   // italics, avoid **
                
                aiAnswerText = html;
                arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                arrayAppend(session.chatHistory, {"role": "assistant", "content": aiAnswerText});
            }
        } catch (any e) {
            aiAnswerText = "Response parse error: " & e.message;
        }
    }
    
    // Final cleanup: strip any remaining HTML tags and convert to plain text with line breaks
    aiAnswerText = trim( reReplace( aiAnswerText, "<[^>]*>", "", "all" ) );
    // Convert HTML entities back to plain text if needed
    aiAnswerText = reReplace(aiAnswerText, "&nbsp;", " ", "all");
    aiAnswerText = reReplace(aiAnswerText, "&amp;", "&", "all");
    aiAnswerText = reReplace(aiAnswerText, "&lt;", "<", "all");
    aiAnswerText = reReplace(aiAnswerText, "&gt;", ">", "all");
    aiAnswerText = reReplace(aiAnswerText, "&quot;", '"', "all");
    // Convert <br> and <br/> to line breaks for better readability
    aiAnswerText = reReplace(aiAnswerText, "<br\s*/?>", chr(10), "all");

    // if (!len(reReplace(aiAnswerText, '<[^>]+>', '', 'all'))) {
    //     aiAnswerText =  htmlEditFormat(left(contextText, 1000)) ;
    // }
   
</cfscript>
    
<!--- Step 5: Display --->
<cfoutput>
    
    <div class="answer-box"> #aiAnswerText#</div>
</cfoutput>

    

