#!/bin/sh
# BPV-1 simulator - backup launcher (macOS / Linux).
# index.html normally works by opening it directly. Use this only if your
# browser refuses to expose window.crypto.subtle on file:// URLs.
cd "$(dirname "$0")" || exit 1
echo "Serving this folder on http://localhost:8000/index.html  (Ctrl+C to stop)"
python3 -m http.server 8000 || python -m http.server 8000
