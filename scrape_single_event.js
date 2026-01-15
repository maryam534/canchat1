// IMMEDIATE LOGGING - FIRST THING IN SCRIPT
// Write to both stdout and stderr so ColdFusion can capture it
process.stdout.write(`[IMMEDIATE] scrape_single_event.js starting...\n`);
process.stderr.write(`[STDERR] [IMMEDIATE] scrape_single_event.js starting...\n`);

// Write to log file immediately (before requiring any modules)
try {
  const fs = require('fs');
  const path = require('path');
  // Get script directory from __filename or use cwd
  const scriptDir = typeof __dirname !== 'undefined' ? __dirname : path.dirname(process.argv[1] || __filename || '.');
  const debugLogFile = path.join(scriptDir, 'scrape_debug.log');
  const immediateLog = `[${new Date().toISOString()}] [IMMEDIATE] Script file loaded, argv=${JSON.stringify(process.argv)}, pid=${process.pid}, cwd=${process.cwd()}\n`;
  fs.appendFileSync(debugLogFile, immediateLog);
  process.stderr.write(`[STDERR] [IMMEDIATE] Wrote to log file: ${debugLogFile}\n`);
} catch (e) {
  process.stderr.write(`[STDERR] [IMMEDIATE] Failed to write initial log: ${e.message}\n`);
}

// #region agent log
try {
  fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:5',message:'Script execution started',data:{argv:process.argv,pid:process.pid,cwd:process.cwd(),__dirname:__dirname},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'A'})}).catch(()=>{});
} catch (e) {}
// #endregion

const path = require('path')
const fs = require('fs')

// Log immediately that we're starting
console.log(`[MODULE LOAD] scrape_single_event.js module loading...`);
console.log(`[MODULE LOAD] __dirname=${__dirname}`);
console.error(`[STDERR] [MODULE LOAD] scrape_single_event.js module loading...`);
console.error(`[STDERR] [MODULE LOAD] __dirname=${__dirname}`);

// Try to load database config with error handling
let pool;
let insertLotFunctions;
try {
    console.log(`[MODULE LOAD] Loading dbConfig...`);
    pool = require('./dbConfig');
    console.log(`[MODULE LOAD] dbConfig loaded successfully`);
} catch (dbConfigErr) {
    console.error(`[MODULE LOAD ERROR] Failed to load dbConfig: ${dbConfigErr.message}`);
    console.error(`[MODULE LOAD ERROR] Stack: ${dbConfigErr.stack}`);
    // Write to file immediately
    try {
        const debugLogFile = path.join(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] MODULE LOAD ERROR (dbConfig): ${dbConfigErr.message}\n${dbConfigErr.stack}\n`);
    } catch (e) {}
    // Don't exit here - let the script continue and fail gracefully later
}

try {
    console.log(`[MODULE LOAD] Loading insert_lots_into_db from ${__dirname}...`);
    insertLotFunctions = require('./insert_lots_into_db');
    console.log(`[MODULE LOAD] insert_lots_into_db loaded successfully`);
    // Log to debug file
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] insert_lots_into_db module loaded successfully\n`);
        // Force immediate flush
        process.stderr.write(`[STDERR] insert_lots_into_db module loaded - continuing...\n`);
        
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:40',message:'Module loaded successfully',data:{debugLogFile:debugLogFile,canWrite:true},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'C'})}).catch(()=>{});
        // #endregion
    } catch (e) {}
} catch (insertErr) {
    console.error(`[MODULE LOAD ERROR] Failed to load insert_lots_into_db: ${insertErr.message}`);
    console.error(`[MODULE LOAD ERROR] Stack: ${insertErr.stack}`);
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] MODULE LOAD ERROR (insert_lots): ${insertErr.message}\n${insertErr.stack}\n__dirname=${__dirname}\n`);
    } catch (e) {
        console.error(`[ERROR] Could not write module load error to debug log: ${e.message}`);
    }
}

// Log before requiring puppeteer (it might take time or fail)
try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] About to require puppeteer...\n`);
    console.error(`[STDERR] About to require puppeteer...`);
} catch (e) {}

// Wrap puppeteer require in try-catch to catch any errors
let puppeteer;
try {
    puppeteer = require('puppeteer');
    // Log after puppeteer loaded
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Puppeteer loaded successfully\n`);
        console.error(`[STDERR] Puppeteer loaded successfully`);
        process.stderr.write(`[STDERR] Puppeteer require complete\n`);
    } catch (e) {
        console.error(`[STDERR] Failed to log puppeteer success: ${e.message}`);
    }
} catch (puppeteerErr) {
    // Log puppeteer load error
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] PUPPETEER LOAD ERROR: ${puppeteerErr.message}\n${puppeteerErr.stack}\n`);
        console.error(`[STDERR] PUPPETEER LOAD ERROR: ${puppeteerErr.message}`);
        process.stderr.write(`[STDERR] PUPPETEER LOAD ERROR: ${puppeteerErr.message}\n`);
    } catch (e) {
        console.error(`[STDERR] Failed to log puppeteer error: ${e.message}`);
    }
    // Don't exit - let the script continue to see if it can work without puppeteer
    // (though it probably can't, but at least we'll see more errors)
}

const profileDir = path.join(__dirname, 'pp-profile')
fs.mkdirSync(profileDir, { recursive: true })

function log(msg) { console.log(`[${new Date().toISOString()}] ${msg}`) }

// Database functions for job tracking
async function logToDatabase(jobId, level, message, source = 'scraper', metadata = {}) {
    if (!jobId) return;
    try {
        // Check if job exists first (for manual testing with fake job IDs)
        const jobCheck = await pool.query('SELECT id FROM scraper_jobs WHERE id = $1', [jobId]);
        if (jobCheck.rows.length === 0) {
            console.log(`[DB Log] Skipping log - jobId ${jobId} does not exist in scraper_jobs table`);
            return;
        }
        
        await pool.query(
            `INSERT INTO scrape_logs (job_id, log_level, message, source, metadata)
             VALUES ($1, $2, $3, $4, $5::jsonb)`,
            [jobId, level, message, source, JSON.stringify(metadata)]
        );
    } catch (err) {
        console.error(`[DB Log Error] ${err.message}`);
        // Don't throw - logging errors shouldn't stop the script
    }
}

