#!/bin/bash
set -euo pipefail

echo "============================================="
echo "   Installing Tidy Mac Native macOS App      "
echo "============================================="

DEST_DIR="${HOME}/Applications"
mkdir -p "${DEST_DIR}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading Tidy Mac..."
if [ -f "TidyMac.zip" ]; then
    cp "TidyMac.zip" "${TMP_DIR}/TidyMac.zip"
elif [ -f "build/TidyMac.zip" ]; then
    cp "build/TidyMac.zip" "${TMP_DIR}/TidyMac.zip"
else
    curl -fsSL "http://localhost:8000/TidyMac.zip" -o "${TMP_DIR}/TidyMac.zip"
fi

echo "Extracting Tidy Mac to ${DEST_DIR}..."
unzip -q -o "${TMP_DIR}/TidyMac.zip" -d "${DEST_DIR}"

echo "Clearing quarantine attributes..."
xattr -cr "${DEST_DIR}/TidyMac.app" 2>/dev/null || true

echo "============================================="
echo "✅ Tidy Mac installed successfully!"
echo "   Location: ${DEST_DIR}/TidyMac.app"
echo "============================================="
echo "Launching Tidy Mac..."
open "${DEST_DIR}/TidyMac.app"
