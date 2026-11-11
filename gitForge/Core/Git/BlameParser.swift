import Foundation

/// Reads `git blame --incremental` (and `--porcelain`, the same records with
/// the file's lines in between) as it streams in, chunk by chunk.
///
/// Each record starts with `<sha> <source line> <final line> [<count>]`,
/// then `key value` lines. A commit's details (`author`, `author-mail`,
/// `author-time`, `summary`, `boundary`) come with its first record only;
/// `previous <sha> <path>` and `filename <path>` close every record in
/// incremental output. In porcelain output a line's content follows its
/// record after a tab, and repeated records of a group carry no `filename`.
nonisolated struct BlameParser {
    /// What one chunk added: commits seen for the first time, ranges of
    /// lines blamed, and (porcelain) the content of blamed lines by number.
    struct Batch: Sendable, Equatable {
        var commits: [BlameCommit] = []
        var ranges: [BlameRange] = []
        var contents: [Int: String] = [:]

        var isEmpty: Bool { commits.isEmpty && ranges.isEmpty && contents.isEmpty }
    }

    private struct CommitFields {
        var authorName = ""
        var authorEmail = ""
        var authorTime: TimeInterval = 0
        var summary = ""
        var isBoundary = false
        /// The last record's `filename` / `previous` for this commit, for
        /// porcelain records that repeat neither.
        var path: String?
        var previous: BlameOrigin?
    }

    private struct Pending {
        let sha: String
        let sourceLine: Int
        let finalLine: Int
        let count: Int
        var path: String?
        var previous: BlameOrigin?
        var sawPrevious = false
    }

    private var buffer: [UInt8] = []
    private var fields: [String: CommitFields] = [:]
    private var emittedCommits: Set<String> = []
    private var pending: Pending?
    /// The final line of the last record: where a porcelain content line goes.
    private var lastFinalLine: Int?
    private var batch = Batch()

    init() {}

    /// Parses every complete line in `data` (plus what an earlier chunk
    /// left unfinished) and returns what they added.
    mutating func feed(_ data: Data) -> Batch {
        buffer.append(contentsOf: data)
        var start = 0
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[start..<newline], as: UTF8.self)
            parse(line)
            start = newline + 1
        }
        buffer.removeFirst(start)
        return takeBatch()
    }

    /// Parses `text` as a whole. For tests and for output read in one go.
    mutating func feed(_ text: String) -> Batch {
        feed(Data(text.utf8))
    }

    /// Ends the stream: a last line without a newline, and a record git
    /// ended without `filename` (porcelain's repeats), are taken as they are.
    mutating func finish() -> Batch {
        if !buffer.isEmpty {
            parse(String(decoding: buffer, as: UTF8.self))
            buffer.removeAll()
        }
        emitPending()
        return takeBatch()
    }

    /// Parses complete output in one go.
    static func parse(_ text: String) -> Batch {
        var parser = BlameParser()
        var all = parser.feed(text)
        let tail = parser.finish()
        all.commits += tail.commits
        all.ranges += tail.ranges
        all.contents.merge(tail.contents) { $1 }
        return all
    }

    private mutating func takeBatch() -> Batch {
        defer { batch = Batch() }
        return batch
    }

    // MARK: Lines

    private mutating func parse(_ line: String) {
        if line.hasPrefix("\t") {
            // Porcelain: the content of the line the last record named.
            emitPending()
            if let number = lastFinalLine {
                batch.contents[number] = String(line.dropFirst())
            }
            return
        }
        if let header = Self.header(line) {
            emitPending()
            let known = fields[header.sha]
            pending = Pending(sha: header.sha, sourceLine: header.source, finalLine: header.final,
                              count: header.count, path: known?.path, previous: known?.previous)
            lastFinalLine = header.final
            return
        }
        guard pending != nil else { return }
        let key: Substring
        let value: Substring
        if let space = line.firstIndex(of: " ") {
            key = line[..<space]
            value = line[line.index(after: space)...]
        } else {
            key = line[...]
            value = ""
        }
        apply(key: key, value: value)
    }

    private mutating func apply(key: Substring, value: Substring) {
        guard let sha = pending?.sha else { return }
        var commit = fields[sha] ?? CommitFields()
        switch key {
        case "author": commit.authorName = String(value)
        case "author-mail": commit.authorEmail = Self.unbracketed(value)
        case "author-time": commit.authorTime = TimeInterval(value) ?? 0
        case "summary": commit.summary = String(value)
        case "boundary": commit.isBoundary = true
        case "previous":
            guard let space = value.firstIndex(of: " ") else { break }
            let origin = BlameOrigin(sha: String(value[..<space]), path: String(value[value.index(after: space)...]))
            pending?.previous = origin
            pending?.sawPrevious = true
            commit.previous = origin
        case "filename":
            let path = String(value)
            pending?.path = path
            commit.path = path
            // A record that names no `previous` has none (git prints
            // `previous` before `filename`), whatever an earlier one said.
            if pending?.sawPrevious == false {
                pending?.previous = nil
                commit.previous = nil
            }
            fields[sha] = commit
            // Incremental output: the record ends here.
            emitPending()
            return
        default:
            break
        }
        fields[sha] = commit
    }

    /// Emits the record being read, with its commit the first time.
    private mutating func emitPending() {
        guard let record = pending else { return }
        pending = nil
        let commit = fields[record.sha] ?? CommitFields()
        if emittedCommits.insert(record.sha).inserted {
            batch.commits.append(BlameCommit(
                sha: record.sha,
                authorName: commit.authorName,
                authorEmail: commit.authorEmail,
                authorDate: Date(timeIntervalSince1970: commit.authorTime),
                summary: commit.summary,
                isBoundary: commit.isBoundary
            ))
        }
        batch.ranges.append(BlameRange(
            sha: record.sha,
            sourceLine: record.sourceLine,
            finalLine: record.finalLine,
            count: record.count,
            path: record.path ?? commit.path ?? "",
            previous: record.previous
        ))
    }

    // MARK: Helpers

    /// `<sha> <source> <final> [<count>]`: 40 (SHA-1) or 64 (SHA-256) hex digits.
    private static func header(_ line: String) -> (sha: String, source: Int, final: Int, count: Int)? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 4,
              parts[0].count == 40 || parts[0].count == 64,
              parts[0].allSatisfy(\.isHexDigit),
              let source = Int(parts[1]), let final = Int(parts[2]) else { return nil }
        let count = parts.count == 4 ? Int(parts[3]) : 1
        guard let count, count > 0 else { return nil }
        return (String(parts[0]), source, final, count)
    }

    /// `<a@b.c>` → `a@b.c`.
    private static func unbracketed(_ value: Substring) -> String {
        var mail = value
        if mail.hasPrefix("<") { mail = mail.dropFirst() }
        if mail.hasSuffix(">") { mail = mail.dropLast() }
        return String(mail)
    }
}

