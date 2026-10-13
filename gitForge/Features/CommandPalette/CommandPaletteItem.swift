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
            case .command: "Actions"
            case .repo:    "Repositories"
            case .branch:  "Branches"
            case .commit:  "Commits"
            case .file:    "Files"
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
        case .all: "All"
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