async function updateJobStatistics(jobId, stats) {
    if (!jobId) return;
    try {
        // Check if job exists first
        const jobCheck = await pool.query('SELECT id FROM scraper_jobs WHERE id = $1', [jobId]);
        if (jobCheck.rows.length === 0) {
            console.log(`[DB Stats] Skipping stats update - jobId ${jobId} does not exist`);
            return;
        }
        
        const checkResult = await pool.query(
            `SELECT id FROM job_statistics WHERE job_id = $1 ORDER BY id DESC LIMIT 1`,
            [jobId]
        );
        
        const statsData = {
            total_events: stats.totalEvents || 1, // Single event = 1
            processed_events: stats.processedEvents || 0,
            total_lots: stats.totalLots || 0,
            processed_lots: stats.processedLots || 0,
            files_created: stats.filesCreated || 0,
            files_completed: stats.filesCompleted || 0
        };
        
        if (checkResult.rows.length > 0) {
            await pool.query(
                `UPDATE job_statistics SET 
                    total_events = $1, processed_events = $2, total_lots = $3, 
                    processed_lots = $4, files_created = $5, files_completed = $6, 
                    last_update = CURRENT_TIMESTAMP
                 WHERE job_id = $7`,
                [statsData.total_events, statsData.processed_events, statsData.total_lots, 
                 statsData.processed_lots, statsData.files_created, statsData.files_completed, jobId]
            );
        } else {
            await pool.query(
                `INSERT INTO job_statistics (job_id, total_events, processed_events, total_lots, processed_lots, files_created, files_completed, start_time, last_update)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
                [jobId, statsData.total_events, statsData.processed_events, statsData.total_lots, 
                 statsData.processed_lots, statsData.files_created, statsData.files_completed]
            );
        }
    } catch (err) {
        console.error(`[DB Stats Error] ${err.message}`);
    }
}

async function updateCurrentLot(jobId, eventId, lotNumber) {
    if (!jobId) return;
    try {
        // Check if job exists first
        const jobCheck = await pool.query('SELECT id FROM scraper_jobs WHERE id = $1', [jobId]);
        if (jobCheck.rows.length === 0) {
            return; // Silently skip if job doesn't exist
        }
        
        await pool.query(
            `UPDATE scraper_jobs 
             SET current_lot_number = $1, current_event_id = $2
             WHERE id = $3`,
            [lotNumber, eventId, jobId]
        );
    } catch (err) {
        console.error(`[Update Current Lot Error] ${err.message}`);
    }
}

/**
 * Check if job is paused or stopped
 * @param {number} jobId - Job ID
 * @returns {Promise<{isPaused: boolean, isStopped: boolean, status: string}>} - Status object
 */
async function checkJobStatus(jobId) {
    if (!jobId) return {isPaused: false, isStopped: false, status: ''};
    try {
        const result = await pool.query(
            `SELECT status FROM scraper_jobs WHERE id = $1`,
            [jobId]
        );
        if (result.rows.length === 0) {
            return {isPaused: false, isStopped: false, status: ''};
        }
        const status = result.rows[0].status || '';
        return {
            isPaused: status === 'paused',
            isStopped: status === 'stopped',
            status: status
        };
    } catch (err) {
        console.error(`[Job Status Check Error] ${err.message}`);
        return {isPaused: false, isStopped: false, status: ''};
    }
}

/**
 * Check if job is paused (backward compatibility)
 * @param {number} jobId - Job ID
 * @returns {Promise<boolean>} - True if job is paused
 */
async function checkPauseStatus(jobId) {
    const status = await checkJobStatus(jobId);
    return status.isPaused;
}

/**
 * Get resume state from database
 * @param {number} jobId - Job ID
 * @returns {Promise<Object|null>} - Resume state object or null
 */
async function getResumeState(jobId) {
    if (!jobId) return null;
    try {
        const result = await pool.query(
            `SELECT resume_state, current_event_id, current_lot_number, current_event_index 
             FROM scraper_jobs WHERE id = $1`,
            [jobId]
        );
        
        if (result.rows.length > 0) {
            const row = result.rows[0];
            let resumeState = null;
            if (row.resume_state) {
                try {
                    resumeState = typeof row.resume_state === 'string' 
                        ? JSON.parse(row.resume_state) 
                        : row.resume_state;
                } catch (e) {
                    console.error(`[Get Resume State] Failed to parse resume_state: ${e.message}`);
                }
            }
            return {
                resumeState: resumeState,
                currentEventId: row.current_event_id,
                currentLotNumber: row.current_lot_number,
                currentEventIndex: row.current_event_index || 0
            };
        }
        return null;
    } catch (err) {
        console.error(`[Get Resume State Error] ${err.message}`);
        return null;
    }
}

/**
 * Save resume state to database
 * @param {number} jobId - Job ID
 * @param {string} eventId - Current event ID
 * @param {string} lotNumber - Last processed lot number
 * @param {number} currentPage - Current page number
 * @param {number} lotsScraped - Number of lots scraped so far
 */
async function saveResumeState(jobId, eventId, lotNumber, currentPage, lotsScraped) {
    if (!jobId) return;
    try {
        const resumeState = {
            eventId,
            lotNumber,
            currentPage,
            lotsScraped,
            timestamp: new Date().toISOString()
        };
        await pool.query(
            `UPDATE scraper_jobs 
             SET resume_state = $1, current_event_id = $2, current_lot_number = $3 
             WHERE id = $4`,
            [JSON.stringify(resumeState), eventId, lotNumber, jobId]
        );
        console.log(`[PAUSE] Resume state saved: eventId=${eventId}, lotNumber=${lotNumber}, page=${currentPage}, lotsScraped=${lotsScraped}`);
    } catch (err) {
        console.error(`[Save Resume State Error] ${err.message}`);
    }
}

// Log that we're about to parse arguments
try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] About to parse arguments, process.argv.length=${process.argv.length}\n`);
    console.error(`[STDERR] About to parse arguments, process.argv.length=${process.argv.length}`);
    process.stderr.write(`[STDERR] process.argv=${JSON.stringify(process.argv)}\n`);
} catch (e) {
    console.error(`[STDERR] Failed to log before argument parsing: ${e.message}`);
}

// args: --event-id <id> --output-file <name> --job-id <id>
const args = process.argv.slice(2)
let eventId = null
let outputFile = null
let jobId = null
for (let i = 0; i < args.length; i++) {
  const a = args[i]
  if (a === '--event-id' && i + 1 < args.length) eventId = args[++i]
  else if (a.startsWith('--event-id=')) eventId = a.split('=')[1]
  else if (a === '--output-file' && i + 1 < args.length) outputFile = args[++i]
  else if (a.startsWith('--output-file=')) outputFile = a.split('=')[1]
  else if (a === '--job-id' && i + 1 < args.length) jobId = parseInt(args[++i])
  else if (a.startsWith('--job-id=')) jobId = parseInt(a.split('=')[1])
}

// Log arguments immediately (BEFORE any validation that might exit)
// This is critical - if this fails, we won't know what happened
try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    const argMsg = `[${new Date().toISOString()}] Arguments parsed: eventId=${eventId}, outputFile=${outputFile}, jobId=${jobId}, process.argv=${JSON.stringify(process.argv)}\n`;
    fs.appendFileSync(debugLogFile, argMsg);
    console.error(`[STDERR] Arguments parsed: eventId=${eventId}, outputFile=${outputFile}, jobId=${jobId}`);
    // Force flush
    process.stderr.write(`[STDERR] Arguments logged to debug file\n`);
    
    // #region agent log
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:182',message:'Arguments parsed and logged',data:{eventId:eventId,jobId:jobId,outputFile:outputFile,debugLogFile:debugLogFile},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'B'})}).catch(()=>{});
    // #endregion
} catch (e) {
    // #region agent log
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:187',message:'Failed to log arguments',data:{error:e.message,stack:e.stack},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'C'})}).catch(()=>{});
    // #endregion
    console.error(`[STDERR] Failed to log arguments: ${e.message}`);
    console.error(`[STDERR] Error stack: ${e.stack}`);
    // Try fallback
    try {
        const fallbackLog = path.join(process.cwd(), 'scrape_debug_fallback.log');
        fs.appendFileSync(fallbackLog, `[${new Date().toISOString()}] Arguments parse error: ${e.message}\n`);
    } catch (fallbackErr) {
        console.error(`[STDERR] Fallback log also failed: ${fallbackErr.message}`);
    }
}

if (!eventId) { 
    console.error('[ERROR] Missing --event-id'); 
    console.error(`[STDERR] ERROR: Missing --event-id. Arguments: ${process.argv.join(' ')}`);
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] ERROR: Missing --event-id\n`);
    } catch (e) {}
    process.exit(1); 
}

if (!outputFile) outputFile = `auction_${eventId}_lots.jsonl`

// Immediate log to verify script is running (BEFORE any async operations)
// These go to stdout/stderr which ColdFusion can capture
console.log(`[STARTUP] scrape_single_event.js starting...`);
console.log(`[STARTUP] eventId=${eventId}, outputFile=${outputFile}, jobId=${jobId}`);
console.log(`[STARTUP] __dirname=${__dirname}`);
console.log(`[STARTUP] process.cwd()=${process.cwd()}`);
console.error(`[STDERR] ==========================================`);
console.error(`[STDERR] Script starting - jobId=${jobId}, eventId=${eventId}`);
console.error(`[STDERR] __dirname=${__dirname}`);
console.error(`[STDERR] process.cwd()=${process.cwd()}`);
console.error(`[STDERR] ==========================================`);

// #region agent log - Hypothesis D: Script startup
try {
  fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:258',message:'Script startup - before async',data:{jobId:jobId,eventId:eventId,outputFile:outputFile,pid:process.pid,cwd:process.cwd(),__dirname:__dirname},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
} catch (e) {}
// #endregion

// Log to file for debugging (synchronous, immediate)
// Use absolute path to ensure we write to the correct location
const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
try {
    const startupMsg = `[${new Date().toISOString()}] Script started: eventId=${eventId}, jobId=${jobId}, outputFile=${outputFile}, __dirname=${__dirname}, cwd=${process.cwd()}\n`;
    fs.appendFileSync(debugLogFile, startupMsg);
    console.log(`[DEBUG] Logged to ${debugLogFile}`);
    console.error(`[STDERR] Debug log written to: ${debugLogFile}`);
    console.error(`[STDERR] [${new Date().toISOString()}] Script started: eventId=${eventId}, jobId=${jobId}`);
    // Force flush to ensure it's written
    process.stdout.write(`[STARTUP COMPLETE] Script initialization done\n`);
    process.stderr.write(`[STDERR] [STARTUP COMPLETE] Script initialization done - jobId=${jobId}\n`);
} catch (e) {
    console.error(`[ERROR] Failed to write debug log: ${e.message}`);
    console.error(`[ERROR] Error stack: ${e.stack}`);
    console.error(`[ERROR] Attempted path: ${debugLogFile}`);
    // Try to write to a fallback location
    try {
        const fallbackLog = path.join(process.cwd(), 'scrape_debug_fallback.log');
        fs.appendFileSync(fallbackLog, `[${new Date().toISOString()}] Script started (fallback log): eventId=${eventId}, jobId=${jobId}\n`);
        console.error(`[FALLBACK] Wrote to fallback log: ${fallbackLog}`);
    } catch (fallbackErr) {
        console.error(`[FALLBACK ERROR] Could not write fallback log: ${fallbackErr.message}`);
    }
}

// Catch unhandled errors immediately
process.on('uncaughtException', (err) => {
    console.error(`[FATAL] Uncaught Exception: ${err.message}`);
    console.error(`[FATAL] Stack: ${err.stack}`);
    process.stderr.write(`[STDERR] [FATAL] Uncaught Exception: ${err.message}\n`);
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] FATAL: ${err.message}\n${err.stack}\n`);
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:295',message:'Uncaught exception',data:{error:err.message,stack:err.stack,jobId:jobId},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
        // #endregion
    } catch (e) {}
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error(`[FATAL] Unhandled Rejection: ${reason}`);
    console.error(`[FATAL] Promise: ${promise}`);
    process.stderr.write(`[STDERR] [FATAL] Unhandled Rejection: ${reason}\n`);
    if (reason && reason.stack) {
        console.error(`[FATAL] Stack: ${reason.stack}`);
    }
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] FATAL REJECTION: ${reason}\n${reason.stack || ''}\n`);
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:304',message:'Unhandled rejection',data:{reason:String(reason),jobId:jobId},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
        // #endregion
    } catch (e) {
        console.error(`[FATAL] Could not write to debug log: ${e.message}`);
    }
    // Don't exit immediately - let the error be logged first
    setTimeout(() => process.exit(1), 1000);
});

// Log process exit
process.on('exit', (code) => {
    try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [PROCESS] Process exiting with code ${code}\n`);
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:317',message:'Process exit',data:{code:code,jobId:jobId},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
        // #endregion
    } catch (e) {}
});

