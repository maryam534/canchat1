<!---
    Generate Summary Chunks for RAG
    Creates statistical summary chunks so chatbot can answer "how many" questions
--->
<cfsetting requesttimeout="600" />
<cfparam name="url.run" default="false" />

<cfif url.run EQ "true">
<cfscript>
    // Get OpenAI configuration
    embedModel = application.ai.embedModel;
    openaiKey = replace(application.ai.openaiKey, '"', "", "all");
    apiBaseUrl = application.ai.apiBaseUrl;
    timeout = application.ai.timeout ?: 90;
    
    summaries = [];
    
    // 1. Total lots count
    totalLots = queryExecute("SELECT COUNT(*) as cnt FROM lots", [], {datasource: application.db.dsn});
    arrayAppend(summaries, {
        id: "summary_total_lots",
        text: "Total Lots Statistics: We have " & totalLots.cnt & " total auction lots in the database. " &
              "The total number of lots available is " & totalLots.cnt & ". " &
              "There are " & totalLots.cnt & " lots in our collection.",
        title: "Total Lots Count",
        category: "statistics"
    });
    
    // 2. Lots by category (majgroup)
    catStats = queryExecute(
        "SELECT majgroup as category, COUNT(*) as cnt FROM lots WHERE majgroup IS NOT NULL AND majgroup != '' GROUP BY majgroup ORDER BY cnt DESC",
        [], {datasource: application.db.dsn}
    );
    
    catText = "Lots by Category Statistics: ";
    catList = [];
    for (row in catStats) {
        arrayAppend(catList, row.category & ": " & row.cnt & " lots");
        // Individual category chunk
        arrayAppend(summaries, {
            id: "summary_category_" & lcase(reReplace(row.category, "[^a-zA-Z0-9]", "_", "all")),
            text: "Category " & row.category & " Statistics: There are " & row.cnt & " lots in the " & row.category & " category. " &
                  "The " & row.category & " category contains " & row.cnt & " auction lots. " &
                  "We have " & row.cnt & " " & row.category & " lots available.",
            title: row.category & " Category Count",
            category: "statistics"
        });
    }
    catText &= arrayToList(catList, ". ") & ".";
    arrayAppend(summaries, {
        id: "summary_all_categories",
        text: catText,
        title: "All Categories Statistics",
        category: "statistics"
    });
    
    // 3. Lots by sale/auction
    saleStats = queryExecute(
        "SELECT s.salename, COUNT(l.lot_pk) as cnt 
         FROM sales s 
         LEFT JOIN lots l ON l.lot_sale_fk = s.sale_pk 
         GROUP BY s.sale_pk, s.salename 
         ORDER BY cnt DESC 
         LIMIT 20",
        [], {datasource: application.db.dsn}
    );
    
    saleText = "Lots by Auction/Sale: ";
    saleList = [];
    for (row in saleStats) {
        if (len(row.salename)) {
            arrayAppend(saleList, row.salename & " has " & row.cnt & " lots");
        }
    }
    saleText &= arrayToList(saleList, ". ") & ".";
    arrayAppend(summaries, {
        id: "summary_sales",
        text: saleText,
        title: "Sales/Auctions Statistics",
        category: "statistics"
    });
    
    // 4. Price statistics
    priceStats = queryExecute(
        "SELECT 
            COUNT(*) as total,
            ROUND(AVG(NULLIF(realized, 0))::numeric, 2) as avg_price,
            MIN(NULLIF(realized, 0)) as min_price,
            MAX(realized) as max_price
         FROM lots WHERE realized > 0",
        [], {datasource: application.db.dsn}
    );
    
    if (priceStats.recordCount > 0 && val(priceStats.total) > 0) {
        arrayAppend(summaries, {
            id: "summary_prices",
            text: "Price Statistics: " & priceStats.total & " lots have realized prices. " &
                  "Average realized price is " & priceStats.avg_price & ". " &
                  "Minimum price is " & priceStats.min_price & ". " &
                  "Maximum price is " & priceStats.max_price & ".",
            title: "Price Statistics",
            category: "statistics"
        });
    }
    
    // Insert summaries with embeddings
    inserted = 0;
    errors = [];
    
    for (summary in summaries) {
        try {
            // Create embedding
            bodyStruct = {"model": embedModel, "input": summary.text};
            
            cfhttp(url=apiBaseUrl & "/embeddings", method="post", timeout=timeout, result="embedCall") {
                cfhttpparam(type="header", name="Authorization", value="Bearer #openaiKey#");
                cfhttpparam(type="header", name="Content-Type", value="application/json");
                cfhttpparam(type="body", value=serializeJSON(bodyStruct));
            }
            
            embedResult = deserializeJSON(embedCall.fileContent);
            
            if (structKeyExists(embedResult, "data") && arrayLen(embedResult.data)) {
                embedding = "[" & arrayToList(embedResult.data[1].embedding, ",") & "]";
                
                queryExecute(
                    "INSERT INTO chunks (chunk_text, embedding, source_type, source_name, source_id, 
                        chunk_index, chunk_size, content_type, title, category, embedding_model)
                     VALUES (?, ?::vector, 'summary', 'statistics', ?, 1, ?, 'text/summary', ?, ?, ?)
                     ON CONFLICT (source_type, source_id, chunk_index) DO UPDATE SET
                        chunk_text = EXCLUDED.chunk_text,
                        embedding = EXCLUDED.embedding,
                        title = EXCLUDED.title,
                        processed_at = CURRENT_TIMESTAMP",
                    [
                        {value: summary.text, cfsqltype: "cf_sql_longvarchar"},
                        {value: embedding, cfsqltype: "cf_sql_varchar"},
                        {value: summary.id, cfsqltype: "cf_sql_varchar"},
                        {value: len(summary.text), cfsqltype: "cf_sql_integer"},
                        {value: summary.title, cfsqltype: "cf_sql_varchar"},
                        {value: summary.category, cfsqltype: "cf_sql_varchar"},
                        {value: embedModel, cfsqltype: "cf_sql_varchar"}
                    ],
                    {datasource: application.db.dsn}
                );
                inserted++;
            }
        } catch (any e) {
            arrayAppend(errors, summary.id & ": " & e.message);
        }
    }
    
    writeOutput("<h2>Summary Chunks Generated</h2>");
    writeOutput("<p>Inserted/Updated: " & inserted & " summary chunks</p>");
    writeOutput("<p>Total summaries: " & arrayLen(summaries) & "</p>");
    if (arrayLen(errors)) {
        writeOutput("<p>Errors: " & arrayToList(errors, "<br>") & "</p>");
    }
    writeOutput("<h3>Generated Summaries:</h3><ul>");
    for (s in summaries) {
        writeOutput("<li><strong>" & s.title & "</strong>: " & left(s.text, 100) & "...</li>");
    }
    writeOutput("</ul>");
</cfscript>
<cfelse>
    <h1>Generate Summary Chunks for RAG</h1>
    <p>This will create statistical summary chunks so the chatbot can answer questions like:</p>
    <ul>
        <li>"How many lots do we have?"</li>
        <li>"How many lots in the Ancients category?"</li>
        <li>"What are the price statistics?"</li>
    </ul>
    <p><a href="generate_summary_chunks.cfm?run=true" style="background: #3b82f6; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">Generate Summary Chunks</a></p>
</cfif>
