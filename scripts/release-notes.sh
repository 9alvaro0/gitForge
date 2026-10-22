#!/bin/bash
#
# Validate or render one release's notes from the What's New file.
#
# Usage:
#   ./scripts/release-notes.sh check <version>
#   ./scripts/release-notes.sh render <version> <html-out>
#
# The app bundles gitForge/Resources/WhatsNew/whats-new.json and shows its
# highlights after an update; `render` writes the English text as escaped HTML,
# which Sparkle shows and the GitHub Release uses as its body. `check` also
# makes sure the app can read the whole file: if it can't, the app shows no
# What's New at all. Set WHATS_NEW_FILE to read another file (fixtures).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="${WHATS_NEW_FILE:-${ROOT}/gitForge/Resources/WhatsNew/whats-new.json}"

fail()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }
usage() { sed -n '5,7p' "$0" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || fail "Missing dependency: jq"

# Shared jq helpers: the entry for $v, a title ending in punctuation, and the
# shape the app's decoder accepts (WhatsNewCatalog.swift).
JQ_DEFS='
def entry: .releases[] | select(.version == $v);
def dotted: if test("[.!?]$") then . else . + "." end;
def text_ok: type == "object" and all(.[]; type == "string");
def texts_ok: . == null or (type == "array" and all(.[]; text_ok));
def release_ok:
  type == "object"
  and (.version | type == "string")
  and (.highlights | type == "array")
  and all(.highlights[];
          type == "object"
          and (.symbol | . == null or type == "string")
          and (.title | text_ok)
          and (.body | text_ok))
  and (.fixes | texts_ok)
  and (.improvements | texts_ok);
'

check() {
  local version="$1"
  [[ -f "${FILE}" ]] || fail "${FILE} not found."
  jq empty "${FILE}" >/dev/null 2>&1 || fail "${FILE} is not valid JSON."

  # One unreadable entry, of any version, empties the app's catalog.
  local unreadable
  unreadable=$(jq -r "${JQ_DEFS}"'
    if type == "object" and (.releases | type == "array") then
      [.releases[] | select(release_ok | not) | (.version? // "?") | tostring] | join(", ")
    else "the whole file (it needs a \"releases\" array)" end' "${FILE}")
  [[ -z "${unreadable}" ]] \
    || fail "${FILE} has entries the app can't read: ${unreadable}. Every text is a string, \"symbol\" is a string, \"highlights\" an array, \"fixes\" and \"improvements\" arrays when present."

  local count
  count=$(jq --arg v "${version}" "${JQ_DEFS}"'[.releases[] | select(.version == $v)] | length' "${FILE}")
  (( count > 0 )) || fail "No release notes for ${version} in ${FILE}. Prepare them first: ask Claude to \"prepara las novedades de la ${version}\"."
  (( count == 1 )) || fail "${version} appears ${count} times in ${FILE}."

  jq -e --arg v "${version}" "${JQ_DEFS}"'
    entry
    | [(.highlights[] | .title, .body), (.fixes // [])[], (.improvements // [])[]]
    | all(type == "object" and ((.en // "") | type == "string" and length > 0))' "${FILE}" >/dev/null 2>&1 \
    || fail "Every text of ${version} in ${FILE} needs a non-empty English (\"en\") version."
}

# Escaped HTML only: GitHub renders it as the release body too, where markdown
# would mangle text like `HEAD~1`, `*` or `<branch>`.
render() {
  local version="$1" html_out="$2"
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
}

case "${1:-}" in
  check)  [[ $# -eq 2 ]] || usage; check "$2" ;;
  render) [[ $# -eq 3 ]] || usage; render "$2" "$3" ;;
  *)      usage ;;
esac