log(`Starting scrape_single_event.js with eventId=${eventId}, outputFile=${outputFile}, jobId=${jobId}`)
console.error(`[STDERR] Starting scrape_single_event.js with eventId=${eventId}, outputFile=${outputFile}, jobId=${jobId}`);

// Log to debug file before creating directories
try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Creating directories...\n`);
} catch (e) {}

const inProgressDir = path.join(__dirname, 'allAuctionLotsData_inprogress')
const finalDir = path.join(__dirname, 'allAuctionLotsData_final')
fs.mkdirSync(inProgressDir, { recursive: true })
fs.mkdirSync(finalDir, { recursive: true })
log(`Directories ready: inProgress=${inProgressDir}, final=${finalDir}`)
console.error(`[STDERR] Directories ready: inProgress=${inProgressDir}, final=${finalDir}`);

// Log to debug file
try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Directories created: inProgress=${inProgressDir}, final=${finalDir}\n`);
    console.error(`[STDERR] Logged directories to debug file`);
} catch (e) {
    console.error(`[STDERR] Failed to log directories: ${e.message}`);
}

const resolvedOutput = path.isAbsolute(outputFile)
  ? outputFile
  : path.resolve(__dirname, outputFile)

// Avoid double-prefixing if caller already points inside inProgressDir
const inProgressFile = resolvedOutput.startsWith(inProgressDir + path.sep)
  ? resolvedOutput
  : path.join(inProgressDir, path.basename(resolvedOutput))
fs.mkdirSync(path.dirname(inProgressFile), { recursive: true })
const finalFile = path.join(finalDir, `auction_${eventId}_lots.json`)

