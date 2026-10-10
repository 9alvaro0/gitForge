import Foundation

/// One line of the read-only result panel: the file as it would be written
/// with the current picks.
nonisolated struct ConflictResultLine: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Outside any conflict.
        case text
        /// Came from a hunk, from this side.
        case ours, theirs
        /// Stands for a hunk that has no pick yet (one row per hunk).
        case unresolved(hunkIndex: Int)
    }

    let id: Int
    /// Line number in the resulting file; `nil` for an unresolved hunk,
    /// which has no lines yet.
    let number: Int?
    let text: String
    let kind: Kind
}

nonisolated enum ConflictResultBuilder {
    /// Walks the parsed segments in order, matching each conflict to the
    /// hunk at the same index (as `ConflictParser.apply` does).
    static func build(segments: [ConflictParser.Segment],
                      hunks: [ConflictHunk],
                      picks: [UUID: ConflictHunk.Pick]) -> [ConflictResultLine] {
        var out: [ConflictResultLine] = []
        var number = 1
        var hunkIndex = 0

        func append(_ text: String, _ kind: ConflictResultLine.Kind) {
            let shown = text.hasSuffix("\r") ? String(text.dropLast()) : text
            out.append(ConflictResultLine(id: out.count, number: number, text: shown, kind: kind))
            number += 1
        }

        for segment in segments {
            switch segment {
            case .text(let lines):
                lines.forEach { append($0, .text) }
            case .conflict:
                defer { hunkIndex += 1 }
                guard hunks.indices.contains(hunkIndex), let pick = picks[hunks[hunkIndex].id] else {
                    out.append(ConflictResultLine(id: out.count, number: nil, text: "", kind: .unresolved(hunkIndex: hunkIndex)))
                    continue
                }
                let hunk = hunks[hunkIndex]
                switch pick {
                case .ours:
                    hunk.ours.forEach { append($0, .ours) }
                case .theirs:
                    hunk.theirs.forEach { append($0, .theirs) }
                case .both:
                    hunk.ours.forEach { append($0, .ours) }
                    hunk.theirs.forEach { append($0, .theirs) }
                case .bothTheirsFirst:
                    hunk.theirs.forEach { append($0, .theirs) }
                    hunk.ours.forEach { append($0, .ours) }
                }
            }
        }
        return out
    }
}

/// Where "Next conflict" goes: the next unpicked hunk after the focused one
/// in this file, else the next unresolved file (wrapping), else nowhere.
nonisolated enum ConflictNavigator {
    enum Target: Equatable, Sendable {
        case hunk(Int)
        case file(String)
    }

    static func next(after focused: Int,
                     hunkIsPicked: [Bool],
                     files: [ConflictFile],
                     selectedPath: String?) -> Target? {
        if let hunk = hunkIsPicked.indices.first(where: { $0 > focused && !hunkIsPicked[$0] }) {
            return .hunk(hunk)
        }
        let start = files.firstIndex { $0.path == selectedPath } ?? -1
        let ordered = files.indices.map { (start + 1 + $0) % max(files.count, 1) }
        if let file = ordered.lazy.map({ files[$0] }).first(where: { !$0.resolved && $0.path != selectedPath }) {
            return .file(file.path)
        }
        // Only this file is left: wrap to its first unpicked hunk.
        if let hunk = hunkIsPicked.firstIndex(of: false), hunk != focused {
            return .hunk(hunk)
        }
        return nil
    }
}
