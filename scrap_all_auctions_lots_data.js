// Immediate console logging (before any requires that might fail)
console.log('[SCRIPT START] Initializing scraper...');
console.log('[SCRIPT START] Process args:', process.argv.slice(2));

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

// Try to load database config with error handling
let pool = null;
try {
    pool = require('./dbConfig');
    console.log('[SCRIPT START] Database config loaded successfully');
} catch (dbErr) {
    console.error('[SCRIPT START] ❌ Failed to load database config:', dbErr.message);
    console.error('[SCRIPT START] Stack:', dbErr.stack);
    // Continue without database - will log errors later
}

// Import real-time insertion functions
let insertLotFunctions = null;
try {
  insertLotFunctions = require('./insert_lots_into_db');
  console.log('[SCRIPT START] Insert functions loaded successfully');
} catch (err) {
  console.warn('[SCRIPT START] [Warning] Could not load insert_lots_into_db module. Real-time insertion disabled.');
}

// Enhanced logging function
function log(message, type = 'info') {
    const timestamp = new Date().toISOString();
    const prefix = type === 'error' ? '❌' : type === 'warning' ? '⚠️' : type === 'success' ? '✅' : 'ℹ️';
    console.log(`[${timestamp}] ${prefix} ${message}`);
}
// Process management
process.on('SIGINT', () => {
    log('Received SIGINT, shutting down gracefully...', 'warning');
    process.exit(0);
});

process.on('SIGTERM', () => {
    log('Received SIGTERM, shutting down gracefully...', 'warning');
    process.exit(0);
});

// Parse command line arguments
const args = process.argv.slice(2);
let targetEventId = null;
let outputFile = null;
let resume = false;
let lastLot = null;
let jobId = null;

// Parse arguments
for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--event-id=')) {
        targetEventId = args[i].split('=')[1];
    } else if (args[i] === '--event-id' && i + 1 < args.length) {
        targetEventId = args[i + 1];
        i++;
    } else if (args[i].startsWith('--output-file=')) {
        outputFile = args[i].split('=')[1];
    } else if (args[i] === '--output-file' && i + 1 < args.length) {
        outputFile = args[i + 1];
        i++;
    } else if (args[i] === '--resume') {
        resume = true;
    } else if (args[i].startsWith('--last-lot=')) {
        lastLot = args[i].split('=')[1];
    } else if (args[i] === '--last-lot' && i + 1 < args.length) {
        lastLot = args[i + 1];
        i++;
    } else if (args[i].startsWith('--job-id=')) {
        jobId = parseInt(args[i].split('=')[1]);
    } else if (args[i] === '--job-id' && i + 1 < args.length) {
        jobId = parseInt(args[i + 1]);
        i++;
    } else if (args[i] === '--help' || args[i] === '-h') {
    console.log(`
Usage: node scrap_all_auctions_lots_data.js [options]

Options:
  --event-id <id>         Process only a specific event ID
  --output-file <name>    Specify output file name
  --job-id <id>           Database job ID for status tracking
  --resume                Resume from existing in-progress file
  --last-lot <number>     Resume from specific lot number
  --help, -h              Show this help message

Examples:
  node scrap_all_auctions_lots_data.js --event-id 9537
  node scrap_all_auctions_lots_data.js --resume --last-lot 100
  node scrap_all_auctions_lots_data.js --output-file "auction_9537_lots.jsonl"
  node scrap_all_auctions_lots_data.js --job-id 5
        `);
        process.exit(0);
    }
}

log(`🚀 Starting scraper with options:`);
if (jobId) log(`   Job ID: ${jobId}`);
if (targetEventId) log(`   Target event ID: ${targetEventId}`);
if (outputFile) log(`   Output file: ${outputFile}`);
if (resume) log(`   Resume mode: enabled`);
if (lastLot) log(`   Resume from lot: ${lastLot}`);
if (!targetEventId) log(`   Processing all available sales`);

// Database status tracking functions
async function logToDatabase(jobId, level, message, source = 'scraper', metadata = {}) {
    if (!jobId) return;
    if (!pool) {
        console.warn(`[DB LOG SKIP] ${level.toUpperCase()}: ${message} (database not available)`);
        return;
    }
    try {
        await pool.query(
            `INSERT INTO scrape_logs (job_id, log_level, message, source, metadata)
             VALUES ($1, $2, $3, $4, $5::jsonb)`,
            [jobId, level, message, source, JSON.stringify(metadata)]
        );
    } catch (err) {
        console.error(`[DB Log Error] ${err.message}`);
    }
}