// Log immediately before async function - this is the last synchronous code
try {
  const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
  fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [BEFORE ASYNC] About to start async IIFE, jobId=${jobId}, eventId=${eventId}\n`);
  process.stderr.write(`[STDERR] [BEFORE ASYNC] About to start async IIFE, jobId=${jobId}\n`);
} catch (e) {
  process.stderr.write(`[STDERR] Failed to log before async: ${e.message}\n`);
}

;(async () => {
  // #region agent log - Hypothesis D: Async function entry
  try {
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:376',message:'Async IIFE starting',data:{jobId:jobId,eventId:eventId,outputFile:outputFile,pid:process.pid},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
  } catch (e) {}
  // #endregion
  
  // Keep process alive - prevent premature exit
  const keepAlive = setInterval(() => {
    // Just keep the process running
  }, 10000);
  
  console.log(`[ASYNC START] Entering async function...`);
  console.error(`[STDERR] [ASYNC START] Entering async function - jobId=${jobId}`);
  process.stdout.write(`[STDOUT] [ASYNC START] Entering async function - jobId=${jobId}\n`);
  
  // Log to debug file immediately - use separate try blocks to ensure each write happens
  try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [ASYNC START] Entering async function, jobId=${jobId}\n`);
  } catch (e) {
    console.error(`[STDERR] Failed to log async start: ${e.message}`);
    process.stderr.write(`[STDERR] Failed to log async start: ${e.message}\n`);
  }
  
  // Write second log immediately - don't wait for HTTP
  try {
    const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [ASYNC START] About to check jobId, jobId=${jobId}, type=${typeof jobId}, truthy=${!!jobId}\n`);
    process.stderr.write(`[STDERR] [ASYNC START] About to check jobId=${jobId}\n`);
    process.stdout.write(`[STDOUT] [ASYNC START] About to check jobId=${jobId}\n`);
  } catch (e) {
    console.error(`[STDERR] Failed to log jobId check: ${e.message}`);
    process.stderr.write(`[STDERR] Failed to log jobId check: ${e.message}\n`);
  }
  
  // Try HTTP logging (non-blocking, don't wait for it)
  try {
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:390',message:'Async function entered and logs written',data:{jobId:jobId,truthy:!!jobId},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
  } catch (e) {
    // Ignore HTTP logging errors
  }
  
  // Ensure process doesn't exit prematurely
  process.on('beforeExit', (code) => {
    try {
      const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [PROCESS] beforeExit event, code=${code}\n`);
    } catch (e) {}
  });
  
  // Test database connection first
  if (jobId) {
    // Log that we're entering the if block
    try {
      const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [ASYNC START] jobId is truthy, entering database test block\n`);
      process.stderr.write(`[STDERR] [ASYNC START] jobId is truthy, entering database test\n`);
    } catch (e) {}
    try {
      // Log immediately to file before any async operations
      try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DB TEST] Starting database connection test, jobId=${jobId}\n`);
      } catch (e) {}
      
      console.log(`[DB TEST] Testing database connection...`);
      log(`Testing database connection...`);
      
      // #region agent log - Hypothesis D: Database connection
      fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:368',message:'About to test database connection',data:{jobId:jobId,poolExists:!!pool},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
      // #endregion
      
      // Log pool check to file
      try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DB TEST] Checking pool, pool exists: ${!!pool}\n`);
      } catch (e) {}
      
      // Check if pool is available
      if (!pool) {
        const errorMsg = 'Database pool is not initialized - dbConfig.js failed to load';
        console.error(`[DB TEST ERROR] ${errorMsg}`);
        try {
          const debugLogFile = path.join(__dirname, 'scrape_debug.log');
          fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] ${errorMsg}\n`);
        } catch (e) {}
        
        // #region agent log
        fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:375',message:'Pool not initialized error',data:{error:errorMsg},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
        // #endregion
        
        throw new Error(errorMsg);
      }
      
      // #region agent log - Before query
      fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:384',message:'About to execute database query',data:{jobId:jobId},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
      // #endregion
      
      // Log before query to file
      try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DB TEST] About to execute pool.query, jobId=${jobId}\n`);
        process.stderr.write(`[STDERR] [DB TEST] About to execute pool.query\n`);
      } catch (e) {}
      
      // Add timeout to database query to prevent hanging
      const queryPromise = pool.query('SELECT NOW() as current_time');
      const timeoutPromise = new Promise((_, reject) => 
        setTimeout(() => reject(new Error('Database query timeout after 5 seconds')), 5000)
      );
      
      const testQuery = await Promise.race([queryPromise, timeoutPromise]);
      
      // Log after query to file immediately
      try {
        const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DB TEST] Query completed, current_time=${testQuery.rows[0].current_time}\n`);
        process.stderr.write(`[STDERR] [DB TEST] Query completed successfully\n`);
      } catch (e) {}
      
      // #region agent log - After query
      fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:387',message:'Database query completed',data:{jobId:jobId,currentTime:testQuery.rows[0].current_time},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
      // #endregion
      
      log(`Database connection OK: ${testQuery.rows[0].current_time}`);
      console.log(`[DB TEST] Connection successful: ${testQuery.rows[0].current_time}`);
      
      // Log to debug file
      try {
        const debugLogFile = path.join(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Database connection successful\n`);
      } catch (e) {
        console.error(`[DEBUG LOG ERROR] ${e.message}`);
      }
      
      // Try to log to database, but don't let it stop the script if it fails
      try {
        await logToDatabase(jobId, 'info', 'Script execution started, testing database connection', 'scraper');
        console.log(`[DB TEST] Logged to database successfully`);
      } catch (logErr) {
        console.error(`[DB TEST] Failed to log to database (non-fatal): ${logErr.message}`);
        // Don't exit - continue with script execution
      }
    } catch (dbErr) {
      console.error(`[DB Connection Error] ${dbErr.message}`);
      console.error(`[DB Connection Error] Stack: ${dbErr.stack}`);
      
      // Log to debug file
      try {
        const debugLogFile = path.join(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] DB CONNECTION ERROR: ${dbErr.message}\n${dbErr.stack}\n`);
      } catch (e) {
        console.error(`[DEBUG LOG ERROR] ${e.message}`);
      }
      
      if (jobId && pool) {
        try {
          await pool.query(
            `UPDATE scraper_jobs SET status = 'error', error_message = $1 WHERE id = $2`,
            ['Database connection failed: ' + dbErr.message, jobId]
          );
        } catch (updateErr) {
          console.error(`[DB UPDATE ERROR] ${updateErr.message}`);
        }
      }
      process.exit(1);
    }
  } else {
    console.log(`[INFO] No jobId provided - script will run without database tracking`);
    // Log to file
    try {
      const debugLogFile = path.resolve(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [INFO] No jobId provided (jobId=${jobId}), skipping database tracking\n`);
    } catch (e) {}
  }
  
  // Log to debug file that we're proceeding to browser launch (ALWAYS, regardless of jobId)
  try {
    const debugLogFile = path.join(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Proceeding to browser launch... (jobId=${jobId || 'none'})\n`);
    console.log(`[DEBUG] Logged to debug file: Proceeding to browser launch`);
    console.error(`[STDERR] About to launch browser - this should be visible`);
    
    // #region agent log - Hypothesis D: Before browser launch
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:432',message:'Proceeding to browser launch',data:{jobId:jobId,puppeteerExists:!!puppeteer},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
    // #endregion
  } catch (e) {
    console.error(`[DEBUG LOG ERROR] ${e.message}`);
  }
  
  log(`Initializing browser...`)
  console.log(`[BROWSER] About to launch browser - script is continuing...`);
  console.error(`[STDERR] Browser launch starting - script is running`);
  console.log(`[BROWSER] Starting browser launch...`);
  
  // Log to debug file
  try {
    const debugLogFile = path.join(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Initializing browser...\n`);
  } catch (e) {
    console.error(`[DEBUG LOG ERROR] ${e.message}`);
  }
  
  // const browser = await puppeteer.launch({
  //   headless: 'new',
  //   args: [
  //     '--no-sandbox',
  //     '--disable-dev-shm-usage',
  //     `--user-data-dir=${profileDir}`
  //   ],
  //   defaultViewport: { width: 1280, height: 800 }
  // })

  let browser;
  try {
    if (!puppeteer) {
      throw new Error('Puppeteer module not loaded - cannot launch browser');
    }
    console.log(`[BROWSER] Calling puppeteer.launch()...`);
    
    // #region agent log - Hypothesis D: Before puppeteer.launch
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:470',message:'About to call puppeteer.launch',data:{jobId:jobId,executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
    // #endregion
    
    browser = await puppeteer.launch({
      executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      headless: 'new',
      args: ['--no-sandbox']
    });
    
    // #region agent log - Hypothesis D: After puppeteer.launch
    fetch('http://127.0.0.1:7242/ingest/bc052aea-d3c1-4aff-b403-3b131120ef5a',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({location:'scrape_single_event.js:476',message:'puppeteer.launch completed',data:{jobId:jobId,browserExists:!!browser},timestamp:Date.now(),sessionId:'debug-session',runId:'run1',hypothesisId:'D'})}).catch(()=>{});
    // #endregion
    
    log(`Browser launched successfully`);
    console.log(`[BROWSER] Browser launched successfully`);
    
    // Log to debug file
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Browser launched successfully\n`);
    } catch (e) {
      console.error(`[DEBUG LOG ERROR] ${e.message}`);
    }
  } catch (browserErr) {
    console.error(`[Browser Launch Error] ${browserErr.message}`);
    console.error(browserErr.stack);
    
    // Log to debug file
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] BROWSER LAUNCH ERROR: ${browserErr.message}\n${browserErr.stack}\n`);
    } catch (e) {}
    
    if (jobId) {
      await logToDatabase(jobId, 'error', `Failed to launch browser: ${browserErr.message}`, 'scraper');
      await pool.query(
        `UPDATE scraper_jobs SET status = 'error', error_message = $1 WHERE id = $2`,
        ['Browser launch failed: ' + browserErr.message, jobId]
      ).catch(() => {});
    }
    process.exit(1);
  }

  const page = await browser.newPage()
  page.setDefaultTimeout(45000)
  page.setDefaultNavigationTimeout(60000)

  // Debug log - page created
  try {
    const debugLogFile = path.join(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DEBUG] Page created, about to navigate...\n`);
  } catch (e) {}

  try {
    const baseUrl = `https://www.numisbids.com/sale/${eventId}`
    log(`Navigating: ${baseUrl}`)
    
    // Debug log - before navigation
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DEBUG] Navigating to: ${baseUrl}\n`);
    } catch (e) {}
    
    if (jobId) {
      await logToDatabase(jobId, 'info', `Navigating: ${baseUrl}`, 'scraper');
    }
    await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
    
    // Debug log - after navigation
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DEBUG] Navigation successful\n`);
    } catch (e) {}

    // View all lots if present
    try {
      const viewAllHref = await page.evaluate(() => {
        const links = Array.from(document.querySelectorAll('a'))
        const m = links.find(a => /view\s*all\s*lots/i.test(a.textContent || ''))
        return m ? m.getAttribute('href') : null
      })
      if (viewAllHref) {
        const fullUrl = new URL(viewAllHref, window.location.href).href
        log(`Following View all lots -> ${fullUrl}`)
        await page.goto(fullUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
      }
    } catch {}

    // Auction metadata and total pages
    let auctionName = ''
    let auctionTitle = ''
    let eventDate = ''
    let totalPages = 1

    try {
      const meta = await page.evaluate(() => {
        const textDiv = document.querySelector('.text')
        const auctionName = textDiv?.querySelector('.name')?.textContent?.trim() || ''
        const bTags = textDiv ? Array.from(textDiv.querySelectorAll('b')) : []
        const titlePart = bTags[0]?.textContent?.trim() || ''
        const fullHtml = textDiv?.innerHTML || ''
        const match = fullHtml.match(/<b>.*?<\/b>&nbsp;&nbsp;([^<]+)/)
        const eventDate = match ? match[1].trim() : ''

        const pageInfo = document.querySelector('.salenav-top .small')?.textContent || ''
        const pagesMatch = pageInfo.match(/Page\s+\d+\s+of\s+(\d+)/i)
        const totalPages = pagesMatch ? parseInt(pagesMatch[1], 10) : 1

        return { auctionName, auctionTitle: `${auctionName}, ${titlePart}`.trim(), eventDate, totalPages }
      })
      auctionName = meta.auctionName
      auctionTitle = meta.auctionTitle
      eventDate = meta.eventDate
      totalPages = meta.totalPages
      
      // Debug log - metadata retrieved
      try {
        const debugLogFile = path.join(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DEBUG] Auction metadata: name=${auctionName}, totalPages=${totalPages}\n`);
      } catch (e) {}
      
      // Log auction info (like command line: "Auction 10258 — Page 1")
      if (jobId) {
        await logToDatabase(jobId, 'info', `Auction ${eventId} — Page 1`, 'scraper');
      }
    } catch (metaErr) {
      // Debug log - metadata error
      try {
        const debugLogFile = path.join(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DEBUG] Metadata error: ${metaErr.message}\n`);
      } catch (e) {}
    }

    const seenLots = new Set()
    let lotsScraped = 0
    let startPage = 1
    
    // Debug log - before resume check
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [DEBUG] About to check resume state, jobId=${jobId}\n`);
    } catch (e) {}
    
    // Check for resume state if jobId is provided (BEFORE clearing the file)
    let resumeState = null;
    if (jobId) {
        console.log(`[RESUME CHECK] Checking for resume state for jobId=${jobId}`);
        
        // Debug log - inside resume check
        try {
          const debugLogFile = path.join(__dirname, 'scrape_debug.log');
          fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [RESUME CHECK] Checking resume state for jobId=${jobId}\n`);
        } catch (e) {}
        
        // First check if file exists (regardless of database state)
        const fileExists = fs.existsSync(inProgressFile);
        const fileHasData = fileExists && fs.statSync(inProgressFile).size > 0;
        
        // Check resume state from database
        const savedState = await getResumeState(jobId);
        console.log(`[RESUME CHECK] Saved state result:`, JSON.stringify(savedState));
        console.log(`[RESUME CHECK] File check: exists=${fileExists}, hasData=${fileHasData}, path=${inProgressFile}`);
        
        // Debug log
        try {
          const debugLogFile = path.join(__dirname, 'scrape_debug.log');
          fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [RESUME CHECK] savedState: ${JSON.stringify(savedState)}\n`);
        } catch (e) {}
        
        console.log(`[RESUME CHECK] File exists: ${fileExists}, has data: ${fileHasData}`);
        try {
          const debugLogFile = path.join(__dirname, 'scrape_debug.log');
          fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [RESUME CHECK] File: ${inProgressFile}, exists=${fileExists}, hasData=${fileHasData}\n`);
        } catch (e) {}
        
        // Load resume state if resume_state exists OR if file has data (indicates previous scraping)
        // Key: Check fileHasData FIRST before database state
        if (fileHasData || (savedState && savedState.resumeState)) {
            if (savedState && savedState.resumeState) {
                resumeState = savedState.resumeState;
                console.log(`[RESUME] Using database resume_state`);
            } else if (fileHasData) {
                // If resume_state is null but file has data, reconstruct from file
                console.log(`[RESUME] No resume_state JSON, but file has data. Reconstructing from file.`);
                resumeState = {
                    eventId: savedState?.currentEventId || eventId,
                    currentPage: 1, // Default to page 1
                    lotsScraped: 0, // Will be loaded from file below
                    lotNumber: savedState?.currentLotNumber || ''
                };
                console.log(`[RESUME] Reconstructed resume state:`, JSON.stringify(resumeState));
            }
            
            if (resumeState) {
                startPage = resumeState.currentPage || 1;
                lotsScraped = resumeState.lotsScraped || 0;
                console.log(`[RESUME] Loading saved state: page=${startPage}, lotsScraped=${lotsScraped}, lotNumber=${resumeState.lotNumber}`);
                console.log(`[RESUME] Full resume state:`, JSON.stringify(resumeState));
                await logToDatabase(jobId, 'info', `Resuming from saved state: page ${startPage}, ${lotsScraped} lots already scraped`, 'scraper');
            }
        } else {
            console.log(`[RESUME CHECK] No resume state found. savedState:`, savedState);
            if (savedState) {
                console.log(`[RESUME CHECK] savedState.resumeState:`, savedState.resumeState);
            }
        }
        
        // Load already seen lots from the file to avoid re-scraping (do this whenever file exists)
        if (fileHasData) {
            try {
                const fileContent = fs.readFileSync(inProgressFile, 'utf-8');
                const lines = fileContent.split('\n').filter(line => line.trim());
                for (const line of lines) {
                    try {
                        const lotData = JSON.parse(line);
                        if (lotData.lotnumber) {
                            seenLots.add(String(lotData.lotnumber)); // Ensure string comparison
                        }
                    } catch (e) {
                        // Skip invalid JSON lines
                    }
                }
                console.log(`[RESUME] Loaded ${seenLots.size} already scraped lots from file: ${Array.from(seenLots).slice(0, 5).join(', ')}...`);
                // Update lotsScraped count from file if resume state didn't have it
                if (lotsScraped === 0 && seenLots.size > 0) {
                    lotsScraped = seenLots.size;
                    console.log(`[RESUME] Updated lotsScraped count from file: ${lotsScraped}`);
                }
                // Set resumeState if we have seen lots (to prevent file clearing)
                if (!resumeState && seenLots.size > 0) {
                    resumeState = {
                        eventId: eventId,
                        currentPage: 1,
                        lotsScraped: seenLots.size,
                        lotNumber: ''
                    };
                    console.log(`[RESUME] Created resumeState from file data: ${seenLots.size} lots`);
                }
            } catch (fileErr) {
                console.error(`[RESUME] Failed to load existing lots from file: ${fileErr.message}`);
            }
        }
    }
    
    // Create/clear the output file ONLY if NOT resuming (if resuming, we want to append to existing file)
    if (!resumeState) {
        try {
            fs.writeFileSync(inProgressFile, '');
            console.log(`[FILE] Created output file: ${inProgressFile}`);
            if (jobId) {
                await logToDatabase(jobId, 'info', `Output file created: ${inProgressFile}`, 'scraper');
            }
        } catch (fileErr) {
            console.error(`[FILE ERROR] Failed to create output file: ${fileErr.message}`);
            if (jobId) {
                await logToDatabase(jobId, 'error', `Failed to create output file: ${fileErr.message}`, 'scraper');
            }
        }
    } else {
        console.log(`[RESUME] Keeping existing file and appending new lots: ${inProgressFile}`);
        await logToDatabase(jobId, 'info', `Resuming - will append to existing file: ${inProgressFile}`, 'scraper');
    }
    
    // Initialize job statistics
    if (jobId) {
        if (resumeState) {
            await logToDatabase(jobId, 'info', `Resuming single event scraping for event ${eventId} from page ${startPage}`, 'scraper');
        } else {
            await logToDatabase(jobId, 'info', `Starting single event scraping for event ${eventId}`, 'scraper');
        }
        await logToDatabase(jobId, 'info', `Navigating: https://www.numisbids.com/sale/${eventId}`, 'scraper');
        await pool.query(
            `UPDATE scraper_jobs SET current_event_id = $1, total_events = 1, current_event_index = 0 WHERE id = $2`,
            [eventId, jobId]
        );
        // Initialize statistics record
        await pool.query(
            `INSERT INTO job_statistics (job_id, total_events, processed_events, total_lots, processed_lots, files_created, files_completed, start_time, last_update)
             VALUES ($1, 1, 0, 0, 0, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
             ON CONFLICT DO NOTHING`,
            [jobId]
        ).catch(() => {}); // Ignore if already exists
        
        // Update statistics with already scraped lots if resuming
        if (resumeState && lotsScraped > 0) {
            await updateJobStatistics(jobId, {
                totalEvents: 1,
                processedEvents: 0,
                totalLots: 0,
                processedLots: lotsScraped,
                filesCreated: 1,
                filesCompleted: 0
            });
        }
    }

    // If resuming, navigate to the resume page first
    if (resumeState && startPage > 1) {
      const pageUrlBase = await page.evaluate(() => window.location.href.split('?')[0])
      const resumePageUrl = `${pageUrlBase}?pg=${startPage}`
      console.log(`[RESUME] Navigating to page ${startPage} to resume scraping...`);
      await logToDatabase(jobId, 'info', `Resuming from page ${startPage}`, 'scraper');
      await page.goto(resumePageUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
    }
    
    // Debug log before main loop
    console.log(`[SCRAPE LOOP] About to start main scraping loop: startPage=${startPage}, totalPages=${totalPages}, seenLots.size=${seenLots.size}`);
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [SCRAPE LOOP] Starting: startPage=${startPage}, totalPages=${totalPages}, seenLots=${seenLots.size}, resumeState=${resumeState ? 'yes' : 'no'}\n`);
    } catch (e) {}
    
    // Start from saved page if resuming, otherwise start from page 1
    for (let currentPage = startPage; currentPage <= totalPages; currentPage++) {
      // CRITICAL: Check if job is paused or stopped before processing each page
      if (jobId) {
        const jobStatus = await checkJobStatus(jobId);
        if (jobStatus.isStopped) {
          console.log(`[STOP] Job ${jobId} is stopped. Exiting immediately...`);
          await logToDatabase(jobId, 'info', `Job stopped at page ${currentPage}, lot ${lotsScraped} scraped`, 'scraper');
          await browser.close();
          process.exit(0);
        }
        if (jobStatus.isPaused) {
          console.log(`[PAUSE] Job ${jobId} is paused. Saving state and exiting...`);
          await logToDatabase(jobId, 'info', `Job paused at page ${currentPage}, lot ${lotsScraped} scraped`, 'scraper');
          // Save resume state with last processed lot
          const lastLotNumber = lotsScraped > 0 ? `Last processed: ${lotsScraped} lots` : '';
          await saveResumeState(jobId, eventId, lastLotNumber, currentPage, lotsScraped);
          await browser.close();
          process.exit(0);
        }
      }
      
      // Only navigate if we're not already on this page (for resume case)
      if (currentPage !== startPage || !resumeState) {
        const pageUrlBase = await page.evaluate(() => window.location.href.split('?')[0])
        const pageUrl = `${pageUrlBase}?pg=${currentPage}`
        log(`Auction ${eventId} — Page ${currentPage}`)
        await page.goto(pageUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
      } else {
        log(`Auction ${eventId} — Page ${currentPage} (resumed)`)
      }

      const lotHandles = await page.$$('.browse')
      console.log(`[PAGE ${currentPage}] Found ${lotHandles.length} lot elements on page`);
      try {
        const debugLogFile = path.join(__dirname, 'scrape_debug.log');
        fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [PAGE ${currentPage}] Found ${lotHandles.length} lots, seenLots.size=${seenLots.size}\n`);
      } catch (e) {}
      
      for (const lot of lotHandles) {
        // CRITICAL: Check pause/stop status BEFORE processing each lot
        if (jobId) {
          const jobStatus = await checkJobStatus(jobId);
          if (jobStatus.isStopped) {
            console.log(`[STOP] Job ${jobId} is stopped. Exiting immediately...`);
            await logToDatabase(jobId, 'info', `Job stopped at page ${currentPage}, lot ${lotsScraped} scraped`, 'scraper');
            await browser.close();
            process.exit(0);
          }
          if (jobStatus.isPaused) {
            console.log(`[PAUSE] Job ${jobId} is paused. Saving state and exiting...`);
            await logToDatabase(jobId, 'info', `Job paused at page ${currentPage}, lot ${lotsScraped} scraped`, 'scraper');
            const lastLotNumber = lotsScraped > 0 ? `Last processed: ${lotsScraped} lots` : '';
            await saveResumeState(jobId, eventId, lastLotNumber, currentPage, lotsScraped);
            await browser.close();
            process.exit(0);
          }
        }
        
        try {
          const lotNumber = await lot.$eval('.lot a', el => el.textContent.trim().replace(/^Lot\s+/i, ''))
          const lotNumberStr = String(lotNumber); // Ensure string for comparison
          
          // Skip if already scraped (but log for debugging)
          if (seenLots.has(lotNumberStr)) {
            if (resumeState && lotsScraped < 10) {
              console.log(`[RESUME] Skipping already scraped lot: ${lotNumberStr}`);
            }
            continue;
          }
          
          // Log when we start scraping new lots after resume
          if (resumeState && lotsScraped === resumeState.lotsScraped) {
            console.log(`[RESUME] Starting to scrape new lots from lot ${lotNumberStr}`);
            await logToDatabase(jobId, 'info', `Resuming scraping from lot ${lotNumberStr} on page ${currentPage}`, 'scraper');
          }

          const relLotUrl = await lot.$eval('a[href*="/lot/"]', el => el.getAttribute('href'))
          const lotUrl = new URL(relLotUrl, 'https://www.numisbids.com').href
          const lotName = await lot.$eval('.summary a', el => el.textContent.trim())
          const description = lotName.split('.')[0]
          const thumbImage = await lot.$eval('img', el => {
            const src = el.getAttribute('src') || ''
            return src.startsWith('http') ? src : 'https:' + src
          })
          const startingPrice = await lot.$eval('.estimate span', el => el.textContent.trim()).catch(() => '')
          const realizedPrice = await lot.$eval('.realized span', el => el.textContent.trim()).catch(() => '')

          // Check again before opening new page (expensive operation)
          if (jobId) {
            const jobStatus = await checkJobStatus(jobId);
            if (jobStatus.isStopped || jobStatus.isPaused) {
              if (jobStatus.isStopped) {
                console.log(`[STOP] Job ${jobId} is stopped. Exiting before opening lot page...`);
                await logToDatabase(jobId, 'info', `Job stopped before scraping lot ${lotNumber}`, 'scraper');
              } else {
                console.log(`[PAUSE] Job ${jobId} is paused. Saving state and exiting...`);
                await logToDatabase(jobId, 'info', `Job paused before scraping lot ${lotNumber}`, 'scraper');
                await saveResumeState(jobId, eventId, lotNumber, currentPage, lotsScraped);
              }
              await browser.close();
              process.exit(0);
            }
          }

          const dpage = await browser.newPage()
          dpage.setDefaultTimeout(30000)
          await dpage.goto(lotUrl, { waitUntil: 'domcontentloaded', timeout: 60000 })
          await dpage.waitForSelector('.viewlottext', { timeout: 10000 }).catch(() => {})

          const details = await dpage.evaluate(() => {
            const activeCat = document.querySelector('#activecat span a:last-of-type')
            const rawCategory = activeCat ? activeCat.textContent.trim() : ''
            const category = rawCategory.replace(/^[A-Z]\.[\s\u00A0]*/, '').replace(/\s*\(\d+\)\s*$/, '').trim()

            const descEl = document.querySelector('.viewlottext > .description:last-of-type')
            let fullDesc = ''
            if (descEl) {
              fullDesc = descEl.innerHTML
                .replace(/<br\s*\/?>(\s*)/gi, '\n')
                .replace(/<[^>]+>/g, '')
                .trim()
            }

            const img = document.querySelector('.viewlotimg img')?.getAttribute('src') || ''
            const fullImage = img ? (img.startsWith('http') ? img : 'https:' + img) : ''

            return { category, fullDescription: fullDesc, fullImage }
          })

          await dpage.close()

          // Check pause/stop status after scraping lot data but before writing to file
          if (jobId) {
            const jobStatus = await checkJobStatus(jobId);
            if (jobStatus.isStopped) {
              console.log(`[STOP] Job ${jobId} is stopped. Exiting before writing lot to file...`);
              await logToDatabase(jobId, 'info', `Job stopped after scraping lot ${lotNumber} data`, 'scraper');
              await browser.close();
              process.exit(0);
            }
            if (jobStatus.isPaused) {
              console.log(`[PAUSE] Job ${jobId} is paused. Saving state and exiting...`);
              await logToDatabase(jobId, 'info', `Job paused after scraping lot ${lotNumber} data`, 'scraper');
              await saveResumeState(jobId, eventId, lotNumber, currentPage, lotsScraped);
              await browser.close();
              process.exit(0);
            }
          }

          const lotData = {
            auctionid: String(eventId),
            loturl: lotUrl,
            auctionname: auctionName,
            auctiontitle: auctionTitle,
            eventdate: eventDate,
            category: details.category,
            startingprice: startingPrice,
            realizedprice: realizedPrice,
            imagepath: details.fullImage || thumbImage,
            fulldescription: details.fullDescription,
            lotnumber: lotNumberStr,
            shortdescription: lotName,
            lotname: description
          }

          // Write lot to file
          try {
            fs.appendFileSync(inProgressFile, JSON.stringify(lotData) + '\n');
            seenLots.add(lotNumberStr);
            lotsScraped++;
            
            // Log more frequently when resuming to verify it's working
            if (resumeState) {
              console.log(`[RESUME] Scraped and wrote lot ${lotNumberStr} (total: ${lotsScraped}, was: ${resumeState.lotsScraped})`);
              if (lotsScraped <= resumeState.lotsScraped + 5) {
                await logToDatabase(jobId, 'info', `Resumed scraping: lot ${lotNumberStr} written (${lotsScraped} total)`, 'scraper');
              }
            }
            
            // Log every 10th lot to reduce console spam
            if (!resumeState && (lotsScraped % 10 === 0 || lotsScraped <= 5)) {
              console.log(`[FILE] Written ${lotsScraped} lots to ${inProgressFile}`);
            }
          } catch (fileErr) {
            console.error(`[FILE ERROR] Failed to write lot ${lotNumberStr}: ${fileErr.message}`);
            if (jobId) {
              await logToDatabase(jobId, 'error', `Failed to write lot ${lotNumberStr} to file: ${fileErr.message}`, 'scraper');
            }
            // Continue even if file write fails
            seenLots.add(lotNumberStr);
            lotsScraped++;
          }
          
          // CRITICAL: Check if job is paused or stopped BEFORE inserting into database
          // This is the most important check - we don't want to insert if paused/stopped
          if (jobId) {
            const jobStatus = await checkJobStatus(jobId);
            if (jobStatus.isStopped) {
              console.log(`[STOP] Job ${jobId} is stopped. Stopping before database insert. Exiting immediately...`);
              await logToDatabase(jobId, 'info', `Job stopped before inserting lot ${lotNumberStr} (${lotsScraped} lots scraped)`, 'scraper');
              await browser.close();
              process.exit(0);
            }
            if (jobStatus.isPaused) {
              console.log(`[PAUSE] Job ${jobId} is paused. Stopping before database insert. Saving state and exiting...`);
              await logToDatabase(jobId, 'info', `Job paused before inserting lot ${lotNumberStr} (${lotsScraped} lots scraped)`, 'scraper');
              await saveResumeState(jobId, eventId, lotNumberStr, currentPage, lotsScraped);
              await browser.close();
              process.exit(0);
            }
          }
          
          // Insert lot into database in real-time (if insert functions available)
          let lotsInserted = 0;
          if (jobId && insertLotFunctions && insertLotFunctions.processLotInRealTime) {
            try {
              // Check pause/stop status again right before insert (double-check)
              const jobStatus = await checkJobStatus(jobId);
              if (jobStatus.isStopped) {
                console.log(`[STOP] Job ${jobId} is stopped. Stopping database insert. Exiting immediately...`);
                await logToDatabase(jobId, 'info', `Job stopped before inserting lot ${lotNumberStr} (${lotsScraped} lots scraped)`, 'scraper');
                await browser.close();
                process.exit(0);
              }
              if (jobStatus.isPaused) {
                console.log(`[PAUSE] Job ${jobId} is paused. Stopping database insert. Saving state and exiting...`);
                await logToDatabase(jobId, 'info', `Job paused before inserting lot ${lotNumberStr} (${lotsScraped} lots scraped)`, 'scraper');
                await saveResumeState(jobId, eventId, lotNumberStr, currentPage, lotsScraped);
                await browser.close();
                process.exit(0);
              }
              
              // Prepare event data for insertion
              const eventData = {
                auctionid: String(eventId),
                auctionname: auctionName,
                auctiontitle: auctionTitle,
                eventdate: eventDate
              };
              const insertResult = await insertLotFunctions.processLotInRealTime(lotData, eventData, true);
              if (insertResult && insertResult.success) {
                lotsInserted = 1;
                await logToDatabase(jobId, 'debug', `Inserted lot ${lotNumber} into database`, 'scraper');
              }
            } catch (insertErr) {
              console.warn(`[Insert Error] Lot ${lotNumber}: ${insertErr.message}`);
              await logToDatabase(jobId, 'warning', `Failed to insert lot ${lotNumberStr}: ${insertErr.message}`, 'scraper');
            }
          }
          
          // Update job statistics in real-time
          if (jobId) {
            await updateCurrentLot(jobId, eventId, lotNumberStr);
            
            // Update statistics - processed_lots represents scraped lots (for monitoring)
            // Update after EVERY lot for real-time monitoring
            try {
              await updateJobStatistics(jobId, {
                totalEvents: 1,
                processedEvents: 0,
                totalLots: 0, // Will be set at end when we know total
                processedLots: lotsScraped, // Number of lots scraped so far (for progress tracking)
                filesCreated: 1,
                filesCompleted: 0
              });
              // Log every 10th update to reduce console spam
              if (lotsScraped % 10 === 0 || lotsScraped <= 5) {
                console.log(`[STATS] Updated: ${lotsScraped} lots scraped`);
              }
            } catch (statsErr) {
              console.error(`[STATS ERROR] Failed to update statistics: ${statsErr.message}`);
            }
            
            // Log every lot for real-time monitoring (matches command line output format)
            await logToDatabase(jobId, 'info', `Scraped lot ${lotNumberStr} (${lotsScraped} scraped, ${lotsInserted > 0 ? 'inserted' : 'pending insert'})`, 'scraper', {
              eventId: eventId,
              lotNumber: lotNumberStr,
              lotsScraped: lotsScraped,
              lotsInserted: lotsInserted
            });
          }
          
          log(`Scraped lot ${lotNumberStr} (${lotsScraped} scraped, ${lotsInserted > 0 ? 'inserted' : 'pending insert'})`)
        } catch (err) {
          console.warn(`Lot error: ${err.message}`)
        }
      }
    }

    // Debug log after main loop
    console.log(`[SCRAPE LOOP] Main loop finished. lotsScraped=${lotsScraped}`);
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] [SCRAPE LOOP] Finished: lotsScraped=${lotsScraped}\n`);
    } catch (e) {}
    
    const lines = fs.readFileSync(inProgressFile, 'utf-8')
      .split('\n').filter(Boolean).map(l => JSON.parse(l))
    fs.writeFileSync(finalFile, JSON.stringify(lines, null, 2))
    
    // Final statistics update
    if (jobId) {
      await updateJobStatistics(jobId, {
        totalEvents: 1,
        processedEvents: 1,
        totalLots: lotsScraped,
        processedLots: lotsScraped,
        filesCreated: 1,
        filesCompleted: 1
      });
      await logToDatabase(jobId, 'info', `Completed event ${eventId}: ${lotsScraped} lots scraped`, 'scraper', {
        eventId: eventId,
        lotsScraped: lotsScraped
      });
    }
    
    log(`Saved final JSON: ${finalFile} (${lotsScraped} lots)`)
    
    // Final status update - mark job as completed
    if (jobId) {
      try {
        await pool.query(
          `UPDATE scraper_jobs SET status = 'completed', completed_at = CURRENT_TIMESTAMP WHERE id = $1`,
          [jobId]
        );
        await logToDatabase(jobId, 'info', `Scraping completed successfully: ${lotsScraped} lots scraped`, 'scraper');
        console.log(`[SUCCESS] Job ${jobId} completed: ${lotsScraped} lots scraped`);
      } catch (updateErr) {
        console.error(`[ERROR] Failed to update job status: ${updateErr.message}`);
      }
    }
    
    // Set exit code to 0 for success
    process.exitCode = 0;
    console.log(`[SUCCESS] Script completed successfully`);
  } catch (e) {
    console.error(`[Fatal Error] ${e.message}`);
    console.error(e.stack);
    
    // Log to debug file
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] FATAL ERROR: ${e.message}\n${e.stack}\n`);
    } catch (logErr) {}
    
    if (jobId) {
      await logToDatabase(jobId, 'error', `Error scraping event ${eventId}: ${e.message}`, 'scraper', {
        eventId: eventId,
        error: e.message,
        stack: e.stack
      });
      // Update job status to error
      await pool.query(
        `UPDATE scraper_jobs SET status = 'error', error_message = $1 WHERE id = $2`,
        [e.message, jobId]
      ).catch(() => {});
    }
    process.exitCode = 1
  } finally {
    // Clear keep-alive interval
    try {
      if (typeof keepAlive !== 'undefined') {
        clearInterval(keepAlive);
      }
    } catch (e) {}
    
    try {
      if (typeof browser !== 'undefined' && browser) {
        await browser.close();
      }
    } catch (closeErr) {
      console.error(`[Error closing browser] ${closeErr.message}`);
    }
    try {
      if (pool) {
        await pool.end();
      }
    } catch (poolErr) {
      console.error(`[Error closing pool] ${poolErr.message}`);
    }
    
    // Final log
    try {
      const debugLogFile = path.join(__dirname, 'scrape_debug.log');
      const exitCode = process.exitCode !== undefined ? process.exitCode : 0;
      fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] Script finished (exit code: ${exitCode})\n`);
      console.log(`[FINAL] Script finished with exit code: ${exitCode}`);
    } catch (logErr) {
      console.error(`[FINAL LOG ERROR] ${logErr.message}`);
    }
    
    // Ensure exit code is set
    if (process.exitCode === undefined) {
      process.exitCode = 0; // Success if no error was set
    }
  }
})().catch((err) => {
  // Catch any unhandled errors in the async IIFE
  console.error(`[ASYNC IIFE ERROR] ${err.message}`);
  console.error(`[ASYNC IIFE ERROR] Stack: ${err.stack}`);
  try {
    const debugLogFile = path.join(__dirname, 'scrape_debug.log');
    fs.appendFileSync(debugLogFile, `[${new Date().toISOString()}] ASYNC IIFE ERROR: ${err.message}\n${err.stack}\n`);
  } catch (logErr) {}
  process.exitCode = 1;
  process.exit(1);
})
