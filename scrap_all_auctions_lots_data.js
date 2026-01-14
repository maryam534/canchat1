const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');
const pool = require('./dbConfig');
// Import real-time insertion functions
let insertLotFunctions = null;
try {
  insertLotFunctions = require('./insert_lots_into_db');
} catch (err) {
  console.warn('[Warning] Could not load insert_lots_into_db module. Real-time insertion disabled.');
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
let maxSales = null;
let targetEventId = null;
let outputFile = null;
let resume = false;
let lastLot = null;
let jobId = null;

// Parse arguments
for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--max-sales=')) {
        maxSales = parseInt(args[i].split('=')[1]);
    } else if (args[i] === '--max-sales' && i + 1 < args.length) {
        maxSales = parseInt(args[i + 1]);
        i++;
    } else if (args[i].startsWith('--event-id=')) {
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
  --max-sales <number>    Limit the number of sales to process (for testing)
  --event-id <id>         Process only a specific event ID
  --output-file <name>    Specify output file name
  --job-id <id>           Database job ID for status tracking
  --resume                Resume from existing in-progress file
  --last-lot <number>     Resume from specific lot number
  --help, -h              Show this help message

Examples:
  node scrap_all_auctions_lots_data.js --max-sales 2
  node scrap_all_auctions_lots_data.js --event-id 9537
  node scrap_all_auctions_lots_data.js --resume --last-lot 100
  node scrap_all_auctions_lots_data.js --output-file "auction_9537_lots.jsonl"
  node scrap_all_auctions_lots_data.js --job-id 5 --max-sales 2
        `);
        process.exit(0);
    }
}

log(`🚀 Starting scraper with options:`);
if (jobId) log(`   Job ID: ${jobId}`);
if (maxSales) log(`   Max sales: ${maxSales}`);
if (targetEventId) log(`   Target event ID: ${targetEventId}`);
if (outputFile) log(`   Output file: ${outputFile}`);
if (resume) log(`   Resume mode: enabled`);
if (lastLot) log(`   Resume from lot: ${lastLot}`);
if (!maxSales && !targetEventId) log(`   Processing all available sales`);

// Database status tracking functions
async function logToDatabase(jobId, level, message, source = 'scraper', metadata = {}) {
    if (!jobId) return;
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
    if (!jobId) return;
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
            // Insert new record
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
 * Check if job is paused
 * @param {number} jobId - Job ID
 * @returns {Promise<boolean>} - True if job is paused
 */
async function checkPauseStatus(jobId) {
    if (!jobId) return false;
    try {
        const result = await pool.query(
            `SELECT status FROM scraper_jobs WHERE id = $1`,
            [jobId]
        );
        return result.rows.length > 0 && result.rows[0].status === 'paused';
    } catch (err) {
        console.error(`[Pause Check Error] ${err.message}`);
        return false;
    }
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
    if (!jobId) return;
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
    if (!jobId) return null;
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
    if (!jobId) return;
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
    if (!jobId) return;
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

(async () => {
    let browser;
    try {
        // Initialize job if jobId is provided
        if (jobId) {
            await updateJobStatus(jobId, 'running');
            await logToDatabase(jobId, 'info', 'Scraper started', 'scraper');
        }
        const executablePath = (process.env.CHROME_PATH || '').trim() ? process.env.CHROME_PATH : undefined;
        browser = await puppeteer.launch({ 
            headless: true,
            executablePath,
            args: ['--no-sandbox', '--disable-setuid-sandbox']
        });

        const mainPage = await browser.newPage();
        await mainPage.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36');
       
        log('Navigating to NumisBids homepage...');
        await mainPage.goto('https://www.numisbids.com/', { timeout: 60000 });

        const eventLinks = await mainPage.$$eval(
            'td.firmcell a[href^="/event/"], td.firmcell-e a[href^="/event/"]',
            links => [...new Set(links.map(link => 'https://www.numisbids.com' + link.getAttribute('href')))]
        );

        log(`Found ${eventLinks.length} event links on homepage`);
        console.log(eventLinks);
        
        const saleLinks = [];

        // Step 2: Loop through each event link
        for (const eventUrl of eventLinks) {
            try {
                console.log(`🔄 Processing: ${eventUrl}`);

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
        console.log(saleLinks);

        let filteredEventLinks = [];

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
        }

        console.log(`filteredEventLinks ${filteredEventLinks}` );
        // Apply max sales limit
        if (maxSales && filteredEventLinks.length > maxSales) {
            filteredEventLinks = filteredEventLinks.slice(0, maxSales);
            log(`Limiting to ${maxSales} sales for testing`);
        }

        // Update statistics after filtering
        if (jobId) {
            jobStats.totalEvents = filteredEventLinks.length > 0 ? filteredEventLinks.length : eventLinks.length;
            await updateJobStatistics(jobId, jobStats);
            await logToDatabase(jobId, 'info', `Found ${eventLinks.length} event links, ${saleLinks.length} sale links, ${filteredEventLinks.length} to process`, 'scraper');
        }

        const newEventObjects = [];
        // for (const eventLink of filteredEventLinks) {
        for (const eventLink of filteredEventLinks) {
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

                        // Look inside the `.text` section
                        const saleTextEl = el.querySelector('.text');
                        let saleNumber = null;

                        if (saleTextEl) {
                            // Try to find <b> tag and extract number from text
                            const boldText = saleTextEl.querySelector('b')?.innerText || '';
                            const match = boldText.match(/(\d+)$/); // Extract the number at the end
                            saleNumber = match ? match[1] : null;
                        }

                        return {
                            saleLogo: logoFullUrl,
                            saleNumber: saleNumber
                        };
                    });

                    // sale name 
                    const saleInfoHref = await eventPage.$eval('a.saleinfopopup.saleinfo', el => el.getAttribute('href'));
                    const saleInfoUrl = `https://www.numisbids.com${saleInfoHref}`;
                    const saleInfoPage = await browser.newPage();
                    await saleInfoPage.goto(saleInfoUrl, { timeout: 60000 });

                    const extractedSaleName = await saleInfoPage.evaluate(() => {
                        const headers = Array.from(document.querySelectorAll('div[style*="background: lightgray"]'));

                        for (const header of headers) {
                            const title = header.innerText.trim();
                            if (title.includes('Auction Location, Timetable')) {
                                // Get the next .indent div after this header
                                const indentDiv = header.nextElementSibling;
                                if (indentDiv && indentDiv.classList.contains('indent')) {
                                    const firstP = indentDiv.querySelector('p');
                                    if (firstP) {
                                        const firstLine = firstP.innerText.split('\n')[0].trim();
                                        return firstLine;
                                    }
                                }
                            }
                        }

                        return 'Unknown Sale Name';
                    });

                    // contact info 
                    const firmHref = await eventPage.$eval('.salestatus a.firminfopopup', el => el.getAttribute('href'));
                    const firmUrl = `https://www.numisbids.com${firmHref}`;
                    const firmPage = await browser.newPage();
                    await firmPage.goto(firmUrl, { timeout: 60000 });

                    const contactDetails = await firmPage.$eval('.indent', el => el.innerText.trim());
                    const contactHtml = await firmPage.$eval('.indent', el => el.innerHTML);
                    
                    // Split lines
                    const lines = contactDetails.split('\n').map(line => line.trim()).filter(Boolean);

                    let phone = '';
                    let fax = '';
                    let tollFree = '';
                    let email = '';
                    let website = '';

                    // Extract from text lines
                    for (const line of lines) {
                    const lowerLine = line.toLowerCase();

                    if (!phone && /(ph|phone|tel|mobile|call)/.test(lowerLine)) phone = line;
                    if (!fax && /fx|fax/.test(lowerLine)) fax = line;
                    if (!tollFree && lowerLine.includes('toll')) tollFree = line;
                    if (!email && line.includes('@')) email = line;
                    if (!website && line.includes('http')) website = line;
                    }

                    // If website not found from text, try extracting from <a href>
                    if (!website) {
                    const match = contactHtml.match(/<a[^>]*href=["'](https?:\/\/[^"']+)["']/i);
                    if (match) website = match[1];
                    }

                    // Build contact object
                    const contact = {
                    firmName: lines[0] || '',
                    address: lines.slice(1, 3).join(', '),
                    phone,
                    fax,
                    tollFree,
                    email,
                    website
                    };

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
            } finally {
            await eventPage.close();
            }
        }

        fs.writeFileSync(eventIdsFile, JSON.stringify(newEventObjects, null, 2));
        console.log(`\n✅ Total new event IDs saved: ${newEventObjects.length}\n`);

        // Get total events count for progress tracking
        const totalEventsCount = newEventObjects.length;
        if (jobId) {
            await pool.query(
                `UPDATE scraper_jobs SET total_events = $1 WHERE id = $2`,
                [totalEventsCount, jobId]
            );
        }

        for (let eventIndex = 0; eventIndex < newEventObjects.length; eventIndex++) {
            const { eventId: auctionId, contact, saleInfo, extractedSaleName, eventName: auctionName } = newEventObjects[eventIndex];

            const inProgressFile = path.join(inProgressFolder, `auction_${auctionId}_lots.jsonl`);
            const finalFile = path.join(finalFolder, `auction_${auctionId}_lots.json`);

            if (fs.existsSync(finalFile)) {
            console.log(`⏭ Skipping auction ${auctionId} (already in final)`);
            if (jobId) {
                jobStats.processedEvents++;
                jobStats.filesCompleted++;
                await updateJobStatistics(jobId, jobStats);
                await updateCurrentEvent(jobId, auctionId, eventIndex);
            }
            continue;
            }

            // Update current event ID
            if (jobId) {
                await updateCurrentEvent(jobId, auctionId, eventIndex);
                jobStats.filesCreated++;
                await updateJobStatistics(jobId, jobStats);
                await logToDatabase(jobId, 'info', `Processing auction ${auctionId}: ${auctionName}`, 'scraper', { auctionId, auctionName });
            }

            let existingLots = [];
            if (fs.existsSync(inProgressFile)) {
            existingLots = fs.readFileSync(inProgressFile, 'utf-8')
                .split('\n')
                .filter(Boolean)
                .map(line => {
                const lot = JSON.parse(line);
                delete lot.auctionid;
                delete lot.auctionname;
                delete lot.auctiontitle;
                delete lot.eventdate;
                return lot;
                });
            }

            const scrapedLotNumbers = new Set(existingLots.map(l => l.lotnumber));
            const page = await browser.newPage();
            const baseUrl = `https://www.numisbids.com/sale/${auctionId}`;
            let allLotsScrapedSuccessfully = true; // ✅ NEW FLAG

            try {
                await page.goto(baseUrl, { timeout: 60000 });

                    const { auctionName, auctionTitle, eventDate, totalPages } = await page.evaluate(() => {
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

                const allLots = [...existingLots];

                for (let currentPage = 1; currentPage <= totalPages; currentPage++) {
                    const pageUrl = `${baseUrl}?pg=${currentPage}`;
                    console.log(`Auction ${auctionId} — Page ${currentPage}`);
                    await page.goto(pageUrl, { timeout: 60000 });

                    const lotElements = await page.$$('.browse');
                    for (const lot of lotElements) {
                        const lotNumber = await lot.$eval('.lot a', el => el.textContent.trim().replace('Lot ', ''));
                        
                        // Check pause status before processing each lot
                        if (jobId && await checkPauseStatus(jobId)) {
                            log(`Job paused. Saving state at event ${auctionId}, lot ${lotNumber}`, 'warning');
                            await saveResumeState(jobId, auctionId, lotNumber, eventIndex, {
                                inProgressFile,
                                finalFile
                            });
                            await logToDatabase(jobId, 'info', `Job paused at event ${auctionId}, lot ${lotNumber}`, 'system');
                            // Wait in loop until resumed
                            while (await checkPauseStatus(jobId)) {
                                await new Promise(resolve => setTimeout(resolve, 2000)); // Check every 2 seconds
                            }
                            log(`Job resumed. Continuing from event ${auctionId}, lot ${lotNumber}`, 'info');
                            await logToDatabase(jobId, 'info', `Job resumed at event ${auctionId}, lot ${lotNumber}`, 'system');
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
                            loturl: prettyLotUrl,
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
                                        auctionname: auctionName,
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
