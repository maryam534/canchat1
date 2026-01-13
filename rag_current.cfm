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
    if (findNoCase("error", embedCall.fileContent) OR findNoCase("overflow", embedCall.fileContent) OR findNoCase("timeout", embedCall.fileContent)) {
            writeOutput("<p>API Error: " & htmlEditFormat(embedCall.fileContent) & "</p>");
            abort;
        }
        embedJSON = deserializeJSON(embedCall.fileContent);
        embedding = embedJSON.data[1].embedding;
        embStr = "[" & ArrayToList(embedding, ",") & "]";
    } catch (any e) {
        writeOutput("<p>Embedding API Error: " & htmlEditFormat(e.message) & "</p>");
        writeOutput("<p>Raw response: " & htmlEditFormat(embedCall.fileContent) & "</p>");
        writeOutput("<p>Please check your OpenAI API key and try again.</p>");
        abort;
    }
</cfscript>

<!--- Step 2: Decide mode (specialized lot/stamp/coin vs generic) --->
<cfscript>
    // Detect explicit lot numbers
    exactLotNum = "";
    lotPatterns = [
        "\b(?:bring\s+)?(?:show\s+(?:me\s+)?)?lot\s*##?\s*(\d+)\b",
        "\blot\s*##?\s*(\d+)\b",
        "\b##\s*(\d+)\b",
        "\bnumber\s+(\d+)\b"
    ];
    for (pattern in lotPatterns) {
        lotMatch = reFindNoCase(pattern, userPrompt, 1, true);
        if (structKeyExists(lotMatch, "len") AND lotMatch.len[1] GT 0) {
            exactLotNum = mid(userPrompt, lotMatch.pos[2], lotMatch.len[2]);
            writeLog(file="rag_debug", text="Detected lot number query: #exactLotNum# from pattern: #pattern#", type="information");
            break;
        }
    }
    isLotQuery = len(exactLotNum) GT 0;
    // Detect stamp/coin/auction/lot domain keywords
    isStampDomainQuery = reFindNoCase("\b(stamp|stamps|coin|coins|auction|auctions|lot|lots|philatelic|numisbids)\b", userPrompt) GT 0;
    useSpecialMode = isLotQuery OR isStampDomainQuery;
</cfscript>

<!--- Step 2a: Specialized mode using chunks + lots (unified table) --->
<cfif useSpecialMode>
    <!--- Prefer direct lot search when we have an exact lot number --->
    <cfif len(exactLotNum)>
        <cfquery name="directLotSearch" datasource="#application.db.dsn#">
            SELECT 
                lots.title,
                lots.catdescr,
                lots.lot_url,
                lots.image_url,
                lots.realized,
                lots.opening,
                lots.est_low,
                lots.est_real,
                lots.currency,
                l.chunk_text,
                1.0 AS similarity
            FROM chunks l
            INNER JOIN lots ON lots.lot_pk = CAST(l.source_id AS INTEGER)
            WHERE l.source_type = 'lot'
              AND (lots.lot_url LIKE <cfqueryparam value="%/lot/#exactLotNum#" cfsqltype="cf_sql_varchar">
               OR l.chunk_text LIKE <cfqueryparam value="%Lot #exactLotNum#:%%" cfsqltype="cf_sql_varchar">)
            LIMIT 5
        </cfquery>
        <cfif directLotSearch.recordCount GT 0>
            <cfset relatedChunks = directLotSearch>
        <cfelse>
            <cfquery name="relatedChunks" datasource="#application.db.dsn#">
                SELECT 
                    lots.title,
                    lots.catdescr,
                    lots.lot_url,
                    lots.image_url,
                    lots.realized,
                    lots.opening,
                    lots.est_low,
                    lots.est_real,
                    lots.currency,
                    l.chunk_text,
                    1 - (l.embedding <-> <cfqueryparam value="#embStr#" cfsqltype="cf_sql_varchar">::vector) AS similarity
                FROM chunks l
                INNER JOIN lots ON lots.lot_pk = CAST(l.source_id AS INTEGER)
                WHERE l.source_type = 'lot'
                  AND l.embedding IS NOT NULL
                ORDER BY l.embedding <-> <cfqueryparam value="#embStr#" cfsqltype="cf_sql_varchar">::vector ASC
                LIMIT 10
            </cfquery>
        </cfif>
    <cfelse>
        <cfquery name="relatedChunks" datasource="#application.db.dsn#">
            SELECT 
                lots.title,
                lots.catdescr,
                lots.lot_url,
                lots.image_url,
                lots.realized,
                lots.opening,
                lots.est_low,
                lots.est_real,
                lots.currency,
                l.chunk_text,
                1 - (l.embedding <-> <cfqueryparam value="#embStr#" cfsqltype="cf_sql_varchar">::vector) AS similarity
            FROM chunks l
            INNER JOIN lots ON lots.lot_pk = CAST(l.source_id AS INTEGER)
            WHERE l.source_type = 'lot'
              AND l.embedding IS NOT NULL
            ORDER BY l.embedding <-> <cfqueryparam value="#embStr#" cfsqltype="cf_sql_varchar">::vector ASC
            LIMIT #application.db.vectorLimit#
        </cfquery>
    </cfif>

