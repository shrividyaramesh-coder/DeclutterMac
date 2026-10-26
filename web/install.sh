#!/bin/bash
set -euo pipefail

echo "============================================="
echo "   Installing Declutter Mac Native App       "
echo "============================================="

DEST_DIR="${HOME}/Applications"
mkdir -p "${DEST_DIR}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading Declutter Mac..."
if [ -f "DeclutterMac.zip" ]; then
    cp "DeclutterMac.zip" "${TMP_DIR}/DeclutterMac.zip"
elif [ -f "build/DeclutterMac.zip" ]; then
    cp "build/DeclutterMac.zip" "${TMP_DIR}/DeclutterMac.zip"
elif [ -f "TidyMac.zip" ]; then
    cp "TidyMac.zip" "${TMP_DIR}/DeclutterMac.zip"
else
    BASE_URL="${DECLUTTERMAC_URL:-https://decluttermac.com}"
    curl -fsSL "${BASE_URL}/DeclutterMac.zip" -o "${TMP_DIR}/DeclutterMac.zip" 2>/dev/null || \
    curl -fsSL "${BASE_URL}/TidyMac.zip" -o "${TMP_DIR}/DeclutterMac.zip" 2>/dev/null || \
    curl -fsSL "http://localhost:8000/DeclutterMac.zip" -o "${TMP_DIR}/DeclutterMac.zip" 2>/dev/null || \
    curl -fsSL "http://localhost:8000/TidyMac.zip" -o "${TMP_DIR}/DeclutterMac.zip"
fi

echo "Extracting Declutter Mac to ${DEST_DIR}..."
unzip -q -o "${TMP_DIR}/DeclutterMac.zip" -d "${DEST_DIR}"

APP_PATH="${DEST_DIR}/DeclutterMac.app"
if [ ! -d "${APP_PATH}" ] && [ -d "${DEST_DIR}/TidyMac.app" ]; then
    APP_PATH="${DEST_DIR}/TidyMac.app"
fi

echo "Clearing quarantine attributes..."
xattr -cr "${APP_PATH}" 2>/dev/null || true

echo "============================================="
echo "✅ Declutter Mac installed successfully!"
echo "   Location: ${APP_PATH}"
echo "============================================="
echo "Launching Declutter Mac..."
open "${APP_PATH}"
