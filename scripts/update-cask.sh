#!/bin/bash
#
# Regenerate the Homebrew cask for a released version and, if a tap checkout
# is given, copy it there and commit.
#
# Usage:
#   ./scripts/update-cask.sh <version> [path/to/homebrew-tap]
#
# Reads dist/gitForge-<version>.dmg if present (the file release.sh produced);
# otherwise downloads the asset from the GitHub release to hash it.

set -euo pipefail

VERSION="${1:-}"
TAP_DIR="${2:-}"
if [[ -z "${VERSION}" ]]; then
  sed -n '2,12p' "$0"; exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK="${ROOT}/packaging/homebrew/Casks/gitforge.rb"
DMG="${ROOT}/dist/gitForge-${VERSION}.dmg"

if [[ ! -f "${DMG}" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  gh release download "v${VERSION}" -R 9alvaro0/gitForge -p "gitForge-${VERSION}.dmg" -D "${TMP}"
  DMG="${TMP}/gitForge-${VERSION}.dmg"
fi

SHA="$(shasum -a 256 "${DMG}" | awk '{print $1}')"

sed -i '' -E \
  -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" \
  "${CASK}"

echo "Cask updated: ${VERSION} (${SHA})"

if [[ -n "${TAP_DIR}" ]]; then
  mkdir -p "${TAP_DIR}/Casks"
  cp "${CASK}" "${TAP_DIR}/Casks/gitforge.rb"
  git -C "${TAP_DIR}" add Casks/gitforge.rb
  git -C "${TAP_DIR}" commit -m "gitforge ${VERSION}"
  echo "Committed to ${TAP_DIR}. Push it to publish."
fi
