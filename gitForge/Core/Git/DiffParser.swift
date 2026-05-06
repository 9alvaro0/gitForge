import Foundation

enum DiffParser {
    static func parse(_ output: String) -> [DiffHunk] {
        parseFile(output).hunks
    }

    /// Same as `parse(_:)` but also captures the raw header (everything before
    /// the first `@@`) and the raw text of each hunk, so callers can rebuild
    /// a partial unified patch.
    static func parseFile(_ output: String) -> FileDiff {
        let lines = output.components(separatedBy: "\n")
        var hunks: [DiffHunk] = []
        var rawHunks: [String] = []
        var headerLines: [String] = []
        var hunkIndex = 0
        var sawFirstHunk = false
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("@@"), let parsed = parseHunk(lines: lines, startIndex: i, id: hunkIndex) {
                sawFirstHunk = true
                hunks.append(parsed.hunk)
                let raw = lines[i..<parsed.nextIndex].joined(separator: "\n")
                rawHunks.append(raw)
                i = parsed.nextIndex
                hunkIndex += 1
            } else {
                if !sawFirstHunk { headerLines.append(line) }
                i += 1
            }
        }
        while headerLines.last == "" { headerLines.removeLast() }
        return FileDiff(header: headerLines, rawHunks: rawHunks, hunks: hunks)
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

    private static func parseHunkHeader(_ raw: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, context: String)? {
        let pattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, options: [], range: range) else { return nil }

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
