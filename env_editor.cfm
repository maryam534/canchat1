<!---
  Minimal .env editor (admin-only if protected at web server level)
  Reads project-root .env, displays keys, and allows updates.
--->
<cfscript>
envPath = expandPath("/.env");
if (!fileExists(envPath)) {
    fileWrite(envPath, "# Generated .env\n");
}

// Load existing .env into struct
function readEnvFile(p) {
    var s = {};
    var txt = fileRead(p);
    var lines = listToArray(txt, chr(10));
    for (var raw in lines) {
        var line = trim(raw);
        if (!len(line) || left(line,1) == "#") continue;
        var eq = find("=", line);
        if (eq gt 1) {
            var k = trim(left(line, eq-1));
            var v = trim(mid(line, eq+1, len(line)-eq));
            v = rereplace(v, '^"|"$', "", "all");
            s[k] = v;
        }
    }
    return s;
}

function writeEnvFile(p, data) {
    var out = "";
    for (var k in data) {
        var v = data[k];
        if (refind('[\r\n\"]', v)) {
            v = '"' & replace(v, '"', '""', 'all') & '"';
        }
        out &= k & "=" & v & chr(10);
    }
    fileWrite(p, out);
}

env = readEnvFile(envPath);

// Defaults for display
defaults = {
    OPENAI_API_KEY: env.OPENAI_API_KEY ?: "",
    EMBED_MODEL: env.EMBED_MODEL ?: "text-embedding-3-small",
    EMBED_DIM: env.EMBED_DIM ?: "1536",
    DATABASE_URL: env.DATABASE_URL ?: "",
    BASE_URL: env.BASE_URL ?: "http://localhost",
    PROCESS_URL: env.PROCESS_URL ?: "http://localhost/canchat1",
    NODE_BINARY: env.NODE_BINARY ?: "C:\\Program Files\\nodejs\\node.exe",
    CMD_EXE: env.CMD_EXE ?: "C:\\Windows\\System32\\cmd.exe",
    SCRAPER_PATH: env.SCRAPER_PATH ?: expandPath("/scrap_all_auctions_lots_data.js"),
    INSERTER_PATH: env.INSERTER_PATH ?: expandPath("/insert_lots_into_db.js"),
    UPLOADS_DIR: env.UPLOADS_DIR ?: expandPath("/uploads"),
    INPROGRESS_DIR: env.INPROGRESS_DIR ?: expandPath("/allAuctionLotsData_inprogress"),
    FINAL_DIR: env.FINAL_DIR ?: expandPath("/allAuctionLotsData_final"),
    TIKA_PATH: env.TIKA_PATH ?: "C:/ColdFusion2023/cfusion/lib/tika-app-3.2.3.jar",
    JSOUP_CLASS: env.JSOUP_CLASS ?: "org.jsoup.Jsoup",
    CHAT_VERSION: env.CHAT_VERSION ?: "11"
};

message = "";
if (structKeyExists(form, "save")) {
    // Build updated map from form
    updated = {};
    for (var k in defaults) {
        updated[k] = trim(form[k] ?: defaults[k]);
    }
    writeEnvFile(envPath, updated);
    message = "Saved .env successfully.";
    // Update server env for current runtime
    if (!structKeyExists(server, "system")) server.system = {};
    if (!structKeyExists(server.system, "environment")) server.system.environment = {};
    for (var k in updated) server.system.environment[k] = updated[k];
}
</cfscript>

<!DOCTYPE html>
<html>
<head>
    <title>.env Editor</title>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
</head>
<body class="bg-gray-100 p-6">
    <div class="max-w-3xl mx-auto bg-white p-6 rounded shadow">
        <h1 class="text-2xl font-bold mb-4">Environment Editor</h1>
        <cfif len(message)>
            <div class="mb-4 p-3 rounded" style="background: ##e8f5e8; border:1px solid ##4CAF50;">#encodeForHtml(message)#</div>
        </cfif>
        <form method="post">
            <div class="grid grid-cols-1 gap-4">
                <cfoutput>
                <cfloop collection="#defaults#" item="k">
                    <div>
                        <label class="block text-sm font-medium text-gray-700">#k#</label>
                        <input type="text" name="#k#" value="#encodeForHtml(defaults[k])#" class="mt-1 block w-full border rounded p-2" />
                    </div>
                </cfloop>
                </cfoutput>
            </div>
            <div class="mt-6 flex items-center gap-4">
                <button type="submit" name="save" value="1" class="px-4 py-2 rounded text-white" style="background: ##3b82f6;">Save</button>
                <a href="config_test.cfm" class="text-blue-600 underline">View Config</a>
            </div>
        </form>
    </div>
</body>
</html>
