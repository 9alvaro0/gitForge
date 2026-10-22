#!/bin/bash
# Builds, in $1 (must not exist), a "server" and a working clone whose main is
# six commits behind origin/main. On the server, main gained three commits and a
# topic branch, forked from the clone's main, merged main after the first of
# them; then main merged the topic. In History that first merge's second parent
# sits a few rows down, past main's later commits, so it gets a track of its own
# (spec §3.3): an S out of the merge, a line down and an S into the parent. A CI
# tag on the server tip makes History load those server-only commits, which the
# graph draws as ghosts (spec §4.3). The clone also has a local feature branch
# (HEAD) and a stash.
# Open "$1/work" in gitForge.
set -e
mkdir -p "$1" && cd "$1"
T=1700000000
c() { T=$((T+3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" git commit -q --allow-empty -m "$1"; }
m() { T=$((T+3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" git merge -q --no-ff -m "$1" "$2"; }
git init -q --bare -b main server.git
git init -q -b main work && cd work
git config user.name T && git config user.email t@t
git remote add origin ../server.git
c "init"; c "main: setup"
git push -q -u origin main
cd .. && git clone -q server.git other && cd other
git config user.name O && git config user.email o@o
c "server: fix A"
git checkout -q -b topic HEAD~1; c "topic: draft"; m "topic: merge main" main
git checkout -q main; c "server: fix B"; c "server: release 2"; m "server: merge topic" topic
git push -q origin main
cd ../work
git fetch -q origin
git tag ci-2 origin/main
git checkout -q -b feature/x; c "x: one"; c "x: two"
echo wip > notes.txt && git stash push -q -u -m "wip notes"
git log --oneline --graph --all
