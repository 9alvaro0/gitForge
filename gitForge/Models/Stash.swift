import Foundation

nonisolated struct Stash: Sendable, Equatable, Identifiable, Hashable {
    let index: Int
    let sha: String
    let subject: String

    var id: Int { index }

    var reference: String { "stash@{\(index)}" }
}
