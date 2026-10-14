#!/bin/bash
set -euo pipefail

PORT=8000
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEB_DIR="${ROOT_DIR}/web"

# Ensure DMG and ZIP are synced with the latest build
if [ -f "${ROOT_DIR}/build/TidyMac.dmg" ]; then
    cp "${ROOT_DIR}/build/TidyMac.dmg" "${WEB_DIR}/TidyMac.dmg"
fi
if [ -f "${ROOT_DIR}/build/TidyMac.zip" ]; then
    cp "${ROOT_DIR}/build/TidyMac.zip" "${WEB_DIR}/TidyMac.zip"
fi

echo "============================================="
echo "   Tidy Mac Download Site Server             "
echo "============================================="
echo "Serving directory: ${WEB_DIR}"
echo "URL: http://localhost:${PORT}"
echo "============================================="
echo "Opening browser..."
open "http://localhost:${PORT}" 2>/dev/null || true

echo "Starting local HTTP server on port ${PORT}... (Press Ctrl+C to stop)"
cd "${WEB_DIR}" && python3 -m http.server "${PORT}"
