#!/bin/bash
#
# Validate or render one release's notes from the What's New file.
#
# Usage:
#   ./scripts/release-notes.sh check <version>
#   ./scripts/release-notes.sh render <version> <html-out> <md-out>
#
# The app bundles gitForge/Resources/WhatsNew/whats-new.json and shows its
# highlights after an update; `render` writes the English text as the HTML
# Sparkle shows and the markdown of the GitHub Release. Set WHATS_NEW_FILE to
# read another file (fixtures).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="${WHATS_NEW_FILE:-${ROOT}/gitForge/Resources/WhatsNew/whats-new.json}"

fail()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }
usage() { sed -n '5,7p' "$0" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || fail "Missing dependency: jq"

# Shared jq helpers: the entry for $v, and a title ending in punctuation.
JQ_DEFS='
def entry: .releases[] | select(.version == $v);
def dotted: if test("[.!?]$") then . else . + "." end;
'

check() {
  local version="$1"
  [[ -f "${FILE}" ]] || fail "${FILE} not found."
  jq empty "${FILE}" >/dev/null 2>&1 || fail "${FILE} is not valid JSON."

  local count
  count=$(jq --arg v "${version}" "${JQ_DEFS}"'[.releases[]? | select(.version == $v)] | length' "${FILE}")
  (( count > 0 )) || fail "No release notes for ${version} in ${FILE}. Prepare them first: ask Claude to \"prepara las novedades de la ${version}\"."
  (( count == 1 )) || fail "${version} appears ${count} times in ${FILE}."

  jq -e --arg v "${version}" "${JQ_DEFS}"'entry | .highlights | type == "array"' "${FILE}" >/dev/null \
    || fail "${version} in ${FILE} needs a \"highlights\" array (empty when it only has fixes)."

  jq -e --arg v "${version}" "${JQ_DEFS}"'
    entry
    | [(.highlights[] | .title, .body), (.fixes // [])[], (.improvements // [])[]]
    | all(type == "object" and ((.en // "") | type == "string" and length > 0))' "${FILE}" >/dev/null 2>&1 \
    || fail "Every text of ${version} in ${FILE} needs a non-empty English (\"en\") version."
}

render() {
  local version="$1" html_out="$2" md_out="$3"
  check "${version}"

  jq -j --arg v "${version}" "${JQ_DEFS}"'
    def list: if length > 0 then "<ul>\n" + (map("<li>" + . + "</li>\n") | join("")) + "</ul>\n" else "" end;
    entry
    | [.highlights[] | "<strong>" + (.title.en | dotted | @html) + "</strong> " + (.body.en | @html)] as $highlights
    | [(.fixes // [])[] | .en | @html] as $fixes
    | [(.improvements // [])[] | .en | @html] as $improvements
    | "<h2>What'"'"'s new in \($v)</h2>\n"
      + if ($highlights + $fixes + $improvements | length) == 0 then
          "<p>Maintenance release.</p>\n"
        else
          ($highlights | list)
          + (if ($fixes | length) > 0 then "<h3>Fixes</h3>\n" + ($fixes | list) else "" end)
          + (if ($improvements | length) > 0 then "<h3>Improvements</h3>\n" + ($improvements | list) else "" end)
        end' "${FILE}" > "${html_out}"

  jq -j --arg v "${version}" "${JQ_DEFS}"'
    entry
    | [.highlights[] | "- **" + (.title.en | dotted) + "** " + .body.en] as $highlights
    | [(.fixes // [])[] | "- " + .en] as $fixes
    | [(.improvements // [])[] | "- " + .en] as $improvements
    | [
        "## What'"'"'s new in \($v)",
        (if ($highlights + $fixes + $improvements | length) == 0 then "Maintenance release." else empty end),
        (if ($highlights | length) > 0 then ($highlights | join("\n")) else empty end),
        (if ($fixes | length) > 0 then "### Fixes\n" + ($fixes | join("\n")) else empty end),
        (if ($improvements | length) > 0 then "### Improvements\n" + ($improvements | join("\n")) else empty end)
      ]
    | join("\n\n") + "\n"' "${FILE}" > "${md_out}"
}

case "${1:-}" in
  check)  [[ $# -eq 2 ]] || usage; check "$2" ;;
  render) [[ $# -eq 4 ]] || usage; render "$2" "$3" "$4" ;;
  *)      usage ;;
esac
