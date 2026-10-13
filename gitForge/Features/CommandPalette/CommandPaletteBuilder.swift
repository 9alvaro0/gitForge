import Foundation

/// Aggregates palette items from app + repository state.
enum CommandPaletteBuilder {
    /// Enough for a single-group scope to be worth searching; All still
    /// shows a few per group (`CommandPaletteSections`).
    static let commitLimit = 300
    static let branchLimit = 300
    static let fileLimit = 300

    @MainActor
    static func build(repositories: [Repository],
                      branches: [GitRef],
                      commits: [Commit],
                      workingFiles: [WorkingCopyFile]) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        for repo in repositories {
            items.append(CommandPaletteItem(
                kind: .repo,
                label: "\(orgName(for: repo))/\(repo.name)",
                hint: nil,
                action: .openRepo(repo.url)
            ))
        }

        for c in commits.prefix(commitLimit) {
            items.append(CommandPaletteItem(
                kind: .commit,
                label: c.subject,
                hint: c.shortSha,
                action: .revealCommit(sha: c.sha)
            ))
        }

        for b in branches.prefix(branchLimit) {
            items.append(CommandPaletteItem(
                kind: .branch,
                label: b.displayName,
                hint: branchHint(for: b),
                action: .revealBranch(b)
            ))
        }

        for f in workingFiles.prefix(fileLimit) {
            items.append(CommandPaletteItem(
                kind: .file,
                label: f.path,
                hint: f.unstagedStatus.displayLetter == " " ? f.stagedStatus.displayLetter : f.unstagedStatus.displayLetter,
                action: .revealFile(path: f.path)
            ))
        }

        items.append(contentsOf: builtInCommands)
        return items
    }

    static let builtInCommands: [CommandPaletteItem] = [
        CommandPaletteItem(kind: .command, label: "Open repository…",  hint: "⌘O",  action: .openRepository),
        CommandPaletteItem(kind: .command, label: "Clone repository…", hint: "⌥⌘C", action: .cloneRepository),
        CommandPaletteItem(kind: .command, label: "Fetch all",       hint: "⌘⇧F", action: .fetch),
        CommandPaletteItem(kind: .command, label: "Pull",            hint: "⌘⇧L", action: .pull),
        CommandPaletteItem(kind: .command, label: "Push",            hint: "⌘⇧P", action: .push),
        CommandPaletteItem(kind: .command, label: "New branch…",     hint: "⌘⇧B", action: .selectSection(.branches)),
        CommandPaletteItem(kind: .command, label: "Stash changes",   hint: nil,   action: .stash),
        CommandPaletteItem(kind: .command, label: "Settings",        hint: "⌘,",  action: .selectSection(.settings)),
    ]

    private static func orgName(for repo: Repository) -> String {
        repo.url.deletingLastPathComponent().lastPathComponent
    }

    private static func branchHint(for ref: GitRef) -> String {
        switch ref.kind {
        case .localBranch:        return "local"
        case .remoteBranch:       return "remote"
        case .tag:                return "tag"
        }
    }
}
