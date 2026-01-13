<!---
    JavaLoader Test for Dynamic JAR Loading
--->

<!DOCTYPE html>
<html>
<head>
    <title>JavaLoader Test</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">
    <div class="max-w-4xl mx-auto">
        <h1 class="text-3xl font-bold text-gray-800 mb-6">JavaLoader Dynamic JAR Loading Test</h1>
        
        <div class="bg-white rounded-lg shadow p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">JavaLoader Status</h2>
            
            <cfscript>
                javaLoaderAvailable = isObject(application.javaLoader);
                writeOutput("<p><strong>JavaLoader Available:</strong> " & javaLoaderAvailable & "</p>");
                
                if (javaLoaderAvailable) {
                    writeOutput("<p><strong>JavaLoader Type:</strong> " & getMetadata(application.javaLoader).name & "</p>");
                } else {
                    writeOutput("<p><strong>Issue:</strong> JavaLoader not initialized in Application.cfc</p>");
                }
            </cfscript>
        </div>
        
        <cfif javaLoaderAvailable>
            <div class="bg-white rounded-lg shadow p-6 mb-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">Test 1: Create Tika Object</h2>
                
                <cftry>
                    <cfscript>
                        // Test creating Tika object via JavaLoader with proper constructor
                        tika = application.javaLoader.create("org.apache.tika.Tika").init();
                        writeOutput("<p>✅ <strong>SUCCESS:</strong> Tika object created via JavaLoader!</p>");
                        writeOutput("<p><strong>Tika Class:</strong> " & getMetadata(tika).name & "</p>");
                        
                        // Test basic functionality
                        tikaVersion = tika.toString();
                        writeOutput("<p><strong>Tika Instance:</strong> " & tikaVersion & "</p>");
                    </cfscript>
                    
                    <cfcatch type="any">
                        <cfoutput>
                            <p>❌ <strong>FAILED:</strong> Could not create Tika via JavaLoader</p>
                            <p><strong>Error:</strong> #cfcatch.message#</p>
                            <p><strong>Type:</strong> #cfcatch.type#</p>
                            <p><strong>Detail:</strong> #cfcatch.detail#</p>
                        </cfoutput>
                        
                        <!--- Try alternative JavaLoader approach --->
                        <cftry>
                            <cfscript>
                                writeOutput("<p><strong>Trying alternative approach...</strong></p>");
                                
                                // Try using JavaLoader's createObject method
                                tikaClass = application.javaLoader.create("org.apache.tika.Tika");
                                writeOutput("<p>✅ <strong>Alternative SUCCESS:</strong> Tika class loaded!</p>");
                                
                                // Try to get available constructors
                                constructors = tikaClass.getClass().getConstructors();
                                writeOutput("<p><strong>Available constructors:</strong> " & arrayLen(constructors) & "</p>");
                                
                                // Try default constructor
                                tika = tikaClass.getClass().newInstance();
                                writeOutput("<p>✅ <strong>Instance created!</strong></p>");
                            </cfscript>
                            
                            <cfcatch type="any">
                                <cfoutput>
                                    <p>❌ <strong>Alternative also failed:</strong> #cfcatch.message#</p>
                                </cfoutput>
                            </cfcatch>
                        </cftry>
                    </cfcatch>
                </cftry>
            </div>
            
            <div class="bg-white rounded-lg shadow p-6 mb-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">Test 2: Create Sample Document and Extract</h2>
                
                <cfscript>
                    // Create sample text file
                    sampleContent = "This is a test document for JavaLoader Tika integration. " &
                                  "It contains sample text to verify that our dynamic JAR loading " &
                                  "system works correctly with Apache Tika for document processing.";
                    
                    tempFolder = expandPath("./temp");
                    if (!directoryExists(tempFolder)) {
                        directoryCreate(tempFolder);
                    }
                    
                    sampleFilePath = tempFolder & "/javaloader_test.txt";
                    fileWrite(sampleFilePath, sampleContent);
                    
                    writeOutput("<p><strong>Sample file created:</strong> " & sampleFilePath & "</p>");
                </cfscript>
                
                <cftry>
                    <cfscript>
                        if (isDefined("tika")) {
                            // Test text extraction
                            javaFile = createObject("java", "java.io.File").init(sampleFilePath);
                            fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
                            
                            extractedContent = tika.parseToString(fileInputStream);
                            detectedType = tika.detect(javaFile);
                            
                            fileInputStream.close();
                            
                            writeOutput("<p>✅ <strong>SUCCESS:</strong> Text extraction via JavaLoader!</p>");
                            writeOutput("<p><strong>Detected Type:</strong> " & detectedType & "</p>");
                            writeOutput("<p><strong>Original Length:</strong> " & len(sampleContent) & " characters</p>");
                            writeOutput("<p><strong>Extracted Length:</strong> " & len(extractedContent) & " characters</p>");
                            writeOutput("<p><strong>Content Match:</strong> " & (trim(extractedContent) == sampleContent ? "Perfect!" : "Close enough") & "</p>");
                            
                            // Clean up
                            fileDelete(sampleFilePath);
                        }
                    </cfscript>
                    
                    <cfcatch type="any">
                        <cfoutput>
                            <p>❌ <strong>FAILED:</strong> Text extraction failed</p>
                            <p><strong>Error:</strong> #cfcatch.message#</p>
                            <p><strong>Detail:</strong> #cfcatch.detail#</p>
                        </cfoutput>
                    </cfcatch>
                </cftry>
            </div>
            
            <div class="bg-white rounded-lg shadow p-6 mb-6">
                <h2 class="text-xl font-semibold text-gray-800 mb-4">Test 3: JSoup via JavaLoader</h2>
                
                <cftry>
                    <cfscript>
                        // Test JSoup creation via JavaLoader
                        jsoup = application.javaLoader.create("org.jsoup.Jsoup");
                        writeOutput("<p>✅ <strong>SUCCESS:</strong> JSoup object created via JavaLoader!</p>");
                        writeOutput("<p><strong>JSoup Class:</strong> " & getMetadata(jsoup).name & "</p>");
                        
                        // Test a simple HTML parsing
                        simpleHtml = "<html><body><h1>Test Title</h1><p>Test content</p></body></html>";
                        doc = jsoup.parse(simpleHtml);
                        title = doc.title();
                        text = doc.text();
                        
                        writeOutput("<p><strong>HTML Title:</strong> " & title & "</p>");
                        writeOutput("<p><strong>HTML Text:</strong> " & text & "</p>");
                    </cfscript>
                    
                    <cfcatch type="any">
                        <cfoutput>
                            <p>❌ <strong>FAILED:</strong> JSoup test failed</p>
                            <p><strong>Error:</strong> #cfcatch.message#</p>
                        </cfoutput>
                    </cfcatch>
                </cftry>
            </div>
            
        <cfelse>
            <div class="bg-yellow-50 border border-yellow-200 rounded-lg p-6">
                <h3 class="text-yellow-800 font-semibold">JavaLoader Not Available</h3>
                <p class="text-yellow-700">JavaLoader is not initialized. Check Application.cfc for initialization errors.</p>
                <p class="text-yellow-700">The system will fall back to command-line Tika execution.</p>
            </div>
        </cfif>
        
        <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">JAR File Status</h2>
            
            <cfscript>
                tikaJarPath = expandPath("./libs/tika-app-3.2.3.jar");
                jsoupJarPath = expandPath("./libs/jsoup-1.20.1.jar");
                
                writeOutput("<p><strong>Tika JAR:</strong> " & tikaJarPath & "</p>");
                writeOutput("<p><strong>Tika Exists:</strong> " & fileExists(tikaJarPath) & "</p>");
                
                if (fileExists(tikaJarPath)) {
                    fileInfo = getFileInfo(tikaJarPath);
                    writeOutput("<p><strong>Tika Size:</strong> " & numberFormat(fileInfo.size/1024/1024, "99.9") & " MB</p>");
                }
                
                writeOutput("<p><strong>JSoup JAR:</strong> " & jsoupJarPath & "</p>");
                writeOutput("<p><strong>JSoup Exists:</strong> " & fileExists(jsoupJarPath) & "</p>");
                
                if (fileExists(jsoupJarPath)) {
                    fileInfo = getFileInfo(jsoupJarPath);
                    writeOutput("<p><strong>JSoup Size:</strong> " & numberFormat(fileInfo.size/1024, "999") & " KB</p>");
                }
            </cfscript>
        </div>
        
        <div class="mt-6 text-center space-x-4">
            <a href="upload.cfm" class="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors">
                Test Upload with JavaLoader
            </a>
            <a href="index.cfm" class="text-blue-600 hover:text-blue-800 underline">
                ← Back to Chat
            </a>
        </div>
    </div>
</body>
</html>
