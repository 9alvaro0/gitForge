import Foundation

nonisolated struct ConflictFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    var path: String
    var resolved: Bool
    var conflicts: Int
}

nonisolated struct ConflictHunk: Identifiable, Hashable, Sendable {
    enum Pick: String, Hashable, Sendable { case ours, theirs, both }
    let id = UUID()
    var ours: [String]
    var base: [String]
    var theirs: [String]

    /// Lines that would be written to disk for the given pick. `.both`
    /// concatenates ours then theirs — there is no native git equivalent so
    /// this is a deliberate UI affordance, not a 3-way merge.
    func lines(for pick: Pick) -> [String] {
        switch pick {
        case .ours:   return ours
        case .theirs: return theirs
        case .both:   return ours + theirs
        }
    }
}
