<cfsetting requesttimeout="300" showdebugoutput="false">

<!--- Minimal cfexecute calling node with exact arguments using absolute paths --->
<cfset out = "">
<cfset err = "">
<cfset workDir    = getDirectoryFromPath(getCurrentTemplatePath())>
<cfset scriptPath = workDir & 'scrape_single_event.js'>
<cfset outPath    = workDir & 'allAuctionLotsData_inprogress\auction_9691_lots.jsonl'>
<cfset cmdExe     = "node.exe"> <!--- Use full path if node isn't on PATH, e.g., C:\\Program Files\\nodejs\\node.exe --->
<!--- Quote paths in case they contain spaces --->
<cfset quotedScript = '"' & scriptPath & '"'>
<cfset quotedOut    = '"' & outPath & '"'>
<cfset args         = quotedScript & ' --event-id 9691 --output-file ' & quotedOut>
<cfoutput>#cmdExe & ' ' & args#</cfoutput>
<cfexecute 
    name="#cmdExe#"
    arguments="#args#"
    timeout="300"
    variable="out"
    errorVariable="err">
</cfexecute>

<cfoutput>
<h2 style="font-family:Segoe UI">CFExecute Test - Node Single Event</h2>
<p><strong>Command:</strong> <code>#encodeForHtml(cmdExe & ' ' & args)#</code></p>

<h3>STDOUT</h3>
<pre style="background: ##111; color: ##0f0; padding: 10px; border-radius: 6px; white-space: pre-wrap;">#encodeForHtml(out)#</pre>

<h3>STDERR</h3>
<pre style="background: ##311; color: ##f88; padding: 10px; border-radius: 6px; white-space: pre-wrap;">#encodeForHtml(err)#</pre>
</cfoutput>



