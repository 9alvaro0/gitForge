import Foundation

/// Models for sections that aren't backed by real git/CLI features yet
/// (PRs, conflicts). Sample data lives in `Previews/PreviewSamples.swift`.

struct PullRequest: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable { case open, review, merged, closed }
    enum Checks: String, Hashable, Sendable { case pass, running, fail }

    let id: Int
    var title: String
    var author: String
    var status: Status
    var reviews: Int
    var checks: Checks
    var branch: String
    var target: String
    var when: String
}

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

struct BlameGroup: Identifiable, Sendable {
    let id = UUID()
    var sha: String
    var author: String
    var when: String
    var lines: [BlameLine]
    var laneColorHex: UInt32
}

struct BlameLine: Identifiable, Sendable {
    let id = UUID()
    var number: Int
    var text: String
}
