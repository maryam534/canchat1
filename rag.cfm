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
        if (len(snippetTxt)) {
            arrayAppend(chunks, {"text": snippetTxt, "similarity": simVal});
            if (len(contextText) LT contextCap) {
                remaining = contextCap - len(contextText);
                contextText &= left(snippetTxt, remaining) & chr(10);
            }
        }
    }
}

systemRole = "You are a grounded assistant. Use only the provided context. " &
    "Produce a complete answer without truncation. Output in Markdown format with proper formatting (**, ##, -, 1.). " &
    "Do not add role labels, do not include external links, and do not hallucinate beyond the context. If you Don't know the answer from query then say, I don't know the answer to that question.";

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
     aiAnswerText = trim( reReplace( aiAnswerText, "<[^>]*>", "", "all" ) );

    // if (!len(reReplace(aiAnswerText, '<[^>]+>', '', 'all'))) {
    //     aiAnswerText =  htmlEditFormat(left(contextText, 1000)) ;
    // }
   
</cfscript>
    
<!--- Step 5: Display --->
<cfoutput>
    
    <div class="answer-box"> #aiAnswerText#</div>
</cfoutput>

    