<cfscript>
    // Process results into structured chunks with price intelligence (specialized)
    maxItems = application.ai.maxItems;
    maxChars = application.ai.maxChars;
    chunks = [];
    totalChars = 0;
    contextText = "";
    if (isQuery(relatedChunks) AND relatedChunks.recordCount GT 0) {
        for (row = 1; row LTE relatedChunks.recordCount; row++) {
            if (arrayLen(chunks) GTE maxItems) break;
            lotUrl = relatedChunks.lot_url[row];
            lotNumber = reReplaceNoCase(lotUrl, ".*/lot/(\d+).*", "\1");
            titleTxt = relatedChunks.title[row];
            catTxt = relatedChunks.catdescr[row];
            snippetTxt = relatedChunks.chunk_text[row];
            simVal = isNumeric(relatedChunks.similarity[row]) ? val(relatedChunks.similarity[row]) : 0;
            imageUrl = relatedChunks.image_url[row];
            startMatch = reFindNoCase("(?i)Starting\s*:\s*([^\s]+(?:\s+[A-Z]{3})?)", snippetTxt, 1, true);
            realizedMatch = reFindNoCase("(?i)Realized\s*:\s*([^\s]+(?:\s+[A-Z]{3})?)", snippetTxt, 1, true);
            startingPrice = "";
            realizedPrice = "";
            if (startMatch.len[1] GT 0) {
                startingPrice = trim(mid(snippetTxt, startMatch.pos[2], startMatch.len[2]));
                startingPrice = trim(reReplaceNoCase(startingPrice, "\s+Realized.*", "", "all"));
            }
            if (realizedMatch.len[1] GT 0) {
                realizedPrice = trim(mid(snippetTxt, realizedMatch.pos[2], realizedMatch.len[2]));
                if (realizedPrice EQ "" OR realizedPrice EQ " ") {
                    realizedPrice = "";
                }
            }
            if (len(realizedPrice) EQ 0 AND isNumeric(relatedChunks.realized[row]) AND relatedChunks.realized[row] GT 0) {
                realizedPrice = numberFormat(relatedChunks.realized[row], "999,999.99") & " " & (relatedChunks.currency[row] ?: "");
            }
            if (len(startingPrice) EQ 0 AND isNumeric(relatedChunks.opening[row]) AND relatedChunks.opening[row] GT 0) {
                startingPrice = numberFormat(relatedChunks.opening[row], "999,999.99") & " " & (relatedChunks.currency[row] ?: "");
            } else if (len(startingPrice) EQ 0 AND isNumeric(relatedChunks.est_low[row]) AND relatedChunks.est_low[row] GT 0) {
                startingPrice = numberFormat(relatedChunks.est_low[row], "999,999.99") & " " & (relatedChunks.currency[row] ?: "") & " (est)";
            }
            bestPrice = "";
            bestPriceLabel = "";
            if (isNumeric(relatedChunks.realized[row]) AND relatedChunks.realized[row] GT 0) {
                bestPrice = numberFormat(relatedChunks.realized[row], "999,999.99") & " " & (relatedChunks.currency[row] ?: "USD");
                bestPriceLabel = "Realized";
            } else if (isNumeric(relatedChunks.opening[row]) AND relatedChunks.opening[row] GT 0) {
                bestPrice = numberFormat(relatedChunks.opening[row], "999,999.99") & " " & (relatedChunks.currency[row] ?: "USD");
                bestPriceLabel = "Starting";
            } else if (len(realizedPrice)) {
                bestPrice = realizedPrice;
                bestPriceLabel = "Realized";
            } else if (len(startingPrice)) {
                bestPrice = startingPrice;
                bestPriceLabel = "Starting";
            } else if (isNumeric(relatedChunks.est_low[row]) AND relatedChunks.est_low[row] GT 0) {
                bestPrice = numberFormat(relatedChunks.est_low[row], "999,999.99") & " " & (relatedChunks.currency[row] ?: "USD") & " (est)";
                bestPriceLabel = "Estimate";
            } else {
                bestPrice = "Not available";
                bestPriceLabel = "Price unavailable";
            }
            arrayAppend(chunks, {
                "id": "lot-" & lotNumber,
                "lotnumber": lotNumber,
                "title": titleTxt,
                "url": lotUrl,
                "category": catTxt,
                "image_url": imageUrl,
                "startingprice": startingPrice,
                "realizedprice": realizedPrice,
                "best_price": bestPrice,
                "best_price_label": bestPriceLabel,
                "similarity": simVal,
                "currency": relatedChunks.currency[row] ?: "",
                "db_realized": relatedChunks.realized[row] ?: "",
                "db_opening": relatedChunks.opening[row] ?: "",
                "db_est_low": relatedChunks.est_low[row] ?: ""
            });
            if (totalChars + len(snippetTxt) LTE maxChars) {
                contextText &= snippetTxt & chr(10);
                totalChars += len(snippetTxt);
            }
        }
    }
    if (len(exactLotNum)) {
        exactIndex = 0;
        for (i = 1; i LTE arrayLen(chunks); i++) {
            if (chunks[i].lotnumber EQ exactLotNum) {
                exactIndex = i;
                break;
            }
        }
        if (exactIndex GT 1) {
            exactChunk = chunks[exactIndex];
            arrayDeleteAt(chunks, exactIndex);
            exactChunk.similarity = 1;
            arrayInsertAt(chunks, 1, exactChunk);
        }
    }
    // Stamp auction specialist instructions (JSON mode)
    systemRole = "You are a stamp auction specialist assistant. Return JSON with items array. " &
        "Answer only about stamp and coin auctions. Be precise, concise, and grounded in provided data. " &
        "PRICE RULES: - Use chunk.best_price as price_value; - Use chunk.best_price_label as price_label; " &
        "If chunk.best_price is empty, use 'Not available'. Never leave price_value empty. " &
        "OUTPUT JSON SCHEMA: " &
        "{""answer"": ""text"", ""items"": [{""id"": ""lot-X"", ""lotnumber"": ""X"", ""title"": ""text"", ""url"": ""URL"", " &
        """price_label"": ""Starting|Realized|Estimate|Price unavailable"", ""price_value"": ""X.XX CUR"", ""similarity"": 0.XX, " &
        """image_url"": ""URL"", ""category"": ""text"", ""currency"": ""CUR""}], ""citations"": [""lot-X""]}";
    modelPayload = {
        "query": userPrompt,
        "chunks": chunks,
        "extracted_lot_number": exactLotNum,
        "instructions": {
            "min_similarity": 0.0,
            "max_items": 5,
            "is_lot_query": isLotQuery,
            "query_type": isLotQuery ? "lot_number" : "general_search"
        }
    };
