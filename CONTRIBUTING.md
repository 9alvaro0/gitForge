# Contributing to gitForge

Thanks for your interest. Issues and pull requests are welcome.

## Before you start

- **Bugs:** open an issue with the bug report template. Include the gitForge and macOS versions and steps to reproduce.
- **Features:** open an issue first and describe the problem you want solved. gitForge is opinionated and focused, so not every feature will fit; agreeing on the idea before writing code saves both of us time.
- **Security issues:** don't open a public issue. See [SECURITY.md](SECURITY.md).

## Building

Requirements: macOS 26.1+ and Xcode 26+.

```bash
open gitForge.xcodeproj
```

Run the test suite from the command line:

```bash
xcodebuild -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' test
```

The suite uses real `git` against throwaway repositories in the temp directory; it never touches your repositories or settings.

## Pull requests

1. Fork the repository and create a branch from `main` (`feat/…`, `fix/…`).
2. Keep each PR to one focused change.
3. Add or update tests for behaviour changes. Views are checked by hand; models, stores and the `git` layer have tests.
4. Make sure the project builds and the tests pass. CI runs the same suite on every PR; a maintainer approves the run for outside contributors.
5. Open the PR against `main` and fill in the template.

### Conventions

- Code, comments and commit messages in English.
- Commit messages follow `type: description`, with `type` one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`. Example: `fix: keep the selection after a stash`.
- Follow the style of the surrounding code: SwiftUI with `@Observable`, Swift 6 language mode, design tokens from `gitForge/DesignSystem` instead of hard-coded values.
- Don't add dependencies without discussing it in an issue first.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
