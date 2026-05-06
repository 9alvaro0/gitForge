import Foundation

/// Parses `git blame --porcelain` output into grouped `BlameGroup` chunks.
///
/// Porcelain format example for a single line:
/// ```
/// <40-hex-sha> <orig-line> <final-line> [num-lines]
/// author Alvaro Guerra
/// author-mail <a@b.com>
/// author-time 1716480000
/// author-tz +0000
/// committer …
/// summary first commit subject line
/// previous <sha> path
/// filename src/lib/lane-layout.ts
/// \t<the actual line content>
/// ```
/// Subsequent lines of the same hunk only emit the `sha orig final` header
/// and the `\t<line>` payload — metadata is "remembered" by sha.
enum BlameParser {
    private static let lanePalette: [UInt32] = [
        0x7c5cff, 0x56b497, 0xff7e6b, 0xdda44b, 0x5da4ff, 0xc976d9,
    ]

    static func parse(_ porcelain: String) -> [BlameGroup] {
        var commits: [String: CommitMeta] = [:]
        var lines: [(meta: CommitMeta, line: BlameLine)] = []
        var currentSha: String?
        var currentLineNumber = 0

        let allLines = porcelain.components(separatedBy: "\n")
        var i = 0
        while i < allLines.count {
            let raw = allLines[i]
            if raw.hasPrefix("\t") {
                guard let sha = currentSha, let meta = commits[sha] else { i += 1; continue }
                let content = String(raw.dropFirst())
                lines.append((meta, BlameLine(number: currentLineNumber, text: content)))
                i += 1
                continue
            }
            // Header for a new line: "<sha> <orig> <final> [count]"
            let parts = raw.split(separator: " ")
            if parts.count >= 3, parts[0].count >= 7, isHexSha(String(parts[0])) {
                let sha = String(parts[0])
                currentSha = sha
                currentLineNumber = Int(parts[2]) ?? 0
                if commits[sha] == nil {
                    commits[sha] = CommitMeta(sha: shortSha(sha))
                }
                i += 1
                continue
            }
            // Metadata for the active sha
            if let sha = currentSha,
               let header = headerKey(in: raw),
               let value = headerValue(in: raw, key: header) {
                applyHeader(header, value: value, to: &commits[sha]!)
            }
            i += 1
        }

        var groups: [BlameGroup] = []
        var bucket: [BlameLine] = []
        var bucketMeta: CommitMeta?
        for entry in lines {
            if bucketMeta?.sha == entry.meta.sha {
                bucket.append(entry.line)
            } else {
                if let meta = bucketMeta, !bucket.isEmpty {
                    groups.append(makeGroup(meta: meta, lines: bucket))
                }
                bucketMeta = entry.meta
                bucket = [entry.line]
            }
        }
        if let meta = bucketMeta, !bucket.isEmpty {
            groups.append(makeGroup(meta: meta, lines: bucket))
        }
        return groups
    }

    private static func makeGroup(meta: CommitMeta, lines: [BlameLine]) -> BlameGroup {
        BlameGroup(
            sha: meta.sha,
            author: meta.author ?? "—",
            when: meta.relativeWhen,
            lines: lines,
            laneColorHex: laneColor(for: meta.sha)
        )
    }

    private static func isHexSha(_ s: String) -> Bool {
        s.allSatisfy { $0.isHexDigit }
    }

    private static func shortSha(_ s: String) -> String {
        String(s.prefix(7))
    }

    private static func headerKey(in line: String) -> String? {
        let candidates = ["author-mail", "author-time", "author-tz", "author",
                          "committer-mail", "committer-time", "committer-tz", "committer",
                          "summary", "previous", "filename", "boundary"]
        return candidates.first { line.hasPrefix($0 + " ") || line == $0 }
    }

    private static func headerValue(in line: String, key: String) -> String? {
        guard line.hasPrefix(key + " ") else { return line == key ? "" : nil }
        return String(line.dropFirst(key.count + 1))
    }

    private static func applyHeader(_ key: String, value: String, to meta: inout CommitMeta) {
        switch key {
        case "author":      meta.author = value
        case "author-time": meta.authorEpoch = Double(value)
        default: break
        }
    }

    private static func laneColor(for sha: String) -> UInt32 {
        var h: Int = 0
        for c in sha.unicodeScalars { h = (h &* 31) &+ Int(c.value) }
        return lanePalette[abs(h) % lanePalette.count]
    }

    private struct CommitMeta {
        var sha: String
        var author: String?
        var authorEpoch: Double?

        var relativeWhen: String {
            guard let epoch = authorEpoch else { return "—" }
            let date = Date(timeIntervalSince1970: epoch)
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: date, relativeTo: .now)
        }
    }
}
