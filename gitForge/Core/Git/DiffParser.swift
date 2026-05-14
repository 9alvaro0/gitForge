import Foundation

enum DiffParser {
    /// Metadata callers can surface when `parse` returns no hunks. A diff
    /// over a binary file, a pure rename, a mode-only change, or a
    /// submodule pointer bump emits zero `@@` hunks — the UI used to render
    /// "no changes" for all of these, hiding real work the user did.
    enum Summary: Equatable, Sendable {
        case binary(oldPath: String, newPath: String)
        case rename(from: String, to: String, similarity: Int?)
        case modeChange(from: String, to: String)
        case submoduleUpdate(path: String, from: String, to: String)
    }

    /// Scans `output` for non-content metadata. Returns the first marker
    /// recognised; nil when the diff is a plain text change with hunks.
    static func parseSummary(_ output: String) -> Summary? {
        let lines = output.components(separatedBy: "\n")
        var renameFrom: String?
        var renameTo: String?
        var similarity: Int?
        var oldMode: String?
        var newMode: String?
        var subprojectOld: String?
        var subprojectNew: String?
        var subprojectPath: String?

        for line in lines {
            if line.hasPrefix("Binary files ") {
                if let (old, new) = parseBinaryHeader(line) {
                    return .binary(oldPath: old, newPath: new)
                }
            } else if line.hasPrefix("rename from ") {
                renameFrom = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                renameTo = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("similarity index ") {
                let pct = line.dropFirst("similarity index ".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "%"))
                similarity = Int(pct)
            } else if line.hasPrefix("old mode ") {
                oldMode = String(line.dropFirst("old mode ".count))
            } else if line.hasPrefix("new mode ") {
                newMode = String(line.dropFirst("new mode ".count))
            } else if line.hasPrefix("-Subproject commit ") {
                subprojectOld = String(line.dropFirst("-Subproject commit ".count))
            } else if line.hasPrefix("+Subproject commit ") {
                subprojectNew = String(line.dropFirst("+Subproject commit ".count))
            } else if line.hasPrefix("diff --git ") {
                subprojectPath = parseDiffGitPath(line)
            }
        }
        if let from = renameFrom, let to = renameTo {
            return .rename(from: from, to: to, similarity: similarity)
        }
        if let from = oldMode, let to = newMode {
            return .modeChange(from: from, to: to)
        }
        if let from = subprojectOld, let to = subprojectNew, let path = subprojectPath {
            return .submoduleUpdate(path: path, from: from, to: to)
        }
        return nil
    }

    /// `Binary files a/foo and b/bar differ` → ("foo", "bar"). git omits the
    /// `a/` and `b/` prefixes for renamed-to-self deletes; we strip both
    /// permissively so the helper works on any shape git emits.
    private static func parseBinaryHeader(_ line: String) -> (String, String)? {
        let rest = line.dropFirst("Binary files ".count)
        guard let andRange = rest.range(of: " and ") else { return nil }
        let oldRaw = String(rest[rest.startIndex..<andRange.lowerBound])
        let afterAnd = rest[andRange.upperBound...]
        guard let differRange = afterAnd.range(of: " differ") else { return nil }
        let newRaw = String(afterAnd[afterAnd.startIndex..<differRange.lowerBound])
        return (stripDiffPrefix(oldRaw), stripDiffPrefix(newRaw))
    }

    /// `diff --git a/sub b/sub` → "sub". The two paths are identical for the
    /// no-rename case, so picking either side is fine; submodule path bumps
    /// take this branch.
    private static func parseDiffGitPath(_ line: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        return stripDiffPrefix(String(parts[2]))
    }

    private static func stripDiffPrefix(_ s: String) -> String {
        if s.hasPrefix("a/") || s.hasPrefix("b/") { return String(s.dropFirst(2)) }
        return s
    }

    static func parse(_ output: String) -> [DiffHunk] {
        let lines = output.components(separatedBy: "\n")
        var hunks: [DiffHunk] = []
        var hunkIndex = 0
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("@@"), let parsed = parseHunk(lines: lines, startIndex: i, id: hunkIndex) {
                hunks.append(parsed.hunk)
                i = parsed.nextIndex
                hunkIndex += 1
            } else {
                i += 1
            }
        }
        return hunks
    }

    private static func parseHunk(lines: [String], startIndex: Int, id: Int) -> (hunk: DiffHunk, nextIndex: Int)? {
        guard let header = parseHunkHeader(lines[startIndex]) else { return nil }
        var diffLines: [DiffLine] = []
        var oldNum = header.oldStart
        var newNum = header.newStart
        var lineId = 0
        var i = startIndex + 1
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("@@") || line.hasPrefix("diff --git") {
                break
            }
            guard let firstChar = line.first else {
                i += 1
                continue
            }
            let content = String(line.dropFirst())
            let kind: DiffLine.Kind
            var oldLine: Int? = nil
            var newLine: Int? = nil
            switch firstChar {
            case "+":
                kind = .added
                newLine = newNum
                newNum += 1
            case "-":
                kind = .removed
                oldLine = oldNum
                oldNum += 1
            case " ":
                kind = .context
                oldLine = oldNum
                newLine = newNum
                oldNum += 1
                newNum += 1
            case "\\":
                kind = .noNewline
            default:
                i += 1
                continue
            }
            diffLines.append(DiffLine(
                id: lineId,
                kind: kind,
                content: content,
                oldLineNumber: oldLine,
                newLineNumber: newLine
            ))
            lineId += 1
            i += 1
        }
        return (
            DiffHunk(
                id: id,
                oldStart: header.oldStart,
                oldCount: header.oldCount,
                newStart: header.newStart,
                newCount: header.newCount,
                header: header.context,
                lines: diffLines
            ),
            i
        )
    }

    private static let hunkHeaderRegex = try! NSRegularExpression(
        pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$"#
    )

    private static func parseHunkHeader(_ raw: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, context: String)? {
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = hunkHeaderRegex.firstMatch(in: raw, options: [], range: range) else { return nil }

        func extract(_ groupIndex: Int) -> String? {
            let r = match.range(at: groupIndex)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: raw) else { return nil }
            return String(raw[swiftRange])
        }

        guard let oldStart = extract(1).flatMap(Int.init) else { return nil }
        let oldCount = extract(2).flatMap(Int.init) ?? 1
        guard let newStart = extract(3).flatMap(Int.init) else { return nil }
        let newCount = extract(4).flatMap(Int.init) ?? 1
        let context = extract(5) ?? ""
        return (oldStart, oldCount, newStart, newCount, context)
    }
}
