import Foundation

/// Parses files with conflict markers into individual `ConflictHunk` instances
/// and re-emits a resolved file given a per-hunk `Pick`.
///
/// Recognized markers:
/// ```
/// <<<<<<< HEAD             ← ours
/// …
/// ||||||| common ancestor  ← optional, only when merge.conflictstyle = diff3 / zdiff3
/// …
/// =======                  ← separator
/// …
/// >>>>>>> branch           ← theirs
/// ```
nonisolated enum ConflictParser {
    /// Logical segment of a parsed file. Either plain text or a 3-way conflict.
    enum Segment: Equatable {
        case text([String])
        case conflict(ours: [String], base: [String], theirs: [String])
    }

    /// Returns segments + the conflict hunks (ConflictHunk) extracted from the file.
    static func parse(_ content: String) -> (segments: [Segment], hunks: [ConflictHunk]) {
        let lines = content.components(separatedBy: "\n")
        var segments: [Segment] = []
        var hunks: [ConflictHunk] = []
        var buffer: [String] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isOursMarker(line) {
                if !buffer.isEmpty {
                    segments.append(.text(buffer))
                    buffer = []
                }
                guard let parsed = parseConflict(lines: lines, start: i) else {
                    buffer.append(line); i += 1; continue
                }
                segments.append(.conflict(ours: parsed.hunk.ours,
                                          base: parsed.hunk.base,
                                          theirs: parsed.hunk.theirs))
                hunks.append(parsed.hunk)
                i = parsed.endIndex
            } else {
                buffer.append(line)
                i += 1
            }
        }
        if !buffer.isEmpty {
            segments.append(.text(buffer))
        }
        return (segments, hunks)
    }

    /// `<<<<<<<` must occupy the whole line or be followed by a space + label.
    /// Without this check, a source comment like `// <<<<<<< TODO resolve` is
    /// taken as the start of a conflict and the parser silently merges all
    /// content up to the next `>>>>>>>` into a corrupt hunk — which then
    /// gets written back to disk when the user picks a side.
    private static func isOursMarker(_ line: String) -> Bool {
        line == "<<<<<<<" || line.hasPrefix("<<<<<<< ")
    }

    /// Same anchor rule for the closing marker.
    private static func isTheirsMarker(_ line: String) -> Bool {
        line == ">>>>>>>" || line.hasPrefix(">>>>>>> ")
    }

    /// Re-emits `content` with the picked side substituted for every conflict.
    /// `picks` is keyed by the hunk's id; missing entries leave the original
    /// markers in place (so the file is still flagged as conflicted).
    static func apply(content: String, picks: [UUID: ConflictHunk.Pick], hunks: [ConflictHunk]) -> String {
        guard !picks.isEmpty else { return content }
        let (segments, parsedHunks) = parse(content)
        guard parsedHunks.count == hunks.count else { return content }

        var out: [String] = []
        var hIdx = 0
        for segment in segments {
            switch segment {
            case .text(let lines):
                out.append(contentsOf: lines)
            case .conflict:
                let originalId = hunks[hIdx].id
                if let pick = picks[originalId] {
                    out.append(contentsOf: parsedHunks[hIdx].lines(for: pick))
                } else {
                    out.append(contentsOf: rebuildMarkers(parsedHunks[hIdx]))
                }
                hIdx += 1
            }
        }
        return out.joined(separator: "\n")
    }

    private static func rebuildMarkers(_ hunk: ConflictHunk) -> [String] {
        var lines = ["<<<<<<< HEAD"]
        lines.append(contentsOf: hunk.ours)
        if !hunk.base.isEmpty {
            lines.append("|||||||")
            lines.append(contentsOf: hunk.base)
        }
        lines.append("=======")
        lines.append(contentsOf: hunk.theirs)
        lines.append(">>>>>>> branch")
        return lines
    }

    private struct ParseResult {
        let hunk: ConflictHunk
        let endIndex: Int
    }

    private static func parseConflict(lines: [String], start: Int) -> ParseResult? {
        var i = start + 1
        var ours: [String] = []
        var base: [String] = []
        var theirs: [String] = []
        var phase: Phase = .ours

        while i < lines.count {
            let line = lines[i]
            if phase == .ours, line == "|||||||" || line.hasPrefix("||||||| ") {
                phase = .base; i += 1; continue
            }
            if phase != .theirs, line == "=======" {
                phase = .theirs; i += 1; continue
            }
            if isTheirsMarker(line) {
                let hunk = ConflictHunk(ours: ours, base: base, theirs: theirs)
                return ParseResult(hunk: hunk, endIndex: i + 1)
            }
            switch phase {
            case .ours:   ours.append(line)
            case .base:   base.append(line)
            case .theirs: theirs.append(line)
            }
            i += 1
        }
        return nil
    }

    private enum Phase { case ours, base, theirs }
}