</cfscript>

<!--- Step 3a: AI Call (JSON mode) --->
<cfhttp url="#application.ai.apiBaseUrl#/chat/completions" method="POST" result="gptCall" timeout="#application.ai.timeout#">
    <cfhttpparam type="header" name="Authorization" value="Bearer #openaiKey#" />
    <cfhttpparam type="header" name="Content-Type" value="application/json; charset=utf-8" />
    <cfset messages = [
        {"role": "system", "content": systemRole},
        {"role": "user", "content": serializeJSON(modelPayload)}
    ] />
    <cfset body = {
        "model": application.ai.chatModel,
        "temperature": 0,
        "response_format": { "type": "json_object" },
        "messages": messages
    } />
    <cfhttpparam type="body" value="#serializeJSON(body)#" />
</cfhttp>

<!--- Step 4a: Parse JSON response and prepare display --->
<cfscript>
    aiAnswerText = "No response from GPT.";
    aiJSON = {};
    if (structKeyExists(gptCall, "fileContent") AND len(gptCall.fileContent)) {
        if (findNoCase("timeout", gptCall.fileContent) OR findNoCase("error", gptCall.fileContent)) {
            aiAnswerText = "API Error: " & gptCall.fileContent & ". Please try again.";
            writeLog(file="rag_debug", text="API Error: #gptCall.fileContent#", type="error");
        } else {
            try {
                gptResponse = deserializeJSON(gptCall.fileContent);
                if (structKeyExists(gptResponse, "choices") AND arrayLen(gptResponse.choices)) {
                    rawContent = gptResponse.choices[1].message.content;
                    try {
                        aiJSON = deserializeJSON(rawContent);
                        aiAnswerText = aiJSON.answer;
                    } catch (any e) {
                        aiAnswerText = rawContent;
                        writeLog(file="rag_debug", text="JSON parse error in AI response: #e.message#", type="error");
                    }
                } else {
                    aiAnswerText = "Invalid AI response format.";
                    writeLog(file="rag_debug", text="Invalid GPT response structure", type="error");
                }
            } catch (any e) {
                aiAnswerText = "API Response Error: " & e.message & ". Raw response: " & gptCall.fileContent;
                writeLog(file="rag_debug", text="GPT response parse error: #e.message# | Raw: #gptCall.fileContent#", type="error");
            }
        }
    } else {
        aiAnswerText = "No response received from AI service.";
    }
    if ((NOT structKeyExists(aiJSON, "items") OR arrayLen(aiJSON.items) EQ 0) AND arrayLen(chunks) GT 0) {
        aiJSON = {"answer": "Found #arrayLen(chunks)# relevant results:", "items": [], "citations": []};
        for (chunk in chunks) {
            arrayAppend(aiJSON.items, {
                "id": chunk.id,
                "lotnumber": chunk.lotnumber,
                "title": chunk.title,
                "url": chunk.url,
                "price_label": chunk.best_price_label,
                "price_value": chunk.best_price,
                "similarity": chunk.similarity,
                "image_url": chunk.image_url,
                "category": chunk.category,
                "currency": chunk.currency
            });
            arrayAppend(aiJSON.citations, chunk.id);
        }
        aiAnswerText = aiJSON.answer;
    }
    if (structKeyExists(aiJSON, "items") AND arrayLen(aiJSON.items) GT 0) {
        for (i = 1; i LTE arrayLen(aiJSON.items); i++) {
            item = aiJSON.items[i];
            if (NOT structKeyExists(item, "price_value") OR len(item.price_value) EQ 0) {
                for (chunk in chunks) {
                    if (chunk.lotnumber EQ item.lotnumber) {
                        aiJSON.items[i].price_value = chunk.best_price;
                        aiJSON.items[i].price_label = chunk.best_price_label;
                        break;
                    }
                }
            }
        }
    }
    // Helper for UI badge styles
    function priceBadgeClass(label) {
        switch (lcase(label)) {
            case "realized":
                return "background:##e8f5e9;color:##256029;border:1px solid ##c8e6c9;";
            case "starting":
                return "background:##e3f2fd;color:##0d47a1;border:1px solid ##bbdefb;";
            case "estimate":
                return "background:##f3e5f5;color:##7b1fa2;border:1px solid ##e1bee7;";
            default:
                return "background:##fff3e0;color:##e65100;border:1px solid ##ffe0b2;";
        }
    }
