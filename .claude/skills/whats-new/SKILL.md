---
name: whats-new
description: Draft a gitForge release's What's New entry (highlights, fixes, improvements in en, es and pt-PT) in gitForge/Resources/WhatsNew/whats-new.json and commit it locally, ready for ship.sh. Use when the user says "prepara las novedades", "novedades de la X.Y.Z", "release notes for X.Y.Z", "escribe las notas de la versión" or similar. Do not use to ship or publish a release — that is ./scripts/ship.sh, which the user runs.
---

# Prepare a release's What's New

gitForge shows a What's New sheet the first time it opens after an update. Its
content is `gitForge/Resources/WhatsNew/whats-new.json`, one entry per
version; `scripts/ship.sh` refuses to release a version without one and turns
the English text into the Sparkle and GitHub release notes.

Your job: draft the entry for the version the user names, get their OK, write
it, check it and commit it locally. Never push and never run `ship.sh`.

## 1. Check where you are

Run:

```bash
git rev-parse --abbrev-ref HEAD
git rev-parse --git-dir
git rev-parse --git-common-dir
```

Continue only if the branch is `main` and both directories are the same (the
main checkout, not a worktree). Otherwise say so and stop: `ship.sh` runs on
`main` in the main checkout and pushes the notes commit from there.

If other tracked files have uncommitted changes, tell the user `ship.sh` will
refuse to run until they are committed or stashed. Don't touch them.

## 2. Read what changed

```bash
git describe --tags --abbrev=0          # last release tag, e.g. v1.3.0
git log <tag>..HEAD --pretty='%h %s'
```

When a subject doesn't say what the user gets, read its PR (`gh pr view <n>`)
or the diff.

## 3. Sort it

- `highlights`: `feat` commits a user would notice.
- `fixes`: `fix` commits a user could have hit.
- `improvements`: `perf` commits and other changes users feel (faster,
  smoother, clearer).
- Leave out internal work: refactors, tests, docs, CI, chore, release commits.

A version with nothing new for users gets `"highlights": []`. It still needs
its entry, and it won't show the sheet.

## 4. Write it

For each highlight:

- `symbol`: an SF Symbol that exists on macOS 26 and fits the feature.
- `title`: 2 to 5 words, no final period.
- `body`: one sentence on what the user can now do, in their words, not the
  commit subject. Name screens and settings as the app shows them.

Fixes and improvements are one sentence each.

Translate every text to `es` and `pt-PT`. Use the names the app already uses
in `gitForge/Localizable.xcstrings` for each language (Settings is "Ajustes"
in Spanish and "Definições" in Portuguese, for example). Spanish uses "tú";
European Portuguese uses the formal register the app uses ("escolha",
"seus").

Format:

```json
{
  "version": "1.4.0",
  "highlights": [
    {
      "symbol": "sparkles",
      "title": { "en": "…", "es": "…", "pt-PT": "…" },
      "body":  { "en": "…", "es": "…", "pt-PT": "…" }
    }
  ],
  "fixes":        [ { "en": "…", "es": "…", "pt-PT": "…" } ],
  "improvements": [ { "en": "…", "es": "…", "pt-PT": "…" } ]
}
```

## 5. Review with the user

Show one table per highlight (rows: symbol, title, body; columns: en, es,
pt-PT), then the fixes and improvements. Wait for their OK or changes. Don't
write the file before they accept.

## 6. Write and check

Add the entry at the top of `releases` in
`gitForge/Resources/WhatsNew/whats-new.json`, keeping the file's 2-space
formatting. Then:

```bash
./scripts/release-notes.sh check <version>
```

Fix anything it reports.

## 7. Commit locally

Commit only that file:

```bash
git add gitForge/Resources/WhatsNew/whats-new.json
git commit -m "docs: release notes for <version>" -- gitForge/Resources/WhatsNew/whats-new.json
```

Don't push. `ship.sh` accepts local `main` being ahead of `origin/main` by
commits that only touch this file, and pushes them with the version bump.

## 8. Hand over

Tell the user the next step is `./scripts/ship.sh <version>`, run by them from
the terminal panel (`--dry-run` first if they want to check).
