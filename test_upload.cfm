<!---
    Test Upload Diagnostics Page
    Helps diagnose upload and processing issues
--->

<cfscript>
    // Test configuration values
    testResults = [];
    
    // Check upload directory
    uploadDir = application.paths.uploadsDir;
    arrayAppend(testResults, {
        test: "Upload Directory Config",
        value: uploadDir,
        status: len(uploadDir) > 0 ? "PASS" : "FAIL"
    });
    
    arrayAppend(testResults, {
        test: "Upload Directory Exists",
        value: uploadDir,
        status: directoryExists(uploadDir) ? "PASS" : "FAIL"
    });
    
    // Check temp directory
    tempDir = expandPath("./temp");
    arrayAppend(testResults, {
        test: "Temp Directory Path",
        value: tempDir,
        status: "INFO"
    });
    
    arrayAppend(testResults, {
        test: "Temp Directory Exists",
        value: tempDir,
        status: directoryExists(tempDir) ? "PASS" : "FAIL"
    });
    
    // Check Tika configuration
    tikaPath = application.processing.tikaPath;
    arrayAppend(testResults, {
        test: "Tika JAR Path",
        value: tikaPath,
        status: len(tikaPath) > 0 ? "INFO" : "FAIL"
    });
    
    arrayAppend(testResults, {
        test: "Tika JAR Exists",
        value: tikaPath,
        status: fileExists(tikaPath) ? "PASS" : "FAIL"
    });
    
    // Test Tika Java Object
    try {
        tikaObj = createObject("java", "org.apache.tika.Tika");
        arrayAppend(testResults, {
            test: "Tika Java Object",
            value: "org.apache.tika.Tika created successfully",
            status: "PASS"
        });
    } catch (any e) {
        arrayAppend(testResults, {
            test: "Tika Java Object",
            value: e.message,
            status: "FAIL"
        });
    }
    
    // Check Java availability
    try {
        cfexecute(name="java", arguments="-version", variable="javaVersion", errorVariable="javaError", timeout="5");
        arrayAppend(testResults, {
            test: "Java Available",
            value: "java -version executed successfully",
            status: "PASS"
        });
    } catch (any e) {
        arrayAppend(testResults, {
            test: "Java Available",
            value: e.message,
            status: "FAIL"
        });
    }
    
    // Check OpenAI API Key
    openaiKey = application.ai.openaiKey;
    arrayAppend(testResults, {
        test: "OpenAI API Key",
        value: len(openaiKey) > 10 ? left(openaiKey, 10) & "..." : "NOT SET",
        status: len(openaiKey) > 10 ? "PASS" : "FAIL"
    });
</cfscript>

<!DOCTYPE html>
<html>
<head>
    <title>Upload Test Diagnostics</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">
    <div class="max-w-4xl mx-auto">
        <h1 class="text-3xl font-bold text-gray-800 mb-6">Upload & Processing Diagnostics</h1>
        
        <div class="bg-white rounded-lg shadow p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">System Tests</h2>
            <div class="overflow-x-auto">
                <table class="w-full table-auto">
                    <thead class="bg-gray-100">
                        <tr>
                            <th class="text-left p-3 font-medium text-gray-700">Test</th>
                            <th class="text-left p-3 font-medium text-gray-700">Value</th>
                            <th class="text-left p-3 font-medium text-gray-700">Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        <cfoutput>
                        <cfloop array="#testResults#" index="result">
                            <tr class="border-t border-gray-200">
                                <td class="p-3 font-medium">#result.test#</td>
                                <td class="p-3 font-mono text-sm">#encodeForHtml(result.value)#</td>
                                <td class="p-3">
                                    <cfif result.status == "PASS">
                                        <span class="bg-green-100 text-green-800 px-2 py-1 rounded text-sm font-medium">PASS</span>
                                    <cfelseif result.status == "FAIL">
                                        <span class="bg-red-100 text-red-800 px-2 py-1 rounded text-sm font-medium">FAIL</span>
                                    <cfelse>
                                        <span class="bg-blue-100 text-blue-800 px-2 py-1 rounded text-sm font-medium">INFO</span>
                                    </cfif>
                                </td>
                            </tr>
                        </cfloop>
                        </cfoutput>
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow p-6 mb-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Test File Upload</h2>
            <form action="upload.cfm" method="post" enctype="multipart/form-data" class="space-y-4">
                <div>
                    <label class="block text-sm font-medium text-gray-700 mb-2">Select PDF File to Test:</label>
                    <input type="file" name="catalogFile" accept=".pdf" class="block w-full border border-gray-300 rounded-lg px-3 py-2" required>
                </div>
                <button type="submit" class="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700">
                    Test Upload
                </button>
            </form>
        </div>
        
        <div class="bg-white rounded-lg shadow p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4">Log File Locations</h2>
            <div class="space-y-2 text-sm">
                <div><strong>Upload Debug:</strong> ColdFusion logs directory → upload_debug.log</div>
                <div><strong>Tika Commands:</strong> ColdFusion logs directory → tika_commands.log</div>
                <div><strong>Process Debug:</strong> ColdFusion logs directory → process_upload_debug.log</div>
                <div><strong>Process Errors:</strong> ColdFusion logs directory → process_upload_errors.log</div>
            </div>
        </div>
        
        <div class="mt-6 text-center">
            <a href="index.cfm" class="text-blue-600 hover:text-blue-800 underline">← Back to Chat</a>
        </div>
    </div>
</body>
</html>
