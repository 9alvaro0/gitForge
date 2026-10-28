import Foundation

/// Single row in the command palette. `kind` decides its group.
struct CommandPaletteItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case repo
        case pull
        case commit
        case branch
        case file
        case command
        /// "Search all of <host>" and what it found (R3 Ruling 12): the
        /// group after all the others, outside `displayOrder` and the scopes.
        case remote

        /// The order groups appear in ⌘K.
        static let displayOrder: [Kind] = [.command, .repo, .pull, .branch, .commit, .file]

        var title: String {
            switch self {
            case .command: String(localized: "Actions")
            case .repo:    String(localized: "Repositories")
            case .pull:    String(localized: "Pull requests")
            case .branch:  String(localized: "Branches")
            case .commit:  String(localized: "Commits")
            case .file:    String(localized: "Files")
            case .remote:  String(localized: "Search all")
            }
        }

        /// The SF Symbol of the group's rows.
        var symbol: String {
            switch self {
            case .command: "bolt"
            case .repo:    "folder"
            case .pull:    "arrow.triangle.pull"
            case .branch:  "arrow.triangle.branch"
            case .commit:  "circle.circle"
            case .file:    "doc"
            case .remote:  "globe"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let label: String
    let hint: String?
    let action: PaletteAction
    /// Other texts the query can find this row by (a pull request's repo
    /// path, branch and author). Empty: only `label` is searched.
    var keywords: [String] = []
    /// A pull request's number, so `#482` finds it exactly.
    var number: Int?
    /// In place of the group's symbol (`Kind.symbol`): a pull request or a
    /// repo found by searching a host, in the Search all group.
    var symbol: String? = nil
    /// A spinner in place of the symbol: the host is being searched.
    var isLoading = false
    /// Left out while browsing (no query) and listed only when the query
    /// matches it: an action worth finding, not worth a row in the first
    /// screen of ⌘K.
    var searchOnly = false
}

/// What happens when a palette item is selected.
enum PaletteAction: Hashable {
    case openRepo(URL)
    case openRepository
    case cloneRepository
    case selectSection(WorkspaceSection)
    /// History, with this commit selected.
    case revealCommit(sha: String)
    /// History, with the branch's tip selected (as a sidebar click does).
    case revealBranch(GitRef)
    /// Changes, with this file's diff open.
    case revealFile(path: String)
    /// Reviews, with this pull request selected.
    case openPull(id: InboxPull.ID)
    /// Reviews, narrowed to this followed repo (a key of `ReviewRepo.id`).
    case showReviews(repoKey: String)
    /// Reviews, with the pull request a pasted link points to opened.
    case openPullLink(PullRequestLink)
    /// The sheet that adds a pasted link's host as an instance of this kind.
    case addInstance(kind: HostingInstance.Kind, host: String)
    case fetch
    case pull
    case push
    case stash
    case noop
    /// Searches the whole of an instance for the trimmed query (R3 Ruling 12).
    case searchHost(instanceId: UUID, query: String)
    /// Reviews, narrowed to a repo found by searching a host (R3 Ruling 13).
    case openFoundRepo(FoundRepo)
    /// The sheet that connects an account on this instance.
    case connectAccount(instanceId: UUID)
    /// Settings, on this pane or, with `nil`, on the last one shown.
    case openSettings(SettingsPane?)
    /// Settings › Identities, with the new-profile editor open.
    case newProfile
    /// Settings › Pull requests, with the add-repository sheet open.
    case followRepository
    /// The sheet that connects an account, on no instance in particular.
    case connectNewAccount

    /// Opens a panel or a sheet: ⌘↵ ("run without closing") still closes
    /// the palette for these, or it would sit on top of what they show. A
    /// link or a found repo may end in the connect sheet, and Reviews takes
    /// the window anyway. Opening a Settings pane doesn't: Settings takes
    /// the window and the palette over it is the user's to keep or close,
    /// as with the other sections; the two Settings actions that open an
    /// editor or a sheet do.
    var presentsUI: Bool {
        switch self {
        case .openRepository, .cloneRepository, .addInstance, .openPullLink, .openFoundRepo, .connectAccount,
             .newProfile, .followRepository, .connectNewAccount: true
        default: false
        }
    }

    /// Runs inside the palette, ⌘ or not: a host search shows its results
    /// there, and a row that does nothing ("Searching…") leaves it as it is.
    var keepsPaletteOpen: Bool {
        switch self {
        case .searchHost, .noop: true
        default: false
        }
    }

    /// Whether picking `action` leaves the palette open: always for those
    /// that run inside it, with ⌘ (⌘↵) for any that doesn't show a panel or
    /// a sheet.
    static func keepOpen(_ action: PaletteAction, commandHeld: Bool) -> Bool {
        action.keepsPaletteOpen || (commandHeld && !action.presentsUI)
    }
}

/// What ⌘K searches: everything (a few rows per group) or one group (all
/// of its rows). ⇥ / ⇧⇥ step through them in display order.
enum CommandPaletteScope: Hashable {
    case all
    case only(CommandPaletteItem.Kind)

    static let ordered: [CommandPaletteScope] = [.all] + CommandPaletteItem.Kind.displayOrder.map { .only($0) }

    var title: String {
        switch self {
        case .all: String(localized: "palette.scope.all", defaultValue: "All")
        case .only(let kind): kind.title
        }
    }

    func next() -> CommandPaletteScope { step(1) }
    func previous() -> CommandPaletteScope { step(-1) }

    private func step(_ delta: Int) -> CommandPaletteScope {
        let all = Self.ordered
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + delta + all.count) % all.count]
    }
}
