#!/bin/bash
#
# Cut a full gitForge release in one shot.
#
# Pipeline:
#   1) Validate (semver, clean tree, on main, tag absent, version not in appcast)
#   2) Bump MARKETING_VERSION in the Xcode project
#   3) Generate release notes from git log (unless --skip-notes)
#   4) Commit version bump + notes
#   5) release.sh        (build / sign / notarize / DMG)
#   6) git tag vX.Y.Z
#   7) gh release create
#   8) update-appcast.sh (EdDSA-sign DMG, prepend <item>)
#   9) Commit appcast
#   10) Push commits + tag
#
# Usage:
#   ./scripts/ship.sh <version> [--dry-run] [--skip-notes] [--skip-push] [--yes]
#
# Examples:
#   ./scripts/ship.sh 1.0.2
#   ./scripts/ship.sh 1.0.3 --dry-run
#   ./scripts/ship.sh 1.0.4 --skip-notes   # use docs/releases/v1.0.4.html as-is

set -euo pipefail

# ---- Parse args ------------------------------------------------------------
VERSION=""
DRY_RUN=0
SKIP_NOTES=0
SKIP_PUSH=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-notes) SKIP_NOTES=1 ;;
    --skip-push)  SKIP_PUSH=1 ;;
    --yes|-y)     ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,25p' "$0"; exit 0 ;;
    -*)
      echo "Unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -n "${VERSION}" ]]; then
        echo "Unexpected argument: $1" >&2; exit 2
      fi
      VERSION="$1"
      ;;
  esac
  shift
done

if [[ -z "${VERSION}" ]]; then
  echo "Usage: ./scripts/ship.sh <version> [--dry-run] [--skip-notes] [--skip-push] [--yes]" >&2
  exit 2
fi

# ---- Helpers ---------------------------------------------------------------
log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }

run() {
  if (( DRY_RUN )); then
    printf '\033[1;90m[dry-run]\033[0m %s\n' "$*"
  else
    eval "$@"
  fi
}

confirm() {
  (( ASSUME_YES )) && return 0
  (( DRY_RUN ))    && return 0
  read -r -p "$1 [y/N] " ans
  [[ "${ans:-}" =~ ^[Yy]$ ]]
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

# ---- Resolve repo root -----------------------------------------------------
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
PROJECT="gitForge.xcodeproj"
PBXPROJ="${PROJECT}/project.pbxproj"
APPCAST="docs/appcast.xml"
NOTES_DIR="docs/releases"
NOTES_HTML="${NOTES_DIR}/v${VERSION}.html"
DMG_PATH="dist/gitForge-${VERSION}.dmg"
TAG="v${VERSION}"

# ---- Preflight -------------------------------------------------------------
require git
require gh
require xcodebuild

log "Preflight"

# Semver shape (X.Y.Z, optionally with -prerelease)
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] \
  || fail "Version must be semver (e.g. 1.0.2). Got: ${VERSION}"

# Branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "${BRANCH}" == "main" ]] || fail "Must be on main. Currently on: ${BRANCH}"

# Clean working tree
if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "Working tree is dirty. Commit or stash first."
fi

# Up to date with origin
git fetch origin --quiet
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
if [[ -n "${REMOTE}" && "${LOCAL}" != "${REMOTE}" ]]; then
  fail "Local main is not in sync with origin/main. Pull or push first."
fi

# Tag must not exist (local or remote)
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  fail "Tag ${TAG} already exists locally."
fi
if git ls-remote --exit-code --tags origin "${TAG}" >/dev/null 2>&1; then
  fail "Tag ${TAG} already exists on origin."
fi

# Version must not be in appcast yet
if grep -q "sparkle:version=\"${VERSION}\"" "${APPCAST}"; then
  fail "Version ${VERSION} is already present in ${APPCAST}."
fi

# gh authenticated
gh auth status >/dev/null 2>&1 || fail "gh CLI is not authenticated. Run: gh auth login"

