#!/bin/bash
#
# Cut a full gitForge release in one shot.
#
# Pipeline:
#   1) Validate (semver, clean tree, on main, tag absent, version not in appcast,
#      release notes present in gitForge/Resources/WhatsNew/whats-new.json)
#   2) Bump MARKETING_VERSION in the Xcode project
#   3) Render release notes from whats-new.json (unless --skip-notes)
#   4) Commit version bump + notes
#   5) release.sh        (build / sign / notarize / DMG)
#   6) git tag vX.Y.Z
#   7) gh release create
#   8) update-appcast.sh (EdDSA-sign DMG, prepend <item>)
#   9) Commit appcast
#   10) Push the appcast commit (the bump commit and tag go up before step 7)
#
# Usage:
#   ./scripts/ship.sh <version> [--dry-run] [--skip-notes] [--skip-push] [--yes]
#
# Examples:
#   ./scripts/ship.sh 1.0.2
#   ./scripts/ship.sh 1.0.3 --dry-run
#   ./scripts/ship.sh 1.0.4 --skip-notes   # use docs/releases/v1.0.4.html as-is
#
# The release notes are written beforehand with Claude ("prepara las
# novedades de la X.Y.Z"), which leaves one local commit on main touching only
# whats-new.json. Local main may be ahead of origin/main by such commits only;
# they go up with the version bump.

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
      sed -n '2,30p' "$0"; exit 0 ;;
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
WHATS_NEW="gitForge/Resources/WhatsNew/whats-new.json"

# ---- Preflight -------------------------------------------------------------
require git
require gh
require xcodebuild
require jq

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

# Up to date with origin. Local main may be ahead only by commits that touch
# nothing but the release notes; they are pushed with the bump.
git fetch origin --quiet
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
NOTES_AHEAD=0
if [[ -n "${REMOTE}" && "${LOCAL}" != "${REMOTE}" ]]; then
  git merge-base --is-ancestor "${REMOTE}" "${LOCAL}" \
    || fail "Local main is behind or has diverged from origin/main. Pull first."
  for commit in $(git rev-list "${REMOTE}..${LOCAL}"); do
    # A merge commit lists no files here, so it is refused too.
    files=$(git diff-tree --no-commit-id --name-only -r "${commit}")
    [[ "${files}" == "${WHATS_NEW}" ]] \
      || fail "Local main is ahead of origin/main with more than release notes ($(git log -1 --format='%h %s' "${commit}")). Push or drop it first."
  done
  NOTES_AHEAD=$(git rev-list --count "${REMOTE}..${LOCAL}")
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

# Release notes written and well formed: the app shows them after updating,
# so this holds with --skip-notes too.
./scripts/release-notes.sh check "${VERSION}" || exit 1

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

cat <<SUMMARY

  Version       : ${VERSION}
  Notes ahead   : ${NOTES_AHEAD} commit(s), pushed with the release
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

# Sparkle compares the appcast's sparkle:version against CFBundleVersion
# (CURRENT_PROJECT_VERSION), so the build number must match the version
# published there, or an installed build keeps being offered itself.
log "Setting CURRENT_PROJECT_VERSION to ${VERSION}"
if (( DRY_RUN )); then
  printf '\033[1;90m[dry-run]\033[0m sed -i "" -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = %s;/g" %s\n' \
    "${VERSION}" "${PBXPROJ}"
else
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${VERSION};/g" "${PBXPROJ}"
  if grep -E "CURRENT_PROJECT_VERSION = " "${PBXPROJ}" | grep -vq "CURRENT_PROJECT_VERSION = ${VERSION};"; then
    fail "Some CURRENT_PROJECT_VERSION entries were not set to ${VERSION}. Aborting."
  fi
fi

# ---- 2. Render release notes ----------------------------------------------
# One escaped HTML file serves Sparkle and the GitHub Release body.
if (( SKIP_NOTES )); then
  [[ -f "${NOTES_HTML}" ]] || fail "--skip-notes requires ${NOTES_HTML} to exist"
  log "Skipping notes generation, using existing ${NOTES_HTML}"
else
  log "Rendering release notes from ${WHATS_NEW}"
  if (( DRY_RUN )); then
    printf '\033[1;90m[dry-run]\033[0m ./scripts/release-notes.sh render %s %s\n' "${VERSION}" "${NOTES_HTML}"
  else
    mkdir -p "${NOTES_DIR}"
    ./scripts/release-notes.sh render "${VERSION}" "${NOTES_HTML}"
    log "Rendered notes:"
    sed 's/^/    /' "${NOTES_HTML}"
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

# gh release create refuses a tag that only exists locally, so the bump
# commit and the tag go up before the release is created.
if (( SKIP_PUSH )); then
  warn "--skip-push set. Stopping before the GitHub Release, which needs the tag on origin. Remember:"
  echo "    git push origin main && git push origin ${TAG}"
  echo "    then gh release create, ./scripts/update-appcast.sh ${VERSION}, commit and push the appcast"
  exit 0
fi
log "Pushing the bump commit and ${TAG}"
run "git push origin main"
run "git push origin '${TAG}'"

# ---- 6. GitHub Release -----------------------------------------------------
log "Creating GitHub Release ${TAG}"
if (( DRY_RUN )); then
  printf '\033[1;90m[dry-run]\033[0m gh release create %s %s --title "gitForge %s" --notes-file %s\n' \
    "${TAG}" "${DMG_PATH}" "${VERSION}" "${NOTES_HTML}"
else
  gh release create "${TAG}" "${DMG_PATH}" \
    --title "gitForge ${VERSION}" \
    --notes-file "${NOTES_HTML}"
fi

# ---- 7. Appcast ------------------------------------------------------------
log "Updating Sparkle appcast"
run "./scripts/update-appcast.sh '${VERSION}'" \
  || fail "update-appcast.sh failed. ${TAG} and its GitHub Release are already out; finish with ./scripts/update-appcast.sh ${VERSION}, then commit and push ${APPCAST}."

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
log "Pushing the appcast commit"
run "git push origin main"

# ---- Done ------------------------------------------------------------------
log "Shipped gitForge ${VERSION}"
cat <<EOM

  DMG     : ${DMG_PATH}
  Tag     : ${TAG}
  Release : https://github.com/9alvaro0/gitForge/releases/tag/${TAG}
  Appcast : https://9alvaro0.github.io/gitForge/appcast.xml  (rebuilds in ~30–60s)

  Smoke test: open an installed gitForge < ${VERSION}, then Help → Check for Updates…

EOM
