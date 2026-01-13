@echo off
cd /d "%~dp0"
"C:\Program Files\nodejs\node.exe" "%~dp0scrape_single_event.js" --event-id %1 --output-file auction_%1_lots.jsonl
