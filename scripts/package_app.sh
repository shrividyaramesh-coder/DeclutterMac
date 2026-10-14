#!/bin/bash
set -euo pipefail

echo "============================================="
echo "   Building Tidy Mac Native macOS App Bundle"
echo "============================================="

# 1. Compile release executable
echo "[1/4] Compiling release binaries via SwiftPM..."
swift build -c release

# 2. Setup bundle structure
APP_NAME="TidyMac.app"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "[2/4] Setting up ${APP_NAME} structure..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy executable
cp ".build/release/TidyMacApp" "${MACOS_DIR}/TidyMacApp"
chmod +x "${MACOS_DIR}/TidyMacApp"

# 3. Generate icon if needed and copy
if [ ! -f "${BUILD_DIR}/AppIcon.icns" ]; then
    echo "Generating AppIcon..."
    swift scripts/generate_icon.swift
    iconutil -c icns "${BUILD_DIR}/icon.iconset" -o "${BUILD_DIR}/AppIcon.icns"
fi
cp "${BUILD_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

# Copy any resource bundles
if [ -d ".build/release/TidyMac_TidyMacCore.bundle" ]; then
    cp -R ".build/release/TidyMac_TidyMacCore.bundle" "${RESOURCES_DIR}/"
fi

# 4. Create Info.plist
echo "[3/4] Writing Info.plist and PkgInfo..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleIdentifier</key>
    <string>com.tidymac.app</string>
    <key>CFBundleName</key>
    <string>Tidy Mac</string>
    <key>CFBundleDisplayName</key>
    <string>Tidy Mac</string>
    <key>CFBundleExecutable</key>
    <string>TidyMacApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Tidy Mac. All rights reserved.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Tidy Mac organizes files and cleans clutter on your Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Tidy Mac organizes documents and removes unneeded duplicates.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Tidy Mac cleans old installers and organizes downloaded files.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Tidy Mac inspects external drives for cleanup and organization when requested.</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# 5. Codesign (ad-hoc for local development)
echo "[4/4] Applying ad-hoc codesign signature..."
codesign --force --deep --sign - "${APP_DIR}"

echo "============================================="
echo "✅ Tidy Mac App Bundle built successfully!"
echo "   Location: ${APP_DIR}"
echo "============================================="
