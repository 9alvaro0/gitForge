# gitForge

A modern, native macOS Git client built with SwiftUI.

> Opinionated and focused. Like Fork but native and modern, like GitKraken without the bloat.

## Status

In active development. See [Issues](https://github.com/9alvaro0/gitForge/issues) for the MVP roadmap organized by Epic.

## MVP Features

- Visual interactive commit graph with branches and tags
- Repository management with drag and drop
- Status, staging by file or by hunk, side-by-side diff viewer
- Commit and amend workflows
- Branch management (create, checkout, delete, rename)
- Push, pull, fetch with clear error feedback
- Keyboard shortcuts and native macOS menus

Explicitly **not** in the MVP: OAuth integration with GitHub/GitLab, PR/issue management, visual conflict resolver, interactive rebase visual, LFS, submodules, custom themes.

## Requirements

- macOS 26.1+
- Xcode 26+
- `git` CLI (installed via Xcode Command Line Tools)

## Tech Stack

- SwiftUI + `@Observable`
- Shell-out to the system `git` CLI via `Process`
- No backend, no telemetry, no analytics
- Distribution: signed and notarized DMG

## License

MIT. See [LICENSE](LICENSE).

## Author

Alvaro Guerra Freitas — [@9alvaro0](https://github.com/9alvaro0)
