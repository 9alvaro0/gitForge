#!/bin/bash
#
# Append a new release entry to docs/appcast.xml after running release.sh.
# Reads the EdDSA private key from the macOS Keychain (account name from
# generate_keys -- see scripts/notarize-credentials.md).
#
# Usage: ./scripts/update-appcast.sh [VERSION]
# - VERSION defaults to MARKETING_VERSION in the Xcode project.
# - DMG must exist at dist/gitForge-<VERSION>.dmg (run release.sh first).
# - Optional release notes: docs/releases/v<VERSION>.html (else link omitted).

set -euo pipefail

# ---- Config ----------------------------------------------------------------
PROJECT="gitForge.xcodeproj"
SCHEME="gitForge"
APP_NAME="gitForge"
APPCAST="docs/appcast.xml"
NOTES_BASE_URL="https://9alvaro0.github.io/gitForge/releases"
DOWNLOAD_BASE_URL="https://github.com/9alvaro0/gitForge/releases/download"
SPARKLE_ACCOUNT="gitForge-sparkle-private"
MIN_SYSTEM_VERSION="26.1"

cd "$(dirname "$0")/.."

# ---- Resolve version -------------------------------------------------------
VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  VERSION=$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION = /{print $2; exit}')
fi
if [[ -z "${VERSION}" ]]; then
  echo "Could not resolve VERSION." >&2
  exit 1
fi

DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"
if [[ ! -f "${DMG_PATH}" ]]; then
  echo "DMG not found: ${DMG_PATH}. Run scripts/release.sh first." >&2
  exit 1
fi

if [[ ! -f "${APPCAST}" ]]; then
  echo "Appcast not found: ${APPCAST}." >&2
  exit 1
fi

if grep -q "sparkle:version=\"${VERSION}\"" "${APPCAST}"; then
  echo "Version ${VERSION} already present in ${APPCAST}." >&2
  exit 1
fi

# ---- Resolve sign_update path (DerivedData hash varies per machine) -------
SIGN_UPDATE=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
  -path "*Sparkle/bin/sign_update" -type f 2>/dev/null | head -1)
if [[ -z "${SIGN_UPDATE}" ]]; then
  echo "sign_update not found. Open the project in Xcode and build once " >&2
  echo "to materialize Sparkle's CLI under DerivedData."  >&2
  exit 1
fi

# ---- Sign DMG and parse signature/length ----------------------------------
SIGN_OUTPUT=$("${SIGN_UPDATE}" --account "${SPARKLE_ACCOUNT}" "${DMG_PATH}")
ED_SIGNATURE=$(echo "${SIGN_OUTPUT}" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')
DMG_LENGTH=$(echo "${SIGN_OUTPUT}" | sed -nE 's/.*length="([^"]+)".*/\1/p')

if [[ -z "${ED_SIGNATURE}" || -z "${DMG_LENGTH}" ]]; then
  echo "sign_update produced unexpected output:" >&2
  echo "${SIGN_OUTPUT}" >&2
  exit 1
fi

PUB_DATE=$(LC_TIME=en_US.UTF-8 date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/v${VERSION}/${APP_NAME}-${VERSION}.dmg"

# ---- Optional release notes ------------------------------------------------
NOTES_PATH="docs/releases/v${VERSION}.html"
NOTES_LINK_TAG=""
if [[ -f "${NOTES_PATH}" ]]; then
  NOTES_LINK_TAG="            <sparkle:releaseNotesLink>${NOTES_BASE_URL}/v${VERSION}.html</sparkle:releaseNotesLink>"
else
  echo "Note: ${NOTES_PATH} not found — release notes link omitted."
fi

# ---- Compose <item> --------------------------------------------------------
read -r -d '' ITEM_XML <<XML || true
        <item>
            <title>gitForge ${VERSION}</title>
${NOTES_LINK_TAG:+${NOTES_LINK_TAG}$'\n'}            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
            <enclosure url="${DOWNLOAD_URL}"
                       sparkle:version="${VERSION}"
                       sparkle:shortVersionString="${VERSION}"
                       length="${DMG_LENGTH}"
                       type="application/octet-stream"
                       sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
XML

# Drop the empty placeholder line if there are no notes.
if [[ -z "${NOTES_LINK_TAG}" ]]; then
  ITEM_XML=$(echo "${ITEM_XML}" | sed '/^[[:space:]]*$/d')
fi

# ---- Splice the item into the channel (after <language> tag) --------------
TMP=$(mktemp)
awk -v item="${ITEM_XML}" '
  /<\/channel>/ && !done {
    print item
    done = 1
  }
  { print }
' "${APPCAST}" > "${TMP}"

mv "${TMP}" "${APPCAST}"

echo "Added gitForge ${VERSION} to ${APPCAST}"
echo "Don't forget to:"
echo "  1) Upload ${DMG_PATH} to GitHub Releases tag v${VERSION}"
echo "  2) Commit and push ${APPCAST} (and any docs/releases/* changes)"
