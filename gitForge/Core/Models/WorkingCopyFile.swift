import Foundation

nonisolated struct WorkingCopyFile: Sendable, Equatable, Identifiable, Hashable {
    enum Status: Sendable, Equatable, Hashable {
        case unmodified
        case modified
        case added
        case deleted
        case renamed
        case copied
        case typeChanged
        case untracked
        case ignored
        case unmerged

        init(porcelainCode: Character) {
            switch porcelainCode {
            case ".", " ": self = .unmodified
            case "M": self = .modified
            case "A": self = .added
            case "D": self = .deleted
            case "R": self = .renamed
            case "C": self = .copied
            case "T": self = .typeChanged
            case "U": self = .unmerged
            case "?": self = .untracked
            case "!": self = .ignored
            default: self = .unmodified
            }
        }

        var displayLetter: String {
            switch self {
            case .unmodified: " "
            case .modified: "M"
            case .added: "A"
            case .deleted: "D"
            case .renamed: "R"
            case .copied: "C"
            case .typeChanged: "T"
            case .untracked: "?"
            case .ignored: "!"
            case .unmerged: "U"
            }
        }
    }

    let path: String
    let stagedStatus: Status
    let unstagedStatus: Status
    let originalPath: String?

    var id: String { path }

    var isStaged: Bool { stagedStatus != .unmodified && stagedStatus != .untracked && stagedStatus != .ignored }
    var isUnstaged: Bool { unstagedStatus != .unmodified && unstagedStatus != .ignored }
    var isUntracked: Bool { stagedStatus == .untracked || unstagedStatus == .untracked }
    var isUnmerged: Bool { stagedStatus == .unmerged || unstagedStatus == .unmerged }
}
