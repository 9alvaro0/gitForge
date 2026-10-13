#!/usr/bin/env bash
# Builds the throwaway repo that audits/PRUEBAS-MANUALES.md asks for:
# - notes.txt with two separate hunks unstaged and a third one staged;
# - an untracked file and a whitespace-only change;
# - main and feature with their own commits (feature not merged), plus a
#   merged branch for the "merged" badge;
# - a local bare remote "origin" with main pushed and feature unpushed.
#
# Usage: scripts/make-manual-test-repo.sh [dir]   (default: ~/gitforge-manual-test)
set -euo pipefail

dir="${1:-$HOME/gitforge-manual-test}"
if [[ -e "$dir" ]]; then
  echo "error: $dir already exists; remove it or pass another path" >&2
  exit 1
fi

mkdir -p "$dir"
remote="$dir/remote.git"
repo="$dir/repo"

git init -q --bare -b main "$remote"
git init -q -b main "$repo"
cd "$repo"
git config user.name  "GitForge Tester"
git config user.email "tester@example.com"
git config commit.gpgsign false

# 60 lines so hunks are far apart and "Show N hidden lines" has room.
seq -f "line %g" 1 60 > notes.txt
printf 'a\tb\n' > spaces.txt
echo "# Manual test repo" > README.md
git add . && git commit -qm "Initial commit"
for i in 1 2 3; do echo "main change $i" >> log.txt; git add log.txt; git commit -qm "main: change $i"; done

git remote add origin "$remote"
git push -q -u origin main

# Branch already contained in main → "merged" badge.
git branch merged-topic HEAD~1

git switch -qc feature
for i in 1 2; do echo "feature work $i" >> feature.txt; git add feature.txt; git commit -qm "feature: work $i"; done
git switch -q main
echo "main after feature split" >> log.txt && git commit -qam "main: diverge from feature"

# Staged hunk near the bottom, then two unstaged hunks elsewhere.
sed -i.bak 's/^line 55$/line 55 (staged edit)/' notes.txt && rm notes.txt.bak
git add notes.txt
sed -i.bak -e 's/^line 5$/line 5 (unstaged edit A)/' \
           -e 's/^line 30$/line 30 (unstaged edit B)/' notes.txt && rm notes.txt.bak

printf 'a    b\n' > spaces.txt         # whitespace-only change
echo "brand new file" > untracked.txt  # untracked

echo "Test repo ready: $repo (remote: $remote)"
git status --short
