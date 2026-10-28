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

    /// The Search all group (R3 Ruling 12): with `ReviewsStore.searchMinimum`
    /// characters or more, not counting the spaces around them, the rows of
    /// each of `instances` in turn. An instance's last search shows while it
    /// was made for this text, trimmed: a spinner while it runs, then what it
    /// found (pull requests, then repos, those in `followed` marked), that it
    /// found nothing, why it failed (picking that searches again) or that an
    /// account must be connected. Otherwise, the row that searches it.
    static func searchItems(for query: String, instances: [HostingInstance], searches: [UUID: HostSearchState],
                            followed: Set<String>) -> [CommandPaletteItem] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= ReviewsStore.searchMinimum else { return [] }
        return instances.flatMap { instance in
            let search = searches[instance.id].flatMap { $0.query == text ? $0 : nil }
            return searchRows(on: instance, text: text, phase: search?.phase, followed: followed)
        }
    }

    private static func searchRows(on instance: HostingInstance, text: String, phase: HostSearchState.Phase?,
                                   followed: Set<String>) -> [CommandPaletteItem] {
        let host = instance.host
        let search = PaletteAction.searchHost(instanceId: instance.id, query: text)
        switch phase {
        case nil:
            return [CommandPaletteItem(kind: .remote, label: String(localized: "Search all of \(host)"),
                                       hint: "“\(text)”", action: search)]
        case .searching:
            return [CommandPaletteItem(kind: .remote, label: String(localized: "Searching \(host)…"),
                                       hint: nil, action: .noop, isLoading: true)]
        case .found(let results) where results.pulls.isEmpty && results.repos.isEmpty:
            return [CommandPaletteItem(kind: .remote, label: String(localized: "Nothing found on \(host)"),
                                       hint: nil, action: .noop)]
        case .found(let results):
            let limit = HostSearchFactory.resultLimit
            return results.pulls.prefix(limit).map(foundPullItem)
                + results.repos.prefix(limit).map { foundRepoItem($0, followed: followed) }
        case .failed(let message):
            return [CommandPaletteItem(kind: .remote, label: String(localized: "Couldn't search \(host)"),
                                       hint: message, action: search)]
        case .connectAccount:
            return [CommandPaletteItem(kind: .remote, label: String(localized: "Connect an account on \(host)…"),
                                       hint: nil, action: .connectAccount(instanceId: instance.id))]
        }
    }

    /// A pull request a host search found, written as the inbox's are; it
    /// opens the way a pasted link does (R2 Ruling 11).
    private static func foundPullItem(_ found: FoundPull) -> CommandPaletteItem {
        CommandPaletteItem(kind: .remote, label: found.title, hint: pullHint(found.link.host, number: found.link.number),
                           action: .openPullLink(found.link), symbol: CommandPaletteItem.Kind.pull.symbol)
    }

    /// A repo a host search found, by its path, marked if it's followed.
    private static func foundRepoItem(_ found: FoundRepo, followed: Set<String>) -> CommandPaletteItem {
        CommandPaletteItem(kind: .remote, label: found.host.slug,
                           hint: followed.contains(FollowedRepos.key(found.host)) ? String(localized: "Followed") : nil,
                           action: .openFoundRepo(found), symbol: CommandPaletteItem.Kind.repo.symbol)
    }

    /// The actions ⌘K always offers. Settings comes last: the item that
    /// opens it on the last pane, one "Settings: <pane>" item per pane in
    /// the sidebar's order, and the three actions that open something
    /// inside one. Only "Settings" shows while browsing; those nine are
    /// search-only, or they would fill the first screen of ⌘K.
    static let builtInCommands: [CommandPaletteItem] = [
        CommandPaletteItem(kind: .command, label: String(localized: "Open repository…"),  hint: "⌘O",  action: .openRepository),
        CommandPaletteItem(kind: .command, label: String(localized: "Clone repository…"), hint: "⌥⌘C", action: .cloneRepository),
        CommandPaletteItem(kind: .command, label: String(localized: "Fetch all"),       hint: "⌘⇧F", action: .fetch),
        CommandPaletteItem(kind: .command, label: String(localized: "Pull"),            hint: "⌘⇧L", action: .pull),
        CommandPaletteItem(kind: .command, label: String(localized: "Push"),            hint: "⌘⇧P", action: .push),
        CommandPaletteItem(kind: .command, label: String(localized: "New branch…"),     hint: "⌘⇧B", action: .selectSection(.branches)),
        CommandPaletteItem(kind: .command, label: String(localized: "Stash changes"),   hint: nil,   action: .stash),
        CommandPaletteItem(kind: .command, label: String(localized: "Settings"),        hint: "⌘,",  action: .openSettings(nil)),
    ] + SettingsPane.allCases.map { pane in
        CommandPaletteItem(kind: .command, label: String(localized: "Settings: \(pane.label)"), hint: nil,
                           action: .openSettings(pane), searchOnly: true)
    } + [
        CommandPaletteItem(kind: .command, label: String(localized: "Connect account…"),    hint: nil, action: .connectNewAccount, searchOnly: true),
        CommandPaletteItem(kind: .command, label: String(localized: "New Profile…"),        hint: nil, action: .newProfile, searchOnly: true),
        CommandPaletteItem(kind: .command, label: String(localized: "Follow Repository…"),  hint: nil, action: .followRepository, searchOnly: true),
    ]

    /// A pull request by its title, found too by its repo path, branch,
    /// author and number (R2 Ruling 5).
    private static func pullItem(_ inbox: InboxPull) -> CommandPaletteItem {
        let host = inbox.repo.host
        let pull = inbox.pull
        return CommandPaletteItem(
            kind: .pull,
            label: pull.title,
            hint: pullHint(host, number: pull.number),
            action: .openPull(id: inbox.id),
            keywords: [host.slug, pull.sourceBranch, pull.authorLogin, pull.authorName, String(pull.number)]
                .compactMap { $0 },
            number: pull.number
        )
    }

    /// `!482 · payments-app`: tells two pull requests of the same title apart.
    private static func pullHint(_ host: RemoteHost, number: Int) -> String {
        "\(host.provider.reference(number)) · \(host.repo)"
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
