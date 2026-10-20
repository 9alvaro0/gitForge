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

        /// VoiceOver-friendly name. The single-letter `displayLetter` reads
        /// as "M", "A" etc., which a screen reader announces as the literal
        /// character — useless. This expands to the full word.
        var spokenName: String {
            switch self {
            case .unmodified:  String(localized: "file.status.spoken.unmodified", defaultValue: "unchanged")
            case .modified:    String(localized: "file.status.spoken.modified", defaultValue: "modified")
            case .added:       String(localized: "file.status.spoken.added", defaultValue: "added")
            case .deleted:     String(localized: "file.status.spoken.deleted", defaultValue: "deleted")
            case .renamed:     String(localized: "file.status.spoken.renamed", defaultValue: "renamed")
            case .copied:      String(localized: "file.status.spoken.copied", defaultValue: "copied")
            case .typeChanged: String(localized: "file.status.spoken.typeChanged", defaultValue: "type changed")
            case .untracked:   String(localized: "file.status.spoken.untracked", defaultValue: "untracked")
            case .ignored:     String(localized: "file.status.spoken.ignored", defaultValue: "ignored")
            case .unmerged:    String(localized: "file.status.spoken.unmerged", defaultValue: "unmerged")
            }
        }
    }

    let path: String
    let stagedStatus: Status
    let unstagedStatus: Status
    let originalPath: String?

    var id: String { path }

    /// A conflicted file isn't staged: it's listed once, under Unstaged, and
    /// doesn't count toward the commit until it's resolved.
    var isStaged: Bool {
        stagedStatus != .unmodified && stagedStatus != .untracked && stagedStatus != .ignored && stagedStatus != .unmerged
    }
    /// The side the file's badge shows: its staged change when there is one.
    var displayStatus: Status { isStaged ? stagedStatus : unstagedStatus }
    var isUnstaged: Bool { unstagedStatus != .unmodified && unstagedStatus != .ignored }
    var isUntracked: Bool { stagedStatus == .untracked || unstagedStatus == .untracked }
    var isUnmerged: Bool { stagedStatus == .unmerged || unstagedStatus == .unmerged }

    /// Paths that need to travel together when staging/unstaging this file.
    /// For renames (staged or detected unstaged), git only records the move
    /// in the index when both sides — the old path's deletion and the new
    /// path's add — go through `git add` / `git restore --staged` together.
    var allPaths: [String] {
        if let originalPath { [path, originalPath] } else { [path] }
    }
}