</cfscript>

<!--- Step 5a: Display specialized results --->
<cfoutput>
    <style>
        .lots-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 16px; margin-top: 12px; }
        .lot-card { border: 1px solid ##ddd; border-radius: 10px; background: ##fff; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }
        .lot-media { width: 100%; height: 170px; object-fit: cover; background: ##f5f5f5; display: block; }
        .lot-body { padding: 12px 14px; }
        .lot-title { font-size: 15px; font-weight: 600; margin: 0 0 8px 0; line-height: 1.3; }
        .lot-meta { font-size: 12px; color: ##666; margin-bottom: 8px; }
        .badge { display: inline-block; padding: 3px 8px; font-size: 12px; border-radius: 999px; margin-right: 6px; }
        .price { font-size: 14px; font-weight: 700; margin-top: 6px; }
        .answer-box { border: 1px solid ##ccc; padding: 10px; background: ##f9f9f9; white-space: pre-wrap; border-radius: 8px; }
        .lot-link { text-decoration: none; color: ##0b57d0; }
        .lot-link:hover { text-decoration: underline; }
    </style>
    <h2>AI Answer</h2>
    <div class="answer-box">#htmlEditFormat(aiAnswerText)#</div>
    <cfif structKeyExists(aiJSON, "items") AND isArray(aiJSON.items) AND arrayLen(aiJSON.items)>
        <div class="lots-grid">
            <cfloop array="#aiJSON.items#" index="it">
                <cfset plabel = structKeyExists(it, "price_label") ? it.price_label : "Price unavailable">
                <cfset pvalue = structKeyExists(it, "price_value") ? it.price_value : "">
                <cfif len(pvalue) EQ 0 OR pvalue EQ "N/A" OR pvalue EQ "">
                    <cfloop array="#chunks#" index="chunk">
                        <cfif chunk.lotnumber EQ it.lotnumber>
                            <cfset pvalue = chunk.best_price>
                            <cfset plabel = chunk.best_price_label>
                            <cfif len(pvalue) EQ 0 AND len(chunk.startingprice)>
                                <cfset pvalue = chunk.startingprice>
                                <cfset plabel = "Starting">
                            </cfif>
                            <cfbreak>
                        </cfif>
                    </cfloop>
                    <cfif len(pvalue) EQ 0>
                        <cfset pvalue = "Not available">
                        <cfset plabel = "Price unavailable">
                    </cfif>
                </cfif>
                <cfset badgeStyle = priceBadgeClass(plabel)>
                <div class="lot-card">
                    <cfif structKeyExists(it, "image_url") AND len(it.image_url)>
                        <img class="lot-media" src="#htmlEditFormat(it.image_url)#" alt="Lot image">
                    <cfelse>
                        <div class="lot-media"></div>
                    </cfif>
                    <div class="lot-body">
                        <div class="lot-meta">Lot ## #htmlEditFormat(it.lotnumber)#</div>
                        <h3 class="lot-title">
                            <a class="lot-link" href="#htmlEditFormat(it.url)#" target="_blank">#htmlEditFormat(it.title)#</a>
                        </h3>
                        <div class="badge" style="#badgeStyle#">#htmlEditFormat(plabel)#</div>
                        <cfif len(pvalue)>
                            <div class="price">#htmlEditFormat(pvalue)#</div>
                        <cfelse>
                            <div class="price">N/A</div>
                        </cfif>
                        <cfif structKeyExists(it, "category") AND len(it.category)>
                            <div class="lot-meta">#htmlEditFormat(it.category)#</div>
                        </cfif>
                        <cfif structKeyExists(aiJSON, "citations") AND arrayFind(aiJSON.citations, it.id)>
                            <div class="lot-meta">[#htmlEditFormat(it.id)#]</div>
                        </cfif>
                    </div>
                </div>
            </cfloop>
        </div>
    </cfif>
    <cfif isQuery(relatedChunks) AND relatedChunks.recordCount GT 0>
        <h2 class="mt-6">Related Lots (Top 3)</h2>
        <div class="lots-grid">
            <cfloop query="relatedChunks" startrow="1" endrow="3">
                <cfset lotNum = reReplaceNoCase(lot_url, ".*/lot/(\d+).*", "\1")>
                <cfset sMatch = reFindNoCase("(?i)Starting\s*:\s*([^\s]+(?:\s+[A-Z]{3})?)", chunk_text, 1, true)>
                <cfset rMatch = reFindNoCase("(?i)Realized\s*:\s*([^\s]+(?:\s+[A-Z]{3})?)", chunk_text, 1, true)>
                <cfset sVal = ""><cfset rVal = "">
                <cfif sMatch.len[1] GT 0><cfset sVal = trim(reReplaceNoCase(mid(chunk_text, sMatch.pos[2], sMatch.len[2]), "\s+Realized.*", "", "all"))></cfif>
                <cfif rMatch.len[1] GT 0><cfset rVal = trim(mid(chunk_text, rMatch.pos[2], rMatch.len[2]))><cfif rVal EQ "" OR rVal EQ " "><cfset rVal = ""></cfif></cfif>
                <cfset bestPrice = ""><cfset bestLabel = "">
                <cfif isNumeric(realized) AND realized GT 0>
                    <cfset bestPrice = numberFormat(realized, "999,999.99") & " " & (currency ?: "USD")><cfset bestLabel = "Realized">
                <cfelseif isNumeric(opening) AND opening GT 0>
                    <cfset bestPrice = numberFormat(opening, "999,999.99") & " " & (currency ?: "USD")><cfset bestLabel = "Starting">
                <cfelseif len(rVal)><cfset bestPrice = rVal><cfset bestLabel = "Realized">
                <cfelseif len(sVal)><cfset bestPrice = sVal><cfset bestLabel = "Starting">
                <cfelseif isNumeric(est_low) AND est_low GT 0>
                    <cfset bestPrice = numberFormat(est_low, "999,999.99") & " " & (currency ?: "USD") & " (est)"><cfset bestLabel = "Estimate">
                <cfelse><cfset bestPrice = "Not available"><cfset bestLabel = "Price unavailable"></cfif>
                <cfset bStyle = priceBadgeClass(bestLabel)>
                <div class="lot-card">
                    <cfif len(image_url)>
                        <img class="lot-media" src="#htmlEditFormat(image_url)#" alt="Lot #htmlEditFormat(lotNum)# preview">
                    <cfelse>
                        <div class="lot-media" style="display:flex; align-items:center; justify-content:center; color:##999; font-size:14px;">
                            <span class="bg-gray-300 px-2 py-1 rounded">No Image</span>
                        </div>
                    </cfif>
                    <div class="lot-body">
                        <div class="lot-meta">Lot ###htmlEditFormat(lotNum)# <span class="float-right text-xs">Match: #numberFormat(similarity * 100, "0")#%</span></div>
                        <h3 class="lot-title"><a class="lot-link" href="#htmlEditFormat(lot_url)#" target="_blank" title="View full lot details">#htmlEditFormat(title)#</a></h3>
                        <div class="badge" style="#bStyle#">#htmlEditFormat(bestLabel)#</div>
                        <cfif len(bestPrice)><div class="price">#htmlEditFormat(bestPrice)#</div><cfelse><div class="price text-gray-500">N/A</div></cfif>
                        <cfif len(catdescr)><div class="lot-meta" title="#htmlEditFormat(catdescr)#">#left(htmlEditFormat(catdescr), 50)##len(catdescr) GT 50 ? "..." : ""#</div></cfif>
                    </div>
                </div>
            </cfloop>
        </div>
    </cfif>
</cfoutput>

<!--- END specialized branch --->
<cfelse>
    <!--- Step 2b: Generic chunks search (existing behavior) --->
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
    // Stamp auction specialist tone (Markdown mode)
    systemRole = "You are a grounded stamp auction specialist. Use only the provided context. " &
    "Produce a complete answer without truncation. Output in Markdown format with proper formatting (**, ##, -, 1.). " &
    "Do not add role labels, do not include external links, and do not hallucinate beyond the context.";
history = session.chatHistory;
priorMessages = [];
for (i = 1; i LTE arrayLen(history); i++) {
    if (structKeyExists(history[i], "role") and structKeyExists(history[i], "content")) {
        arrayAppend(priorMessages, { "role": history[i].role, "content": left(history[i].content, 800) });
    }
}
</cfscript>

<!--- Step 3b: AI Call (Markdown mode) --->
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

<!--- Step 4b: Response --->
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
    
    if (!len(reReplace(aiAnswerText, '<[^>]+>', '', 'all'))) {
        aiAnswerText = '<p>' & htmlEditFormat(left(contextText, 1000)) & '</p>';
    }
    </cfscript>
    
    <!--- Step 5b: Display --->
    <cfoutput>
       
        <div class="answer-box">#aiAnswerText#</div>
    </cfoutput>
</cfif>
    

    