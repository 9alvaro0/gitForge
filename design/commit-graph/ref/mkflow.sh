#!/bin/bash
# Builds a synthetic gitflow repo in $1 (must not exist).
set -e
mkdir -p "$1" && cd "$1"
git init -q -b main && git config user.name T && git config user.email t@t
T=1700000000
c() { T=$((T+3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" git commit -q --allow-empty -m "$1"; }
m() { T=$((T+3600)); GIT_AUTHOR_DATE="@$T" GIT_COMMITTER_DATE="@$T" git merge -q --no-ff --no-edit -m "$2" "$1"; }
c "init"; c "main: setup"; git tag v1.0
git checkout -q -b develop; c "dev: base"
git checkout -q -b feature/login; c "login: form"; c "login: api"
git checkout -q develop; git checkout -q -b feature/cart; c "cart: model"
git checkout -q develop; c "dev: tweak"
git checkout -q feature/login; c "login: tests"
git checkout -q develop; m feature/login "Merge feature/login into develop"
git checkout -q feature/cart; c "cart: ui"; m develop "Merge develop into feature/cart"
git checkout -q main; git checkout -q -b hotfix/crash; c "hotfix: crash"
git checkout -q main; m hotfix/crash "Merge hotfix/crash"; git tag v1.0.1
git checkout -q develop; m hotfix/crash "Merge hotfix/crash into develop"
git checkout -q -b release/1.1; c "release: bump 1.1"
git checkout -q feature/cart; c "cart: checkout"
git checkout -q release/1.1; c "release: fix typo"
git checkout -q main; m release/1.1 "Merge release/1.1"; git tag v1.1
git checkout -q develop; m release/1.1 "Merge release/1.1 into develop"
git checkout -q -b feature/search; c "search: index"; c "search: ui"
git checkout -q feature/cart; c "cart: payment"
git checkout -q develop; c "dev: deps bump"
git checkout -q feature/search; c "search: ranking"
git checkout -q develop
git log --oneline --graph --all
