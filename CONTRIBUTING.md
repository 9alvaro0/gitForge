# Contributing to gitForge

Thanks for your interest in gitForge! Bug reports, ideas and pull requests are welcome.

## Reporting bugs and requesting features

Open an [issue](https://github.com/9alvaro0/gitForge/issues/new/choose) and pick the template that fits. Any GitHub account can open issues — no special permissions are needed.

Before opening one, search the [existing issues](https://github.com/9alvaro0/gitForge/issues?q=is%3Aissue) to avoid duplicates.

**Security vulnerabilities:** don't open a public issue. See [SECURITY.md](SECURITY.md).

## Contributing code

You don't need write access to the repository. Contributions go through a **fork**:

1. **Fork** the repository with the *Fork* button on GitHub.
2. **Clone your fork** and add this repository as `upstream`:

   ```bash
   git clone https://github.com/<your-user>/gitForge.git
   cd gitForge
   git remote add upstream https://github.com/9alvaro0/gitForge.git
   ```

3. **Create a branch** from an up-to-date `main`:

   ```bash
   git fetch upstream
   git switch -c fix/short-description upstream/main
   ```

4. **Make your changes**, build and run the tests (see below).
5. **Push to your fork** — not to this repository:

   ```bash
   git push -u origin fix/short-description
   ```

6. **Open a pull request** from `<your-user>/gitForge:<branch>` into `9alvaro0/gitForge:main`. GitHub shows a *Compare & pull request* button after the push.

> If `git push` fails with `403` / `Permission denied`, you are pushing to `9alvaro0/gitForge` instead of your fork. Check `git remote -v`: `origin` must point to your fork.

For larger changes (new features, refactors, UI changes), please open an issue first so we can agree on the approach before you spend time on it.

### Keeping your branch up to date

```bash
git fetch upstream
git merge upstream/main   # or: git rebase upstream/main, then git push --force-with-lease
```

## Development setup

Requirements:

- macOS 26.1+
- Xcode 26+
- `git` CLI (Xcode Command Line Tools)

Open the project in Xcode:

```bash
open gitForge.xcodeproj
```

Or build and run the tests from the command line (the same command CI runs):

```bash
xcodebuild test \
  -project gitForge.xcodeproj \
  -scheme gitForge \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO
```

The test suite (Swift Testing) runs real `git` against throwaway repositories in the temp directory. Some tests create commits, so you need a global git identity (`user.name` / `user.email`) configured.

`scripts/make-manual-test-repo.sh` creates a sample repository with branches, stashes and conflicts that is useful for manual testing.

See the [Layout section of the README](README.md#layout) for an overview of the codebase.

## Guidelines

- **Swift 6 language mode**, SwiftUI with `@Observable`. Follow the style of the surrounding code.
- **Git access goes through `GitCLI`** (shell-out to the system `git`); don't add libgit2 or other Git libraries.
- **No telemetry, analytics or backend.** gitForge only talks to the Git remotes and the GitHub / GitLab APIs the user configures.
- **UI** uses the tokens and components in `gitForge/DesignSystem`. Check light and dark mode, and keep VoiceOver, Increase Contrast and Reduce Motion working.
- **Localization**: the app ships in English, Spanish (`es`) and European Portuguese (`pt-PT`) via `gitForge/Localizable.xcstrings`. SwiftUI literals (`Text("…")`, `Button("…")`, `.help("…")`) are picked up automatically; user-facing text typed as `String` (component titles, enum labels, toasts, errors) must use `String(localized: "…")`. Add the `es` and `pt-PT` translations for every new string in the catalog. Tests run in English (see `gitForge.xctestplan`).
- **Add or update tests** for changes in `Core` (git operations, parsers, graph layout).
- **Keep pull requests focused**: one fix or feature per PR.

### Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: arrow-key navigation in file lists
fix: horizontal diff scroll reaches the end of long lines
docs: release notes for 1.2.0
```

Common types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`.

## Pull request review

- CI (build and tests on macOS) must pass.
- A maintainer reviews every PR and may ask for changes.
- PRs are merged into `main` by a maintainer; releases are cut from `main` (see [`scripts/RELEASE.md`](scripts/RELEASE.md)).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
