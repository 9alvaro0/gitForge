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
# - SPARKLE_SIGN_UPDATE: path to Sparkle's sign_update, skipping the lookup.

set -Eeuo pipefail

# A failing command used to end the script with no output at all when its
# error went to /dev/null; name the line and command instead.
trap 'echo "update-appcast.sh: stopped at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

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
# Sparkle's CLI sits in each DerivedData folder that resolved the package.
# Prefer this checkout's folder (Xcode records its project in the folder's
# info.plist), else the newest copy. A glob, not a recursive find over all of
# DerivedData: a find that can't walk some folder (one Xcode removes mid-walk
# right after release.sh archives, say) exits non-zero with its error sent to
# /dev/null, the likely reason ship.sh stopped silently before the appcast in
# 1.6.0 and 1.7.0.
DERIVED_DATA="${DERIVED_DATA:-${HOME}/Library/Developer/Xcode/DerivedData}"

resolve_sign_update() {
  local project_path candidate workspace newest=""
  local candidates=()
  project_path="$(pwd -P)/${PROJECT}"

  shopt -s nullglob
  candidates=( "${DERIVED_DATA}"/*/SourcePackages/artifacts/*/Sparkle/bin/sign_update )
  shopt -u nullglob
  # bash 3.2 treats an empty array as unbound under set -u.
  (( ${#candidates[@]} > 0 )) || return 0

  for candidate in "${candidates[@]}"; do
    [[ -x "${candidate}" ]] || continue
    workspace=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' \
      "${candidate%%/SourcePackages/*}/info.plist" 2>/dev/null || true)
    if [[ "${workspace}" == "${project_path}" ]]; then
      echo "${candidate}"
      return 0
    fi
    if [[ -z "${newest}" || "${candidate}" -nt "${newest}" ]]; then
      newest="${candidate}"
    fi
  done
  echo "${newest}"
}

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$(resolve_sign_update)}"
if [[ -z "${SIGN_UPDATE}" || ! -x "${SIGN_UPDATE}" ]]; then
  echo "sign_update not found under ${DERIVED_DATA}. Open the project in Xcode" >&2
  echo "and build once to materialize Sparkle's CLI, or set SPARKLE_SIGN_UPDATE." >&2
  exit 1
fi
echo "Signing with ${SIGN_UPDATE}"

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
  # Ends in a newline: $'\n' isn't expanded inside the here-doc below.
  NOTES_LINK_TAG="            <sparkle:releaseNotesLink>${NOTES_BASE_URL}/v${VERSION}.html</sparkle:releaseNotesLink>"$'\n'
else
  echo "Note: ${NOTES_PATH} not found — release notes link omitted."
fi

# ---- Compose <item> --------------------------------------------------------
# IFS= keeps the first line's indentation.
IFS= read -r -d '' ITEM_XML <<XML || true
        <item>
            <title>gitForge ${VERSION}</title>
${NOTES_LINK_TAG}            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
            <enclosure url="${DOWNLOAD_URL}"
                       sparkle:version="${VERSION}"
                       sparkle:shortVersionString="${VERSION}"
                       length="${DMG_LENGTH}"
                       type="application/octet-stream"
                       sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
XML
ITEM_XML="${ITEM_XML%$'\n'}"

# ---- Splice the item into the channel (after <language> tag) --------------
TMP=$(mktemp)
# The item goes through the environment: BSD awk rejects newlines in -v values.
ITEM="${ITEM_XML}" awk '
  /<\/channel>/ && !done {
    print ENVIRON["ITEM"]
    done = 1
  }
  { print }
' "${APPCAST}" > "${TMP}"

mv "${TMP}" "${APPCAST}"

echo "Added gitForge ${VERSION} to ${APPCAST}"
echo "Don't forget to:"
echo "  1) Upload ${DMG_PATH} to GitHub Releases tag v${VERSION}"
echo "  2) Commit and push ${APPCAST} (and any docs/releases/* changes)"
