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
    /// The marker lines exactly as they appeared on disk (labels and CRLF
    /// endings included), so a hunk left unresolved is written back verbatim.
    var markers = ConflictMarkers()

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

nonisolated struct ConflictMarkers: Hashable, Sendable {
    var ours = "<<<<<<< HEAD"
    var base = "|||||||"
    var separator = "======="
    var theirs = ">>>>>>> branch"
}
