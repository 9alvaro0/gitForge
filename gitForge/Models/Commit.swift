import Foundation

nonisolated struct Commit: Sendable, Equatable, Identifiable, Hashable {
    let sha: String
    let parentShas: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let subject: String

    var id: String { sha }
    var shortSha: String { String(sha.prefix(7)) }
    var isMerge: Bool { parentShas.count > 1 }
}
