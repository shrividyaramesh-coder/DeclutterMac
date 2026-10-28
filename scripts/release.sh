#!/bin/bash
# Builds Declutter Mac, packages DeclutterMac.dmg/.zip, and publishes them as a GitHub Release.
# The website's download links redirect to the latest release, so this is all a release needs:
#   1. bump the version in scripts/package_app.sh and merge to main
#   2. scripts/release.sh "Short notes about what changed"
set -euo pipefail

NOTES="${1:?Usage: scripts/release.sh \"Release notes\"}"

if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ] || [ -n "$(git status --porcelain)" ]; then
    echo "Release from a clean main branch." >&2
    exit 1
fi
git pull --ff-only

bash scripts/package_app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/DeclutterMac.app/Contents/Info.plist)
TAG="v${VERSION}"
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists. Bump the version in scripts/package_app.sh first." >&2
    exit 1
fi

OUT="build/release"
rm -rf "$OUT"
mkdir -p "$OUT/dmgroot"
ditto -c -k --sequesterRsrc --keepParent build/DeclutterMac.app "$OUT/DeclutterMac.zip"
# Older copies of install.sh fetch this name
cp "$OUT/DeclutterMac.zip" "$OUT/TidyMac.zip"
ditto build/DeclutterMac.app "$OUT/dmgroot/DeclutterMac.app"
hdiutil create -quiet -volname "Declutter Mac" -srcfolder "$OUT/dmgroot" -format UDZO -ov "$OUT/DeclutterMac.dmg"

gh release create "$TAG" "$OUT/DeclutterMac.dmg" "$OUT/DeclutterMac.zip" "$OUT/TidyMac.zip" \
    --title "Declutter Mac $VERSION" --notes "$NOTES" --target main --latest

echo "Published $TAG. https://decluttermac.com/DeclutterMac.dmg now serves it."