async function updateJobStatistics(jobId, stats) {
    if (!jobId || !pool) return;
    try {
        // Check if statistics record exists
        const checkResult = await pool.query(
            `SELECT id FROM job_statistics WHERE job_id = $1 ORDER BY id DESC LIMIT 1`,
            [jobId]
        );
        
        const statsData = {
            total_events: stats.totalEvents || 0,
            processed_events: stats.processedEvents || 0,
            total_lots: stats.totalLots || 0,
            processed_lots: stats.processedLots || 0,
            files_created: stats.filesCreated || 0,
            files_completed: stats.filesCompleted || 0
        };
        
        if (checkResult.rows.length > 0) {
            // Update existing record
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

// -------- Pause/Resume State Management --------
/**
 * Check if job is paused or stopped
 * @param {number} jobId - Job ID
 * @returns {Promise<{isPaused: boolean, isStopped: boolean, status: string}>} - Status object
 */
async function checkJobStatus(jobId) {
    if (!jobId || !pool) return {isPaused: false, isStopped: false, status: ''};
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
 * Save resume state to database
 * @param {number} jobId - Job ID
 * @param {string} eventId - Current event ID
 * @param {string} lotNumber - Last processed lot number
 * @param {number} eventIndex - Current event index (0-based)
 * @param {Object} additionalState - Additional state to save
 */
async function saveResumeState(jobId, eventId, lotNumber, eventIndex, additionalState = {}) {
    if (!jobId || !pool) return;
    try {
        const resumeState = {
            eventId,
            lotNumber,
            eventIndex,
            timestamp: new Date().toISOString(),
            ...additionalState
        };
        
        await pool.query(
            `UPDATE scraper_jobs 
             SET resume_state = $1::jsonb,
                 current_event_id = $2,
                 current_lot_number = $3,
                 current_event_index = $4
             WHERE id = $5`,
            [JSON.stringify(resumeState), eventId, lotNumber, eventIndex, jobId]
        );
    } catch (err) {
        console.error(`[Save Resume State Error] ${err.message}`);
    }
}

/**
 * Get resume state from database
 * @param {number} jobId - Job ID
 * @returns {Promise<Object|null>} - Resume state object or null
 */
async function getResumeState(jobId) {
    if (!jobId || !pool) return null;
    try {
        const result = await pool.query(
            `SELECT resume_state, current_event_id, current_lot_number, current_event_index, total_events
             FROM scraper_jobs WHERE id = $1`,
            [jobId]
        );
        
        if (result.rows.length > 0) {
            const row = result.rows[0];
            return {
                resumeState: row.resume_state ? (typeof row.resume_state === 'string' ? JSON.parse(row.resume_state) : row.resume_state) : null,
                currentEventId: row.current_event_id,
                currentLotNumber: row.current_lot_number,
                currentEventIndex: row.current_event_index,
                totalEvents: row.total_events
            };
        }
        return null;
    } catch (err) {
        console.error(`[Get Resume State Error] ${err.message}`);
        return null;
    }
}

/**
 * Update current event ID in job
 * @param {number} jobId - Job ID
 * @param {string} eventId - Current event ID
 * @param {number} eventIndex - Current event index
 */
async function updateCurrentEvent(jobId, eventId, eventIndex) {
    if (!jobId || !pool) return;
    try {
        await pool.query(
            `UPDATE scraper_jobs 
             SET current_event_id = $1, current_event_index = $2
             WHERE id = $3`,
            [eventId, eventIndex, jobId]
        );
    } catch (err) {
        console.error(`[Update Current Event Error] ${err.message}`);
    }
}

async function updateJobStatus(jobId, status, errorMessage = null) {
    if (!jobId || !pool) return;
    try {
        if (status === 'completed') {
            await pool.query(
                `UPDATE scraper_jobs SET status = $1, completed_at = CURRENT_TIMESTAMP, error_message = $2 WHERE id = $3`,
                [status, errorMessage, jobId]
            );
        } else if (status === 'failed' || status === 'error') {
            await pool.query(
                `UPDATE scraper_jobs SET status = 'error', error_message = $1 WHERE id = $2`,
                [errorMessage || 'Unknown error', jobId]
            );
        } else {
            await pool.query(
                `UPDATE scraper_jobs SET status = $1 WHERE id = $2`,
                [status, jobId]
            );
        }
    } catch (err) {
        console.error(`[DB Status Error] ${err.message}`);
    }
}

/**
 * Check if auction is already inserted in database
 * Checks sales table, uploaded_files table, and lots table
 * @param {string} auctionId - Auction ID to check
 * @returns {Promise<boolean>} - True if auction is already inserted
 */
async function isAuctionAlreadyInserted(auctionId) {
    if (!auctionId || !pool) return false;
    try {
        // Check 1: sales table - check if sale exists with this auctionId
        const salesCheck = await pool.query(
            `SELECT s.sale_pk 
             FROM sales s 
             JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk 
             WHERE ah.firm_id = $1 AND s.sale_no = $1 
             LIMIT 1`,
            [auctionId]
        );
        if (salesCheck.rows.length > 0) {
            return true;
        }

        // Check 2: uploaded_files table - check if file is marked as completed
        const fileName = `auction_${auctionId}_lots.json`;
        const uploadedCheck = await pool.query(
            `SELECT status FROM uploaded_files WHERE file_name = $1 AND status = 'Completed' LIMIT 1`,
            [fileName]
        );
        if (uploadedCheck.rows.length > 0) {
            return true;
        }

        // Check 3: lots table - check if lots exist for this sale
        const lotsCheck = await pool.query(
            `SELECT COUNT(*) as lot_count 
             FROM lots l 
             JOIN sales s ON l.lot_sale_fk = s.sale_pk 
             JOIN auction_houses ah ON s.sale_firm_fk = ah.firm_pk 
             WHERE ah.firm_id = $1 AND s.sale_no = $1`,
            [auctionId]
        );
        if (lotsCheck.rows.length > 0 && parseInt(lotsCheck.rows[0].lot_count) > 0) {
            return true;
        }

        return false;
    } catch (err) {
        console.error(`[DB Check Error] ${err.message}`);
        // On error, return false to allow processing (fail-safe)
        return false;
    }
}

// Initialize job statistics if jobId is provided
let jobStats = {
    totalEvents: 0,
    processedEvents: 0,
    totalLots: 0,
    processedLots: 0,
    filesCreated: 0,
    filesCompleted: 0
};

// Load .env if present
try { require('dotenv').config({ path: path.join(__dirname, '.env') }); } catch (_) {}

const eventIdsFile = process.env.EVENT_IDS_FILE
  ? path.isAbsolute(process.env.EVENT_IDS_FILE)
    ? process.env.EVENT_IDS_FILE
    : path.join(__dirname, process.env.EVENT_IDS_FILE)
  : path.join(__dirname, 'eventIds.json');

const inProgressFolder = process.env.INPROGRESS_DIR
  ? (path.isAbsolute(process.env.INPROGRESS_DIR)
      ? process.env.INPROGRESS_DIR
      : path.join(__dirname, process.env.INPROGRESS_DIR))
  : path.join(__dirname, 'allAuctionLotsData_inprogress');

const finalFolder = process.env.FINAL_DIR
  ? (path.isAbsolute(process.env.FINAL_DIR)
      ? process.env.FINAL_DIR
      : path.join(__dirname, process.env.FINAL_DIR))
  : path.join(__dirname, 'allAuctionLotsData_final');

// Ensure directories exist
if (!fs.existsSync(inProgressFolder)) {
    fs.mkdirSync(inProgressFolder, { recursive: true });
    log(`Created in-progress folder: ${inProgressFolder}`);
}
if (!fs.existsSync(finalFolder)) {
    fs.mkdirSync(finalFolder, { recursive: true });
    log(`Created final folder: ${finalFolder}`);
}

// Add process-level error handlers
process.on('uncaughtException', (err) => {
    console.error('[UNCAUGHT EXCEPTION]', err.message);
    console.error('[UNCAUGHT EXCEPTION] Stack:', err.stack);
    if (jobId && pool) {
        // Try to log to database, but don't wait (might hang)
        logToDatabase(jobId, 'error', `Uncaught exception: ${err.message}`, 'scraper', { error: err.message, stack: err.stack }).catch(() => {});
    }
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('[UNHANDLED REJECTION]', reason);
    if (jobId && pool) {
        logToDatabase(jobId, 'error', `Unhandled rejection: ${reason}`, 'scraper', { error: String(reason) }).catch(() => {});
    }
});

(async () => {
    let browser;
    try {
        console.log('[MAIN] Entering main async function...');
        console.log('[MAIN] Job ID:', jobId);
        console.log('[MAIN] Pool available:', !!pool);
        
        // Initialize job if jobId is provided
        let resumeState = null;
        let startEventIndex = 0;
        
        if (jobId) {
            console.log('[MAIN] Attempting to log to database...');
            // Immediately log that script started
            await logToDatabase(jobId, 'info', 'Script process started - initializing...', 'scraper');
            console.log('[MAIN] Database log successful');
            
            // Check for resume state from database
            const stateData = await getResumeState(jobId);
            if (stateData && stateData.resumeState) {
                resumeState = stateData.resumeState;
                startEventIndex = resumeState.eventIndex || 0;
                log(`📋 Resuming from saved state: event index ${startEventIndex}, eventId: ${resumeState.eventId || 'N/A'}`, 'info');
                await logToDatabase(jobId, 'info', `Resuming from saved state: event index ${startEventIndex}`, 'scraper', resumeState);
            }
            
            await updateJobStatus(jobId, 'running');
            await logToDatabase(jobId, 'info', resumeState ? 'Scraper resumed' : 'Scraper started', 'scraper');
            await logToDatabase(jobId, 'info', 'Starting browser and navigating to NumisBids...', 'scraper');
        }
        const executablePath = (process.env.CHROME_PATH || '').trim() ? process.env.CHROME_PATH : undefined;
        if (jobId) await logToDatabase(jobId, 'info', 'Launching browser...', 'scraper');
        browser = await puppeteer.launch({ 
            headless: true,
            executablePath,
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });
        if (jobId) await logToDatabase(jobId, 'info', 'Browser launched successfully', 'scraper');

        const mainPage = await browser.newPage();
        await mainPage.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
       
        log('Navigating to NumisBids homepage...');
        if (jobId) await logToDatabase(jobId, 'info', 'Navigating to NumisBids homepage...', 'scraper');
        await mainPage.goto('https://www.numisbids.com/', { timeout: 60000 });
        if (jobId) await logToDatabase(jobId, 'info', 'Homepage loaded, extracting event links...', 'scraper');

        const eventLinks = await mainPage.$$eval(
            'td.firmcell a[href^="/event/"], td.firmcell-e a[href^="/event/"]',
            links => [...new Set(links.map(link => 'https://www.numisbids.com' + link.getAttribute('href')))]
        );

        log(`Found ${eventLinks.length} event links on homepage`);
        if (jobId) await logToDatabase(jobId, 'info', `Found ${eventLinks.length} event links on homepage`, 'scraper', { eventLinksCount: eventLinks.length });
        console.log(eventLinks);
        
        const saleLinks = [];

        // Step 2: Loop through each event link
        if (jobId) await logToDatabase(jobId, 'info', `Processing ${eventLinks.length} event links to find sale URLs...`, 'scraper');
        let processedCount = 0;
        for (const eventUrl of eventLinks) {
            try {
                processedCount++;
                if (jobId && processedCount % 10 === 0) {
                    await logToDatabase(jobId, 'info', `Processing event links: ${processedCount}/${eventLinks.length}...`, 'scraper', { processed: processedCount, total: eventLinks.length });
                }
                console.log(`🔄 Processing: ${eventUrl} (${processedCount}/${eventLinks.length})`);

                // Go to event page (which usually redirects to sale page)
                const eventPage = await browser.newPage();
                await eventPage.goto(eventUrl, { waitUntil: 'domcontentloaded' });

                // Step 3: Wait for a known sale pattern or find redirected sale URL
                const redirectedUrl = eventPage.url(); // after redirection
                if (redirectedUrl.includes('/sale/')) {
                    console.log(`➡️ Found sale URL: ${redirectedUrl}`);
                    saleLinks.push(redirectedUrl);
                } else {
                    // Optionally, try to extract sale link from DOM if not redirected
                    const possibleSaleLink = await eventPage.$eval('a[href*="/sale/"]', a => a.href).catch(() => null);
                    if (possibleSaleLink) {
                        console.log(`🔍 Extracted sale URL from DOM: ${possibleSaleLink}`);
                        saleLinks.push(possibleSaleLink);
                    } else {
                        console.log(`⚠️ Sale link not found for: ${eventUrl}`);
                    }
                }

                await eventPage.close();
            } catch (err) {
                console.log(`❌ Error processing ${eventUrl}: ${err.message}`);
            }
        }

        console.log(`🎯 Total sale links found: ${saleLinks.length}`);
        if (jobId) await logToDatabase(jobId, 'info', `Found ${saleLinks.length} sale links from ${eventLinks.length} event links`, 'scraper', { saleLinksCount: saleLinks.length, eventLinksCount: eventLinks.length });
        console.log(saleLinks);

        let filteredEventLinks = [];

        // Log mode detection
        console.log(`[MODE] targetEventId: ${targetEventId || 'null/empty'}, runMode: All Events`);
        if (jobId) await logToDatabase(jobId, 'info', `Mode: All Events (targetEventId: ${targetEventId || 'none'})`, 'scraper');

        if (targetEventId) {
            const eventMatch = eventLinks.filter(link => link.includes(`/event/${targetEventId}`));
            const saleMatch = saleLinks.filter(link => link.includes(`/sale/${targetEventId}`));

            if (eventMatch.length > 0) {
                filteredEventLinks = eventMatch;
                log(`✅ Found ${eventMatch.length} event link(s) matching Event ID ${targetEventId}`, 'success');
            } else if (saleMatch.length > 0) {
                filteredEventLinks = saleMatch;
                log(`✅ Found ${saleMatch.length} sale link(s) matching Sale ID ${targetEventId}`, 'success');
            } else {
                // Neither found — fallback to try direct event and sale URLs
                log(`⚠️ ID ${targetEventId} not found in eventLinks or saleLinks, trying direct URL...`, 'warning');
                
                const directEventUrl = `https://www.numisbids.com/event/${targetEventId}`;
                const directSaleUrl = `https://www.numisbids.com/sale/${targetEventId}`;
                
                // Try both URLs in order
                filteredEventLinks = [directEventUrl, directSaleUrl];
            }
        } else {
            // All events mode - use all sale links
            filteredEventLinks = saleLinks;
            log(`📋 Processing all ${saleLinks.length} auctions from homepage`, 'info');
        }

        console.log(`filteredEventLinks ${filteredEventLinks}` );

        // Update statistics after filtering
        if (jobId) {
            jobStats.totalEvents = filteredEventLinks.length > 0 ? filteredEventLinks.length : eventLinks.length;
            await updateJobStatistics(jobId, jobStats);
            await logToDatabase(jobId, 'info', `Found ${eventLinks.length} event links, ${saleLinks.length} sale links, ${filteredEventLinks.length} to process`, 'scraper');
            // Update current event to show we're in discovery phase
            await pool.query(
                `UPDATE scraper_jobs SET current_event_id = 'Discovering auctions...', current_event_index = 0 WHERE id = $1`,
                [jobId]
            );
        }

        const newEventObjects = [];
        if (jobId) await logToDatabase(jobId, 'info', `Extracting auction details from ${filteredEventLinks.length} sale links...`, 'scraper', { totalLinks: filteredEventLinks.length });
        
        let extractedCount = 0;
        const startTime = Date.now();
        
        for (const eventLink of filteredEventLinks) {
            extractedCount++;
            
            // Update progress more frequently (every 2 auctions instead of 5)
            if (jobId) {
                if (extractedCount % 2 === 0 || extractedCount === 1) {
                    const elapsed = Math.round((Date.now() - startTime) / 1000);
                    const avgTimePerAuction = elapsed / extractedCount;
                    const remaining = Math.round(avgTimePerAuction * (filteredEventLinks.length - extractedCount));
                    await logToDatabase(jobId, 'info', `Extracting auction details: ${extractedCount}/${filteredEventLinks.length} (est. ${remaining}s remaining)...`, 'scraper', { 
                        extracted: extractedCount, 
                        total: filteredEventLinks.length,
                        elapsed: elapsed,
                        remaining: remaining
                    });
                }
                
                // Update current event ID to show which auction is being processed
                const linkMatch = eventLink.match(/\/sale\/(\d+)/);
                if (linkMatch) {
                    await pool.query(
                        `UPDATE scraper_jobs SET current_event_id = $1 WHERE id = $2`,
                        [`Extracting details: ${extractedCount}/${filteredEventLinks.length} (Auction ${linkMatch[1]})`, jobId]
                    );
                }
            }
            
            const eventPage = await browser.newPage();
            try {
                await eventPage.goto(eventLink, { waitUntil: 'domcontentloaded' });

                const redirectedUrl = eventPage.url();
                const match = redirectedUrl.match(/\/sale\/(\d+)/);

                if (match) {
                    const eventId = match[1];
                    const saleUrl = `https://www.numisbids.com/sale/${eventId}`;
                    const auctionName = await eventPage.$eval('.text .name', el => el.textContent.trim()).catch(() => 'Unknown');
                    
                    // sale info
                    const saleInfo = await eventPage.$eval('.salestatus', (el) => {
                        const logoImg = el.querySelector('img');
                        const logoSrc = logoImg?.getAttribute('src') || '';
                        const logoFullUrl = logoSrc.startsWith('//') ? `https:${logoSrc}` : logoSrc;

                        const saleTextEl = el.querySelector('.text');
                        let saleNumber = null;

                        if (saleTextEl) {
                            const boldText = saleTextEl.querySelector('b')?.innerText || '';
                            const match = boldText.match(/(\d+)$/);
                            saleNumber = match ? match[1] : null;
                        }

                        return {
                            saleLogo: logoFullUrl,
                            saleNumber: saleNumber
                        };
                    });

                    // sale name - use shorter timeout and better error handling
                    const saleInfoHref = await eventPage.$eval('a.saleinfopopup.saleinfo', el => el.getAttribute('href')).catch(() => null);
                    let extractedSaleName = 'Unknown Sale Name';
                    
                    if (saleInfoHref) {
                        const saleInfoUrl = `https://www.numisbids.com${saleInfoHref}`;
                        const saleInfoPage = await browser.newPage();
                        try {
                            await saleInfoPage.goto(saleInfoUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
                            extractedSaleName = await saleInfoPage.evaluate(() => {
                                const headers = Array.from(document.querySelectorAll('div[style*="background: lightgray"]'));
                                for (const header of headers) {
                                    const title = header.innerText.trim();
                                    if (title.includes('Auction Location, Timetable')) {
                                        const indentDiv = header.nextElementSibling;
                                        if (indentDiv && indentDiv.classList.contains('indent')) {
                                            const firstP = indentDiv.querySelector('p');
                                            if (firstP) {
                                                return firstP.innerText.split('\n')[0].trim();
                                            }
                                        }
                                    }
                                }
                                return 'Unknown Sale Name';
                            });
                        } catch (err) {
                            console.warn(`Failed to extract sale name for ${eventId}: ${err.message}`);
                            if (jobId) {
                                await logToDatabase(jobId, 'warning', `Failed to extract sale name for auction ${eventId}: ${err.message}`, 'scraper');
                            }
                        } finally {
                            await saleInfoPage.close();
                        }
                    }

                    // contact info - use shorter timeout and better error handling
                    const firmHref = await eventPage.$eval('.salestatus a.firminfopopup', el => el.getAttribute('href')).catch(() => null);
                    let contact = {
                        firmName: '',
                        address: '',
                        phone: '',
                        fax: '',
                        tollFree: '',
                        email: '',
                        website: ''
                    };
                    
                    if (firmHref) {
                        const firmUrl = `https://www.numisbids.com${firmHref}`;
                        const firmPage = await browser.newPage();
                        try {
                            await firmPage.goto(firmUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
                            const contactDetails = await firmPage.$eval('.indent', el => el.innerText.trim()).catch(() => '');
                            const contactHtml = await firmPage.$eval('.indent', el => el.innerHTML).catch(() => '');
                            
                            const lines = contactDetails.split('\n').map(line => line.trim()).filter(Boolean);

                            for (const line of lines) {
                                const lowerLine = line.toLowerCase();
                                if (!contact.phone && /(ph|phone|tel|mobile|call)/.test(lowerLine)) contact.phone = line;
                                if (!contact.fax && /fx|fax/.test(lowerLine)) contact.fax = line;
                                if (!contact.tollFree && lowerLine.includes('toll')) contact.tollFree = line;
                                if (!contact.email && line.includes('@')) contact.email = line;
                                if (!contact.website && line.includes('http')) contact.website = line;
                            }

                            if (!contact.website) {
                                const match = contactHtml.match(/<a[^>]*href=["'](https?:\/\/[^"']+)["']/i);
                                if (match) contact.website = match[1];
                            }

                            contact.firmName = lines[0] || '';
                            contact.address = lines.slice(1, 3).join(', ');
                        } catch (err) {
                            console.warn(`Failed to extract contact info for ${eventId}: ${err.message}`);
                            if (jobId) {
                                await logToDatabase(jobId, 'warning', `Failed to extract contact info for auction ${eventId}: ${err.message}`, 'scraper');
                            }
                        } finally {
                            await firmPage.close();
                        }
                    }

                    // Add to new event object
                    const newObj = {
                        number: newEventObjects.length + 1,
                        eventId,
                        eventUrl: saleUrl,
                        eventName: auctionName,
                        extractedSaleName,
                        contact,
                        saleInfo
                    };

                    newEventObjects.push(newObj);
                    console.log(`✅ ${newEventObjects.length} Found event ID: ${eventId} → Name : ${auctionName} → Url : ${saleUrl}`);
                }
            } catch (err) {
                console.warn(`❌ Failed to process ${eventLink}: ${err.message}`);
                if (jobId) {
                    await logToDatabase(jobId, 'warning', `Failed to process ${eventLink}: ${err.message}`, 'scraper');
                }
            } finally {
                await eventPage.close();
            }
        }

        fs.writeFileSync(eventIdsFile, JSON.stringify(newEventObjects, null, 2));
        console.log(`\n✅ Total new event IDs saved: ${newEventObjects.length}\n`);
        if (jobId) await logToDatabase(jobId, 'info', `Extracted ${newEventObjects.length} auction details, saved to eventIds.json`, 'scraper', { totalAuctions: newEventObjects.length });

        // Validate that we have events to process
        if (newEventObjects.length === 0) {
            log('⚠️ No events to process after extraction. Exiting.', 'warning');
            if (jobId) {
                await logToDatabase(jobId, 'warning', 'No events to process after extraction', 'scraper');
                await updateJobStatus(jobId, 'completed');
            }
            await browser.close();
            process.exit(0);
        }

        // Get total events count for progress tracking
        const totalEventsCount = newEventObjects.length;
        if (jobId) {
            await pool.query(
                `UPDATE scraper_jobs SET total_events = $1 WHERE id = $2`,
                [totalEventsCount, jobId]
            );
            await logToDatabase(jobId, 'info', `Ready to process ${totalEventsCount} auctions`, 'scraper', { totalEvents: totalEventsCount });
        }

        // Start from resume state if available, otherwise start from beginning
        let startIndex = resumeState ? (resumeState.eventIndex || 0) : 0;
        
        // Check if there are any in-progress files that need to be completed first
        // This ensures we complete partially scraped auctions before moving to new ones
        log('🔍 Checking for incomplete auctions to complete first...', 'info');
        if (jobId) await logToDatabase(jobId, 'info', 'Checking for incomplete auctions to complete first...', 'scraper');
        for (let checkIndex = 0; checkIndex < newEventObjects.length; checkIndex++) {
            const { eventId: checkAuctionId } = newEventObjects[checkIndex];
            const checkInProgressFile = path.join(inProgressFolder, `auction_${checkAuctionId}_lots.jsonl`);
            const checkFinalFile = path.join(finalFolder, `auction_${checkAuctionId}_lots.json`);
            
            // If there's an in-progress file but no final file, start from this auction
            // Don't check database here - if in-progress file exists, it needs to be completed
            if (fs.existsSync(checkInProgressFile) && !fs.existsSync(checkFinalFile)) {
                startIndex = checkIndex;
                log(`📋 Found in-progress file for auction ${checkAuctionId}, will complete it first (starting from index ${startIndex})`, 'info');
                if (jobId) {
                    await logToDatabase(jobId, 'info', `Found in-progress auction ${checkAuctionId}, will complete it first`, 'scraper', { auctionId: checkAuctionId, startIndex });
                }
                break; // Found the first incomplete auction, start from here
            }
        }
        
        log(`🚀 Starting from event index ${startIndex} (total events: ${newEventObjects.length})`, 'info');
        if (jobId) {
            await logToDatabase(jobId, 'info', `Starting processing from event index ${startIndex} of ${newEventObjects.length}`, 'scraper', { startIndex, totalEvents: newEventObjects.length });
            // Update to show we're ready to start scraping
            if (newEventObjects.length > 0 && startIndex < newEventObjects.length) {
                const firstAuction = newEventObjects[startIndex];
                await pool.query(
                    `UPDATE scraper_jobs SET current_event_id = $1, current_event_index = $2 WHERE id = $3`,
                    [firstAuction.eventId || 'Starting...', startIndex, jobId]
                );
            }
        }
        
        // Log that we're about to start the main processing loop
        log(`📊 Beginning main processing loop for ${newEventObjects.length - startIndex} auctions...`, 'info');
        if (jobId) await logToDatabase(jobId, 'info', `Beginning main processing loop for ${newEventObjects.length - startIndex} auctions`, 'scraper', { remainingAuctions: newEventObjects.length - startIndex });
        
        for (let eventIndex = startIndex; eventIndex < newEventObjects.length; eventIndex++) {
            // CRITICAL: Check if job is paused or stopped before processing each event
            if (jobId) {
                const jobStatus = await checkJobStatus(jobId);
                if (jobStatus.isStopped) {
                    log(`Job stopped. Exiting at event index ${eventIndex}`, 'warning');
                    await logToDatabase(jobId, 'info', `Job stopped at event index ${eventIndex}`, 'system');
                    await browser.close();
                    await updateJobStatus(jobId, 'stopped');
                    process.exit(0);
                }
                if (jobStatus.isPaused) {
                    log(`Job paused. Saving state at event index ${eventIndex}`, 'warning');
                    const currentEvent = newEventObjects[eventIndex];
                    await saveResumeState(jobId, currentEvent?.eventId || '', '', eventIndex, {
                        totalEvents: newEventObjects.length,
                        currentEventIndex: eventIndex
                    });
                    await logToDatabase(jobId, 'info', `Job paused at event index ${eventIndex}`, 'system');
                    await browser.close();
                    process.exit(0);
                }
            }

            // Validate event object
            const eventObj = newEventObjects[eventIndex];
            if (!eventObj || !eventObj.eventId) {
                log(`⚠️ Invalid event object at index ${eventIndex}, skipping...`, 'warning');
                if (jobId) {
                    await logToDatabase(jobId, 'warning', `Invalid event object at index ${eventIndex}, skipping`, 'scraper', { eventIndex });
                }
                continue;
            }

            const { eventId: auctionId, contact, saleInfo, extractedSaleName, eventName: auctionName } = eventObj;

            // Validate required fields
            if (!auctionId) {
                log(`⚠️ Missing eventId at index ${eventIndex}, skipping...`, 'warning');
                if (jobId) {
                    await logToDatabase(jobId, 'warning', `Missing eventId at index ${eventIndex}, skipping`, 'scraper', { eventIndex });
                }
                continue;
            }

            const inProgressFile = path.join(inProgressFolder, `auction_${auctionId}_lots.jsonl`);
            const finalFile = path.join(finalFolder, `auction_${auctionId}_lots.json`);

            // Priority 1: Check final file first - if exists, auction is complete, skip it
            if (fs.existsSync(finalFile)) {
                console.log(`⏭ Skipping auction ${auctionId} (already in final file - complete)`);
                if (jobId) {
                    jobStats.processedEvents++;
                    jobStats.filesCompleted++;
                    await updateJobStatistics(jobId, jobStats);
                    await updateCurrentEvent(jobId, auctionId, eventIndex);
                    await logToDatabase(jobId, 'info', `Skipped auction ${auctionId} - already in final file (complete)`, 'scraper', { auctionId });
                }
                continue;
            }

            // Priority 2: If in-progress file exists but no final file, continue (incomplete auction)
            if (fs.existsSync(inProgressFile)) {
                console.log(`📋 Found in-progress file for auction ${auctionId}, will continue scraping...`);
                if (jobId) {
                    await logToDatabase(jobId, 'info', `Found in-progress file for auction ${auctionId}, continuing...`, 'scraper', { auctionId });
                }
                // Don't skip - continue to process this auction
            }

            // Priority 3: Check database only if no files exist - but be more strict
            // Only skip if uploaded_files says Completed (meaning it was fully processed)
            if (!fs.existsSync(inProgressFile) && !fs.existsSync(finalFile)) {
                const fileName = `auction_${auctionId}_lots.json`;
                try {
                    const uploadedCheck = await pool.query(
                        `SELECT status FROM uploaded_files WHERE file_name = $1 AND status = 'Completed' LIMIT 1`,
                        [fileName]
                    );
                    if (uploadedCheck.rows.length > 0) {
                        console.log(`⏭ Skipping auction ${auctionId} (marked as Completed in uploaded_files)`);
                        if (jobId) {
                            jobStats.processedEvents++;
                            jobStats.filesCompleted++;
                            await updateJobStatistics(jobId, jobStats);
                            await updateCurrentEvent(jobId, auctionId, eventIndex);
                            await logToDatabase(jobId, 'info', `Skipped auction ${auctionId} - marked as Completed in database`, 'scraper', { auctionId });
                        }
                        continue;
                    }
                } catch (dbErr) {
                    // If database check fails, continue processing (fail-safe)
                    console.warn(`Database check failed for ${auctionId}, continuing...`);
                }
            }

            // Update current event ID
            if (jobId) {
                await updateCurrentEvent(jobId, auctionId, eventIndex);
                jobStats.filesCreated++;
                await updateJobStatistics(jobId, jobStats);
                await logToDatabase(jobId, 'info', `Processing auction ${auctionId}: ${auctionName || 'Unknown'}`, 'scraper', { auctionId, auctionName: auctionName || 'Unknown' });
            }

            // Extract auction metadata from page FIRST (before processing existing lots)
            const page = await browser.newPage();
            const baseUrl = `https://www.numisbids.com/sale/${auctionId}`;
            let auctionTitle = '';
            let eventDate = '';
            let totalPages = 1;
            let pageAuctionName = auctionName || 'Unknown'; // Use extracted name as fallback

            try {
                await page.goto(baseUrl, { timeout: 60000 });
                const pageMetadata = await page.evaluate(() => {
                    const textDiv = document.querySelector('.text');
                    const auctionName = textDiv?.querySelector('.name')?.textContent.trim() || '';
                    const bTags = textDiv?.querySelectorAll('b');
                    const title = bTags?.[0]?.textContent.trim() || '';
                    const fullHtml = textDiv?.innerHTML || '';
                    const match = fullHtml.match(/<b>.*?<\/b>&nbsp;&nbsp;([^<]+)/);
                    const eventDate = match ? match[1].trim() : '';

                    const pageInfo = document.querySelector('.salenav-top .small')?.textContent || '';
                    const pagesMatch = pageInfo.match(/Page\s+\d+\s+of\s+(\d+)/i);
                    const totalPages = pagesMatch ? parseInt(pagesMatch[1]) : 1;

                    return { auctionName, auctionTitle: `${auctionName}, ${title}`, eventDate, totalPages };
                });
                
                pageAuctionName = pageMetadata.auctionName || auctionName;
                auctionTitle = pageMetadata.auctionTitle || `${auctionName}, Unknown`;
                eventDate = pageMetadata.eventDate || '';
                totalPages = pageMetadata.totalPages || 1;
            } catch (err) {
                console.warn(`⚠️ Failed to extract metadata from page for ${auctionId}: ${err.message}`);
                // Use fallback values
                auctionTitle = `${auctionName}, Unknown`;
                if (jobId) {
                    await logToDatabase(jobId, 'warning', `Failed to extract metadata from page for ${auctionId}: ${err.message}`, 'scraper');
                }
            }

            // Now process existing lots with metadata available
            // Preserve field order to match single event mode: auctionid → loturl → auctionname → auctiontitle → eventdate → ...
            let existingLots = [];
            if (fs.existsSync(inProgressFile)) {
                existingLots = fs.readFileSync(inProgressFile, 'utf-8')
                    .split('\n')
                    .filter(Boolean)
                    .map(line => {
                        const lot = JSON.parse(line);
                        
                        // Reorder fields to match single event mode structure
                        const orderedLot = {
                            auctionid: lot.auctionid && lot.auctionid === String(auctionId) ? lot.auctionid : String(auctionId),
                            loturl: lot.loturl || '',
                            auctionname: lot.auctionname && lot.auctionid === String(auctionId) ? lot.auctionname : pageAuctionName,
                            auctiontitle: lot.auctiontitle && lot.auctionid === String(auctionId) ? lot.auctiontitle : auctionTitle,
                            eventdate: lot.eventdate && lot.auctionid === String(auctionId) ? lot.eventdate : eventDate,
                            category: lot.category || '',
                            startingprice: lot.startingprice || '',
                            realizedprice: lot.realizedprice || '',
                            imagepath: lot.imagepath || '',
                            fulldescription: lot.fulldescription || '',
                            lotnumber: lot.lotnumber || '',
                            shortdescription: lot.shortdescription || '',
                            lotname: lot.lotname || ''
                        };
                        return orderedLot;
                    });
            }

            const scrapedLotNumbers = new Set(existingLots.map(l => l.lotnumber));
            let allLotsScrapedSuccessfully = true; // ✅ NEW FLAG

            try {

                const allLots = [...existingLots];

                for (let currentPage = 1; currentPage <= totalPages; currentPage++) {
                    const pageUrl = `${baseUrl}?pg=${currentPage}`;
                    console.log(`Auction ${auctionId} — Page ${currentPage}`);
                    await page.goto(pageUrl, { timeout: 60000 });

                    const lotElements = await page.$$('.browse');
                    for (const lot of lotElements) {
                        const lotNumber = await lot.$eval('.lot a', el => el.textContent.trim().replace('Lot ', ''));
                        
                        // Check pause/stop status before processing each lot
                        if (jobId) {
                            const jobStatus = await checkJobStatus(jobId);
                            if (jobStatus.isStopped) {
                                log(`Job stopped. Exiting at event ${auctionId}, lot ${lotNumber}`, 'warning');
                                await logToDatabase(jobId, 'info', `Job stopped at event ${auctionId}, lot ${lotNumber}`, 'system');
                                await browser.close();
                                await updateJobStatus(jobId, 'stopped');
                                process.exit(0);
                            }
                            if (jobStatus.isPaused) {
                                log(`Job paused. Saving state at event ${auctionId}, lot ${lotNumber}`, 'warning');
                                await saveResumeState(jobId, auctionId, lotNumber, eventIndex, {
                                    inProgressFile,
                                    finalFile
                                });
                                await logToDatabase(jobId, 'info', `Job paused at event ${auctionId}, lot ${lotNumber}`, 'system');
                                await browser.close();
                                process.exit(0);
                            }
                        }
                        if (scrapedLotNumbers.has(lotNumber)) {
                            console.log(`  ↪️ Already scraped lot ${lotNumber}, skipping.`);
                            continue;
                        }

                        try {
                            const relativeLotUrl = await lot.$eval('a[href*="/lot/"]', el => el.getAttribute('href'));
                            const prettyLotUrl = 'https://www.numisbids.com' + relativeLotUrl;
                            const lotName = await lot.$eval('.summary a', el => el.textContent.trim());
                            const description = lotName.split('.')[0];
                            const thumbImage = await lot.$eval('img', el => 'https:' + el.getAttribute('src'));
                            const startingPrice = await lot.$eval('.estimate span', el => el.textContent.trim());

                            let realizedPrice = '';
                            try {
                            realizedPrice = await lot.$eval('.realized span', el => el.textContent.trim());
                            } catch (_) {}

                            const detailPage = await browser.newPage();
                            await detailPage.goto(prettyLotUrl, { timeout: 60000 });
                            await detailPage.waitForSelector('.viewlottext .description:last-of-type', { timeout: 10000 }).catch(() => {});
                            await detailPage.waitForSelector('#activecat', { timeout: 10000 }).catch(() => {});

                            const { category, fullDescription, fullImage } = await detailPage.evaluate(() => {
                            const activeCat = document.querySelector('#activecat span a:last-of-type');
                            const rawCategory = activeCat ? activeCat.textContent.trim() : '';
                            const category = rawCategory.replace(/^[A-Z]\.\s*/, '').replace(/\s*\(\d+\)\s*$/, '').trim();

                            const descEl = document.querySelector('.viewlottext > .description:last-of-type');
                            let fullDesc = '';
                            if (descEl) {
                                fullDesc = descEl.innerHTML.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').trim();
                            }

                            const img = document.querySelector('.viewlotimg img')?.getAttribute('src');
                            const fullImage = img ? 'https:' + img : '';

                            return { category, fullDescription: fullDesc, fullImage };
                            });

                            await detailPage.close();

                            const lotData = {
                            auctionid: String(auctionId),
                            loturl: prettyLotUrl,
                            auctionname: pageAuctionName,
                            auctiontitle: auctionTitle,
                            eventdate: eventDate,
                            category,
                            startingprice: startingPrice,
                            realizedprice: realizedPrice,
                            imagepath: fullImage || thumbImage,
                            fulldescription: fullDescription,
                            lotnumber: lotNumber,
                            shortdescription: lotName,
                            lotname: description
                            };

                            fs.appendFileSync(inProgressFile, JSON.stringify(lotData) + '\n');
                            allLots.push(lotData);
                            scrapedLotNumbers.add(lotNumber);

                            // Real-time insertion: Insert lot immediately to database
                            if (insertLotFunctions && jobId) {
                                try {
                                    const eventData = {
                                        auctionid: auctionId,
                                        auctionname: pageAuctionName,
                                        auctiontitle: auctionTitle,
                                        eventdate: eventDate,
                                        contact,
                                        saleInfo,
                                        extractedSaleName
                                    };
                                    
                                    const insertResult = await insertLotFunctions.processLotInRealTime(lotData, eventData, true);
                                    if (insertResult.success) {
                                        jobStats.processedLots++;
                                        console.log(`✅ Inserted lot ${lotNumber} to database (lot_pk: ${insertResult.lotPk})`);
                                    } else {
                                        console.warn(`⚠️ Failed to insert lot ${lotNumber}: ${insertResult.error}`);
                                        await logToDatabase(jobId, 'warning', `Failed to insert lot ${lotNumber}: ${insertResult.error}`, 'scraper', { lotNumber, error: insertResult.error });
                                    }
                                } catch (insertErr) {
                                    console.warn(`⚠️ Error inserting lot ${lotNumber}: ${insertErr.message}`);
                                    await logToDatabase(jobId, 'warning', `Error inserting lot ${lotNumber}: ${insertErr.message}`, 'scraper', { lotNumber, error: insertErr.message });
                                }
                            }

                            // Save resume state and update statistics after each lot (real-time)
                            if (jobId) {
                                // Update current lot number in job
                                await pool.query(
                                    `UPDATE scraper_jobs 
                                     SET current_lot_number = $1, current_event_id = $2
                                     WHERE id = $3`,
                                    [lotNumber, auctionId, jobId]
                                );
                                
                                // Update statistics after each lot for real-time monitoring
                                jobStats.processedLots = allLots.length;
                                await updateJobStatistics(jobId, jobStats);
                                
                                // Save resume state
                                await saveResumeState(jobId, auctionId, lotNumber, eventIndex, {
                                    inProgressFile,
                                    finalFile,
                                    lotsScraped: allLots.length
                                });
                                
                                // Log every 5 lots for activity feed
                                if (allLots.length % 5 === 0) {
                                    await logToDatabase(jobId, 'info', `Scraped ${allLots.length} lots from event ${auctionId}`, 'scraper', { 
                                        eventId: auctionId, 
                                        lotsScraped: allLots.length,
                                        currentLot: lotNumber 
                                    });
                                }
                            }

                            console.log(`✅ Scraped lot ${lotNumber} - ${prettyLotUrl}`);
                        } catch (err) {
                            allLotsScrapedSuccessfully = false; // ❗ Mark failure
                            console.warn(`❌ Error scraping lot: ${err.message}`);
                            
                            // On error, pause job and save state for resume
                            if (jobId) {
                                try {
                                    await updateJobStatus(jobId, 'paused');
                                    await saveResumeState(jobId, auctionId, lotNumber, eventIndex, {
                                        inProgressFile,
                                        finalFile,
                                        error: err.message,
                                        errorStack: err.stack
                                    });
                                    await logToDatabase(jobId, 'error', `Error scraping lot ${lotNumber}: ${err.message}. Job paused.`, 'scraper', { 
                                        lotNumber, 
                                        eventId: auctionId, 
                                        error: err.message 
                                    });
                                    await browser.close();
                                    process.exit(0);
                                } catch (pauseErr) {
                                    console.error(`Failed to pause job on error: ${pauseErr.message}`);
                                }
                            }
                        }
                    }
                }
                if (allLotsScrapedSuccessfully) {
                    // Sort all lots by lot number before saving
                    allLots.sort((a, b) => {
                    const numA = parseInt(a.lotnumber.replace(/\D/g, ''), 10);
                    const numB = parseInt(b.lotnumber.replace(/\D/g, ''), 10);
                    return numA - numB;
                    });
                    const finalData = {
                    auctionid: auctionId,
                    auctionname: auctionName,
                    auctiontitle: auctionTitle,
                    eventdate: eventDate,
                    extractedSaleName,
                    contact,
                    saleInfo,
                    lots: allLots
                    };
                    
                    fs.writeFileSync(finalFile, JSON.stringify(finalData, null, 2));
                    if (fs.existsSync(inProgressFile)) fs.unlinkSync(inProgressFile);
                    console.log(`✅ Auction ${auctionId} finished → saved to final folder\n`);
                    
                    // Update statistics
                    if (jobId) {
                        jobStats.processedEvents++;
                        jobStats.processedLots += allLots.length;
                        jobStats.filesCompleted++;
                        jobStats.totalLots += allLots.length;
                        await updateJobStatistics(jobId, jobStats);
                        await logToDatabase(jobId, 'info', `Completed auction ${auctionId}: ${allLots.length} lots`, 'scraper', { auctionId, lotsCount: allLots.length });
                    }
                } else {
                    console.warn(`⚠️ Auction ${auctionId} not fully scraped — kept in in-progress folder\n`);
                    if (jobId) {
                        await logToDatabase(jobId, 'warning', `Auction ${auctionId} partially scraped`, 'scraper', { auctionId });
                    }
                }

            } catch (err) {
                console.error(`❌ Failed auction ${auctionId}: ${err.message}`);
                if (jobId) {
                    // Check if job was stopped before pausing on error
                    const jobStatus = await checkJobStatus(jobId);
                    if (jobStatus.isStopped) {
                        await logToDatabase(jobId, 'info', `Job stopped after error on auction ${auctionId}`, 'scraper', { auctionId, error: err.message });
                        await browser.close();
                        await updateJobStatus(jobId, 'stopped');
                        process.exit(0);
                    }
                    // Pause job on error and save state
                    try {
                        await updateJobStatus(jobId, 'paused');
                        await saveResumeState(jobId, auctionId, null, eventIndex, {
                            inProgressFile,
                            finalFile,
                            error: err.message,
                            errorStack: err.stack
                        });
                        await logToDatabase(jobId, 'error', `Failed auction ${auctionId}: ${err.message}. Job paused.`, 'scraper', { auctionId, error: err.message });
                        await browser.close();
                        process.exit(0);
                    } catch (pauseErr) {
                        console.error(`Failed to pause job on error: ${pauseErr.message}`);
                        await logToDatabase(jobId, 'error', `Failed auction ${auctionId}: ${err.message}`, 'scraper', { auctionId, error: err.message });
                    }
                }
            }

            await page.close();
        }
        
        // Final statistics update and job completion
        if (jobId) {
            await updateJobStatistics(jobId, jobStats);
            await updateJobStatus(jobId, 'completed');
            await logToDatabase(jobId, 'info', 'Scraping completed successfully', 'scraper', { 
                totalEvents: jobStats.totalEvents,
                processedEvents: jobStats.processedEvents,
                totalLots: jobStats.totalLots,
                processedLots: jobStats.processedLots
            });
        }
        
        log('Scraping completed successfully!', 'success');
    } catch (err) {
        log(`Fatal error: ${err.message}`, 'error');
        if (jobId) {
            await updateJobStatus(jobId, 'failed', err.message);
            await logToDatabase(jobId, 'error', `Fatal error: ${err.message}`, 'scraper', { error: err.message, stack: err.stack });
        }
        process.exit(1);
    } finally {
        if (browser) {
            await browser.close();
            log('Browser closed');
        }
        // Close database connection
        if (pool) {
            await pool.end();
        }
    }
})();
