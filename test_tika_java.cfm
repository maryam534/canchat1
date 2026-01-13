<!---
    Test Tika Java Object Loading
--->

<h1>Tika Java Object Test</h1>

<cfscript>
    tikaPath = application.processing.tikaPath;
    writeOutput("<p><strong>Tika JAR Path:</strong> " & tikaPath & "</p>");
    writeOutput("<p><strong>Tika JAR Exists:</strong> " & fileExists(tikaPath) & "</p>");
</cfscript>

<h2>Test 1: Create Tika Object</h2>
<cftry>
    <cfscript>
        // Try to create Tika object
        tika = createObject("java", "org.apache.tika.Tika");
        writeOutput("<p>✅ <strong>SUCCESS:</strong> Tika object created successfully!</p>");
        writeOutput("<p><strong>Tika Class:</strong> " & tika.getClass().getName() & "</p>");
    </cfscript>
    
    <cfcatch type="any">
        <cfoutput>
            <p>❌ <strong>FAILED:</strong> Could not create Tika object</p>
            <p><strong>Error:</strong> #cfcatch.message#</p>
            <p><strong>Type:</strong> #cfcatch.type#</p>
            <p><strong>Detail:</strong> #cfcatch.detail#</p>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 2: Check Available Parsers</h2>
<cftry>
    <cfscript>
        if (isDefined("tika")) {
            // Get available parsers
            parserContext = createObject("java", "org.apache.tika.parser.ParseContext");
            autoDetectParser = createObject("java", "org.apache.tika.parser.AutoDetectParser");
            
            writeOutput("<p>✅ <strong>SUCCESS:</strong> AutoDetectParser created!</p>");
            writeOutput("<p><strong>Parser Class:</strong> " & autoDetectParser.getClass().getName() & "</p>");
            
            // Test supported types
            supportedTypes = autoDetectParser.getSupportedTypes(parserContext);
            writeOutput("<p><strong>Supported Types Count:</strong> " & supportedTypes.size() & "</p>");
            
            // Show first few supported types
            iterator = supportedTypes.iterator();
            count = 0;
            writeOutput("<p><strong>Sample Supported Types:</strong></p><ul>");
            while (iterator.hasNext() && count < 10) {
                mediaType = iterator.next();
                writeOutput("<li>" & mediaType.toString() & "</li>");
                count++;
            }
            writeOutput("</ul>");
        }
    </cfscript>
    
    <cfcatch type="any">
        <cfoutput>
            <p>❌ <strong>FAILED:</strong> Could not test parsers</p>
            <p><strong>Error:</strong> #cfcatch.message#</p>
            <p><strong>Detail:</strong> #cfcatch.detail#</p>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 3: Create Test File and Extract</h2>
<cfscript>
    // Create a simple text file for testing
    testFilePath = expandPath("./temp/test_document.txt");
    testContent = "This is a test document for Tika extraction. It contains sample text to verify that Tika can read basic text files.";
    
    if (!directoryExists(expandPath("./temp"))) {
        directoryCreate(expandPath("./temp"));
    }
    
    fileWrite(testFilePath, testContent);
    writeOutput("<p><strong>Test file created:</strong> " & testFilePath & "</p>");
</cfscript>

<cftry>
    <cfscript>
        if (isDefined("tika")) {
            // Create Java File object
            javaFile = createObject("java", "java.io.File").init(testFilePath);
            
            // Create FileInputStream
            fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
            
            // Extract text using Tika
            extractedText = tika.parseToString(fileInputStream);
            
            // Close stream
            fileInputStream.close();
            
            writeOutput("<p>✅ <strong>SUCCESS:</strong> Text extracted successfully!</p>");
            writeOutput("<p><strong>Original text length:</strong> " & len(testContent) & "</p>");
            writeOutput("<p><strong>Extracted text length:</strong> " & len(extractedText) & "</p>");
            writeOutput("<p><strong>Extracted text:</strong> " & encodeForHtml(extractedText) & "</p>");
            
            // Clean up test file
            fileDelete(testFilePath);
            writeOutput("<p><strong>Test file cleaned up.</strong></p>");
        }
    </cfscript>
    
    <cfcatch type="any">
        <cfoutput>
            <p>❌ <strong>FAILED:</strong> Could not extract text</p>
            <p><strong>Error:</strong> #cfcatch.message#</p>
            <p><strong>Detail:</strong> #cfcatch.detail#</p>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Recommendations</h2>
<cfif isDefined("tika")>
    <p>✅ Tika is working correctly! You can now use it for document processing.</p>
<cfelse>
    <div style="background: ##fff3cd; border: 1px solid ##ffeaa7; padding: 10px; border-radius: 5px;">
        <p><strong>Tika is not available. Possible solutions:</strong></p>
        <ol>
            <li>Ensure the Tika JAR file exists at: <code>#tikaPath#</code></li>
            <li>Copy the Tika JAR to the <code>./libs/</code> folder</li>
            <li>Restart the ColdFusion application</li>
            <li>Check ColdFusion Java classpath settings</li>
        </ol>
    </div>
</cfif>

<p><a href="index.cfm">← Back to main page</a></p>
