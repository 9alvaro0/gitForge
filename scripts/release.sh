#!/bin/bash
#
# Build, sign, notarize and package gitForge as a distributable DMG.
# Requires: Xcode, a Developer ID Application certificate in the Keychain,
# and a stored notarytool profile (see scripts/notarize-credentials.md).
# DMG layout uses hdiutil directly (no create-dmg) so no Finder Automation
# permissions are needed.
#
# Usage: ./scripts/release.sh
# Output: dist/gitForge-<version>.dmg

set -euo pipefail

# ---- Config ----------------------------------------------------------------
PROJECT="gitForge.xcodeproj"
SCHEME="gitForge"
CONFIG="Release"
APP_NAME="gitForge"
TEAM_ID="T6B3T6K6TZ"
SIGNING_IDENTITY="Developer ID Application: Álvaro Guerra (${TEAM_ID})"
NOTARY_PROFILE="gitForge-notary"

BUILD_DIR="build"
DIST_DIR="dist"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${BUILD_DIR}/exportOptions.plist"
APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"

# ---- Helpers ---------------------------------------------------------------
log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }
}

# ---- Preflight -------------------------------------------------------------
require xcodebuild
require xcrun
require ditto

cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIG}" \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION = /{print $2; exit}')

if [[ -z "${VERSION}" ]]; then
  echo "Could not read MARKETING_VERSION from the project."
  exit 1
fi

DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

log "Releasing ${APP_NAME} ${VERSION}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

# ---- Archive ---------------------------------------------------------------
log "Archiving Release build"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  archive

# ---- Export with Developer ID ---------------------------------------------
log "Writing export options"
cat > "${EXPORT_OPTIONS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

log "Exporting signed .app"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}"

# ---- Notarize the .app -----------------------------------------------------
log "Zipping .app for notarization"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

log "Submitting .app to notary service (this can take a few minutes)"
xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

log "Stapling .app"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

# ---- Build DMG -------------------------------------------------------------
# We use hdiutil directly (not create-dmg) because create-dmg relies on
# AppleScript/Finder Automation permissions that often time out on first run.
# This produces a functional DMG with an Applications symlink. A prettier
# layout (custom background, icon positioning) can be wired up later once
# the app icon (#33) lands.
log "Building DMG"
rm -f "${DMG_PATH}"
DMG_STAGE="${BUILD_DIR}/dmg-stage"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${APP_PATH}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "${DMG_STAGE}" \
  -ov -format UDZO \
  "${DMG_PATH}"

# ---- Sign and notarize the DMG --------------------------------------------
log "Signing DMG"
codesign --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"

log "Submitting DMG to notary service"
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

log "Stapling DMG"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

# ---- Verify with Gatekeeper -----------------------------------------------
log "Verifying with Gatekeeper"
spctl --assess --type execute --verbose "${APP_PATH}"
spctl --assess --type open --context context:primary-signature --verbose "${DMG_PATH}"

log "Done"
echo "Artifact: ${DMG_PATH}"
ls -la "${DMG_PATH}"

cat <<EOM

Next steps for distribution:
  1) gh release create v${VERSION} ${DMG_PATH} \\
       --title "gitForge ${VERSION}" --notes-file <release-notes.md>
  2) ./scripts/update-appcast.sh ${VERSION}
  3) git add docs/appcast.xml docs/releases/ && git commit -m "release: v${VERSION}" && git push
EOM
