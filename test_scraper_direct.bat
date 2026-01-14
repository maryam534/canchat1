@echo off
echo ========================================
echo Direct Scraper Test - Job ID 23
echo ========================================
echo.

cd /d C:\box\canchat1

echo Current directory: %CD%
echo.

echo Running script with jobId=23...
echo.

node scrape_single_event.js --event-id 10258 --output-file "./allAuctionLotsData_inprogress/auction_10258_lots.jsonl" --job-id 23

echo.
echo ========================================
echo Script execution finished
echo ========================================
echo.

echo Checking debug log file...
if exist "scrape_debug.log" (
    echo.
    echo Last 30 lines of scrape_debug.log:
    echo ----------------------------------------
    powershell -Command "Get-Content scrape_debug.log -Tail 30"
    echo ----------------------------------------
) else (
    echo [ERROR] scrape_debug.log file NOT FOUND
)

echo.
pause
