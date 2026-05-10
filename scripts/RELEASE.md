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

One command does the full pipeline:

```bash
./scripts/ship.sh 1.0.2
```

This orchestrates: validate → bump `MARKETING_VERSION` → generate release
notes from `git log v{prev}..HEAD` (grouped into New / Fixes / Improvements)
→ commit → `release.sh` → tag → `gh release create` → `update-appcast.sh`
→ commit appcast → push commits + tag.

Useful flags:

- `--dry-run` — print every step without doing anything.
- `--skip-notes` — skip auto-generation; expects `docs/releases/v<version>.html`
  to already exist (write notes by hand first).
- `--skip-push` — stop before pushing to origin.
- `--yes` / `-y` — skip the interactive confirmation prompt.

Preflight refuses to run if: not on `main`, working tree dirty, local out of
sync with `origin/main`, tag already exists, or version already in
`docs/appcast.xml`.

If you prefer to drive each step manually, the underlying scripts still work
standalone: `release.sh` (build/sign/notarize), `update-appcast.sh <version>`
(EdDSA-sign + prepend `<item>`).

Within 24 hours, every running gitForge ≥ 1.0.2 picks up the update on its
next background check. Users can also force a check from **Help → Check for
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