/// Moves a line across one commit's change to a file, for "Blame before
/// this commit": the line of the parent's file that a line of the commit's
/// file corresponds to.
nonisolated enum BlameLineMapping {
    /// `line` of the new side of `hunks` (a `-U0` diff, parent → commit) on
    /// the old side. A line the commit didn't touch moves by what the hunks
    /// above it added or removed; a line inside a change goes to the same
    /// place in what it replaced, or to where an insertion went in.
    static func oldLine(forNewLine line: Int, in hunks: [DiffHunk]) -> Int {
        var delta = 0
        for hunk in hunks.sorted(by: { $0.newStart < $1.newStart }) {
            // With no new lines, the hunk sits after line `newStart`.
            let newFirst = hunk.newCount == 0 ? hunk.newStart + 1 : hunk.newStart
            if line < newFirst { break }
            let newEnd = hunk.newStart + max(hunk.newCount, 1)
            if hunk.newCount > 0, line < hunk.newStart + hunk.newCount {
                guard hunk.oldCount > 0 else { return max(hunk.oldStart, 1) }
                return hunk.oldStart + min(line - hunk.newStart, hunk.oldCount - 1)
            }
            let oldEnd = hunk.oldStart + max(hunk.oldCount, 1)
            delta = oldEnd - newEnd
        }
        return max(line + delta, 1)
    }
}
