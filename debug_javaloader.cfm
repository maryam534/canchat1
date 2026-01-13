<!---
    Debug JavaLoader Tika Issues
--->

<h1>JavaLoader Debug - Tika Constructor Issues</h1>

<cfscript>
    writeOutput("<h2>JavaLoader Status:</h2>");
    writeOutput("<p><strong>JavaLoader Available:</strong> " & isObject(application.javaLoader) & "</p>");
    
    if (isObject(application.javaLoader)) {
        writeOutput("<p><strong>JavaLoader Type:</strong> " & getMetadata(application.javaLoader).name & "</p>");
    }
</cfscript>

<cfif isObject(application.javaLoader)>
    <h2>Test 1: List Available Classes</h2>
    <cftry>
        <cfscript>
            // Try to see what classes are available
            writeOutput("<p>Attempting to load Tika class...</p>");
            
            // Method 1: Direct class loading
            tikaClass = application.javaLoader.create("org.apache.tika.Tika");
            writeOutput("<p>✅ Tika class loaded successfully!</p>");
            writeOutput("<p><strong>Class Type:</strong> " & getMetadata(tikaClass).name & "</p>");
            
            // Get class information
            javaClass = tikaClass.getClass();
            writeOutput("<p><strong>Java Class Name:</strong> " & javaClass.getName() & "</p>");
            
            // Get constructors
            constructors = javaClass.getConstructors();
            writeOutput("<p><strong>Number of constructors:</strong> " & arrayLen(constructors) & "</p>");
            
            for (i = 1; i <= arrayLen(constructors); i++) {
                constructor = constructors[i];
                paramTypes = constructor.getParameterTypes();
                writeOutput("<p><strong>Constructor " & i & ":</strong> " & arrayLen(paramTypes) & " parameters</p>");
                
                if (arrayLen(paramTypes) == 0) {
                    writeOutput("<p>  → Default constructor (no parameters)</p>");
                } else {
                    for (j = 1; j <= arrayLen(paramTypes); j++) {
                        writeOutput("<p>  → Parameter " & j & ": " & paramTypes[j].getName() & "</p>");
                    }
                }
            }
        </cfscript>
        
        <cfcatch type="any">
            <cfoutput>
                <p>❌ <strong>Class loading failed:</strong> #cfcatch.message#</p>
                <p><strong>Detail:</strong> #cfcatch.detail#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
    
    <h2>Test 2: Try Different Constructor Approaches</h2>
    
    <h3>Approach A: Default Constructor</h3>
    <cftry>
        <cfscript>
            if (isDefined("tikaClass")) {
                tika1 = tikaClass.getClass().newInstance();
                writeOutput("<p>✅ <strong>SUCCESS A:</strong> Default constructor worked!</p>");
                writeOutput("<p><strong>Instance:</strong> " & tika1.toString() & "</p>");
            }
        </cfscript>
        
        <cfcatch type="any">
            <cfoutput>
                <p>❌ <strong>Approach A failed:</strong> #cfcatch.message#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
    
    <h3>Approach B: JavaLoader Create with Init</h3>
    <cftry>
        <cfscript>
            tika2 = application.javaLoader.create("org.apache.tika.Tika").init();
            writeOutput("<p>✅ <strong>SUCCESS B:</strong> JavaLoader.create().init() worked!</p>");
            writeOutput("<p><strong>Instance:</strong> " & tika2.toString() & "</p>");
        </cfscript>
        
        <cfcatch type="any">
            <cfoutput>
                <p>❌ <strong>Approach B failed:</strong> #cfcatch.message#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
    
    <h3>Approach C: Manual Reflection</h3>
    <cftry>
        <cfscript>
            if (isDefined("tikaClass")) {
                // Get the class object
                javaClass = tikaClass.getClass();
                
                // Get default constructor
                defaultConstructor = javaClass.getConstructor([]);
                
                // Create new instance
                tika3 = defaultConstructor.newInstance([]);
                
                writeOutput("<p>✅ <strong>SUCCESS C:</strong> Reflection constructor worked!</p>");
                writeOutput("<p><strong>Instance:</strong> " & tika3.toString() & "</p>");
            }
        </cfscript>
        
        <cfcatch type="any">
            <cfoutput>
                <p>❌ <strong>Approach C failed:</strong> #cfcatch.message#</p>
            </cfoutput>
        </cfcatch>
    </cftry>
    
    <h2>Test 3: If Any Approach Worked, Test Text Extraction</h2>
    <cfscript>
        // Test with any successful Tika instance
        workingTika = "";
        if (isDefined("tika1")) workingTika = tika1;
        else if (isDefined("tika2")) workingTika = tika2;
        else if (isDefined("tika3")) workingTika = tika3;
        
        if (len(workingTika)) {
            writeOutput("<p><strong>Testing with working Tika instance...</strong></p>");
            
            try {
                // Create sample file
                sampleFilePath = expandPath("./temp/simple_test.txt");
                fileWrite(sampleFilePath, "Hello World! This is a test document.");
                
                // Test detection
                javaFile = createObject("java", "java.io.File").init(sampleFilePath);
                detectedType = workingTika.detect(javaFile);
                writeOutput("<p><strong>Content type detection:</strong> " & detectedType & "</p>");
                
                // Test text extraction
                fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
                extractedText = workingTika.parseToString(fileInputStream);
                fileInputStream.close();
                
                writeOutput("<p>✅ <strong>Text extraction successful!</strong></p>");
                writeOutput("<p><strong>Extracted:</strong> " & extractedText & "</p>");
                
                // Clean up
                fileDelete(sampleFilePath);
                
            } catch (any testError) {
                writeOutput("<p>❌ <strong>Text extraction test failed:</strong> " & testError.message & "</p>");
            }
        } else {
            writeOutput("<p>⚠️ No working Tika instance found. Will use command-line fallback.</p>");
        }
    </cfscript>
    
<cfelse>
    <div class="bg-red-50 border border-red-200 rounded-lg p-6">
        <h3 class="text-red-800 font-semibold">JavaLoader Not Available</h3>
        <p class="text-red-700">JavaLoader is not initialized. Check the javaloader folder and Application.cfc.</p>
    </div>
</cfif>

<h2>Recommendations</h2>
<div style="background: ##f0f8ff; padding: 15px; border-radius: 8px;">
    <cfif isDefined("tika1") OR isDefined("tika2") OR isDefined("tika3")>
        <p>✅ <strong>JavaLoader Tika is working!</strong> The upload system should now work properly.</p>
    <cfelse>
        <p>⚠️ <strong>JavaLoader Tika has issues.</strong> The system will use command-line Tika as fallback.</p>
        <p><strong>Command-line approach is still reliable</strong> and will work for your RAG system.</p>
    </cfif>
</div>

<p><a href="upload.cfm?appreset=1">→ Test Upload with JavaLoader</a></p>
<p><a href="index.cfm">← Back to Chat</a></p>
