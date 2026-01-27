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
auctionName = "";
isAuctionQuery = false;
lowerPrompt = lcase(userPrompt);

// Detect category queries (show categories, list categories, name of categories, categories in X)
isCategoryQuery = false;
if (reFindNoCase("show.*categor|list.*categor|name.*categor|categor.*name|categor.*list|categor.*in|how many categor", lowerPrompt)) {
    isCategoryQuery = true;
}

// Detect counting queries like "how many lots of X", "how many lots in X category", "count of X"
if (reFindNoCase("how many|count|number of", lowerPrompt)) {
    isCountingQuery = true;
    
    // Check if query mentions "auction" or "sale" - indicates auction-specific query
    // Also detect patterns like "X Auction Y" or "Auction Y" where Y is a number
    // Also detect "categories in X" pattern
    if (reFindNoCase("(in|this|the)\s+(auction|sale)", lowerPrompt) OR 
        reFindNoCase("auction\s+\d+|sale\s+\d+", lowerPrompt) OR
        (reFindNoCase("auction|sale", lowerPrompt) AND reFindNoCase("\d+", lowerPrompt)) OR
        reFindNoCase("categor.*in\s+", lowerPrompt)) {
        isAuctionQuery = true;
        // PRIORITY 1: Check for "of this auction title", "of auction title", "of auction name" patterns FIRST (most specific)
        posOfTitle = findNoCase(" of this auction title ", lowerPrompt);
        if (posOfTitle EQ 0) posOfTitle = findNoCase(" of auction title ", lowerPrompt);
        if (posOfTitle EQ 0) posOfTitle = findNoCase(" of auction name ", lowerPrompt);
        if (posOfTitle EQ 0) posOfTitle = findNoCase(" of this auction name ", lowerPrompt);
        if (posOfTitle GT 0) {
            if (findNoCase(" of this auction title ", lowerPrompt) GT 0) {
                startPos = posOfTitle + 24; // " of this auction title " length
            } else if (findNoCase(" of auction title ", lowerPrompt) GT 0) {
                startPos = posOfTitle + 19; // " of auction title " length
            } else if (findNoCase(" of this auction name ", lowerPrompt) GT 0) {
                startPos = posOfTitle + 22; // " of this auction name " length
            } else {
                startPos = posOfTitle + 17; // " of auction name " length
            }
            strLen = len(userPrompt);
            count = strLen - startPos + 1;
            auctionName = trim(mid(userPrompt, startPos, count));
            // Remove quotes if present
            auctionName = reReplace(auctionName, "^""|""$", "", "all");
            auctionName = reReplace(auctionName, "(\?|\.|,|;|:)$", "", "all");
        }
        
        // PRIORITY 2: Extract auction name - look for text after "in this auction", "in auction", "in the auction", "in this sale"
        if (len(auctionName) EQ 0) {
            posAuction = reFindNoCase("(in\s+(this|the)?\s*(auction|sale)\s+)(.+?)(\?|$|\.)", userPrompt, 1, true);
            if (arrayLen(posAuction.pos) GTE 4) {
                matchStart = posAuction.pos[4];
                matchLen = posAuction.len[4];
                if (matchStart GT 0 AND matchLen GT 0) {
                    auctionName = trim(mid(userPrompt, matchStart, matchLen));
                    // Remove trailing punctuation
                    auctionName = reReplace(auctionName, "(\?|\.|,|;|:)$", "", "all");
                }
            }
        }
        // Fallback: extract text after "in this auction" or "in auction"
        if (len(auctionName) EQ 0) {
            posInAuction = findNoCase(" in this auction ", lowerPrompt);
            if (posInAuction EQ 0) posInAuction = findNoCase(" in auction ", lowerPrompt);
            if (posInAuction EQ 0) posInAuction = findNoCase(" in the auction ", lowerPrompt);
            if (posInAuction EQ 0) posInAuction = findNoCase(" in this sale ", lowerPrompt);
            if (posInAuction EQ 0) posInAuction = findNoCase(" in sale ", lowerPrompt);
            
            if (posInAuction GT 0) {
                // Find the position after "in this auction " or "in auction "
                if (findNoCase(" in this auction ", lowerPrompt) GT 0) {
                    startPos = posInAuction + 18; // " in this auction " length
                } else if (findNoCase(" in the auction ", lowerPrompt) GT 0) {
                    startPos = posInAuction + 16; // " in the auction " length
                } else if (findNoCase(" in this sale ", lowerPrompt) GT 0) {
                    startPos = posInAuction + 14; // " in this sale " length
                } else {
                    startPos = posInAuction + 11; // " in auction " or " in sale " length
                }
                strLen = len(userPrompt);
                count = strLen - startPos + 1;
                auctionName = trim(mid(userPrompt, startPos, count));
                auctionName = reReplace(auctionName, "(\?|\.|,|;|:)$", "", "all");
            }
        }
        
        // If still no auction name, try to extract from patterns like "X Auction Y" or "Auction Y"
        // IMPORTANT: Capture complete name including "Showcase Auction 61586" or similar patterns
        if (len(auctionName) EQ 0) {
            // Try to find pattern: "how many lots X Auction Y" or "how many lots Auction Y"
            // Also handle patterns like "X Showcase Auction Y" or "X Auction Y"
            // Use non-greedy match to capture everything up to the auction number
            auctionMatch = reFindNoCase("(how many lots\s+)?(show me\s+)?(total\s+number\s+of\s+lots\s+)?(of\s+)?(auction\s+name\s+)?(.+?)\s+(showcase\s+)?(auction|sale)\s+(\d+)", userPrompt, 1, true);
            if (arrayLen(auctionMatch.pos) GTE 8) {
                // Extract the full match including auction house name, "Showcase" if present, and auction number
                // Find the position of the auction house name (group 6)
                nameStart = auctionMatch.pos[6];
                nameLen = auctionMatch.len[6];
                showcaseStart = auctionMatch.pos[7];
                showcaseLen = auctionMatch.len[7];
                auctionWordStart = auctionMatch.pos[8];
                auctionWordLen = auctionMatch.len[8];
                auctionNumStart = auctionMatch.pos[9];
                auctionNumLen = auctionMatch.len[9];
                
                if (nameStart GT 0 AND auctionNumStart GT 0) {
                    // Extract everything from auction house name to auction number
                    fullMatch = mid(userPrompt, nameStart, auctionNumStart + auctionNumLen - nameStart);
                    // Remove common prefixes if present
                    fullMatch = reReplace(fullMatch, "^(how many lots|show me|total number of lots|of|auction name)\s+", "", "all");
                    auctionName = trim(fullMatch);
                }
            } else {
                // Try simpler pattern: "Auction 25" or "Sale 25" or "Showcase Auction 25"
                simpleMatch = reFindNoCase("(showcase\s+)?(auction|sale)\s+(\d+)", userPrompt, 1, true);
                if (arrayLen(simpleMatch.pos) GTE 3) {
                    // Get text before "Auction" or "Showcase Auction" and include full pattern + number
                    auctionWordPos = simpleMatch.pos[1];
                    if (auctionWordPos EQ 0) auctionWordPos = simpleMatch.pos[2];
                    auctionNumPos = simpleMatch.pos[3];
                    auctionNumLen = simpleMatch.len[3];
                    auctionNum = mid(userPrompt, auctionNumPos, auctionNumLen);
                    
                    // Get text before "Showcase Auction" or "Auction" (auction house name)
                    beforeAuction = trim(left(userPrompt, auctionWordPos - 1));
                    // Remove "how many lots" and "of this auction title" if present
                    beforeAuction = reReplace(beforeAuction, "^(how many lots|show me|total number of lots|of|auction name|this auction title)\s+", "", "all");
                    
                    // Build complete name: "Auction House Showcase Auction 61586" or "Auction House Auction 25"
                    if (simpleMatch.pos[1] GT 0 AND simpleMatch.len[1] GT 0) {
                        // "Showcase" is present
                        showcaseText = mid(userPrompt, simpleMatch.pos[1], simpleMatch.len[1]);
                        auctionText = mid(userPrompt, simpleMatch.pos[2], simpleMatch.len[2]);
                        if (len(beforeAuction) GT 0) {
                            auctionName = beforeAuction & " " & showcaseText & " " & auctionText & " " & auctionNum;
                        } else {
                            auctionName = showcaseText & " " & auctionText & " " & auctionNum;
                        }
                    } else {
                        // No "Showcase", just "Auction" or "Sale"
                        auctionText = mid(userPrompt, simpleMatch.pos[2], simpleMatch.len[2]);
                        if (len(beforeAuction) GT 0) {
                            auctionName = beforeAuction & " " & auctionText & " " & auctionNum;
                        } else {
                            auctionName = auctionText & " " & auctionNum;
                        }
                    }
                    auctionName = trim(auctionName);
                }
            }
            
            // Final fallback: if still no auction name but query contains "auction" or "sale", extract everything after "how many lots" or "show me"
            if (len(auctionName) EQ 0 AND isAuctionQuery) {
                // Try "show me total number of lots of auction name"
                posShowMe = findNoCase("show me", lowerPrompt);
                if (posShowMe GT 0) {
                    posAuctionName = findNoCase(" of auction name ", lowerPrompt);
                    if (posAuctionName GT 0) {
                        startPos = posAuctionName + 17; // " of auction name " length
                        strLen = len(userPrompt);
                        count = strLen - startPos + 1;
                        extracted = trim(mid(userPrompt, startPos, count));
                        // Remove quotes if present
                        extracted = reReplace(extracted, "^""|""$", "", "all");
                        if (len(extracted) GT 0) {
                            auctionName = extracted;
                        }
                    }
                }
                
                // Try "how many lots"
                if (len(auctionName) EQ 0) {
                    posHowMany = findNoCase("how many lots", lowerPrompt);
                    if (posHowMany GT 0) {
                        startPos = posHowMany + 13; // "how many lots" length
                        strLen = len(userPrompt);
                        count = strLen - startPos + 1;
                        extracted = trim(mid(userPrompt, startPos, count));
                        // Remove common prefixes: "of", "in", "this", "the", "auction title", "title", "auction name", "name"
                        extracted = reReplace(extracted, "^(of|in|this|the)\s+", "", "all");
                        extracted = reReplace(extracted, "^(of\s+)?(this\s+)?(auction\s+)?(title\s+|name\s+)", "", "all");
                        // Remove quotes if present
                        extracted = reReplace(extracted, "^""|""$", "", "all");
                        if (len(extracted) GT 0) {
                            auctionName = extracted;
                        }
                    }
                }
                
                // Try "categories in" or "category in" pattern
                if (len(auctionName) EQ 0) {
                    posCategoriesIn = findNoCase("categories in ", lowerPrompt);
                    if (posCategoriesIn EQ 0) posCategoriesIn = findNoCase("category in ", lowerPrompt);
                    if (posCategoriesIn GT 0) {
                        startPos = posCategoriesIn + (posCategoriesIn EQ findNoCase("categories in ", lowerPrompt) ? 14 : 12);
                        strLen = len(userPrompt);
                        count = strLen - startPos + 1;
                        extracted = trim(mid(userPrompt, startPos, count));
                        // Remove trailing question mark or period
                        extracted = reReplace(extracted, "(\?|\.)$", "", "all");
                        if (len(extracted) GT 0) {
                            auctionName = extracted;
                        }
                    }
                }
            }
            
            // Clean up auction name: remove any remaining prefixes and normalize
            if (len(auctionName) GT 0) {
                // Remove common prefixes that might have been missed (only from start)
                auctionName = reReplace(auctionName, "^(of\s+)?(this\s+)?(auction\s+)?(title\s+|name\s+)", "", "all");
                auctionName = reReplace(auctionName, "^(in|this|the)\s+", "", "all");
                // Remove quotes if present
                auctionName = reReplace(auctionName, "^""|""$", "", "all");
                auctionName = trim(auctionName);
                // Normalize: remove extra spaces
                auctionName = reReplace(auctionName, "\s+", " ", "all");
            }
        }
    }
    
    // Fallback: If we have a category query and extracted auction name, ensure isAuctionQuery is set
    if (isCategoryQuery AND len(auctionName) GT 0 AND !isAuctionQuery) {
        isAuctionQuery = true;
    }
    
    // Try to extract category name from the query (if not auction query)
    if (!isAuctionQuery) {
        posOf = findNoCase(" of ", userPrompt);
        posIn = findNoCase(" in ", userPrompt);
        
        if (posOf GT 0) {
            startPos = posOf + 4;
            strLen = len(userPrompt);
            count = strLen - startPos + 1;
            remaining = mid(userPrompt, startPos, count);
            remaining = trim(reReplace(remaining, "(\s+category|\s+lots?|\?|\.|$)", "", "all"));
            if (len(remaining) GT 0 AND len(remaining) LT 200) {
                categoryName = remaining;
            }
        } else if (posIn GT 0) {
            startPos = posIn + 4;
            strLen = len(userPrompt);
            count = strLen - startPos + 1;
            remaining = mid(userPrompt, startPos, count);
            remaining = trim(reReplace(remaining, "(\s+category|\s+lots?|\?|\.|$)", "", "all"));
            if (len(remaining) GT 0 AND len(remaining) LT 200) {
                categoryName = remaining;
            }
        }
    }
    
    // If we detected a counting query, query the database directly
    if (isCountingQuery) {
        try {
            // PRIORITY: Handle category queries FIRST (before lot counting)
            // This prevents category queries from being treated as lot counting queries
            if (isCountingQuery AND reFindNoCase("categor", lowerPrompt) AND isAuctionQuery AND len(auctionName) GT 0) {
                // Handle "how many categories" queries for specific auctions
                try {
                    // Use the same robust auction matching logic as lot counting
                    auctionNameNormalized = reReplace(auctionName, ",", "", "all");
                    
                    // Try 1: Exact match on normalized name (without comma)
                    salePkResult = queryExecute(
                        "SELECT s.sale_pk, s.salename, s.sale_no
                         FROM sales s
                         WHERE LOWER(TRIM(REPLACE(s.salename, ',', ''))) = LOWER(TRIM(?))
                         LIMIT 1",
                        [{value: auctionNameNormalized, cfsqltype: "cf_sql_varchar"}],
                        {datasource: application.db.dsn}
                    );
                    
                    // Try 2: Exact match with original (with comma)
                    if (salePkResult.recordCount EQ 0) {
                        salePkResult = queryExecute(
                            "SELECT s.sale_pk, s.salename, s.sale_no
                             FROM sales s
                             WHERE LOWER(TRIM(s.salename)) = LOWER(TRIM(?))
                             LIMIT 1",
                            [{value: auctionName, cfsqltype: "cf_sql_varchar"}],
                            {datasource: application.db.dsn}
                        );
                    }
                    
                    // Try 3: Partial match with auction number extraction
                    if (salePkResult.recordCount EQ 0) {
                        auctionNameForMatch = lcase(trim(reReplace(auctionName, ",", "", "all")));
                        auctionNumMatch = reFindNoCase("(auction|sale|buy or bid sale)\s+(\d+)", auctionName, 1, true);
                        auctionNum = "";
                        if (arrayLen(auctionNumMatch.pos) GTE 2 AND auctionNumMatch.pos[2] GT 0) {
                            auctionNum = mid(auctionName, auctionNumMatch.pos[2], auctionNumMatch.len[2]);
                        }
                        
                        if (len(auctionNum) GT 0) {
                            // Try partial match with auction number
                            salePkResult = queryExecute(
                                "SELECT s.sale_pk, s.salename, s.sale_no
                                 FROM sales s
                                 WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                   AND (s.salename ILIKE ? OR REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?)
                                 ORDER BY 
                                   CASE WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?)) THEN 1
                                        WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') LIKE ? THEN 2
                                        ELSE 3 END,
                                   s.salename
                                 LIMIT 1",
                                [
                                    {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"},
                                    {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"},
                                    {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"},
                                    {value: auctionNameForMatch, cfsqltype: "cf_sql_varchar"},
                                    {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}
                                ],
                                {datasource: application.db.dsn}
                            );
                        } else {
                            // Try simple partial match without auction number
                            salePkResult = queryExecute(
                                "SELECT s.sale_pk, s.salename, s.sale_no
                                 FROM sales s
                                 WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                 ORDER BY LENGTH(s.salename) ASC
                                 LIMIT 1",
                                [{value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}],
                                {datasource: application.db.dsn}
                            );
                        }
                    }
                    
                    if (salePkResult.recordCount GT 0) {
                        salePk = salePkResult.sale_pk[1];
                        actualAuctionName = salePkResult.salename[1];
                        
                        // Count distinct categories for this auction
                        categoryCountResult = queryExecute(
                            "SELECT COUNT(DISTINCT l.majgroup) as cnt
                             FROM lots l
                             WHERE l.lot_sale_fk = ?
                             AND l.majgroup IS NOT NULL
                             AND TRIM(l.majgroup) != ''",
                            [{value: salePk, cfsqltype: "cf_sql_integer"}],
                            {datasource: application.db.dsn}
                        );
                        
                        if (categoryCountResult.recordCount GT 0 AND val(categoryCountResult.cnt) GT 0) {
                            countResult = "The total number of categories in the auction <strong>" & htmlEditFormat(actualAuctionName) & "</strong> is <strong>" & categoryCountResult.cnt & " categor" & (val(categoryCountResult.cnt) EQ 1 ? "y" : "ies") & "</strong>.";
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        } else {
                            countResult = "I could not find information about the number of categories in " & htmlEditFormat(actualAuctionName) & " in the database.";
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        }
                    } else {
                        // Auction not found - abort with error message
                        countResult = "I could not find information about the number of categories in " & htmlEditFormat(auctionName) & " in the database.";
                        writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                        arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                        arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                        abort;
                    }
                } catch (any e) {
                    // If query fails, abort with error message (don't fall through to lot counting)
                    countResult = "I could not find information about the number of categories in " & htmlEditFormat(auctionName) & " in the database.";
                    writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                    abort;
                }
            }
            
            // Then, try auction/sale name match if this is an auction query (for lot counting)
            if (isAuctionQuery AND len(auctionName) GT 0) {
                // Extract auction number if present (e.g., "Auction 25" -> "25")
                auctionNumber = "";
                numMatch = reFindNoCase("(auction|sale)\s+(\d+)", auctionName, 1, true);
                if (arrayLen(numMatch.pos) GTE 2) {
                    auctionNumber = mid(auctionName, numMatch.pos[2], numMatch.len[2]);
                }
                
                // Try 1a: Match by sale_no using auction ID from JSON (auctionid field)
                // The auctionid in JSON is the sale_no in database
                // IMPORTANT: Only try this if the number is NOT part of "Auction X" or "Sale X" pattern
                // (e.g., "Auction 61596" is an auction number, not an auction ID)
                // Auction IDs are typically standalone numbers, not part of the auction name
                hasAuctionNumberPattern = reFindNoCase("(auction|sale)\s+\d+", auctionName, 1, true);
                if (NOT structKeyExists(hasAuctionNumberPattern, "pos") OR arrayLen(hasAuctionNumberPattern.pos) EQ 0) {
                    // No "Auction X" pattern found, so try matching by sale_no if we find a standalone 4+ digit number
                    auctionIdMatch = reFindNoCase("\b(\d{4,})\b", auctionName, 1, true);
                    if (structKeyExists(auctionIdMatch, "pos") AND arrayLen(auctionIdMatch.pos) GTE 2 AND auctionIdMatch.pos[2] GT 0) {
                        potentialAuctionId = mid(auctionName, auctionIdMatch.pos[2], auctionIdMatch.len[2]);
                        saleMatch = queryExecute(
                            "SELECT s.sale_pk, s.salename, s.sale_no
                             FROM sales s
                             WHERE s.sale_no = ?
                             LIMIT 1",
                            [{value: potentialAuctionId, cfsqltype: "cf_sql_varchar"}],
                            {datasource: application.db.dsn}
                        );
                        
                        if (saleMatch.recordCount GT 0) {
                            salePk = saleMatch.sale_pk[1];
                            actualAuction = saleMatch.salename[1] ?: "Auction " & potentialAuctionId;
                            // Count lots for this specific sale_pk
                            lotCount = queryExecute(
                                "SELECT COUNT(*) as cnt FROM lots WHERE lot_sale_fk = ?",
                                [{value: salePk, cfsqltype: "cf_sql_integer"}],
                                {datasource: application.db.dsn}
                            );
                            
                            if (lotCount.recordCount GT 0 AND val(lotCount.cnt) GT 0) {
                                countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & lotCount.cnt & " lots</strong>.";
                                writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                                arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                                arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                                abort;
                            }
                        }
                    }
                }
                
                // Try 2: Exact match on sale name (with and without comma normalization) - PRIORITY
                // This is the most reliable method since sale_no = auctionid (e.g., "10279") not auction number ("25")
                // Strategy: First find the exact sale_pk, then count its lots (more reliable)
                auctionNameNormalized = reReplace(auctionName, ",", "", "all");
                
                // Try 2a: Find sale_pk first, then count lots (most reliable)
                saleMatch = queryExecute(
                    "SELECT s.sale_pk, s.salename, s.sale_no
                     FROM sales s
                     WHERE LOWER(TRIM(REPLACE(s.salename, ',', ''))) = LOWER(TRIM(?))
                     LIMIT 1",
                    [{value: auctionNameNormalized, cfsqltype: "cf_sql_varchar"}],
                    {datasource: application.db.dsn}
                );
                
                if (saleMatch.recordCount GT 0) {
                    salePk = saleMatch.sale_pk[1];
                    actualAuction = saleMatch.salename[1];
                    // Now count lots for this specific sale_pk
                    lotCount = queryExecute(
                        "SELECT COUNT(*) as cnt FROM lots WHERE lot_sale_fk = ?",
                        [{value: salePk, cfsqltype: "cf_sql_integer"}],
                        {datasource: application.db.dsn}
                    );
                    
                    if (lotCount.recordCount GT 0 AND val(lotCount.cnt) GT 0) {
                        countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & lotCount.cnt & " lots</strong>.";
                        writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                        arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                        arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                        abort;
                    }
                }
                
                // Try 2b: Exact match with original (with comma)
                saleMatch = queryExecute(
                    "SELECT s.sale_pk, s.salename, s.sale_no
                     FROM sales s
                     WHERE LOWER(TRIM(s.salename)) = LOWER(TRIM(?))
                     LIMIT 1",
                    [{value: auctionName, cfsqltype: "cf_sql_varchar"}],
                    {datasource: application.db.dsn}
                );
                
                if (saleMatch.recordCount GT 0) {
                    salePk = saleMatch.sale_pk[1];
                    actualAuction = saleMatch.salename[1];
                    // Now count lots for this specific sale_pk
                    lotCount = queryExecute(
                        "SELECT COUNT(*) as cnt FROM lots WHERE lot_sale_fk = ?",
                        [{value: salePk, cfsqltype: "cf_sql_integer"}],
                        {datasource: application.db.dsn}
                    );
                    
                    if (lotCount.recordCount GT 0 AND val(lotCount.cnt) GT 0) {
                        countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & lotCount.cnt & " lots</strong>.";
                        writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                        arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                        arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                        abort;
                    }
                }
                
                
                // Try 3: Partial match on sale name (contains) - with comma normalization
                // IMPORTANT: Group by sale_pk to count per auction, not all matching auctions
                // This is important because DB has "Rzeszowski Dom Aukcyjny, Auction 25" but query might have "Rzeszowski Dom Aukcyjny Auction 25"
                // Normalize both sides: remove commas, lowercase, trim
                auctionNameForMatch = lcase(trim(reReplace(auctionName, ",", "", "all")));
                // Extract auction number if present (e.g., "Auction 25" -> "25", "Buy or Bid Sale 234" -> "234")
                auctionNumMatch = reFindNoCase("(auction|sale|buy or bid sale)\s+(\d+)", auctionName, 1, true);
                auctionNum = "";
                if (arrayLen(auctionNumMatch.pos) GTE 2 AND auctionNumMatch.pos[2] GT 0) {
                    auctionNum = mid(auctionName, auctionNumMatch.pos[2], auctionNumMatch.len[2]);
                }
                
                // Try 3a: Match with auction number if available (more specific)
                // Strategy: Find sale_pk first, then count lots (more reliable than JOIN with COUNT)
                if (len(auctionNum) GT 0) {
                    // First try: Exact match on normalized name with auction number
                    saleMatch = queryExecute(
                        "SELECT s.sale_pk, s.salename, s.sale_no
                         FROM sales s
                         WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?))
                           AND (s.salename ILIKE ? OR REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?)
                         LIMIT 1",
                        [
                            {value: auctionNameForMatch, cfsqltype: "cf_sql_varchar"},
                            {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"},
                            {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"}
                        ],
                        {datasource: application.db.dsn}
                    );
                    
                    if (saleMatch.recordCount GT 0) {
                        salePk = saleMatch.sale_pk[1];
                        actualAuction = saleMatch.salename[1];
                        // Count lots for this specific sale_pk
                        lotCount = queryExecute(
                            "SELECT COUNT(*) as cnt FROM lots WHERE lot_sale_fk = ?",
                            [{value: salePk, cfsqltype: "cf_sql_integer"}],
                            {datasource: application.db.dsn}
                        );
                        
                        if (lotCount.recordCount GT 0 AND val(lotCount.cnt) GT 0) {
                            countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & lotCount.cnt & " lots</strong>.";
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        }
                    }
                    
                    // Second try: Partial match with auction number
                    saleMatch = queryExecute(
                        "SELECT s.sale_pk, s.salename, s.sale_no
                         FROM sales s
                         WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                           AND (s.salename ILIKE ? OR REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?)
                         ORDER BY 
                           CASE WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?)) THEN 1
                                WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') LIKE ? THEN 2
                                ELSE 3 END,
                           s.salename
                         LIMIT 1",
                        [
                            {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"},
                            {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"},
                            {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"},
                            {value: auctionNameForMatch, cfsqltype: "cf_sql_varchar"},
                            {value: auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}
                        ],
                        {datasource: application.db.dsn}
                    );
                    
                    if (saleMatch.recordCount GT 0) {
                        salePk = saleMatch.sale_pk[1];
                        actualAuction = saleMatch.salename[1];
                        // Count lots for this specific sale_pk
                        lotCount = queryExecute(
                            "SELECT COUNT(*) as cnt FROM lots WHERE lot_sale_fk = ?",
                            [{value: salePk, cfsqltype: "cf_sql_integer"}],
                            {datasource: application.db.dsn}
                        );
                        
                        if (lotCount.recordCount GT 0 AND val(lotCount.cnt) GT 0) {
                            countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & lotCount.cnt & " lots</strong>.";
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        }
                    }
                }
                
                // Try 3b: Partial match without auction number (group by sale_pk to avoid counting multiple auctions)
                auctionCount = queryExecute(
                    "SELECT COUNT(*) as cnt, s.salename as actual_name, s.sale_pk
                     FROM lots l
                     INNER JOIN sales s ON s.sale_pk = l.lot_sale_fk
                     WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                     GROUP BY s.sale_pk, s.salename
                     ORDER BY 
                       CASE WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?)) THEN 1
                            WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ? THEN 2
                            ELSE 3 END,
                       COUNT(*) DESC
                     LIMIT 1",
                    [
                        {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"},
                        {value: auctionNameForMatch, cfsqltype: "cf_sql_varchar"},
                        {value: auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}
                    ],
                    {datasource: application.db.dsn}
                );
                
                if (auctionCount.recordCount GT 0 AND val(auctionCount.cnt) GT 0) {
                    actualAuction = auctionCount.actual_name[1];
                    countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & auctionCount.cnt & " lots</strong>.";
                    writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                    abort;
                }
                
                // Try 3c: Match by key words from auction name (split and match) - with GROUP BY
                // Extract main words (remove "Auction", "Sale", numbers)
                keyWords = reReplace(auctionName, "\s*(auction|sale)\s+\d+", "", "all");
                keyWords = trim(reReplace(keyWords, "\s+", " ", "all"));
                
                if (len(keyWords) GT 5) {
                    // Match salename containing the key words - group by sale_pk
                    auctionCount = queryExecute(
                        "SELECT COUNT(*) as cnt, s.salename as actual_name, s.sale_pk
                         FROM lots l
                         INNER JOIN sales s ON s.sale_pk = l.lot_sale_fk
                         WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                         GROUP BY s.sale_pk, s.salename
                         ORDER BY COUNT(*) DESC
                         LIMIT 1",
                        [{value: "%" & reReplace(lcase(trim(keyWords)), ",", "", "all") & "%", cfsqltype: "cf_sql_varchar"}],
                        {datasource: application.db.dsn}
                    );
                    
                    if (auctionCount.recordCount GT 0 AND val(auctionCount.cnt) GT 0) {
                        actualAuction = auctionCount.actual_name[1];
                        countResult = "The total number of lots in the auction <strong>" & htmlEditFormat(actualAuction) & "</strong> is <strong>" & auctionCount.cnt & " lots</strong>.";
                        writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                        arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                        arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                        abort;
                    }
                }
                
            }
            
            // Handle category queries for specific auctions (e.g., "show me name of categories in Numismática Leilões Auction 119")
            if (isCategoryQuery AND isAuctionQuery AND len(auctionName) GT 0) {
                try {
                    // First, find the sale_pk for this auction
                    salePkResult = queryExecute(
                        "SELECT s.sale_pk, s.salename
                         FROM sales s
                         JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk
                         WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?))
                         LIMIT 1",
                        [{value: reReplace(auctionName, ",", "", "all"), cfsqltype: "cf_sql_varchar"}],
                        {datasource: application.db.dsn}
                    );
                    
                    // If exact match fails, try partial match
                    if (salePkResult.recordCount EQ 0) {
                        salePkResult = queryExecute(
                            "SELECT s.sale_pk, s.salename
                             FROM sales s
                             JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk
                             WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                             ORDER BY LENGTH(s.salename) ASC
                             LIMIT 1",
                            [{value: "%" & reReplace(lcase(trim(auctionName)), ",", "", "all") & "%", cfsqltype: "cf_sql_varchar"}],
                            {datasource: application.db.dsn}
                        );
                    }
                    
                    // Try with auction number extraction
                    if (salePkResult.recordCount EQ 0) {
                        auctionNumMatch = reFind("\s+(auction|sale|buy or bid sale)\s+(\d+)", lcase(auctionName), 1, true);
                        if (arrayLen(auctionNumMatch.pos) GTE 3 AND auctionNumMatch.pos[3] GT 0) {
                            auctionNum = mid(auctionName, auctionNumMatch.pos[3], auctionNumMatch.len[3]);
                            keyWords = reReplace(auctionName, "\s*(auction|sale|buy or bid sale)\s+\d+", "", "all");
                            keyWords = trim(reReplace(keyWords, "\s+", " ", "all"));
                            
                            if (len(keyWords) GT 5) {
                                salePkResult = queryExecute(
                                    "SELECT s.sale_pk, s.salename
                                     FROM sales s
                                     JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk
                                     WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                     AND REPLACE(LOWER(TRIM(s.salename)), ',', '') LIKE ?
                                     ORDER BY LENGTH(s.salename) ASC
                                     LIMIT 1",
                                    [
                                        {value: "%" & reReplace(lcase(trim(keyWords)), ",", "", "all") & "%", cfsqltype: "cf_sql_varchar"},
                                        {value: "%" & auctionNum & "%", cfsqltype: "cf_sql_varchar"}
                                    ],
                                    {datasource: application.db.dsn}
                                );
                            }
                        }
                    }
                    
                    if (salePkResult.recordCount GT 0) {
                        salePk = salePkResult.sale_pk[1];
                        actualAuctionName = salePkResult.salename[1];
                        
                        // Get distinct categories for this auction
                        categoriesResult = queryExecute(
                            "SELECT DISTINCT l.majgroup, COUNT(*) as lot_count
                             FROM lots l
                             WHERE l.lot_sale_fk = ?
                             AND l.majgroup IS NOT NULL
                             AND TRIM(l.majgroup) != ''
                             GROUP BY l.majgroup
                             ORDER BY l.majgroup",
                            [{value: salePk, cfsqltype: "cf_sql_integer"}],
                            {datasource: application.db.dsn}
                        );
                        
                        if (categoriesResult.recordCount GT 0) {
                            categoryList = [];
                            for (i = 1; i LTE categoriesResult.recordCount; i++) {
                                arrayAppend(categoryList, categoriesResult.majgroup[i]);
                            }
                            
                            if (categoriesResult.recordCount EQ 1) {
                                countResult = "The category in the auction <strong>" & htmlEditFormat(actualAuctionName) & "</strong> is: <strong>" & htmlEditFormat(categoryList[1]) & "</strong>.";
                            } else {
                                countResult = "The categories in the auction <strong>" & htmlEditFormat(actualAuctionName) & "</strong> are: <strong>" & htmlEditFormat(arrayToList(categoryList, ", ")) & "</strong>.";
                            }
                            
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        } else {
                            countResult = "No categories found for the auction <strong>" & htmlEditFormat(actualAuctionName) & "</strong>.";
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        }
                    }
                } catch (any e) {
                    // If query fails, fall through to RAG search
                }
            }
            
            // Handle "how many categories" queries for specific auctions
            if (isCountingQuery AND reFindNoCase("categor", lowerPrompt) AND isAuctionQuery AND len(auctionName) GT 0) {
                try {
                    // First, find the sale_pk for this auction (same logic as above)
                    salePkResult = queryExecute(
                        "SELECT s.sale_pk, s.salename
                         FROM sales s
                         JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk
                         WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?))
                         LIMIT 1",
                        [{value: reReplace(auctionName, ",", "", "all"), cfsqltype: "cf_sql_varchar"}],
                        {datasource: application.db.dsn}
                    );
                    
                    if (salePkResult.recordCount EQ 0) {
                        salePkResult = queryExecute(
                            "SELECT s.sale_pk, s.salename
                             FROM sales s
                             JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk
                             WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                             ORDER BY LENGTH(s.salename) ASC
                             LIMIT 1",
                            [{value: "%" & reReplace(lcase(trim(auctionName)), ",", "", "all") & "%", cfsqltype: "cf_sql_varchar"}],
                            {datasource: application.db.dsn}
                        );
                    }
                    
                    // Try with auction number extraction
                    if (salePkResult.recordCount EQ 0) {
                        auctionNumMatch = reFind("\s+(auction|sale|buy or bid sale)\s+(\d+)", lcase(auctionName), 1, true);
                        if (arrayLen(auctionNumMatch.pos) GTE 3 AND auctionNumMatch.pos[3] GT 0) {
                            auctionNum = mid(auctionName, auctionNumMatch.pos[3], auctionNumMatch.len[3]);
                            keyWords = reReplace(auctionName, "\s*(auction|sale|buy or bid sale)\s+\d+", "", "all");
                            keyWords = trim(reReplace(keyWords, "\s+", " ", "all"));
                            
                            if (len(keyWords) GT 5) {
                                salePkResult = queryExecute(
                                    "SELECT s.sale_pk, s.salename
                                     FROM sales s
                                     JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk
                                     WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                     AND REPLACE(LOWER(TRIM(s.salename)), ',', '') LIKE ?
                                     ORDER BY LENGTH(s.salename) ASC
                                     LIMIT 1",
                                    [
                                        {value: "%" & reReplace(lcase(trim(keyWords)), ",", "", "all") & "%", cfsqltype: "cf_sql_varchar"},
                                        {value: "%" & auctionNum & "%", cfsqltype: "cf_sql_varchar"}
                                    ],
                                    {datasource: application.db.dsn}
                                );
                            }
                        }
                    }
                    
                    if (salePkResult.recordCount GT 0) {
                        salePk = salePkResult.sale_pk[1];
                        actualAuctionName = salePkResult.salename[1];
                        
                        // Count distinct categories for this auction
                        categoryCountResult = queryExecute(
                            "SELECT COUNT(DISTINCT l.majgroup) as cnt
                             FROM lots l
                             WHERE l.lot_sale_fk = ?
                             AND l.majgroup IS NOT NULL
                             AND TRIM(l.majgroup) != ''",
                            [{value: salePk, cfsqltype: "cf_sql_integer"}],
                            {datasource: application.db.dsn}
                        );
                        
                        if (categoryCountResult.recordCount GT 0 AND val(categoryCountResult.cnt) GT 0) {
                            countResult = "The total number of categories in the auction <strong>" & htmlEditFormat(actualAuctionName) & "</strong> is <strong>" & categoryCountResult.cnt & " categor" & (val(categoryCountResult.cnt) EQ 1 ? "y" : "ies") & "</strong>.";
                            writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                            arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                            arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                            abort;
                        }
                    }
                } catch (any e) {
                    // If query fails, fall through to RAG search
                }
            }
            
            // Then try category match if category name is provided
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
            }
            
            // If no specific match found
            if (isAuctionQuery AND len(auctionName) GT 0) {
                // Auction query but no match found
                countResult = "I could not find an auction matching ""<strong>" & htmlEditFormat(auctionName) & "</strong>"". Please check the auction name and try again.";
                writeOutput("<div class=""answer-box"">" & countResult & "</div>");
                arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                arrayAppend(session.chatHistory, {"role": "assistant", "content": countResult});
                abort;
            } else if (!isAuctionQuery AND len(categoryName) EQ 0) {
                // General count query - total lots (only if not auction query and no category specified)
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

// Handle specific lot queries (e.g., "Rzeszowski Dom Aukcyjny Auction 25 - Lot 3122")
// Only process if NOT a counting query (to avoid conflicts)
if (isDefined("isCountingQuery") AND !isCountingQuery) {
    // Simple lot query detection - look for "Lot X" or "lot X" pattern
    lotMatch = reFindNoCase("lot\s+(\d+)", userPrompt, 1, true);
    if (structKeyExists(lotMatch, "pos") AND arrayLen(lotMatch.pos) GTE 2 AND lotMatch.pos[2] GT 0) {
        // Make sure this isn't a "how many lots" query
        if (!reFindNoCase("how many lots", userPrompt)) {
            try {
                lotNumber = trim(mid(userPrompt, lotMatch.pos[2], lotMatch.len[2]));
                lotAuctionName = "";
                
                // PRIORITY 1: Extract from "lot X of [auction name]" pattern
                lotOfPattern = reFindNoCase("lot\s+\d+\s+of\s+(.+?)(?:\s*$|\s*\?|\.|,|;|:)", userPrompt, 1, true);
                if (structKeyExists(lotOfPattern, "pos") AND arrayLen(lotOfPattern.pos) GTE 2 AND lotOfPattern.pos[2] GT 0) {
                    extractedAuction = trim(mid(userPrompt, lotOfPattern.pos[2], lotOfPattern.len[2]));
                    // Remove trailing punctuation
                    extractedAuction = reReplace(extractedAuction, "(\?|\.|,|;|:|\s+)$", "", "all");
                    if (len(extractedAuction) GT 5) {
                        lotAuctionName = extractedAuction;
                    }
                }
                
                // If not found with regex, try simple string extraction for "lot X of"
                if (len(lotAuctionName) EQ 0) {
                    lotOfPos = findNoCase("lot " & lotNumber & " of ", userPrompt);
                    if (lotOfPos GT 0) {
                        startPos = lotOfPos + len("lot " & lotNumber & " of ");
                        remainingText = mid(userPrompt, startPos, len(userPrompt) - startPos + 1);
                        remainingText = trim(reReplace(remainingText, "(\?|\.|,|;|:|\s+)$", "", "all"));
                        if (len(remainingText) GT 5) {
                            lotAuctionName = remainingText;
                        }
                    }
                }
                
                // PRIORITY 2: Extract from "lot X from [auction name]" pattern
                if (len(lotAuctionName) EQ 0) {
                    lotFromPattern = reFindNoCase("lot\s+\d+\s+from\s+(.+?)(?:\s*$|\s*\?|\.|,|;|:)", userPrompt, 1, true);
                    if (structKeyExists(lotFromPattern, "pos") AND arrayLen(lotFromPattern.pos) GTE 2 AND lotFromPattern.pos[2] GT 0) {
                        extractedAuction = trim(mid(userPrompt, lotFromPattern.pos[2], lotFromPattern.len[2]));
                        extractedAuction = reReplace(extractedAuction, "(\?|\.|,|;|:|\s+)$", "", "all");
                        if (len(extractedAuction) GT 5) {
                            lotAuctionName = extractedAuction;
                        }
                    }
                }
                
                // If not found with regex, try simple string extraction for "lot X from"
                if (len(lotAuctionName) EQ 0) {
                    lotFromPos = findNoCase("lot " & lotNumber & " from ", userPrompt);
                    if (lotFromPos GT 0) {
                        startPos = lotFromPos + len("lot " & lotNumber & " from ");
                        remainingText = mid(userPrompt, startPos, len(userPrompt) - startPos + 1);
                        remainingText = trim(reReplace(remainingText, "(\?|\.|,|;|:|\s+)$", "", "all"));
                        if (len(remainingText) GT 5) {
                            lotAuctionName = remainingText;
                        }
                    }
                }
                
                // PRIORITY 3: Extract from "[auction name] lot X" or "[auction name] - lot X" pattern
                if (len(lotAuctionName) EQ 0) {
                    lotPos = lotMatch.pos[1];
                    beforeLot = trim(left(userPrompt, lotPos - 1));
                    
                    if (len(beforeLot) GT 5) {
                        // Remove common prefixes
                        beforeLot = reReplace(beforeLot, "^(show me|tell me about|information about|details about|find|show|get|details of)\s+", "", "all");
                        beforeLot = trim(reReplace(beforeLot, "[-:]\s*$", "", "all"));
                        if (len(beforeLot) GT 5) {
                            lotAuctionName = beforeLot;
                        }
                    }
                }
                
                // PRIORITY 4: Try pattern like "X Auction Y - Lot Z" or "X Auction Y Lot Z"
                if (len(lotAuctionName) EQ 0) {
                    auctionLotPattern = reFindNoCase("(.+?)\s*(?:[-–—]|lot)\s+lot\s+(\d+)", userPrompt, 1, true);
                    if (structKeyExists(auctionLotPattern, "pos") AND arrayLen(auctionLotPattern.pos) GTE 2 AND auctionLotPattern.pos[1] GT 0) {
                        extractedAuction = trim(mid(userPrompt, auctionLotPattern.pos[1], auctionLotPattern.len[1]));
                        extractedAuction = reReplace(extractedAuction, "^(show me|tell me about|information about|details about|find|show|get|details of)\s+", "", "all");
                        if (len(extractedAuction) GT 5) {
                            lotAuctionName = extractedAuction;
                        }
                    }
                }
                
                // Try to find the auction in database using robust matching (same as counting queries)
                salePk = 0;
                actualAuctionName = "";
                
                if (len(lotAuctionName) GT 0) {
                    try {
                        // Use the same robust auction matching logic as counting queries
                        auctionNameNormalized = reReplace(lotAuctionName, ",", "", "all");
                        
                        // Try 1: Exact match on normalized name (without comma)
                        saleMatch = queryExecute(
                            "SELECT s.sale_pk, s.salename, s.sale_no
                             FROM sales s
                             WHERE LOWER(TRIM(REPLACE(s.salename, ',', ''))) = LOWER(TRIM(?))
                             LIMIT 1",
                            [{value: auctionNameNormalized, cfsqltype: "cf_sql_varchar"}],
                            {datasource: application.db.dsn}
                        );
                        
                        // Try 2: Exact match with original (with comma)
                        if (saleMatch.recordCount EQ 0) {
                            saleMatch = queryExecute(
                                "SELECT s.sale_pk, s.salename, s.sale_no
                                 FROM sales s
                                 WHERE LOWER(TRIM(s.salename)) = LOWER(TRIM(?))
                                 LIMIT 1",
                                [{value: lotAuctionName, cfsqltype: "cf_sql_varchar"}],
                                {datasource: application.db.dsn}
                            );
                        }
                        
                        // Try 3: Partial match with auction number extraction
                        if (saleMatch.recordCount EQ 0) {
                            auctionNameForMatch = lcase(trim(reReplace(lotAuctionName, ",", "", "all")));
                            
                            // Try to extract auction number - handle both "Auction 25" and "Auction C26001" patterns
                            auctionNumMatch = reFindNoCase("(auction|sale|buy or bid sale)\s+([A-Z]?\d+)", lotAuctionName, 1, true);
                            auctionNum = "";
                            if (arrayLen(auctionNumMatch.pos) GTE 3 AND auctionNumMatch.pos[3] GT 0) {
                                auctionNum = mid(lotAuctionName, auctionNumMatch.pos[3], auctionNumMatch.len[3]);
                            }
                            
                            if (len(auctionNum) GT 0) {
                                // Try partial match with auction number (handles both "25" and "C26001" formats)
                                saleMatch = queryExecute(
                                    "SELECT s.sale_pk, s.salename, s.sale_no
                                     FROM sales s
                                     WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                       AND (s.salename ILIKE ? OR REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?)
                                     ORDER BY 
                                       CASE WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?)) THEN 1
                                            WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') LIKE ? THEN 2
                                            ELSE 3 END,
                                       s.salename
                                     LIMIT 1",
                                    [
                                        {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"},
                                        {value: "%auction " & auctionNum & "%", cfsqltype: "cf_sql_varchar"},
                                        {value: "%auction " & lcase(auctionNum) & "%", cfsqltype: "cf_sql_varchar"},
                                        {value: auctionNameForMatch, cfsqltype: "cf_sql_varchar"},
                                        {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}
                                    ],
                                    {datasource: application.db.dsn}
                                );
                                
                                // If still not found, try with case-insensitive auction number
                                if (saleMatch.recordCount EQ 0) {
                                    saleMatch = queryExecute(
                                        "SELECT s.sale_pk, s.salename, s.sale_no
                                         FROM sales s
                                         WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                           AND REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                         ORDER BY 
                                           CASE WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') = LOWER(TRIM(?)) THEN 1
                                                WHEN REPLACE(LOWER(TRIM(s.salename)), ',', '') LIKE ? THEN 2
                                                ELSE 3 END,
                                           s.salename
                                         LIMIT 1",
                                        [
                                            {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"},
                                            {value: "%auction " & lcase(auctionNum) & "%", cfsqltype: "cf_sql_varchar"},
                                            {value: auctionNameForMatch, cfsqltype: "cf_sql_varchar"},
                                            {value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}
                                        ],
                                        {datasource: application.db.dsn}
                                    );
                                }
                            } else {
                                // Try simple partial match without auction number
                                saleMatch = queryExecute(
                                    "SELECT s.sale_pk, s.salename, s.sale_no
                                     FROM sales s
                                     WHERE REPLACE(LOWER(TRIM(s.salename)), ',', '') ILIKE ?
                                     ORDER BY LENGTH(s.salename) ASC
                                     LIMIT 1",
                                    [{value: "%" & auctionNameForMatch & "%", cfsqltype: "cf_sql_varchar"}],
                                    {datasource: application.db.dsn}
                                );
                            }
                        }
                        
                        if (saleMatch.recordCount GT 0) {
                            salePk = saleMatch.sale_pk[1];
                            actualAuctionName = saleMatch.salename[1];
                        }
                    } catch (any e) {
                        // If auction lookup fails, continue without sale_pk
                    }
                }
                
                // Query for the lot - first try with sale_pk if available, then without
                lotResult = queryNew("");
                lotPk = 0;
                
                if (salePk GT 0) {
                    // Query with sale_pk (more specific)
                    lotResult = queryExecute(
                        "SELECT l.lot_pk, l.lot_no, l.title, l.htmltext, l.majgroup, l.opening, l.realized, l.image_url, l.lot_url, s.salename 
                         FROM lots l 
                         INNER JOIN sales s ON s.sale_pk = l.lot_sale_fk 
                         WHERE l.lot_sale_fk = ? AND TRIM(l.lot_no) = ? 
                         LIMIT 1",
                        [
                            {value: salePk, cfsqltype: "cf_sql_integer"}, 
                            {value: lotNumber, cfsqltype: "cf_sql_varchar"}
                        ],
                        {datasource: application.db.dsn}
                    );
                }
                
                // If not found with sale_pk, try without (in case auction name wasn't matched)
                if (lotResult.recordCount EQ 0) {
                    lotResult = queryExecute(
                        "SELECT l.lot_pk, l.lot_no, l.title, l.htmltext, l.majgroup, l.opening, l.realized, l.image_url, l.lot_url, s.salename 
                         FROM lots l 
                         INNER JOIN sales s ON s.sale_pk = l.lot_sale_fk 
                         WHERE TRIM(l.lot_no) = ? 
                         LIMIT 1",
                        [{value: lotNumber, cfsqltype: "cf_sql_varchar"}],
                        {datasource: application.db.dsn}
                    );
                }
                
                // If found in lots table, also check chunks table for additional data
                chunkData = queryNew("");
                if (lotResult.recordCount GT 0) {
                    lotPk = lotResult.lot_pk[1];
                    
                    // Get data from chunks table (may have more detailed info)
                    try {
                        chunkData = queryExecute(
                            "SELECT chunk_text, title, category, metadata 
                             FROM chunks 
                             WHERE source_type = 'lot' AND source_id = ? 
                             LIMIT 1",
                            [{value: string(lotPk), cfsqltype: "cf_sql_varchar"}],
                            {datasource: application.db.dsn}
                        );
                    } catch (any e) {
                        // Chunks query failed, continue with lots data
                    }
                }
                
                if (lotResult.recordCount GT 0) {
                    // Found the lot - format response
                    try {
                        lotTitle = lotResult.title[1];
                    } catch (any e) {
                        lotTitle = "";
                    }
                    
                    // Use chunk title if available and lot title is empty
                    if (len(trim(lotTitle)) EQ 0 AND chunkData.recordCount GT 0) {
                        try {
                            lotTitle = chunkData.title[1];
                        } catch (any e) {
                            lotTitle = "";
                        }
                    }
                    
                    if (len(trim(lotTitle)) EQ 0) lotTitle = "Lot " & lotNumber;
                    
                    try {
                        lotDesc = lotResult.htmltext[1];
                    } catch (any e) {
                        lotDesc = "";
                    }
                    
                    // Use chunk text if lot description is empty
                    if (len(trim(lotDesc)) EQ 0 AND chunkData.recordCount GT 0) {
                        try {
                            lotDesc = chunkData.chunk_text[1];
                        } catch (any e) {
                            lotDesc = "";
                        }
                    }
                    
                    try {
                        lotCategory = lotResult.majgroup[1];
                    } catch (any e) {
                        lotCategory = "";
                    }
                    
                    // Use chunk category if lot category is empty
                    if (len(trim(lotCategory)) EQ 0 AND chunkData.recordCount GT 0) {
                        try {
                            lotCategory = chunkData.category[1];
                        } catch (any e) {
                            lotCategory = "";
                        }
                    }
                    
                    try {
                        lotStartingPrice = lotResult.opening[1];
                    } catch (any e) {
                        lotStartingPrice = "";
                    }
                    
                    // Try to get price from chunk metadata
                    if ((!isNumeric(lotStartingPrice) OR val(lotStartingPrice) EQ 0) AND chunkData.recordCount GT 0) {
                        try {
                            chunkMeta = deserializeJSON(chunkData.metadata[1]);
                            if (structKeyExists(chunkMeta, "startingPrice") AND len(chunkMeta.startingPrice)) {
                                lotStartingPrice = chunkMeta.startingPrice;
                            }
                        } catch (any e) {}
                    }
                    
                    try {
                        lotRealizedPrice = lotResult.realized[1];
                    } catch (any e) {
                        lotRealizedPrice = "";
                    }
                    
                    // Try to get realized price from chunk metadata
                    if ((!isNumeric(lotRealizedPrice) OR val(lotRealizedPrice) EQ 0) AND chunkData.recordCount GT 0) {
                        try {
                            chunkMeta = deserializeJSON(chunkData.metadata[1]);
                            if (structKeyExists(chunkMeta, "realizedPrice") AND len(chunkMeta.realizedPrice)) {
                                lotRealizedPrice = chunkMeta.realizedPrice;
                            }
                        } catch (any e) {}
                    }
                    
                    try {
                        lotImageUrl = lotResult.image_url[1];
                    } catch (any e) {
                        lotImageUrl = "";
                    }
                    
                    // Try to get image URL from chunk metadata
                    if (len(trim(lotImageUrl)) EQ 0 AND chunkData.recordCount GT 0) {
                        try {
                            chunkMeta = deserializeJSON(chunkData.metadata[1]);
                            if (structKeyExists(chunkMeta, "imageUrl") AND len(chunkMeta.imageUrl)) {
                                lotImageUrl = chunkMeta.imageUrl;
                            }
                        } catch (any e) {}
                    }
                    
                    try {
                        lotUrl = lotResult.lot_url[1];
                    } catch (any e) {
                        lotUrl = "";
                    }
                    
                    // Try to get lot URL from chunk metadata
                    if (len(trim(lotUrl)) EQ 0 AND chunkData.recordCount GT 0) {
                        try {
                            chunkMeta = deserializeJSON(chunkData.metadata[1]);
                            if (structKeyExists(chunkMeta, "lotUrl") AND len(chunkMeta.lotUrl)) {
                                lotUrl = chunkMeta.lotUrl;
                            }
                        } catch (any e) {}
                    }
                    
                    try {
                        foundAuctionName = lotResult.salename[1];
                    } catch (any e) {
                        foundAuctionName = "";
                    }
                    
                    if (len(trim(foundAuctionName)) EQ 0) {
                        if (len(trim(actualAuctionName)) GT 0) {
                            foundAuctionName = actualAuctionName;
                        } else if (len(trim(lotAuctionName)) GT 0) {
                            foundAuctionName = lotAuctionName;
                        } else {
                            foundAuctionName = "Unknown Auction";
                        }
                    }
                    
                    // Build response in Markdown format
                    lotResponse = "**Lot " & lotNumber & ": " & htmlEditFormat(lotTitle) & "**" & chr(10) & chr(10);
                    lotResponse &= "**Auction:** " & htmlEditFormat(foundAuctionName) & chr(10);
                    
                    if (len(trim(lotCategory)) GT 0) {
                        lotResponse &= "**Category:** " & htmlEditFormat(lotCategory) & chr(10);
                    }
                    
                    if (isNumeric(lotStartingPrice) AND val(lotStartingPrice) GT 0) {
                        lotResponse &= "**Starting Price:** " & numberFormat(val(lotStartingPrice), "0.00") & chr(10);
                    } else if (len(trim(lotStartingPrice)) GT 0) {
                        lotResponse &= "**Starting Price:** " & htmlEditFormat(lotStartingPrice) & chr(10);
                    }
                    
                    if (isNumeric(lotRealizedPrice) AND val(lotRealizedPrice) GT 0) {
                        lotResponse &= "**Realized Price:** " & numberFormat(val(lotRealizedPrice), "0.00") & chr(10);
                    } else if (len(trim(lotRealizedPrice)) GT 0) {
                        lotResponse &= "**Realized Price:** " & htmlEditFormat(lotRealizedPrice) & chr(10);
                    }
                    
                    if (len(trim(lotDesc)) GT 0) {
                        cleanDesc = reReplace(lotDesc, "<[^>]+>", "", "all");
                        cleanDesc = reReplace(cleanDesc, "&nbsp;|&amp;|&lt;|&gt;|&quot;", " ", "all");
                        cleanDesc = trim(cleanDesc);
                        if (len(cleanDesc) GT 0) {
                            lotResponse &= chr(10) & htmlEditFormat(cleanDesc) & chr(10);
                        }
                    }
                    
                    if (len(trim(lotImageUrl)) GT 0) {
                        lotResponse &= chr(10) & "![Lot Image](" & lotImageUrl & ")" & chr(10);
                    }
                    
                    if (len(trim(lotUrl)) GT 0) {
                        lotResponse &= chr(10) & "[View Lot](" & lotUrl & ")" & chr(10);
                    }
                    
                    writeOutput("<div class=""answer-box"">" & replace(lotResponse, chr(10), "<br>", "all") & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": lotResponse});
                    abort;
                } else {
                    // Lot not found - provide helpful error message
                    errorMsg = "I could not find Lot " & lotNumber;
                    if (len(trim(lotAuctionName)) GT 0) {
                        errorMsg &= " in the auction ""<strong>" & htmlEditFormat(lotAuctionName) & "</strong>""";
                    }
                    errorMsg &= " in the database. Please check the lot number and auction name.";
                    
                    writeOutput("<div class=""answer-box"">" & errorMsg & "</div>");
                    arrayAppend(session.chatHistory, {"role": "user", "content": userPrompt});
                    arrayAppend(session.chatHistory, {"role": "assistant", "content": errorMsg});
                    abort;
                }
            } catch (any e) {
                // If lot query fails, silently continue to RAG search
                // Don't break other queries
            }
        }
    }
}
</cfscript>

<!--- Step 1: Embedding --->
<cfscript>
    // Properly escape userPrompt for JSON using serializeJSON
    embedBody = {
        "model": application.ai.embedModel,
        "input": userPrompt
    };
    embedBodyJSON = serializeJSON(embedBody);
</cfscript>
<cfhttp url="#application.ai.apiBaseUrl#/embeddings" method="POST" result="embedCall" timeout="#application.ai.timeout#">
    <cfhttpparam type="header" name="Authorization" value="Bearer #openaiKey#" />
    <cfhttpparam type="header" name="Content-Type" value="application/json" />
    <cfhttpparam type="body" value="#embedBodyJSON#" />
</cfhttp>

<cfscript>
    try {
        if (findNoCase("error", embedCall.fileContent) OR findNoCase("timeout", embedCall.fileContent)) {
            writeOutput("<div class=""answer-box""><p>❌ API Error: " & htmlEditFormat(embedCall.fileContent) & "</p><p>Please try again with a shorter query.</p></div>");
            abort;
        }
        embedJSON = deserializeJSON(embedCall.fileContent);
        embedding = embedJSON.data[1].embedding;
        embStr = "[" & ArrayToList(embedding, ",") & "]";
    } catch (any e) {
        writeOutput("<div class=""answer-box""><p>❌ Embedding API Error: " & htmlEditFormat(e.message) & "</p>");
        if (findNoCase("timeout", e.message)) {
            writeOutput("<p>Request timed out. Please try again with a shorter query.</p>");
        }
        writeOutput("</div>");
        abort;
    }
</cfscript>

<!--- Step 2: DB Search --->
<cfscript>
    try {
        relatedChunks = queryExecute(
            "SELECT 
                l.source_type,
                l.source_name,
                l.source_id,
                l.title,
                l.category,
                l.content_type,
                l.chunk_text,
                l.metadata,
                1 - (l.embedding <-> ?::vector) AS similarity
            FROM chunks l
            WHERE l.embedding IS NOT NULL
            ORDER BY l.embedding <-> ?::vector ASC
            LIMIT 15",
            [
                {value: embStr, cfsqltype: "cf_sql_varchar"},
                {value: embStr, cfsqltype: "cf_sql_varchar"}
            ],
            {
                datasource: application.db.dsn,
                timeout: 30
            }
        );
    } catch (any e) {
        writeOutput("<div class=""answer-box""><p>❌ Database search error: " & htmlEditFormat(e.message) & "</p><p>Please try again or contact support.</p></div>");
        abort;
    }
</cfscript>

<cfscript>
    maxItems = application.ai.maxItems;
    maxChars = application.ai.maxChars;
    chunks = [];
    contextText = "";
    contextCap = 15000;

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
        {"role": "system", "content": "Context:\n\n" & left(contextText, 15000)}
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
            // Check for timeout errors
            if (findNoCase("timeout", gptCall.fileContent) OR findNoCase("exceeded", gptCall.fileContent)) {
                writeOutput("<div class=""answer-box""><p>❌ Request timed out. The query took too long to process.</p><p>Please try a more specific search term or contact support.</p></div>");
                abort;
            }
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

    

