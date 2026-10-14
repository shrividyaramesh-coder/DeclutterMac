#!/bin/bash
set -euo pipefail

DEST_DIR="${HOME}/Applications"
if [ ! -d "${DEST_DIR}" ]; then
    mkdir -p "${DEST_DIR}"
fi

if [ ! -d "build/TidyMac.app" ]; then
    echo "App bundle not found. Building first..."
    bash scripts/package_app.sh
fi

echo "Installing Tidy Mac to ${DEST_DIR}..."
rm -rf "${DEST_DIR}/TidyMac.app"
cp -R "build/TidyMac.app" "${DEST_DIR}/"

echo "✅ Tidy Mac installed successfully to ${DEST_DIR}/TidyMac.app"
echo "You can launch it via: open \"${DEST_DIR}/TidyMac.app\""
