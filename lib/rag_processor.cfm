<!---
    RAG Processor Component
    Reusable functions for processing lots into RAG embeddings
    
    Functions:
    - processLotForRAG(lotId, lotData) - Create chunk and embedding for a single lot
    - processJobLotsForRAG(jobId) - Batch process all lots from a scraping job
--->
<cfscript>
    /**
     * Process a single lot for RAG
     * @lotId - The lot_pk from the lots table
     * @lotData - Structure containing lot information (optional, will query if not provided)
     * Returns: struct with success boolean and message
     */
    function processLotForRAG(lotId, lotData = {}) {
        try {
            // If lotData not provided, query it from database
            if (!structKeyExists(lotData, "lot_pk") || !len(lotData.lot_pk)) {
                lotQuery = queryExecute(
                    "SELECT l.lot_pk, l.lot_no, l.title, l.catdescr, l.htmltext, 
                            l.image_url, l.lot_url, l.est_low, l.est_real, l.realized, 
                            l.opening, l.currency, s.salename
                     FROM lots l
                     INNER JOIN sales s ON s.sale_pk = l.lot_sale_fk
                     WHERE l.lot_pk = ?",
                    [{value = lotId, cfsqltype = "cf_sql_integer"}],
                    {datasource = application.db.dsn}
                );
                
                if (lotQuery.recordCount == 0) {
                    return {success: false, message: "Lot not found: " & lotId};
                }
                
                lotData = {
                    lot_pk: lotQuery.lot_pk[1],
                    lot_no: lotQuery.lot_no[1],
                    title: lotQuery.title[1],
                    catdescr: lotQuery.catdescr[1],
                    htmltext: lotQuery.htmltext[1],
                    image_url: lotQuery.image_url[1],
                    lot_url: lotQuery.lot_url[1],
                    est_low: lotQuery.est_low[1],
                    est_real: lotQuery.est_real[1],
                    realized: lotQuery.realized[1],
                    opening: lotQuery.opening[1],
                    currency: lotQuery.currency[1],
                    saleName: lotQuery.salename[1]
                };
            }
            
            // Build chunk text (similar to insert_lots_into_db.js pattern)
            chunkText = "Lot " & (lotData.lot_no ?: "") & ": " & (lotData.title ?: "");
            if (len(lotData.catdescr ?: "")) {
                chunkText &= chr(10) & lotData.catdescr;
            }
            if (len(lotData.htmltext ?: "")) {
                // Strip HTML tags
                cleanText = reReplace(lotData.htmltext, "<[^>]+>", " ", "all");
                chunkText &= chr(10) & cleanText;
            }
            if (len(lotData.catdescr ?: "")) {
                chunkText &= chr(10) & "Category: " & lotData.catdescr;
            }
            if (len(lotData.est_low ?: "") || len(lotData.realized ?: "")) {
                priceText = "Starting: " & (lotData.est_low ?: "") & " Realized: " & (lotData.realized ?: "");
                chunkText &= chr(10) & priceText;
            }
            if (len(lotData.saleName ?: "")) {
                chunkText &= chr(10) & "Sale: " & lotData.saleName;
            }
            if (len(lotData.lot_url ?: "")) {
                chunkText &= chr(10) & "URL: " & lotData.lot_url;
            }
            
            // Get OpenAI configuration
            embedModel = application.ai.embedModel;
            openaiKey = replace(application.ai.openaiKey, '"', "", "all");
            apiBaseUrl = application.ai.apiBaseUrl;
            timeout = application.ai.timeout ?: 90;
            
            // Create embedding
            bodyStruct = {
                "model": embedModel,
                "input": chunkText
            };
            
            cfhttp(url=apiBaseUrl & "/embeddings", method="post", timeout=timeout, result="embedCall") {
                cfhttpparam(type="header", name="Authorization", value="Bearer #openaiKey#");
                cfhttpparam(type="header", name="Content-Type", value="application/json");
                cfhttpparam(type="body", value=serializeJSON(bodyStruct));
            }
            
            embedResult = deserializeJSON(embedCall.fileContent);
            
            if (!structKeyExists(embedResult, "data") || !arrayLen(embedResult.data)) {
                return {success: false, message: "Failed to generate embedding"};
            }
            
            embedding = "[" & arrayToList(embedResult.data[1].embedding, ",") & "]";
            
            // Get sale information for source_name
            saleName = lotData.saleName ?: "";
            if (!len(saleName)) {
                saleQuery = queryExecute(
                    "SELECT s.salename FROM sales s 
                     INNER JOIN lots l ON l.lot_sale_fk = s.sale_pk 
                     WHERE l.lot_pk = ?",
                    [{value = lotId, cfsqltype = "cf_sql_integer"}],
                    {datasource = application.db.dsn}
                );
                if (saleQuery.recordCount > 0) {
                    saleName = saleQuery.salename[1];
                }
            }
            
            // Insert/update chunk
            queryExecute(
                "INSERT INTO chunks (
                    chunk_text, embedding, source_type, source_name, source_id,
                    chunk_index, chunk_size, content_type, title, category,
                    embedding_model, metadata
                )
                VALUES (?, ?::vector, 'lot', ?, ?, 1, ?, 'auction/lot', ?, ?, ?, ?::jsonb)
                ON CONFLICT (source_type, source_id, chunk_index) DO UPDATE SET
                    chunk_text = EXCLUDED.chunk_text,
                    embedding = EXCLUDED.embedding,
                    title = EXCLUDED.title,
                    category = EXCLUDED.category,
                    metadata = EXCLUDED.metadata,
                    processed_at = CURRENT_TIMESTAMP",
                [
                    {value = chunkText, cfsqltype = "cf_sql_longvarchar"},
                    {value = embedding, cfsqltype = "cf_sql_varchar"},
                    {value = saleName, cfsqltype = "cf_sql_varchar"},
                    {value = string(lotId), cfsqltype = "cf_sql_varchar"},
                    {value = len(chunkText), cfsqltype = "cf_sql_integer"},
                    {value = lotData.title ?: "", cfsqltype = "cf_sql_varchar"},
                    {value = lotData.catdescr ?: "", cfsqltype = "cf_sql_varchar"},
                    {value = embedModel, cfsqltype = "cf_sql_varchar"},
                    {value = serializeJSON({
                        lotNumber: lotData.lot_no,
                        startingPrice: lotData.est_low,
                        realizedPrice: lotData.realized,
                        lotUrl: lotData.lot_url,
                        imageUrl: lotData.image_url
                    }), cfsqltype = "cf_sql_varchar"}
                ],
                {datasource = application.db.dsn}
            );
            
            return {success: true, message: "Processed lot " & lotId};
            
        } catch (any err) {
            return {success: false, message: "Error processing lot " & lotId & ": " & err.message};
        }
    }
    
    /**
     * Process all lots from a scraping job for RAG
     * @jobId - The scraper_jobs.id
     * Returns: struct with success, processed count, failed count
     */
    function processJobLotsForRAG(jobId) {
        try {
            // Get job information
            jobQuery = queryExecute(
                "SELECT id, target_event_id, status FROM scraper_jobs WHERE id = ?",
                [{value = jobId, cfsqltype = "cf_sql_integer"}],
                {datasource = application.db.dsn}
            );
            
            if (jobQuery.recordCount == 0) {
                return {success: false, message: "Job not found: " & jobId};
            }
            
            // Find lots that need processing (lots without chunks)
            // We'll process lots that were created/updated recently (within last 24 hours)
            // or lots associated with the job's target_event_id if specified
            lotsQuery = queryExecute(
                "SELECT DISTINCT l.lot_pk 
                 FROM lots l
                 WHERE NOT EXISTS (
                     SELECT 1 FROM chunks c 
                     WHERE c.source_type = 'lot' 
                     AND c.source_id = CAST(l.lot_pk AS VARCHAR)
                 )
                 AND l.last_edit >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
                 ORDER BY l.lot_pk",
                [],
                {datasource = application.db.dsn}
            );
            
            processedCount = 0;
            failedCount = 0;
            errors = [];
            
            if (lotsQuery.recordCount > 0) {
                for (row in lotsQuery) {
                    result = processLotForRAG(row.lot_pk);
                    if (result.success) {
                        processedCount++;
                    } else {
                        failedCount++;
                        arrayAppend(errors, result.message);
                    }
                }
            }
            
            // Update job to mark RAG processing complete
            queryExecute(
                "UPDATE scraper_jobs SET rag_processed_at = CURRENT_TIMESTAMP WHERE id = ?",
                [{value = jobId, cfsqltype = "cf_sql_integer"}],
                {datasource = application.db.dsn}
            );
            
            return {
                success: true,
                processed: processedCount,
                failed: failedCount,
                total: lotsQuery.recordCount,
                errors: errors
            };
            
        } catch (any err) {
            return {success: false, message: "Error processing job lots: " & err.message};
        }
    }
</cfscript>