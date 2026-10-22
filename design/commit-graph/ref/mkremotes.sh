#!/bin/bash
# Builds, in $1 (must not exist), a "server", a second remote "fork" and a working
# clone for the remote branches of the history graph (spec §3.1 and §4):
# - develop is 60 commits behind origin/develop, more than a page with 50-commit
#   pages, so loading the next page must not move what is drawn;
# - feature/login has diverged (1 local commit, 2 on the server);
# - feature/cart (HEAD) is 2 commits ahead of origin/feature/cart;
# - the local main is deleted, so origin/main, with 2 commits only on the server,
#   stands in as the main trunk;
# - release/2.0 only exists on the server (it shows with the Remote branches toggle);
# - the remote "fork" has its own commit on main, so with the toggle on, origin/main
#   and fork/main (and the other shared names) show their remote's prefix.
# Open "$1/work" in gitForge.
set -e
mkdir -p "$1" && cd "$1"
T=1700000000
c() { T=$((T+3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" git commit -q --allow-empty -m "$1"; }
git init -q --bare -b main server.git
git init -q -b main work && cd work
git config user.name T && git config user.email t@t
git remote add origin ../server.git
c "init"; c "main: setup"
git checkout -q -b develop; c "dev: base"
git checkout -q -b feature/login develop; c "login: form"
git checkout -q -b feature/cart develop; c "cart: model"
git push -q -u origin main develop feature/login feature/cart
cd .. && git clone -q server.git other && cd other
git config user.name O && git config user.email o@o
git checkout -q main; c "server: hotfix 1"; c "server: hotfix 2"
git checkout -q develop; for i in $(seq 1 60); do c "server: develop $i"; done
git checkout -q feature/login; c "login: server api"; c "login: server tests"
git checkout -q -b release/2.0 main; c "release: 2.0"
git push -q origin main develop feature/login release/2.0
cd .. && git clone -q --bare server.git fork.git
cd other && git remote add fork ../fork.git && git checkout -q main && c "fork: experiment" && git push -q fork main
cd ../work
git remote add fork ../fork.git
git checkout -q feature/login; c "login: local validation"
git checkout -q feature/cart; c "cart: payment"; c "cart: summary"
git branch -q -D main
git fetch -q --all
git remote set-head origin main
git log --oneline --graph --all | head -30
