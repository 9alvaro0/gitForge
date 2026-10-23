import Foundation

/// Aggregates palette items from app + repository state.
enum CommandPaletteBuilder {
    /// Enough for a single-group scope to be worth searching; All still
    /// shows a few per group (`CommandPaletteSections`).
    static let commitLimit = 300
    static let branchLimit = 300
    static let fileLimit = 300
    static let pullLimit = 300

    /// `pulls` are the inbox's, already in the order ⌘K keeps them in
    /// (`ReviewsStore.searchablePulls`); `unclonedRepos` are the followed
    /// repos with no clone, listed after the local ones.
    @MainActor
    static func build(repositories: [Repository],
                      branches: [GitRef],
                      commits: [Commit],
                      workingFiles: [WorkingCopyFile],
                      pulls: [InboxPull] = [],
                      unclonedRepos: [ReviewRepo] = []) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        for repo in repositories {
            items.append(CommandPaletteItem(
                kind: .repo,
                label: "\(orgName(for: repo))/\(repo.name)",
                hint: nil,
                action: .openRepo(repo.url)
            ))
        }

        for repo in unclonedRepos {
            items.append(CommandPaletteItem(
                kind: .repo,
                label: repo.host.slug,
                hint: String(localized: "Not cloned"),
                action: .showReviews(repoKey: repo.id)
            ))
        }

        for inbox in pulls.prefix(pullLimit) {
            items.append(pullItem(inbox))
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

    /// The row a pasted pull request link adds above the results, if `query`
    /// is one: "Open <repo> <ref>" for a link on a declared instance, "Add as
    /// <kind> instance…" for one on a host that isn't. Anything else, none.
    static func linkItems(for query: String, instances: [HostingInstance]) -> [CommandPaletteItem] {
        if let link = PullRequestLink.parse(query, instances: instances) {
            let reference = link.host.provider.reference(link.number)
            return [CommandPaletteItem(
                kind: .pull,
                label: String(localized: "Open \(link.host.repo) \(reference)"),
                hint: link.host.owner,
                action: .openPullLink(link)
            )]
        }
        if let suggestion = PullRequestLink.suggestion(for: query, instances: instances) {
            return [CommandPaletteItem(
                kind: .pull,
                label: String(localized: "Add as \(suggestion.kind.label) instance…"),
                hint: suggestion.host,
                action: .addInstance(kind: suggestion.kind, host: suggestion.host)
            )]
        }
        return []
    }

    static let builtInCommands: [CommandPaletteItem] = [
        CommandPaletteItem(kind: .command, label: String(localized: "Open repository…"),  hint: "⌘O",  action: .openRepository),
        CommandPaletteItem(kind: .command, label: String(localized: "Clone repository…"), hint: "⌥⌘C", action: .cloneRepository),
        CommandPaletteItem(kind: .command, label: String(localized: "Fetch all"),       hint: "⌘⇧F", action: .fetch),
        CommandPaletteItem(kind: .command, label: String(localized: "Pull"),            hint: "⌘⇧L", action: .pull),
        CommandPaletteItem(kind: .command, label: String(localized: "Push"),            hint: "⌘⇧P", action: .push),
        CommandPaletteItem(kind: .command, label: String(localized: "New branch…"),     hint: "⌘⇧B", action: .selectSection(.branches)),
        CommandPaletteItem(kind: .command, label: String(localized: "Stash changes"),   hint: nil,   action: .stash),
        CommandPaletteItem(kind: .command, label: String(localized: "Settings"),        hint: "⌘,",  action: .selectSection(.settings)),
    ]

    /// A pull request by its title, found too by its repo path, branch,
    /// author and number (R2 Ruling 5).
    private static func pullItem(_ inbox: InboxPull) -> CommandPaletteItem {
        let host = inbox.repo.host
        let pull = inbox.pull
        return CommandPaletteItem(
            kind: .pull,
            label: pull.title,
            hint: "\(host.provider.reference(pull.number)) · \(host.repo)",
            action: .openPull(id: inbox.id),
            keywords: [host.slug, pull.sourceBranch, pull.authorLogin, pull.authorName, String(pull.number)]
                .compactMap { $0 },
            number: pull.number
        )
    }

    private static func orgName(for repo: Repository) -> String {
        repo.url.deletingLastPathComponent().lastPathComponent
    }

    private static func branchHint(for ref: GitRef) -> String {
        switch ref.kind {
        case .localBranch:        return String(localized: "palette.branch.local", defaultValue: "local")
        case .remoteBranch:       return String(localized: "palette.branch.remote", defaultValue: "remote")
        case .tag:                return String(localized: "palette.branch.tag", defaultValue: "tag")
        }
    }
}
