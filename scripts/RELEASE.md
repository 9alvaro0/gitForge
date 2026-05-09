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

For every new version (e.g. 1.0.2):

```bash
# 1. Bump MARKETING_VERSION in Xcode (target → General → Version)

# 2. Optional: write release notes for Sparkle's update sheet
#    docs/releases/v1.0.2.html  (plain HTML body — no <html> wrapper needed)

# 3. Build, sign, notarize, package
./scripts/release.sh

# 4. Publish DMG to GitHub Releases (Sparkle reads the URL from the appcast)
gh release create v1.0.2 dist/gitForge-1.0.2.dmg \
   --title "gitForge 1.0.2" \
   --notes-file path/to/release-notes.md

# 5. Sign DMG with EdDSA and prepend a new <item> to docs/appcast.xml
./scripts/update-appcast.sh 1.0.2

# 6. Commit and push the appcast (triggers GitHub Pages rebuild ~30s later)
git add docs/appcast.xml docs/releases/
git commit -m "release: v1.0.2"
git push
```

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

- `scripts/release.sh` — build / sign / notarize / DMG.
- `scripts/update-appcast.sh` — EdDSA-sign DMG and update appcast.
- `gitForge/Info.plist` — `SUFeedURL`, `SUPublicEDKey`, check policy.
- `gitForge/App/State/Updater.swift` — observable wrapper around
  `SPUStandardUpdaterController`.
- `docs/appcast.xml` — Sparkle feed (served by GitHub Pages).
- `docs/releases/v<version>.html` — optional per-release notes shown inline
  in Sparkle's update sheet.
