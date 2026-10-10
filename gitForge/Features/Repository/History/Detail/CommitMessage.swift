import Foundation

/// Commit message presentation helpers.
nonisolated enum CommitMessage {
    /// Git messages are hard-wrapped near 72 columns; shown in a narrower
    /// pane those breaks leave ragged half-lines. Joins the lines of each
    /// paragraph, but keeps blank lines, list items, indented code and
    /// trailers (`Co-authored-by: …`, `Refs #187`) on their own lines.
    static func reflow(_ message: String) -> String {
        var lines: [String] = []
        for line in message.components(separatedBy: "\n") {
            if let previous = lines.last, joinable(line, after: previous) {
                lines[lines.count - 1] = previous + " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func joinable(_ line: String, after previous: String) -> Bool {
        let current = line.trimmingCharacters(in: .whitespaces)
        let prior = previous.trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty, !prior.isEmpty else { return false }
        if isCode(line) || isCode(previous) { return false }
        if isListItem(current) || isTrailer(current) || isTrailer(prior) { return false }
        return true
    }

    private static func isCode(_ line: String) -> Bool {
        line.hasPrefix("    ") || line.hasPrefix("\t")
    }

    private static func isListItem(_ trimmed: String) -> Bool {
        trimmed.wholeMatch(of: /([-*+]|\d+[.)])\s.*/) != nil
    }

    private static func isTrailer(_ trimmed: String) -> Bool {
        trimmed.wholeMatch(of: /[A-Za-z][A-Za-z-]*:\s.*/) != nil
            || trimmed.wholeMatch(of: /(Refs|Fixes|Closes|Resolves|See)\s+#?\w.*/) != nil
    }
}
