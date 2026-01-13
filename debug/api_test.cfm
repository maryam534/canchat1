<!---
    Simple OpenAI API Test
    Tests both embedding and chat completion endpoints
--->

<cfparam name="url.test" default="embed" />

<cfscript>
    // Get API key
    openaiKey = replace(application.ai.openaiKey, '"', "", "all");
    
    if (len(openaiKey) EQ 0) {
        writeOutput("<h2>Error: No OpenAI API Key</h2>");
        writeOutput("<p>Please set OPENAI_API_KEY environment variable.</p>");
        abort;
    }
</cfscript>

<h2>OpenAI API Test</h2>
<p><a href="?test=embed">Test Embedding API</a> | <a href="?test=chat">Test Chat API</a></p>

<cfif url.test EQ "embed">
    <h3>Testing Embedding API...</h3>
    
    <cfhttp url="#application.ai.apiBaseUrl#/embeddings" 
            method="POST" 
            result="testCall"
            timeout="30">
        <cfhttpparam type="header" 
                     name="Authorization" 
                     value="Bearer #openaiKey#" />
        <cfhttpparam type="header" 
                     name="Content-Type" 
                     value="application/json" />
        <cfhttpparam type="body" 
                     value='{"model": "#application.ai.embedModel#", "input": "test"}' />
    </cfhttp>
    
    <cfoutput>
        <p><strong>Status:</strong> #testCall.statusCode#</p>
        <p><strong>Response:</strong></p>
        <pre style="background:##f5f5f5; padding:10px; border:1px solid ##ccc;">#htmlEditFormat(testCall.fileContent)#</pre>
    </cfoutput>

<cfelseif url.test EQ "chat">
    <h3>Testing Chat API...</h3>
    
    <cfhttp url="#application.ai.apiBaseUrl#/chat/completions" 
            method="POST" 
            result="testCall"
            timeout="30">
        <cfhttpparam type="header" 
                     name="Authorization" 
                     value="Bearer #openaiKey#" />
        <cfhttpparam type="header" 
                     name="Content-Type" 
                     value="application/json" />
        <cfhttpparam type="body" 
                     value='{"model": "#application.ai.chatModel#", "messages": [{"role": "user", "content": "Say hello"}], "temperature": 0}' />
    </cfhttp>
    
    <cfoutput>
        <p><strong>Status:</strong> #testCall.statusCode#</p>
        <p><strong>Response:</strong></p>
        <pre style="background:##f5f5f5; padding:10px; border:1px solid ##ccc;">#htmlEditFormat(testCall.fileContent)#</pre>
    </cfoutput>
</cfif>
