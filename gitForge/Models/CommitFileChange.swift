import Foundation

nonisolated struct CommitFileChange: Sendable, Equatable, Identifiable, Hashable {
    enum Status: Sendable, Equatable, Hashable {
        case added
        case modified
        case deleted
        case renamed(from: String)
        case copied(from: String)
        case typeChanged
        case unmerged
        case unknown(String)

        var displayLetter: String {
            switch self {
            case .added: "A"
            case .modified: "M"
            case .deleted: "D"
            case .renamed: "R"
            case .copied: "C"
            case .typeChanged: "T"
            case .unmerged: "U"
            case .unknown(let raw): raw
            }
        }
    }

    let path: String
    let status: Status

    var id: String { path }
}
