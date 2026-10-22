# Release pipeline

How to cut a new gitForge release.

## One-time setup

These only run once, the first time gitForge is released with Sparkle.

### 1. Generate the EdDSA key pair

Sparkle's `generate_keys` stores the private key in the macOS Keychain and
prints the public key. Locate the binary under DerivedData (Sparkle ships it
as part of the SPM artifact bundle):

```bash
find ~/Library/Developer/Xcode/DerivedData -path "*Sparkle/bin/generate_keys" -type f
```

Run it with the project-specific account name:

```bash
<path-to-generate_keys> --account gitForge-sparkle-private
```

The Keychain will prompt for permission to save the new key. Allow it.

The command prints the public key, e.g.

```
SUPublicEDKey
abc123...XYZ
```

### 2. Embed the public key into Info.plist

Replace the `PUBKEY_PLACEHOLDER_REPLACE_AFTER_GENERATE_KEYS` string in
`gitForge/Info.plist` with the printed public key. Commit.

> **Lose this Keychain item and existing users can no longer auto-update.**
> Back up the private key with `<generate_keys> --account gitForge-sparkle-private -x backup.pem`
> and store the file somewhere safe (offline, encrypted).

### 3. Enable GitHub Pages

In GitHub: **Settings → Pages → Source: Deploy from a branch → Branch: main /
docs**. The feed will be served at
`https://9alvaro0.github.io/gitForge/appcast.xml`.

## Per-release steps

### 1. Prepare the release notes

The notes live in `gitForge/Resources/WhatsNew/whats-new.json`, one entry per
version, each text in English, Spanish and European Portuguese. The app ships
that file and shows the version's highlights the first time it opens after
updating; the English text also becomes the Sparkle and GitHub Release notes.

Write them with Claude in the main checkout, on `main`:

> prepara las novedades de la 1.4.0

The `whats-new` skill reads the commits since the last tag, drafts the entry
(highlights with an SF Symbol, title and one sentence; fixes; improvements)
and its translations, and waits for your review. Once you accept it, it runs
`./scripts/release-notes.sh check 1.4.0` and leaves one local commit touching
only `whats-new.json`. It does not push.

A release with nothing new for users gets an entry with `"highlights": []`:
it still needs one, but it doesn't show the What's New sheet.

### 2. Ship

One command does the full pipeline:

```bash
./scripts/ship.sh 1.1.0
```

This orchestrates: validate → bump `MARKETING_VERSION` and set `CURRENT_PROJECT_VERSION` to the
same value (Sparkle compares the appcast's `sparkle:version` against
`CFBundleVersion`) → render the release notes from `whats-new.json`
(`scripts/release-notes.sh render`) → commit → `release.sh` → tag → push
commit + tag → `gh release create` → `update-appcast.sh` → commit and push the
appcast.

Useful flags:

- `--dry-run` — print every step without doing anything.
- `--skip-notes` — don't render; expects `docs/releases/v<version>.html` to
  already exist (written by hand). The entry in `whats-new.json` is still
  required, because the app shows it.
- `--skip-push` — stop after tagging, before pushing to origin (the GitHub
  Release needs the tag on origin, so it is skipped too).
- `--yes` / `-y` — skip the interactive confirmation prompt.

Preflight refuses to run if: not on `main`, working tree dirty, local `main`
behind or diverged from `origin/main`, local `main` ahead with any commit that
touches more than `whats-new.json`, tag already exists, version already in
`docs/appcast.xml`, or no valid entry for the version in `whats-new.json`.
Commits ahead that only touch the notes are pushed with the bump.

If you prefer to drive each step manually, the underlying scripts still work
standalone: `release.sh` (build/sign/notarize), `update-appcast.sh <version>`
(EdDSA-sign + prepend `<item>`).

Within 24 hours, every running gitForge ≥ 1.1.0 picks up the update on its
next background check (every 6 hours after 1.2.0; newer versions also
download it silently and install it on quit). Users can also force a check from **Help → Check for
Updates…**.

## Smoke test

After the first Sparkle-signed release ships, validate the loop end-to-end:

1. Build a "current" version (say 1.0.2) with Sparkle integrated.
2. Install the DMG.
3. Bump to 1.0.3, run the per-release steps above.
4. Open the installed 1.0.2, choose **Help → Check for Updates…**.
5. The update sheet should show 1.0.3 with release notes; install proceeds
   without Gatekeeper warnings.

## Files involved

- `scripts/ship.sh` — single-command release orchestrator.
- `scripts/release.sh` — build / sign / notarize / DMG.
- `scripts/update-appcast.sh` — EdDSA-sign DMG and update appcast.
- `gitForge/Info.plist` — `SUFeedURL`, `SUPublicEDKey`, check policy.
- `gitForge/App/State/Updater.swift` — observable wrapper around
  `SPUStandardUpdaterController`.
- `docs/appcast.xml` — Sparkle feed (served by GitHub Pages).
- `docs/releases/v<version>.html` — optional per-release notes shown inline
  in Sparkle's update sheet.