# Read current MARKETING_VERSION
CURRENT_VERSION=$(awk -F' = ' '/MARKETING_VERSION = /{gsub(/[ ;]/,"",$2); print $2; exit}' "${PBXPROJ}")
[[ -n "${CURRENT_VERSION}" ]] || fail "Could not read current MARKETING_VERSION from ${PBXPROJ}"

if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
  warn "MARKETING_VERSION is already ${VERSION}. Bump step will be a no-op."
else
  log "Bumping ${CURRENT_VERSION} → ${VERSION}"
fi

PREV_TAG=$(git tag --list 'v*' --sort=-v:refname | head -1)
if [[ -n "${PREV_TAG}" ]]; then
  RANGE="${PREV_TAG}..HEAD"
  log "Release notes range: ${RANGE}"
else
  RANGE="HEAD"
  log "No previous tag — release notes will include full history"
fi

cat <<SUMMARY

  Version       : ${VERSION}
  Previous tag  : ${PREV_TAG:-<none>}
  DMG output    : ${DMG_PATH}
  Tag           : ${TAG}
  Notes file    : ${NOTES_HTML}
  Skip notes    : $((SKIP_NOTES))
  Skip push     : $((SKIP_PUSH))
  Dry run       : $((DRY_RUN))

SUMMARY

confirm "Proceed?" || { warn "Aborted."; exit 0; }

# ---- 1. Bump MARKETING_VERSION --------------------------------------------
if [[ "${CURRENT_VERSION}" != "${VERSION}" ]]; then
  log "Bumping MARKETING_VERSION in ${PBXPROJ}"
  if (( DRY_RUN )); then
    printf '\033[1;90m[dry-run]\033[0m sed -i "" "s/MARKETING_VERSION = %s;/MARKETING_VERSION = %s;/g" %s\n' \
      "${CURRENT_VERSION}" "${VERSION}" "${PBXPROJ}"
  else
    sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${VERSION};/g" "${PBXPROJ}"
    # Verify every occurrence got bumped
    if grep -q "MARKETING_VERSION = ${CURRENT_VERSION};" "${PBXPROJ}"; then
      fail "Bump left some MARKETING_VERSION = ${CURRENT_VERSION} entries behind. Aborting."
    fi
  fi
fi

# ---- 2. Generate release notes --------------------------------------------
generate_notes() {
  local md_file="$1"
  local html_file="$2"
  local feats fixes perfs

  # Strip leading "type(scope): " or "type: " from each subject
  collect() {
    git log "${RANGE}" --pretty=format:'%s' \
      | grep -E "^$1(\([^)]+\))?:" \
      | sed -E "s/^$1(\([^)]+\))?: //" \
      || true
  }

  feats=$(collect 'feat')
  fixes=$(collect 'fix')
  perfs=$(collect 'perf')

  {
    echo "## What's new in ${VERSION}"
    echo
    [[ -n "${feats}" ]] && { echo "### New"; echo "${feats}" | sed 's/^/- /'; echo; }
    [[ -n "${fixes}" ]] && { echo "### Fixes"; echo "${fixes}" | sed 's/^/- /'; echo; }
    [[ -n "${perfs}" ]] && { echo "### Improvements"; echo "${perfs}" | sed 's/^/- /'; echo; }
    if [[ -z "${feats}${fixes}${perfs}" ]]; then
      echo "Maintenance release."
    fi
  } > "${md_file}"

  # HTML version for Sparkle (body fragment, no <html> wrapper)
  {
    echo "<h2>What's new in ${VERSION}</h2>"
    [[ -n "${feats}" ]] && { echo "<h3>New</h3><ul>"; echo "${feats}" | sed 's|^|<li>|;s|$|</li>|'; echo "</ul>"; }
    [[ -n "${fixes}" ]] && { echo "<h3>Fixes</h3><ul>"; echo "${fixes}" | sed 's|^|<li>|;s|$|</li>|'; echo "</ul>"; }
    [[ -n "${perfs}" ]] && { echo "<h3>Improvements</h3><ul>"; echo "${perfs}" | sed 's|^|<li>|;s|$|</li>|'; echo "</ul>"; }
    if [[ -z "${feats}${fixes}${perfs}" ]]; then
      echo "<p>Maintenance release.</p>"
    fi
  } > "${html_file}"
}

