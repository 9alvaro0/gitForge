import Foundation

/// Single row in the command palette. Kind drives icon + tag color.
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

    var tag: String {
        switch kind {
        case .repo:    return "Repo"
        case .commit:  return "Commit"
        case .branch:  return "Branch"
        case .file:    return "File"
        case .command: return "Command"
        }
    }

    var icon: GFIconKind {
        switch kind {
        case .repo:    return .folder
        case .commit:  return .diamond
        case .branch:  return .branch
        case .file:    return .diff
        case .command: return .cmd
        }
    }

    func matches(_ query: String) -> Bool {
        FuzzyMatcher.match(query, in: label) != nil
    }
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
}
