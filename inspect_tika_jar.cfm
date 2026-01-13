<!---
    Inspect Tika JAR Contents
--->

<h1>Tika JAR Inspection</h1>

<cfscript>
    tikaJarPath = expandPath("./libs/tika-app-3.2.3.jar");
    writeOutput("<p><strong>Tika JAR Path:</strong> " & tikaJarPath & "</p>");
    writeOutput("<p><strong>JAR Exists:</strong> " & fileExists(tikaJarPath) & "</p>");
    
    if (fileExists(tikaJarPath)) {
        fileInfo = getFileInfo(tikaJarPath);
        writeOutput("<p><strong>JAR Size:</strong> " & numberFormat(fileInfo.size/1024/1024, "99.9") & " MB</p>");
        writeOutput("<p><strong>Last Modified:</strong> " & fileInfo.lastModified & "</p>");
    }
</cfscript>

<h2>Test 1: Command Line JAR Inspection</h2>
<cftry>
    <cfexecute name="jar" arguments='tf "#tikaJarPath#"' variable="jarContents" errorVariable="jarError" timeout="30">
    
    <cfscript>
        // Look for Tika classes in the JAR
        lines = listToArray(jarContents, chr(10));
        tikaClasses = [];
        
        for (line in lines) {
            if (findNoCase("tika", line) && findNoCase(".class", line)) {
                arrayAppend(tikaClasses, line);
            }
        }
        
        writeOutput("<p><strong>Total entries in JAR:</strong> " & arrayLen(lines) & "</p>");
        writeOutput("<p><strong>Tika classes found:</strong> " & arrayLen(tikaClasses) & "</p>");
        
        if (arrayLen(tikaClasses) > 0) {
            writeOutput("<h3>Sample Tika Classes:</h3><ul>");
            for (i = 1; i <= min(20, arrayLen(tikaClasses)); i++) {
                className = tikaClasses[i];
                // Convert file path to class name
                if (findNoCase("org/apache/tika/Tika.class", className)) {
                    writeOutput("<li><strong>" & className & " ← MAIN TIKA CLASS</strong></li>");
                } else {
                    writeOutput("<li>" & className & "</li>");
                }
            }
            writeOutput("</ul>");
        }
    </cfscript>
    
    <cfcatch type="any">
        <cfoutput>
            <p>❌ <strong>JAR inspection failed:</strong> #cfcatch.message#</p>
            <cfif len(jarError)>
                <p><strong>Error output:</strong> #jarError#</p>
            </cfif>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 2: Direct Java Class Check</h2>
<cftry>
    <cfexecute name="java" arguments='-cp "#tikaJarPath#" org.apache.tika.Tika --help' variable="tikaHelp" errorVariable="tikaHelpError" timeout="15">
    <cfoutput>
        <p>✅ <strong>Tika main class is accessible!</strong></p>
        <pre style="background: ##f5f5f5; padding: 10px; max-height: 200px; overflow-y: auto;">#left(tikaHelp, 1000)#</pre>
    </cfoutput>
    
    <cfcatch type="any">
        <cfoutput>
            <p>❌ <strong>Tika main class test failed:</strong> #cfcatch.message#</p>
            <cfif len(tikaHelpError)>
                <p><strong>Error output:</strong> #tikaHelpError#</p>
            </cfif>
        </cfoutput>
    </cfcatch>
</cftry>

<h2>Test 3: JavaLoader Class Loading Test</h2>
<cfif isObject(application.javaLoader)>
    <cftry>
        <cfscript>
            // Try to list all classes JavaLoader can see
            writeOutput("<p>Testing JavaLoader class discovery...</p>");
            
            // Try different Tika class names that might exist
            classesToTry = [
                "org.apache.tika.Tika",
                "org.apache.tika.parser.AutoDetectParser",
                "org.apache.tika.metadata.Metadata",
                "org.apache.tika.sax.BodyContentHandler"
            ];
            
            for (className in classesToTry) {
                try {
                    testClass = application.javaLoader.create(className);
                    writeOutput("<p>✅ <strong>Found class:</strong> " & className & "</p>");
                } catch (any e) {
                    writeOutput("<p>❌ <strong>Not found:</strong> " & className & " - " & e.message & "</p>");
                }
            }
        </cfscript>
        
        <cfcatch type="any">
            <cfoutput>
                <p>❌ <strong>JavaLoader class test failed:</strong> #cfcatch.message#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
<cfelse>
    <p>❌ JavaLoader not available</p>
</cfif>

<h2>Test 4: Alternative Tika Classes</h2>
<cfif isObject(application.javaLoader)>
    <cftry>
        <cfscript>
            // Try AutoDetectParser instead of Tika facade
            writeOutput("<p>Trying AutoDetectParser approach...</p>");
            
            parser = application.javaLoader.create("org.apache.tika.parser.AutoDetectParser").init();
            metadata = application.javaLoader.create("org.apache.tika.metadata.Metadata").init();
            contentHandler = application.javaLoader.create("org.apache.tika.sax.BodyContentHandler").init();
            parseContext = application.javaLoader.create("org.apache.tika.parser.ParseContext").init();
            
            writeOutput("<p>✅ <strong>All Tika components created successfully!</strong></p>");
            writeOutput("<p><strong>Parser:</strong> " & getMetadata(parser).name & "</p>");
            writeOutput("<p><strong>Metadata:</strong> " & getMetadata(metadata).name & "</p>");
            writeOutput("<p><strong>ContentHandler:</strong> " & getMetadata(contentHandler).name & "</p>");
            
            // Test with sample file
            sampleFilePath = expandPath("./temp/javaloader_test.txt");
            if (fileExists(sampleFilePath)) {
                javaFile = createObject("java", "java.io.File").init(sampleFilePath);
                fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
                
                parser.parse(fileInputStream, contentHandler, metadata, parseContext);
                extractedText = contentHandler.toString();
                
                fileInputStream.close();
                
                writeOutput("<p>✅ <strong>Text extraction via AutoDetectParser successful!</strong></p>");
                writeOutput("<p><strong>Extracted:</strong> " & extractedText & "</p>");
            }
        </cfscript>
        
        <cfcatch type="any">
            <cfoutput>
                <p>❌ <strong>AutoDetectParser failed:</strong> #cfcatch.message#</p>
                <p><strong>Detail:</strong> #cfcatch.detail#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
</cfif>

<div style="background: ##f0f8ff; padding: 15px; border-radius: 8px; margin-top: 20px;">
    <h3>📋 Analysis & Recommendations:</h3>
    <cfif isDefined("parser")>
        <p>✅ <strong>AutoDetectParser works!</strong> Use this approach instead of the Tika facade.</p>
        <p>🔄 The upload system will be updated to use AutoDetectParser for better compatibility.</p>
    <cfelse>
        <p>⚠️ <strong>JavaLoader has issues with this Tika JAR.</strong></p>
        <p>🔄 The system will use command-line Tika which is more reliable for this version.</p>
    </cfif>
</div>

<p><a href="upload.cfm?appreset=1">→ Test Upload with Updated Tika</a></p>
<p><a href="index.cfm">← Back to Chat</a></p>