NOTES_MD=$(mktemp -t "gitforge-notes-${VERSION}.XXXXXX.md")
trap 'rm -f "${NOTES_MD}"' EXIT

if (( SKIP_NOTES )); then
  [[ -f "${NOTES_HTML}" ]] || fail "--skip-notes requires ${NOTES_HTML} to exist"
  log "Skipping notes generation, using existing ${NOTES_HTML}"
  # Still need a markdown for gh release. Use the HTML as-is — gh accepts it.
  cp "${NOTES_HTML}" "${NOTES_MD}"
else
  log "Generating release notes from ${RANGE}"
  if (( DRY_RUN )); then
    printf '\033[1;90m[dry-run]\033[0m would generate %s and %s\n' "${NOTES_MD}" "${NOTES_HTML}"
  else
    mkdir -p "${NOTES_DIR}"
    generate_notes "${NOTES_MD}" "${NOTES_HTML}"
    log "Generated notes:"
    sed 's/^/    /' "${NOTES_MD}"
  fi
fi

# ---- 3. Commit version bump + notes ---------------------------------------
log "Staging version bump and notes"
if ! (( DRY_RUN )); then
  git add "${PBXPROJ}"
  [[ -f "${NOTES_HTML}" ]] && git add "${NOTES_HTML}"
  if git diff --cached --quiet; then
    warn "Nothing to commit for the bump (already at ${VERSION} with notes present)"
  else
    git commit -m "release: bump to ${VERSION}"
  fi
fi

# ---- 4. release.sh ---------------------------------------------------------
log "Running release.sh (build / sign / notarize — 5–10 min)"
if (( DRY_RUN )); then
  printf '\033[1;90m[dry-run]\033[0m ./scripts/release.sh\n'
else
  ./scripts/release.sh
  [[ -f "${DMG_PATH}" ]] || fail "release.sh did not produce ${DMG_PATH}"
fi

# ---- 5. Tag ----------------------------------------------------------------
log "Tagging ${TAG}"
run "git tag -a '${TAG}' -m 'gitForge ${VERSION}'"

# ---- 6. GitHub Release -----------------------------------------------------
log "Creating GitHub Release ${TAG}"
if (( DRY_RUN )); then
  printf '\033[1;90m[dry-run]\033[0m gh release create %s %s --title "gitForge %s" --notes-file <generated>\n' \
    "${TAG}" "${DMG_PATH}" "${VERSION}"
else
  gh release create "${TAG}" "${DMG_PATH}" \
    --title "gitForge ${VERSION}" \
    --notes-file "${NOTES_MD}"
fi

# ---- 7. Appcast ------------------------------------------------------------
log "Updating Sparkle appcast"
run "./scripts/update-appcast.sh '${VERSION}'"

# ---- 8. Commit appcast -----------------------------------------------------
log "Committing appcast"
if ! (( DRY_RUN )); then
  git add "${APPCAST}"
  [[ -d "${NOTES_DIR}" ]] && git add "${NOTES_DIR}"
  if git diff --cached --quiet; then
    warn "No appcast changes to commit"
  else
    git commit -m "release: publish ${VERSION} appcast entry"
  fi
fi

# ---- 9. Push ---------------------------------------------------------------
if (( SKIP_PUSH )); then
  warn "--skip-push set. Not pushing to origin. Remember:"
  echo "    git push origin main && git push origin ${TAG}"
else
  log "Pushing to origin (commits + tag)"
  run "git push origin main"
  run "git push origin '${TAG}'"
fi

# ---- Done ------------------------------------------------------------------
log "Shipped gitForge ${VERSION}"
cat <<EOM

  DMG     : ${DMG_PATH}
  Tag     : ${TAG}
  Release : https://github.com/9alvaro0/gitForge/releases/tag/${TAG}
  Appcast : https://9alvaro0.github.io/gitForge/appcast.xml  (rebuilds in ~30–60s)

  Smoke test: open an installed gitForge < ${VERSION}, then Help → Check for Updates…

EOM
