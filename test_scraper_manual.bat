@echo off
echo ========================================
echo Manual Scraper Test
echo ========================================
echo.

cd /d C:\box\canchat1

echo Current directory: %CD%
echo.

echo Checking for required files...
if exist "scrape_single_event.js" (
    echo [OK] scrape_single_event.js found
) else (
    echo [ERROR] scrape_single_event.js NOT FOUND
    pause
    exit /b 1
)

if exist "dbConfig.js" (
    echo [OK] dbConfig.js found
) else (
    echo [ERROR] dbConfig.js NOT FOUND
    pause
    exit /b 1
)

if exist ".env" (
    echo [OK] .env file found
) else (
    echo [WARNING] .env file NOT FOUND - database connection may fail
)

echo.
echo ========================================
echo Running scraper script...
echo ========================================
echo.

node scrape_single_event.js --event-id 10258 --output-file "./allAuctionLotsData_inprogress/auction_10258_lots.jsonl" --job-id 999

echo.
echo ========================================
echo Script execution finished
echo ========================================
echo.

if exist "scrape_debug.log" (
    echo Debug log file exists. Last 20 lines:
    echo ----------------------------------------
    powershell -Command "Get-Content scrape_debug.log -Tail 20"
    echo ----------------------------------------
) else (
    echo [WARNING] scrape_debug.log file NOT FOUND
    echo The script may have failed before creating the log file.
)

echo.
pause
