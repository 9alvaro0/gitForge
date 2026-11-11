import Foundation

/// The file a blame is shown over, as read before the blame runs.
nonisolated enum BlameSource: Sendable, Equatable {
    case text([String])
    /// NUL bytes in the first few kilobytes, as git decides it.
    case binary
    case tooLarge(bytes: Int)
}

extension GitCLI {
    /// Above this the blame view declines the file: every line is a row.
    static let blameMaxBytes = 10_000_000

    /// Streams `git blame --incremental` of `path`: at `revision`, or the
    /// working tree's version when `nil` (its uncommitted lines blamed on
    /// the all-zero SHA). Batches arrive as git finds each run of lines,
    /// parsed off the main actor; the stream ends when git does, or throws
    /// its error. Cancelling the consumer stops git.
    ///
    /// `-M -C`: lines moved within the file, or moved or copied from
    /// another file changed in the same commit, are blamed on where they
    /// came from. `-w` with `ignoreWhitespace`.
    nonisolated func blame(path: String, revision: String?, ignoreWhitespace: Bool)
        -> AsyncThrowingStream<BlameParser.Batch, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let args = try Self.blameArguments(path: path, revision: revision,
                                                       ignoreWhitespace: ignoreWhitespace)
                    let parser = LockedBlameParser()
                    try await self.runStreaming(args) { data in
                        let batch = parser.feed(data)
                        if !batch.isEmpty { continuation.yield(batch) }
                    }
                    let tail = parser.finish()
                    if !tail.isEmpty { continuation.yield(tail) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// git 2.43's `blame` rejects `--end-of-options`, so a revision that
    /// could read as an option is refused here instead.
    static func blameArguments(path: String, revision: String?, ignoreWhitespace: Bool) throws -> [String] {
        var args = ["blame", "--incremental", "-M", "-C"]
        if ignoreWhitespace { args.append("-w") }
        if let revision {
            guard !revision.isEmpty, !revision.hasPrefix("-") else {
                throw GitError.commandFailed(args: ["blame", revision], exitCode: 128,
                                             stderr: "invalid revision \(revision)")
            }
            args.append(revision)
        }
        return args + ["--", path]
    }

    /// The text blame runs over: the working tree's file (`revision` nil)
    /// or the file at `revision`. Throws when it isn't there.
    func blameSource(path: String, revision: String?) async throws -> BlameSource {
        let data: Data
        if let revision {
            guard !revision.hasPrefix("-") else { throw GitError.commandFailed(args: ["show"], exitCode: 128, stderr: "") }
            let size = try await run(["cat-file", "-s", "\(revision):\(path)"])
            if let bytes = Int(size.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), bytes > Self.blameMaxBytes {
                return .tooLarge(bytes: bytes)
            }
            data = Data(try await run(["cat-file", "-p", "\(revision):\(path)"]).stdout.utf8)
        } else {
            let url = workingDirectory.appendingPathComponent(path)
            let read: Result<Data, Error> = await GitProcess.offPool {
                Result { try Data(contentsOf: url, options: .mappedIfSafe) }
            }
            data = try read.get()
            if data.count > Self.blameMaxBytes { return .tooLarge(bytes: data.count) }
        }
        if data.prefix(8_000).contains(0) { return .binary }
        return .text(DiffGaps.splitLines(GitProcess.decode(data)))
    }

    /// `line` of `path` at `sha`, moved to `parent`'s `parentPath` across
    /// the commit's change: where "Blame before this commit" lands. For
    /// uncommitted lines (the all-zero SHA) the change is the working
    /// tree's. The same number when the diff can't be read.
    func lineBefore(_ line: Int, path: String, at sha: String, parent: String, parentPath: String) async -> Int {
        let paths = parentPath == path ? [path] : [parentPath, path]
        let revisions = BlameCommit.isUncommitted(sha) ? [parent] : [parent, sha]
        guard !revisions.contains(where: { $0.hasPrefix("-") }),
              let result = try? await run(["diff", "-U0", "-M"] + Self.diffOutputFlags
                                          + revisions + ["--"] + paths) else { return line }
        return BlameLineMapping.oldLine(forNewLine: line, in: DiffParser.parse(result.stdout))
    }
}

/// `BlameParser` behind a lock, fed from `runStreaming`'s reader thread.
nonisolated final class LockedBlameParser: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = BlameParser()

    func feed(_ data: Data) -> BlameParser.Batch {
        lock.lock(); defer { lock.unlock() }
        return parser.feed(data)
    }

    func finish() -> BlameParser.Batch {
        lock.lock(); defer { lock.unlock() }
        return parser.finish()
    }
}
