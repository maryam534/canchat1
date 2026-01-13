<cfsetting requesttimeout="900" showdebugoutput="false">

<cfscript>
// Inputs
eventId = trim(toString(url.eventid ?: form.eventid ?: ""));
if (!len(eventId)) {
    writeOutput("<p style='color: red'>Missing required parameter: eventid</p>");
    abort;
}

// Paths/config
paths        = application.paths ?: {};
workDir      = getDirectoryFromPath(getCurrentTemplatePath());
nodeExe      = (paths.nodeBinary ?: "node.exe");
singleScript = workDir & "scrape_single_event.js";
// Force local directories to avoid resolve issues when CF temp dirs differ
finalDir     = workDir & "allAuctionLotsData_final";
inProgDir    = workDir & "allAuctionLotsData_inprogress";
finalFile    = finalDir & "\\auction_" & eventId & "_lots.json";
outPath      = inProgDir & "\\auction_" & eventId & "_lots.jsonl";

// Ensure dirs
if (!directoryExists(inProgDir)) directoryCreate(inProgDir);
if (!directoryExists(finalDir)) directoryCreate(finalDir);

// Build args
args = '"' & singleScript & '" --event-id ' & eventId & ' --output-file "' & outPath & '"';

// Execute scraper
outTxt = ""; errTxt = "";
cfexecute(
    name          = nodeExe,
    arguments     = args,
    timeout       = 600,
    variable      = "outTxt",
    errorVariable = "errTxt"
);

// Post-process: if final file is an array, wrap into object with lots
if (fileExists(finalFile)) {
    fileContent = fileRead(finalFile, "utf-8");
    trimmed = trim(fileContent);
    if (left(trimmed, 1) EQ "[") {
        // Parse array and wrap
        lotsArr = deserializeJSON(trimmed);
        saleInfo = structNew();
        if (arrayLen(lotsArr)) {
            firstLot = lotsArr[1];
        } else {
            firstLot = {};
        }
        wrapped = {
            auctionid: toString(firstLot["auctionid"] ?: eventId),
            auctionname: firstLot["auctionname"] ?: "",
            auctiontitle: firstLot["auctiontitle"] ?: "",
            eventdate: firstLot["eventdate"] ?: "",
            saleInfo: {},
            contact: {},
            lots: lotsArr
        };
        fileWrite(finalFile, serializeJSON(wrapped, true));
    }
}

// Decide whether to run inserter: must exist and contain lots
shouldInsert = false;
if (fileExists(finalFile)) {
    try {
        j = deserializeJSON(fileRead(finalFile, "utf-8"));
        hasLots = isStruct(j) AND structKeyExists(j, "lots") AND isArray(j.lots) AND arrayLen(j.lots) GT 0;
        shouldInsert = hasLots;
    } catch (any e) {
        shouldInsert = false;
    }
}

// Guard against double-insert using uploaded_files table (status Completed)
if (shouldInsert) {
    fileNameOnly = getFileFromPath(finalFile);
    alreadyDone = false;
    try {
        q = queryExecute(
            "SELECT status FROM uploaded_files WHERE file_name = ? LIMIT 1",
            [ { value = fileNameOnly, cfsqltype = "cf_sql_varchar" } ],
            { datasource = application.db.dsn }
        );
        if (q.recordCount AND uCase(q.status) EQ "COMPLETED") {
            alreadyDone = true;
        }
    } catch (any e) {
        // ignore db errors; fall back to executing
    }

    if (!alreadyDone) {
        inserter = workDir & "insert_lots_into_db.js";
        insOut = ""; insErr = "";
        cfexecute(
            name          = nodeExe,
            arguments     = '"' & inserter & '"',
            timeout       = 900,
            variable      = "insOut",
            errorVariable = "insErr"
        );
    }
}
</cfscript>

<cfoutput>
<h2 style="font-family:Segoe UI">Single Event Scrape & Insert</h2>
<p><strong>Event:</strong> #encodeForHtml(eventId)#</p>
<p><strong>Scrape Cmd:</strong> <code>#encodeForHtml(nodeExe & " " & args)#</code></p>

<h3>Scraper STDOUT</h3>
<pre style="background: ##111; color: ##0f0; padding: 10px; border-radius: 6px; white-space: pre-wrap;">#encodeForHtml(outTxt)#</pre>

<h3>Scraper STDERR</h3>
<pre style="background: ##311; color: ##f88; padding: 10px; border-radius: 6px; white-space: pre-wrap;">#encodeForHtml(errTxt)#</pre>

<cfif fileExists(finalFile)>
    <p><strong>Final JSON:</strong> #encodeForHtml(finalFile)#</p>
<cfelse>
    <p style="color: ##f88"><strong>Final JSON not found.</strong></p>
</cfif>

<cfif shouldInsert>
    <h3>Inserter Result</h3>
    <pre style="background: ##111; color: ##0f0; padding: 10px; border-radius: 6px; white-space: pre-wrap;">#encodeForHtml(insOut ?: "")#</pre>
    <h3>Inserter Errors</h3>
    <pre style="background: ##311; color: ##f88; padding: 10px; border-radius: 6px; white-space: pre-wrap;">#encodeForHtml(insErr ?: "")#</pre>
<cfelse>
    <p style="color: ##f88">Insert skipped (no lots found or parse error).</p>
</cfif>
</cfoutput>


