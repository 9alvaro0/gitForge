# gitForge

A modern, native macOS Git client built with SwiftUI.

> Opinionated and focused. Like Fork but native and modern, like GitKraken without the bloat.

## Status

In active development. See [Issues](https://github.com/9alvaro0/gitForge/issues) for the roadmap.

## Features

- **History** — interactive commit graph (branches, tags, stashes as dashed lanes), commit detail with per-file diffs, unified or side-by-side, syntax highlighted
- **Changes** — stage / unstage / discard by file (with batch selection), commit and amend
- **Branches & tags** — create, checkout, rename, delete, move a branch tip; drag a branch onto a commit or another branch to move / merge / rebase; create, push and delete tags
- **Stashes** — stash (optionally with untracked files), apply, pop, drop, browse a stash's files and diffs
- **Conflicts** — visual resolver for merge / rebase / cherry-pick / revert / stash conflicts: pick ours / theirs / both per hunk, or resolve whole files
- **Remotes** — fetch, pull (merge / rebase / fast-forward only), push, force-push with lease, optional background auto-fetch, categorised errors (auth, network, rejected, protected branch…)
- **Pull / merge requests** — read-only list and detail for GitHub and GitLab (including self-hosted), with CI status; integrate a PR locally to resolve its conflicts
- **Clone** — from a URL or by browsing your GitHub / GitLab repositories
- **Identity profiles** — switch the repo's `user.name` / `user.email` / signing key between saved profiles
- Command palette, native menus and keyboard shortcuts; light / dark themes and accessibility support (VoiceOver, Increase Contrast, Reduce Motion)

Not supported (yet): staging individual hunks or lines, interactive rebase, LFS, submodule management, creating or reviewing PRs.

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘O` | Open Repository… |
| `⇧⌘W` | Close Repository |
| `⌘B` | New Branch… |
| `⌘1` … `⌘4` | Show History / Changes / Branches / Pull Requests |
| `⌘K` | Command palette |
| `⌘F` | Filter history (History tab) |
| `⌘R` | Refresh |
| `⇧⌘F` | Fetch |
| `⇧⌘L` | Pull |
| `⇧⌘P` | Push |
| `⇧⌘C` | Go to the commit composer (Changes) |
| `⌘,` | Settings |
| `↑` / `↓` | Move through commits (History table focused) |

The full action set is also exposed through the native menu bar (File / View / Repository / Help).

## Requirements

- macOS 26.1+
- Xcode 26+ (to build)
- `git` CLI (installed with the Xcode Command Line Tools — the app offers to install them)

## Tech Stack

- SwiftUI + `@Observable`, Swift 6 language mode
- Shell-out to the system `git` CLI via `Process` — no libgit2
- No backend, no telemetry, no analytics
- Distribution: signed and notarized DMG, with Sparkle for auto-updates

## Development

```bash
open gitForge.xcodeproj
```

Build and run the unit tests from the command line:

```bash
xcodebuild -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' test
```

The suite (Swift Testing) uses real `git` against throwaway repositories in the temp directory; it never touches your repositories or settings. Under XCTest the app launches as an inert test host (no window, no background work).

### Layout

| Path | Contents |
| --- | --- |
| `gitForge/Core/Git` | `GitCLI` (one actor per repository), process spawning (`GitProcess`), output parsers |
| `gitForge/Core/Watchers` | FSEvents-based repository watcher, auto-fetcher |
| `gitForge/Core/RemoteHosting` | GitHub / GitLab API clients, token storage (Keychain), pinned TLS trust |
| `gitForge/Core/Graph` | Commit graph layout engine |
| `gitForge/App` | App entry point, shell, app-wide stores (`AppState`, `RepositoryCatalog`, preferences) |
| `gitForge/Features` | One folder per screen; `Repository/ViewModel` is the per-repository session plus feature stores (`PullRequestStore`, `StashDetailStore`, `ConflictStore`) |
| `gitForge/DesignSystem` | Tokens (spacing, type scale, colours), theme, shared components, icons |
| `audits/BITACORA.md` | Log of the code-quality audits (in Spanish): findings, fixes and open follow-ups |
| `design/` | Original HTML/CSS design prototype (v1 reference) |
| `scripts/` | Release pipeline — see [`scripts/RELEASE.md`](scripts/RELEASE.md) |

## Updates

gitForge ships with [Sparkle](https://sparkle-project.org). New versions are
fetched in the background once a day from
`https://9alvaro0.github.io/gitForge/appcast.xml`. The DMG must pass an EdDSA
signature check against the embedded `SUPublicEDKey` before installation, so
unsigned or tampered builds are rejected even if served from the right URL.

Manual check: **Help → Check for Updates…**

## License

MIT. See [LICENSE](LICENSE).

## Author

Alvaro Guerra Freitas — [@9alvaro0](https://github.com/9alvaro0)
