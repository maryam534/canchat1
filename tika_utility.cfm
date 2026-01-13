<!---
    Apache Tika Utility Functions
    Similar to JSoup usage - provides various Tika parsing methods
--->

<cfscript>
/**
 * Tika Utility Class - Similar to JSoup usage pattern
 * Provides various document parsing methods using Apache Tika
 */
component {
    
    /**
     * Simple text extraction - equivalent to JSoup's .text()
     */
    public string function extractText(required string filePath) {
        try {
            var tika = createObject("java", "org.apache.tika.Tika");
            var javaFile = createObject("java", "java.io.File").init(arguments.filePath);
            var fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
            
            var extractedText = tika.parseToString(fileInputStream);
            fileInputStream.close();
            
            return extractedText;
        } catch (any e) {
            writeLog(file="tika_utility", text="Text extraction failed for #arguments.filePath#: #e.message#", type="error");
            return "";
        }
    }
    
    /**
     * Extract metadata - equivalent to JSoup's attribute extraction
     */
    public struct function extractMetadata(required string filePath) {
        try {
            var metadata = createObject("java", "org.apache.tika.metadata.Metadata");
            var parser = createObject("java", "org.apache.tika.parser.AutoDetectParser");
            var parseContext = createObject("java", "org.apache.tika.parser.ParseContext");
            var contentHandler = createObject("java", "org.apache.tika.sax.BodyContentHandler");
            
            var javaFile = createObject("java", "java.io.File").init(arguments.filePath);
            var fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
            
            parser.parse(fileInputStream, contentHandler, metadata, parseContext);
            fileInputStream.close();
            
            // Convert Java metadata to ColdFusion struct
            var result = {};
            var metadataNames = metadata.names();
            
            for (var i = 0; i < arrayLen(metadataNames); i++) {
                var name = metadataNames[i];
                var value = metadata.get(name);
                if (len(value)) {
                    result[name] = value;
                }
            }
            
            return result;
        } catch (any e) {
            writeLog(file="tika_utility", text="Metadata extraction failed for #arguments.filePath#: #e.message#", type="error");
            return {};
        }
    }
    
    /**
     * Extract with content type detection - equivalent to JSoup's document type detection
     */
    public struct function parseDocument(required string filePath) {
        try {
            var tika = createObject("java", "org.apache.tika.Tika");
            var javaFile = createObject("java", "java.io.File").init(arguments.filePath);
            var fileInputStream = createObject("java", "java.io.FileInputStream").init(javaFile);
            
            // Detect content type
            var contentType = tika.detect(javaFile);
            
            // Extract text
            var extractedText = tika.parseToString(fileInputStream);
            fileInputStream.close();
            
            // Get basic file info
            var fileInfo = getFileInfo(arguments.filePath);
            
            return {
                contentType: contentType,
                text: extractedText,
                textLength: len(extractedText),
                fileName: getFileFromPath(arguments.filePath),
                fileSize: fileInfo.size,
                lastModified: fileInfo.lastModified
            };
        } catch (any e) {
            writeLog(file="tika_utility", text="Document parsing failed for #arguments.filePath#: #e.message#", type="error");
            return {
                contentType: "unknown",
                text: "",
                textLength: 0,
                fileName: getFileFromPath(arguments.filePath),
                error: e.message
            };
        }
    }
    
    /**
     * Parse with language detection - advanced feature
     */
    public struct function parseWithLanguage(required string filePath) {
        try {
            var result = parseDocument(arguments.filePath);
            
            // Simple language detection based on common words
            var text = result.text;
            var language = detectLanguage(text);
            result.language = language;
            
            return result;
        } catch (any e) {
            writeLog(file="tika_utility", text="Language parsing failed for #arguments.filePath#: #e.message#", type="error");
            return {error: e.message};
        }
    }
    
    /**
     * Simple language detection helper
     */
    private string function detectLanguage(required string text) {
        var lowerText = lcase(arguments.text);
        
        // Simple keyword-based detection
        if (findNoCase("the", lowerText) > 0 && findNoCase("and", lowerText) > 0) {
            return "en";
        } else if (findNoCase("der", lowerText) > 0 && findNoCase("und", lowerText) > 0) {
            return "de";
        } else if (findNoCase("le", lowerText) > 0 && findNoCase("et", lowerText) > 0) {
            return "fr";
        } else if (findNoCase("el", lowerText) > 0 && findNoCase("y", lowerText) > 0) {
            return "es";
        }
        
        return "unknown";
    }
    
    /**
     * Batch processing - similar to JSoup batch operations
     */
    public array function processMultipleFiles(required array filePaths) {
        var results = [];
        
        for (var filePath in arguments.filePaths) {
            if (fileExists(filePath)) {
                var result = parseDocument(filePath);
                result.filePath = filePath;
                arrayAppend(results, result);
            } else {
                arrayAppend(results, {
                    filePath: filePath,
                    error: "File not found",
                    contentType: "unknown",
                    text: ""
                });
            }
        }
        
        return results;
    }
}
</cfscript>

