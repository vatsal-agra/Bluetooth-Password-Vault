@echo off
REM BPV-1 simulator - backup launcher (Windows).
REM index.html normally works by double-clicking it. Use this only if your
REM browser refuses to expose window.crypto.subtle on file:// URLs.
cd /d "%~dp0"
echo Serving this folder on http://localhost:8000/index.html  (Ctrl+C to stop)
start "" http://localhost:8000/index.html
python -m http.server 8000 || py -m http.server 8000
