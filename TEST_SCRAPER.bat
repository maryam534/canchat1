@echo off
echo Testing scraper script execution...
echo.

cd /d C:\box\canchat1

echo Current directory: %CD%
echo.

echo Running script...
node scrape_single_event.js --event-id 10258 --output-file "./allAuctionLotsData_inprogress/auction_10258_lots.jsonl" --job-id 19

echo.
echo Script execution finished.
echo Check scrape_debug.log for details.
pause