<!--- Demo Usage Examples --->
<h1>Apache Tika Utility - JSoup-style Usage</h1>

<cfscript>
    // Initialize Tika utility (similar to JSoup initialization)
    tikaUtil = new tika_utility();
</cfscript>

<h2>Usage Examples:</h2>

<h3>1. Simple Text Extraction (like JSoup .text())</h3>
<cfif structKeyExists(url, "testFile") AND fileExists(url.testFile)>
    <cfscript>
        extractedText = tikaUtil.extractText(url.testFile);
    </cfscript>
    <cfoutput>
        <div style="background: ##f0f8ff; padding: 10px; border: 1px solid ##ccc; margin: 10px 0;">
            <strong>File:</strong> #url.testFile#<br>
            <strong>Extracted Text:</strong><br>
            <pre>#left(extractedText, 500)#...</pre>
        </div>
    </cfoutput>
</cfif>

<h3>2. Metadata Extraction (like JSoup attributes)</h3>
<cfif structKeyExists(url, "testFile") AND fileExists(url.testFile)>
    <cfscript>
        metadata = tikaUtil.extractMetadata(url.testFile);
    </cfscript>
    <cfoutput>
        <div style="background: ##f0fff0; padding: 10px; border: 1px solid ##ccc; margin: 10px 0;">
            <strong>Metadata for:</strong> #url.testFile#<br>
            <cfloop collection="#metadata#" item="key">
                <strong>#key#:</strong> #metadata[key]#<br>
            </cfloop>
        </div>
    </cfoutput>
</cfif>

<h3>3. Full Document Parsing (like JSoup document parsing)</h3>
<cfif structKeyExists(url, "testFile") AND fileExists(url.testFile)>
    <cfscript>
        document = tikaUtil.parseDocument(url.testFile);
    </cfscript>
    <cfoutput>
        <div style="background: ##fff8dc; padding: 10px; border: 1px solid ##ccc; margin: 10px 0;">
            <strong>Document Analysis:</strong><br>
            <strong>Content Type:</strong> #document.contentType#<br>
            <strong>File Size:</strong> #numberFormat(document.fileSize/1024, "999.9")# KB<br>
            <strong>Text Length:</strong> #document.textLength# characters<br>
            <strong>Last Modified:</strong> #dateFormat(document.lastModified, "yyyy-mm-dd")#<br>
        </div>
    </cfoutput>
</cfif>

<h3>Test with Sample Files:</h3>
<cfscript>
    // Find sample files in uploads directory
    uploadsDir = expandPath("./uploads");
    sampleFiles = [];
    
    if (directoryExists(uploadsDir)) {
        files = directoryList(uploadsDir, false, "path", "*.*");
        for (file in files) {
            arrayAppend(sampleFiles, file);
        }
    }
</cfscript>

<cfoutput>
    <cfif arrayLen(sampleFiles) > 0>
        <p><strong>Sample files found in uploads:</strong></p>
        <ul>
            <cfloop array="#sampleFiles#" index="file">
                <li>
                    <a href="?testFile=#urlEncodedFormat(file)#">#getFileFromPath(file)#</a>
                </li>
            </cfloop>
        </ul>
    <cfelse>
        <p>No files found in uploads directory. Upload a file first to test Tika parsing.</p>
    </cfif>
</cfoutput>

<h3>Code Examples (JSoup vs Tika):</h3>
<div style="background: #f5f5f5; padding: 15px; border-radius: 5px;">
    <strong>JSoup Usage Pattern:</strong>
    <pre>
jsoup = createObject("java", "org.jsoup.Jsoup");
doc = jsoup.connect("http://example.com").get();
title = doc.title();
text = doc.select("body").text();
    </pre>
    
    <strong>Tika Usage Pattern:</strong>
    <pre>
tikaUtil = new tika_utility();
document = tikaUtil.parseDocument("/path/to/file.pdf");
text = document.text;
contentType = document.contentType;
metadata = tikaUtil.extractMetadata("/path/to/file.pdf");
    </pre>
</div>

<p><a href="index.cfm">← Back to main page</a></p>
