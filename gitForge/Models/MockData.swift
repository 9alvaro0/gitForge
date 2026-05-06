import Foundation

/// Models for sections that aren't backed by real git/CLI features yet
/// (only conflicts at the moment — see `Previews/PreviewMocks.swift` for
/// preview-only sample data).

struct ConflictFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    var path: String
    var resolved: Bool
    var conflicts: Int
}

struct ConflictHunk: Identifiable, Hashable, Sendable {
    enum Pick: String, Hashable, Sendable { case ours, theirs, both }
    let id = UUID()
    var ours: [String]
    var base: [String]
    var theirs: [String]
}
