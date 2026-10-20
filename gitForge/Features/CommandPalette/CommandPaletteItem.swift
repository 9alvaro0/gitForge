import Foundation

/// Single row in the command palette. `kind` decides its group.
struct CommandPaletteItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case repo
        case commit
        case branch
        case file
        case command

        /// The order groups appear in ⌘K.
        static let displayOrder: [Kind] = [.command, .repo, .branch, .commit, .file]

        var title: String {
            switch self {
            case .command: String(localized: "Actions")
            case .repo:    String(localized: "Repositories")
            case .branch:  String(localized: "Branches")
            case .commit:  String(localized: "Commits")
            case .file:    String(localized: "Files")
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let label: String
    let hint: String?
    let action: PaletteAction
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
    case fetch
    case pull
    case push
    case stash
    case noop

    /// Opens a panel or a sheet: ⌘↵ ("run without closing") still closes
    /// the palette for these, or it would sit on top of what they show.
    var presentsUI: Bool {
        switch self {
        case .openRepository, .cloneRepository: true
        default: false
        }
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
