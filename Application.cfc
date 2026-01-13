/**
 * Application.cfc - Main application configuration for NumisBids Stamp ChatBot
 * Handles application initialization, configuration management, and environment setup
 */
component {

    // Application settings
    this.name = "numisbids_app";
    this.sessionManagement = true;
    this.charset = "utf-8";

    // File upload settings
    this.enableFileUpload = true;
    this.maxFileSize = 50 * 1024 * 1024; // 50MB max file size
    this.uploadTimeout = 300; // 5 minutes timeout
    
    // Java library configuration
    this.javaSettings = {
        loadPaths: ["./libs"],
        loadColdFusionClassPath: true,
        reloadOnChange: true,
        ignoreBundles: false
    };

    /**
     * System configuration reader
     * Reads configuration from Java system properties, environment variables, or defaults
     * @param name The configuration key to read
     * @param defVal Default value if not found
     * @return The configuration value
     */
    private string function sys(required string name, string defVal = "") {
        var JSys = createObject("java", "java.lang.System");

        // 1) Check Java system property first
        var propVal = JSys.getProperty(arguments.name);
        if (!isNull(propVal) && isSimpleValue(propVal) && len(propVal)) {
            return propVal;
        }

        // 2) Check OS environment variable
        var envMap = JSys.getenv();
        if (!isNull(envMap) && envMap.containsKey(arguments.name)) {
            var envVal = envMap.get(arguments.name);
            if (!isNull(envVal) && isSimpleValue(envVal) && len(envVal)) {
                return envVal;
            }
        }

        // 3) Check ColdFusion server environment (optional fallback)
        if (structKeyExists(server, "system") 
            && structKeyExists(server.system, "environment")
            && structKeyExists(server.system.environment, arguments.name)
            && len(server.system.environment[arguments.name])) {
            return server.system.environment[arguments.name];
        }

        return arguments.defVal;
    }

    /**
     * Application startup initialization
     * Sets up configuration, paths, and application-scoped variables
     * @return boolean indicating successful initialization
     */
    public boolean function onApplicationStart() {
        // Load .env into server.system.environment for CF access
        try {
            var envFilePath = expandPath("/.env");
            if (fileExists(envFilePath)) {
                if (!structKeyExists(server, "system")) server.system = {};
                if (!structKeyExists(server.system, "environment")) server.system.environment = {};

                var envText = fileRead(envFilePath);
                var envLines = listToArray(envText, chr(10));
                for (var rawLine in envLines) {
                    var line = trim(rawLine);
                    if (not len(line) or left(line, 1) == "##") continue;
                    var eqPos = find("=", line);
                    if (eqPos gt 1) {
                        var key = trim(left(line, eqPos - 1));
                        var val = trim(mid(line, eqPos + 1, len(line) - eqPos));
                        // Strip optional surrounding quotes
                        val = reReplace(val, '^"|"$', "", "all");
                        if (len(key)) server.system.environment[key] = val;
                    }
                }
            }
        } catch (any e) {
            // Ignore .env loading errors; fall back to defaults and OS env
        }
        // Define default configuration
        var defaults = {
            envName: "dev", // Environment: dev|staging|prod
            
            // File paths configuration
            paths: {
                nodeBinary: sys("NODE_BINARY", "C:\\Program Files\\nodejs\\node.exe"),
                cmdExe: sys("CMD_EXE", "C:\\Windows\\System32\\cmd.exe"),
                chromePath: sys("CHROME_PATH", "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"),
                scraper: sys("SCRAPER_PATH", expandPath("./scrap_all_auctions_lots_data.js")),
                inserter: sys("INSERTER_PATH", expandPath("./insert_lots_into_db.js")),
                uploadsDir: sys("UPLOADS_DIR", expandPath("./uploads/")),
                inProgressDir: sys("INPROGRESS_DIR", expandPath("./allAuctionLotsData_inprogress")),
                finalDir: sys("FINAL_DIR", expandPath("./allAuctionLotsData_final")),
                libsDir: sys("LIBS_DIR", expandPath("./libs")),
                cfmlDir: "./",
                debugDir: sys("DEBUG_DIR", expandPath("./debug"))
            },
            
            // AI/OpenAI configuration
            ai: {
                // OpenAI API key - loaded from environment or system properties
                // IMPORTANT: Set OPENAI_API_KEY in your .env file or environment variables
                openaiKey: sys("OPENAI_API_KEY", ""),
                embedModel: "text-embedding-3-small",
                embedDim: 1536,
                chatModel: "gpt-4o-mini",
                apiBaseUrl: "https://api.openai.com/v1",
                timeout: 90,
                maxChars: 12000,
                maxItems: 30
            },
            
            // Database configuration
            db: {
                dsn: "ragdb",
                vectorLimit: 10,
                chunkLimit: 5
            },
            
            // Processing configuration
            processing: {
                chunkSize: 500,
                tikaPath: sys("TIKA_PATH", expandPath("./libs/tika-app-3.2.3.jar")),
                tikaClass: sys("TIKA_CLASS", "org.apache.tika.Tika"),
                jsoupClass: sys("JSOUP_CLASS", "org.jsoup.Jsoup"),
                defaultTimeout: 10,
                maxRetries: 3
            },
            
            // Web server configuration  
            web: {
                baseUrl: sys("BASE_URL", "http://localhost/canchat1"),
                processUrl: sys("PROCESS_URL", "http://localhost/canchat1"),
                chatVersion: sys("CHAT_VERSION", "11")
            },
            
            // UI configuration
            ui: {
                maxSimilarityResults: 3,
                showDebugLogs: true,
                defaultPlaceholder: "Ask about stamp auctions, lot numbers, prices..."
            }
        };

        // Create working configuration copy
        var cfg = duplicate(defaults);
        
        // Apply environment-specific overrides
        switch (lcase(cfg.envName)) {
            case "staging":
                // cfg.db.dsn = "numis_stg";
                break;
                
            case "prod":
                // cfg.db.dsn = "numis_prod";
                // cfg.paths.nodeBinary = "C:\Program Files\nodejs\node.exe";
                break;
        }

        // Initialize JavaLoader for dynamic JAR loading
        try {
            var javaLoaderPaths = [
                expandPath("./libs/tika-app-3.2.3.jar"),
                expandPath("./libs/jsoup-1.20.1.jar")
            ];
            
            // Create JavaLoader instance
            application.javaLoader = createObject("component", "javaloader.JavaLoader").init(javaLoaderPaths);
            
            // Capture the underlying URLClassLoader for context-classloader dependent libs
            try {
                if (structKeyExists(application.javaLoader, "getURLClassLoader")) {
                    application.tikaClassLoader = application.javaLoader.getURLClassLoader();
                } else if (structKeyExists(application.javaLoader, "getClassLoader")) {
                    application.tikaClassLoader = application.javaLoader.getClassLoader();
                }
            } catch (any ignoreCL) {
                application.tikaClassLoader = "";
            }
            
            writeLog(file="application_startup", text="JavaLoader initialized successfully with JAR paths", type="information");
            
        } catch (any jlError) {
            writeLog(file="application_startup", text="JavaLoader initialization failed: " & jlError.message, type="error");
            // Continue without JavaLoader - fallback to other methods
            application.javaLoader = "";
        }

        // Expose configuration to application scope
        application.config = cfg;
        application.paths = cfg.paths;
        application.ai = cfg.ai;
        application.db = cfg.db;
        application.processing = cfg.processing;
        application.web = cfg.web;
        application.ui = cfg.ui;

        return true;
    }

    /**
     * Optional: Allow runtime re-init via URL param appreset=1
     */
    public boolean function onRequestStart(required string targetPage) {
      
        if (structKeyExists(url, "appreset") && toString(url.appreset) == "1") {
            try {
                onApplicationStart();
            } catch (any e) {
                // swallow errors; normal request continues
            }
        }
        return true;
    }
}
