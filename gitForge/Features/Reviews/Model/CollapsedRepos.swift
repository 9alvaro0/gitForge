import Foundation

/// The repos whose rows Team and Mine keep folded under their heading, by
/// repo key (`ReviewRepo.id`), saved as one line per key.
nonisolated struct CollapsedRepos: Equatable, Sendable {
    private(set) var keys: Set<String>

    init(raw: String) {
        keys = Set(raw.split(separator: "\n").map(String.init))
    }

    /// What's saved: the keys, sorted so the same set always saves the same.
    var raw: String { keys.sorted().joined(separator: "\n") }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    mutating func toggle(_ key: String) {
        if keys.remove(key) == nil { keys.insert(key) }
    }

    /// Unfolds `key`'s rows, as revealing one of them does. `false` when
    /// they weren't folded.
    @discardableResult
    mutating func expand(_ key: String) -> Bool {
        keys.remove(key) != nil
    }
}
