<cfmodule template="layout.cfm" title="Test Bulk Processor" currentPage="bulk_processor">

<div class="fade-in">
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            ⚡ <span class="ml-3">Test Bulk Data Processor</span>
        </h1>
        <p class="text-gray-600 mt-2">Testing file listing functionality.</p>
    </div>

    <cfscript>
    // Get paths from application
    paths = application.paths ?: {};
    finalDir = paths.finalDir ?: expandPath("./allAuctionLotsData_final");
    inProgressDir = paths.inProgressDir ?: expandPath("./allAuctionLotsData_inprogress");
    
    // Get all JSON files
    allFiles = [];
    
    writeOutput("<!-- Debug: finalDir = " & finalDir & " -->");
    writeOutput("<!-- Debug: inProgressDir = " & inProgressDir & " -->");
    writeOutput("<!-- Debug: directoryExists(finalDir) = " & directoryExists(finalDir) & " -->");
    
    if (directoryExists(finalDir)) {
        finalDirContents = directoryList(finalDir, false, "name", "*.json");
        writeOutput("<!-- Debug: finalDirContents type = " & getMetadata(finalDirContents).getName() & " -->");
        writeOutput("<!-- Debug: finalDirContents length = " & (isArray(finalDirContents) ? arrayLen(finalDirContents) : finalDirContents.recordCount) & " -->");
        
        if (isArray(finalDirContents)) {
            for (i = 1; i <= arrayLen(finalDirContents); i++) {
                fileName = finalDirContents[i];
                filePath = finalDir & "\" & fileName;
                fileInfo = {
                    name: fileName,
                    path: filePath,
                    size: getFileInfo(filePath).size,
                    modified: getFileInfo(filePath).lastModified,
                    directory: "Final",
                    selected: false
                };
                arrayAppend(allFiles, fileInfo);
            }
        } else {
            for (i = 1; i <= finalDirContents.recordCount; i++) {
                fileName = finalDirContents.name[i];
                filePath = finalDir & "\" & fileName;
                fileInfo = {
                    name: fileName,
                    path: filePath,
                    size: getFileInfo(filePath).size,
                    modified: getFileInfo(filePath).lastModified,
                    directory: "Final",
                    selected: false
                };
                arrayAppend(allFiles, fileInfo);
            }
        }
    }
    
    writeOutput("<!-- Debug: allFiles length = " & arrayLen(allFiles) & " -->");
    </cfscript>

    <div class="bg-white rounded-xl shadow-sm p-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4">Files Found</h2>
        <p>Total files: #arrayLen(allFiles)#</p>
        
        <cfif arrayLen(allFiles) GT 0>
            <div class="space-y-2">
                <cfloop array="#allFiles#" index="file">
                    <div class="border border-gray-200 rounded-lg p-3">
                        <p class="text-sm font-medium text-gray-900">#encodeForHtml(file.name)#</p>
                        <p class="text-xs text-gray-500">#formatFileSize(file.size)# • #dateFormat(file.modified, "mm/dd/yyyy")# #timeFormat(file.modified, "HH:mm")# • #file.directory#</p>
                    </div>
                </cfloop>
            </div>
        <cfelse>
            <p class="text-gray-500">No files found.</p>
        </cfif>
    </div>
</div>

<cfscript>
function formatFileSize(size) {
    if (size LT 1024) {
        return size & " B";
    } else if (size LT 1048576) {
        return round(size / 1024) & " KB";
    } else if (size LT 1073741824) {
        return round(size / 1048576) & " MB";
    } else {
        return round(size / 1073741824) & " GB";
    }
}
</cfscript>

</cfmodule>
