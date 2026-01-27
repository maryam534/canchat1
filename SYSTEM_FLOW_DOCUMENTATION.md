
# 📚 System Flow & Functionality Documentation## 📋 Table of Contents1. [System Overview](#system-overview)2. [Complete Scraping Flow](#complete-scraping-flow)3. [Pause/Resume/Stop Functionality](#pauseresumestop-functionality)4. [File Structure & Responsibilities](#file-structure--responsibilities)5. [Database Schema & State Management](#database-schema--state-management)6. [Error Handling & Recovery](#error-handling--recovery)7. [Real-time Monitoring](#real-time-monitoring)---## 🎯 System Overview### Architecture Components**Frontend (User Interface):**- `bulk_processor.cfm` - Bulk scraping interface with real-time monitoring- `lot_scraping.cfm` - Single event scraping interface- JavaScript functions for AJAX calls and UI updates**Backend (ColdFusion):**- `tasks/run_scraper.cfm` - Main controller for scraper operations- `Application.cfc` - Configuration management- Database interaction layer**Scraping Scripts (Node.js):**- `scrap_all_auctions_lots_data.js` - All events scraping mode- `scrape_single_event.js` - Single event ID scraping mode- `insert_lots_into_db.js` - Real-time database insertion**Database (PostgreSQL):**- `scraper_jobs` - Job status and metadata- `scrape_logs` - Activity logging- `job_statistics` - Progress tracking- `sales`, `lots`, `uploaded_files` - Scraped data storage---## 🔄 Complete Scraping Flow### Phase 1: User Initiates Scraping**1.1 Frontend (bulk_processor.cfm)**
User clicks "Start Scraping" button
↓
startBulkScraping() function called
↓
Form data prepared (runMode, eventId, etc.)
↓
AJAX POST request to tasks/run_scraper.cfm?action=start
↓
Monitoring dashboard displayed
↓
Real-time monitoring started (polling every 2 seconds)
**1.2 Backend (tasks/run_scraper.cfm)**
Receives action=start request
↓
Validates database tables exist
↓
Checks for existing running/paused jobs
↓
Creates new job record in scraper_jobs table
↓
Sets job status to 'running'
↓
Determines which script to launch:
Single Event: scrape_single_event.js
All Events: scrap_all_auctions_lots_data.js
↓
Launches Node.js script via cfexecute (non-blocking)
↓
Returns jobId to frontend immediately
### Phase 2: Script Initialization**2.1 Script Startup (scrap_all_auctions_lots_data.js)**
Script receives --job-id parameter
↓
Loads database configuration (dbConfig.js)
↓
Initializes PostgreSQL connection pool
↓
Logs "Script process started" to database
↓
Checks for resume state from database:
getResumeState(jobId) called
Loads saved eventIndex, eventId, lotNumber
↓
Launches Puppeteer browser (headless mode)
↓
Logs "Browser launched successfully"
### Phase 3: Auction Discovery (All Events Mode Only)**3.1 Homepage Navigation**
Navigates to https://www.numisbids.com/
↓
Extracts event links from homepage:
Selector: 'td.firmcell a[href^="/event/"]'
Logs: "Found X event links on homepage"
↓
Processes each event link:
Opens new page for each event
Follows redirects to sale pages
Extracts sale URLs (/sale/{id})
↓
Logs progress: "Processing event links: X/Y..."
**3.2 Auction Details Extraction**
For each sale link:
↓
Opens sale page
↓
Extracts metadata:
Event ID (from URL: /sale/{id})
Auction Name
Sale Name (from sale info popup)
Contact Information (firm details)
Sale Info (logo, sale number)
↓
Creates event object with all metadata
↓
Saves to eventIds.json file
↓
Logs: "Extracting auction details: X/Y..."
### Phase 4: Auction Processing Loop**4.1 Pre-Processing Checks**
For each auction in newEventObjects array:
↓
Check 1: Final file exists?
If YES: Skip auction (already complete)
If NO: Continue
↓
Check 2: In-progress file exists?
If YES: Continue (resume this auction)
If NO: Continue (new auction)
↓
Check 3: Database check (only if no files exist)
Check uploaded_files table for 'Completed' status
If YES: Skip auction
If NO: Continue
↓
Update current_event_id in database
**4.2 Auction Metadata Extraction**
Opens auction page: https://www.numisbids.com/sale/{auctionId}
↓
Extracts from page:
auctionTitle (from .text .name)
eventDate (from HTML parsing)
totalPages (from pagination)
pageAuctionName
↓
Loads existing lots from in-progress file (if exists)
↓
Preserves field order: auctionid → loturl → auctionname → auctiontitle → eventdate
**4.3 Lot Scraping Loop**
For each page (1 to totalPages):
↓
Navigate to: {baseUrl}?pg={currentPage}
↓
Extract lot elements: page.$$('.browse')
↓
For each lot element:
↓
⚠️ PAUSE/STOP CHECK #1 (Before processing lot)
checkJobStatus(jobId)
If stopped: process.exit(0)
If paused: saveResumeState() + process.exit(0)
↓
Extract lot number
↓
Check if already scraped (from scrapedLotNumbers Set)
If YES: Skip lot
If NO: Continue
↓
Extract lot data from browse page:
Lot URL
Lot Name
Description
Thumbnail Image
Starting Price
Realized Price
↓
Open lot detail page
↓
⚠️ PAUSE/STOP CHECK #2 (Before opening detail page)
↓
Extract from detail page:
Category (from #activecat)
Full Description (from .viewlottext)
Full Image URL
↓
Close detail page
↓
Build lotData object with all fields
↓
Append to in-progress file (JSONL format)
↓
⚠️ PAUSE/STOP CHECK #3 (After scraping, before DB insert)
↓
Real-time database insertion:
insertLotFunctions.processLotInRealTime()
Inserts to sales, lots tables
Creates embeddings for RAG
↓
Update statistics:
current_lot_number in scraper_jobs
job_statistics table
saveResumeState() after each lot
↓
Log every 5 lots: "Scraped X lots from event Y"
**4.4 Auction Completion**
After all lots scraped:
↓
Sort all lots by lot number
↓
Create final JSON structure:
{
auctionid, auctionname, auctiontitle, eventdate,
extractedSaleName, contact, saleInfo,
lots: [array of all lots]
}
↓
Write to final folder: auction_{id}lots.json
↓
Delete in-progress file
↓
Update statistics:
processedEvents++
filesCompleted++
totalLots += allLots.length
↓
Log: "Completed auction X: Y lots"
### Phase 5: Job Completion**5.1 Final Steps**
After all auctions processed:
↓
Update job status to 'completed'
↓
Update final statistics
↓
Log: "Scraping completed successfully"
↓
Close browser
↓
Close database connection pool
↓
Script exits (process.exit(0))
---## ⏸️ Pause/Resume/Stop Functionality### Pause Flow**1. User Clicks Pause Button**
Frontend: pauseJob() function
↓
AJAX POST: tasks/run_scraper.cfm?action=pause
**2. Backend Processing (tasks/run_scraper.cfm)**
Receives action=pause
↓
Finds running job from database
↓
Kills Node.js process: taskkill /f /pid {processId}
↓
Updates job status to 'paused' in database
↓
Logs: "Scraper job paused by user"
↓
Returns success response
**3. Script Detection (scrap_all_auctions_lots_data.js)**
Script is running in loop
↓
Before each event: checkJobStatus(jobId)
↓
Before each lot: checkJobStatus(jobId)
↓
After scraping lot: checkJobStatus(jobId)
↓
Before DB insert: checkJobStatus(jobId)
↓
If status === 'paused':
saveResumeState(jobId, eventId, lotNumber, eventIndex, {...})
Logs pause location
Closes browser
process.exit(0)
### Resume Flow**1. User Clicks Resume Button**
Frontend: resumeJob() function
↓
AJAX POST: tasks/run_scraper.cfm?action=resume
**2. Backend Processing (tasks/run_scraper.cfm)**
Receives action=resume
↓
Finds paused job from database
↓
Loads resume_state from database
↓
Launches script with same --job-id
↓
Updates job status to 'running'
↓
Returns success response
**3. Script Resume (scrap_all_auctions_lots_data.js)**
Script starts with --job-id
↓
Calls getResumeState(jobId)
↓
Loads saved state:
eventIndex (which auction to resume)
eventId (current auction ID)
lotNumber (last processed lot)
↓
Checks for in-progress files:
Finds first incomplete auction (has in-progress but no final)
Sets startIndex to that auction
↓
For resumed auction:
Loads existing lots from in-progress file
Creates scrapedLotNumbers Set
Continues from next lot (not last one)
↓
Continues normal scraping flow
### Stop Flow**1. User Clicks Stop Button**
Frontend: stopJob() function
↓
Confirmation dialog
↓
AJAX POST: tasks/run_scraper.cfm?action=stop
**2. Backend Processing (tasks/run_scraper.cfm)**
Receives action=stop
↓
Finds active job (running or paused)
↓
Kills Node.js process: taskkill /f /pid {processId}
↓
Updates job status to 'stopped' in database
↓
Logs: "Scraper job stopped by user"
↓
Returns success response
**3. Script Detection**
Same check points as pause
↓
If status === 'stopped':
Logs stop location
Closes browser
Updates job status to 'stopped'
process.exit(0)
↓
No state saved (intentional - stop means don't resume)
### Check Points in Script**Location 1: Before Each Event** (Line ~814)ascriptconst jobStatus = await checkJobStatus(jobId);if (jobStatus.isStopped) { process.exit(0); }if (jobStatus.isPaused) { saveResumeState(); process.exit(0); }
Location 2: Before Each Lot (Line ~1002)
const jobStatus = await checkJobStatus(jobId);if (jobStatus.isStopped) { process.exit(0); }if (jobStatus.isPaused) { saveResumeState(); process.exit(0); }
Location 3: After Scraping Lot (Line ~1288)
const jobStatus = await checkJobStatus(jobId);if (jobStatus.isStopped) { process.exit(0); }if (jobStatus.isPaused) { saveResumeState(); process.exit(0); }
Location 4: Before Database Insert (Line ~1348)
const jobStatus = await checkJobStatus(jobId);if (jobStatus.isStopped) { process.exit(0); }if (jobStatus.isPaused) { saveResumeState(); process.exit(0); }
Location 5: On Error (Line ~1212)
const jobStatus = await checkJobStatus(jobId);if (jobStatus.isStopped) { process.exit(0); }// Auto-pause on errorawait updateJobStatus(jobId, 'paused');await saveResumeState(...);process.exit(0);
📁 File Structure & Responsibilities
Frontend Files
bulk_processor.cfm
Purpose: Main UI for bulk scraping operations
Key Functions:
startBulkScraping() - Initiates scraping with validation
pauseJob() - Sends pause request
resumeJob() - Sends resume request
stopJob() - Sends stop request
startMonitoring() - Polls for status updates
updateMonitoring() - Updates UI with latest stats
AJAX Endpoints:
tasks/run_scraper.cfm?action=start
tasks/run_scraper.cfm?action=pause
tasks/run_scraper.cfm?action=resume
tasks/run_scraper.cfm?action=stop
api/scraper_status.cfm?jobId=X
lot_scraping.cfm
Purpose: Single event scraping interface
Similar functions to bulk_processor.cfm
Mode: Single event ID only
Backend Files
tasks/run_scraper.cfm
Purpose: Main controller for all scraper operations
Actions Handled:
action=start - Creates job and launches script
action=pause - Pauses running job
action=resume - Resumes paused job
action=stop - Stops active job
action=status - Returns job status
Key Functions:
updateJobStatus(jobId, status) - Updates job status
logToDatabase(jobId, level, message, source) - Logs activity
Process management via cfexecute and taskkill
Scraping Scripts
scrap_all_auctions_lots_data.js
Purpose: Scrapes all available auctions from NumisBids
Command Line Args:
--job-id <id> - Database job ID (required)
--event-id <id> - Optional: specific event only
--output-file <name> - Optional: custom output file
Key Functions:
checkJobStatus(jobId) - Checks pause/stop status
saveResumeState(jobId, eventId, lotNumber, eventIndex, ...) - Saves state
getResumeState(jobId) - Loads saved state
updateJobStatus(jobId, status) - Updates job status
logToDatabase(jobId, level, message, source, data) - Logs activity
isAuctionAlreadyInserted(auctionId) - Checks if auction complete
updateJobStatistics(jobId, stats) - Updates progress stats
Flow:
Initialize → 2. Discover auctions → 3. Extract details → 4. Process each auction → 5. Complete
scrape_single_event.js
Purpose: Scrapes single event ID only
Command Line Args:
--event-id <id> - Event ID to scrape (required)
--output-file <name> - Output file path
--job-id <id> - Database job ID
Similar pause/resume/stop functionality
Flow:
Initialize → 2. Load resume state → 3. Navigate to event → 4. Scrape all pages → 5. Complete
insert_lots_into_db.js
Purpose: Real-time database insertion during scraping
Key Function:
processLotInRealTime(lotData, eventData, skipEmbedding) - Inserts lot immediately
Process:
Insert/update sale record
Insert/update lot record
Create embeddings (if not skipped)
Return lot_pk
Database Files
dbConfig.js
Purpose: PostgreSQL connection pool configuration
Exports: Connection pool for use in Node.js scripts
🗄️ Database Schema & State Management
Key Tables
scraper_jobs
- id (PK)- job_name- status ('queued', 'running', 'paused', 'stopped', 'completed', 'failed')- current_event_id- current_lot_number- current_event_index- total_events- resume_state (JSONB) - Stores: {eventId, lotNumber, eventIndex, timestamp, ...}- created_at- completed_at- error_message
scrape_logs
- id (PK)- job_id (FK → scraper_jobs.id)- log_level ('info', 'warning', 'error', 'debug')- message- source ('scraper', 'user', 'system')- metadata (JSONB) - Additional data- created_at
job_statistics
- job_id (PK, FK → scraper_jobs.id)- total_events- processed_events- total_lots- processed_lots- files_created- files_completed- updated_at
Resume State Structure
resume_state JSONB Field:
{  "eventId": "10243",  "lotNumber": "284",  "eventIndex": 15,  "timestamp": "2026-01-23T10:30:00.000Z",  "inProgressFile": "/path/to/auction_10243_lots.jsonl",  "finalFile": "/path/to/auction_10243_lots.json",  "lotsScraped": 284,  "totalEvents": 63}
State Management Flow
Saving State:
saveResumeState() called  ↓Creates resume_state object with current position  ↓Updates scraper_jobs table:  - resume_state = JSON.stringify(state)  - current_event_id = eventId  - current_lot_number = lotNumber  - current_event_index = eventIndex
Loading State:
getResumeState() called  ↓Queries scraper_jobs table  ↓Parses resume_state JSONB field  ↓Returns: {resumeState, currentEventId, currentLotNumber, currentEventIndex}
⚠️ Error Handling & Recovery
Error Types
1. Network Errors
Detection: Puppeteer timeout, connection errors
Handling: Retry logic, log to database, continue to next auction
2. Page Load Errors
Detection: Page.goto() failures
Handling: Skip auction, log warning, continue
3. Element Not Found
Detection: $eval() throws error
Handling: Use fallback values, log warning, continue
4. Database Errors
Detection: Pool query failures
Handling: Log error, continue (fail-safe), don't crash script
5. Fatal Errors
Detection: Uncaught exceptions
Handling:
Process-level handlers catch
Log to database
Update job status to 'failed'
Exit gracefully
Recovery Mechanisms
1. In-Progress Files
If script crashes, in-progress file preserved
On resume, loads existing lots and continues
2. Database State
Resume state saved to database
On resume, loads state and continues from saved position
3. Auto-Pause on Error
If lot scraping fails, job auto-pauses
State saved for manual resume
Prevents data loss
4. Skip Already Complete
Checks final files before processing
Checks database for 'Completed' status
Skips auctions already fully processed
📊 Real-time Monitoring
Frontend Polling
Monitoring Function:
function startMonitoring() {  intervalId = setInterval(() => {    fetch('api/scraper_status.cfm?jobId=' + currentJobId)      .then(response => response.json())      .then(data => {        updateUI(data); // Update progress bars, stats, logs      });  }, 2000); // Poll every 2 seconds}
Backend Status Endpoint
api/scraper_status.cfm
Queries scraper_jobs table for current job
Queries job_statistics for progress
Queries scrape_logs for recent activity
Returns JSON with all status information
UI Updates
Progress Bars:
Event Progress: processedEvents / totalEvents
Lot Progress: processedLots / totalLots
Statistics Display:
Current Event ID
Lots Scraped
Lots Inserted
Current Lot Number
Activity Log:
Recent logs from scrape_logs table
Color-coded by log level
Auto-scrolls to latest
🔑 Key Functions Reference
checkJobStatus(jobId)
// Returns: {isPaused: boolean, isStopped: boolean, status: string}// Checks database for current job status// Called at multiple check points in script
saveResumeState(jobId, eventId, lotNumber, eventIndex, additionalState)
// Saves current position to database// Called when pausing or after each lot// Stores in resume_state JSONB field
getResumeState(jobId)
// Returns: {resumeState, currentEventId, currentLotNumber, currentEventIndex}// Loads saved state from database// Called at script startup
logToDatabase(jobId, level, message, source, metadata)
// Logs activity to scrape_logs table// Used throughout script for tracking// Frontend displays these logs
updateJobStatistics(jobId, stats)
// Updates job_statistics table// Called after processing events/lots// Used for progress tracking
📝 Notes & Best Practices
Always check pause/stop status before long operations
Save resume state frequently (after each lot)
Use in-progress files for crash recovery
Check final files before processing to skip complete auctions
Log all important operations for debugging
Handle errors gracefully - don't crash on single lot failure
Update statistics in real-time for monitoring
Close browser and database connections properly on exit
Last Updated: January 23, 2026