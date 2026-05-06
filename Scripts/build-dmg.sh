#!/bin/bash
set -euo pipefail

# MacMule DMG builder
# Usage: ./Scripts/build-dmg.sh [version]
#   version defaults to a date-based snapshot (e.g. 2026.01.01)

CONFIGURATION="${CONFIGURATION:-Release}"
VERSION="${1:-$(date +%Y.%m.%d)}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$PROJECT_DIR/.build-dmg"
ARCHIVE_PATH="$DERIVED_DATA/MacMule.xcarchive"
EXPORT_DIR="$DERIVED_DATA/Export"
APP_NAME="MacMule"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
VOLUME_NAME="MacMule"

echo "==> Cleaning previous build..."
rm -rf "$DERIVED_DATA" "$DMG_PATH"

echo "==> Archiving $APP_NAME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_DIR/MacMule.xcodeproj" \
  -scheme MacMule \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  archive

echo "==> Exporting archive..."
xcodebuild \
  -archivePath "$ARCHIVE_PATH" \
  -exportArchive \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PROJECT_DIR/Scripts/export-options.plist"

echo "==> Creating DMG..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

echo "==> DMG created at: $DMG_PATH"
