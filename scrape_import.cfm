<!---
    Web Scraping and Import Handler
    Scrapes content from URLs and creates embeddings
--->

<cfparam name="form.inputURLs" default="" />

<cfscript>
    // Get configuration from application scope
    jsoupClass = application.processing.jsoupClass;
    embedModel = application.ai.embedModel;
    openaiKey = replace(application.ai.openaiKey, '"', "", "all");
    apiBaseUrl = application.ai.apiBaseUrl;
    chunkSize = application.processing.chunkSize;
    
    jsoup = createObject("java", jsoupClass);
</cfscript>

<cfset urlList = [] />

<cfif form.inputURLs contains "sitemap">
  <cfhttp url="#form.inputURLs#" method="get" />
  <cfset sitemap = xmlParse(cfhttp.fileContent) />
  <cfloop array="#xmlSearch(sitemap, '//url/loc')#" index="u">
    <cfset arrayAppend(urlList, u.xmlText) />
  </cfloop>
<cfelse>
  <cfset urlList = listToArray(form.inputURLs, chr(10)) />
</cfif>

<cfset scrapeResults = [] />

<cfloop array="#urlList#" index="urlIndex">
  <cftry>
    <cfset doc = jsoup.connect(trim(urlIndex)).get() />
    <cfset pageTitle = doc.title().toString()>
    <cfset text = doc.select("body").text() />

    <cfif len(text) lte 200>
      <cfset arrayAppend(scrapeResults, "Skipped (Too short): #urlIndex#") />
      <cfcontinue>
    </cfif>

    <cfset wordArray = listToArray(text, " ") />
    <cfset chunks = [] />
    <cfloop from="1" to="#arrayLen(wordArray)#" step="#chunkSize#" index="currentRow">
      <cfset length = min(chunkSize, arrayLen(wordArray) - currentRow + 1)>
      <cfset chunk = arraySlice(wordArray, currentRow, length)>
      <cfset arrayAppend(chunks, arrayToList(chunk, " "))>
    </cfloop>

    <cfloop array="#chunks#" index="chunkText">
      <!--- Prevent duplicate chunks --->
      <cfquery name="checkDup" datasource="#application.db.dsn#">
        SELECT 1 FROM stamp_chunks
        WHERE chunk_text = <cfqueryparam value="#chunkText#" cfsqltype="cf_sql_varchar">
        AND source_name = <cfqueryparam value="#urlIndex#" cfsqltype="cf_sql_varchar">
      </cfquery>

      <cfif checkDup.recordCount EQ 0>
        <cfset bodyStruct = {
          "model": embedModel,
          "input": chunkText
        } />
        <cfhttp url="#apiBaseUrl#/embeddings" method="post">
          <cfhttpparam type="header" name="Authorization" value="Bearer #openaiKey#" />
          <cfhttpparam type="header" name="Content-Type" value="application/json" />
          <cfhttpparam type="body" value="#serializeJSON(bodyStruct)#" />
        </cfhttp>
        <cfset embedResult = DeserializeJSON(cfhttp.filecontent) />
        
        <cfif NOT structKeyExists(embedResult, "data")>
          <cfset arrayAppend(scrapeResults, "OpenAI error at #urlIndex#: #serializeJSON(embedResult)#") />
          <cfcontinue>
        </cfif>
        <cfset embedding = "[" & ArrayToList(embedResult.data[1].embedding, ",") & "]" />
        <cfquery datasource="#application.db.dsn#">
          INSERT INTO stamp_chunks (chunk_text, embedding, source_type, source_name)
          VALUES (
            <cfqueryparam value="#chunkText#" cfsqltype="cf_sql_varchar">,
            <cfqueryparam value="#embedding#" cfsqltype="cf_sql_varchar">::vector,
            'web',
            <cfqueryparam value="#urlIndex#" cfsqltype="cf_sql_varchar">
          )
        </cfquery>
      </cfif>
      <cfset sleep(200)>
    </cfloop>

    <cfset arrayAppend(scrapeResults, "Processed: #urlIndex#") />

    <cfcatch>
      <cfset arrayAppend(scrapeResults, "Error at #urlIndex#: #serializeJSON(cfcatch)#") />
    </cfcatch>
  </cftry>
</cfloop>

<cfoutput>
  <p class="font-bold">Web scraping completed:</p>
  <ul class="list-disc pl-6">
    <cfloop array="#scrapeResults#" index="item">
      <li>#item#</li>
    </cfloop>
  </ul>
  <p class="mt-4"><a href="dashboard.cfm" class="text-blue-600 underline">← Back to Dashboard</a></p>
</cfoutput>
