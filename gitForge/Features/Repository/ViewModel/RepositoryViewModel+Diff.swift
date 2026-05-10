import Foundation
import os

extension RepositoryViewModel {
    /// Hard ceiling on bytes read from disk when synthesizing an untracked
    /// file's diff. Anything larger gets a "binary"-style placeholder so we
    /// don't blow up trying to render a 50 MB log as a single hunk.
    private static let untrackedDiffByteCap = 1_000_000

    func loadCommitFileDiff(sha: String, path: String) async {
        // Snapshot the selection token. If the user moves on while we await
        // on the CLI, the token will fall behind and we drop the write-back
        // so the pane keeps showing the diff for the *current* selection,
        // not whichever async call finishes last.
        let gen = commitFileDiffGen
        loadingCommitFileDiff = true
        defer {
            if gen == commitFileDiffGen { loadingCommitFileDiff = false }
        }
        do {
            let raw = try await cli.diff(sha: sha, file: path)
            guard gen == commitFileDiffGen else { return }
            let hunks = DiffParser.parse(raw)
            commitFileDiff = hunks
            commitFileDiffEmptyState = hunks.isEmpty ? Self.classifyEmptyDiff(raw: raw) : .empty
        } catch {
            guard gen == commitFileDiffGen else { return }
            Self.logger.error("Failed to load commit diff: \(error.localizedDescription, privacy: .public)")
            commitFileDiff = []
            commitFileDiffEmptyState = .empty
        }
    }

    func loadWorkingCopyDiff(file: WorkingCopyFile) async {
        let gen = workingCopyDiffGen
        loadingWorkingCopyDiff = true
        defer {
            if gen == workingCopyDiffGen { loadingWorkingCopyDiff = false }
        }
        do {
            if file.isUntracked && !file.isStaged {
                let synthesized = await synthesizeUntrackedDiff(path: file.path)
                guard gen == workingCopyDiffGen else { return }
                workingCopyDiff = DiffParser.parse(synthesized.raw)
                workingCopyDiffEmptyState = workingCopyDiff.isEmpty ? synthesized.emptyState : .empty
                return
            }
            let raw: String
            if file.isStaged {
                raw = try await cli.diffStaged(file: file.path)
            } else {
                raw = try await cli.diffUnstaged(file: file.path)
            }
            guard gen == workingCopyDiffGen else { return }
            let hunks = DiffParser.parse(raw)
            workingCopyDiff = hunks
            workingCopyDiffEmptyState = hunks.isEmpty ? Self.classifyEmptyDiff(raw: raw) : .empty
        } catch {
            guard gen == workingCopyDiffGen else { return }
            Self.logger.error("Failed to load working-copy diff: \(error.localizedDescription, privacy: .public)")
            workingCopyDiff = []
            workingCopyDiffEmptyState = .empty
        }
    }

    /// Reads an untracked file off the main thread and emits a unified-diff
    /// string that marks every line as added. Empty files and binaries
    /// short-circuit to an empty raw string + the matching `DiffEmptyState`
    /// so the renderer can show a meaningful placeholder.
    ///
    /// Binary detection mirrors git's heuristic: a NUL byte in the first 8 KB
    /// of the file is enough to classify as binary. Files larger than
    /// `untrackedDiffByteCap` are also routed through the binary path — the
    /// goal is "tell the user something exists", not "parse a 50 MB log".
    private func synthesizeUntrackedDiff(path: String) async -> (raw: String, emptyState: DiffEmptyState) {
        let absolute = repository.url.appendingPathComponent(path)
        let cap = Self.untrackedDiffByteCap
        return await Task.detached {
            guard let data = try? Data(contentsOf: absolute, options: [.mappedIfSafe]) else {
                return ("", DiffEmptyState.empty)
            }
            if data.isEmpty {
                return ("", DiffEmptyState.empty)
            }
            if data.count > cap {
                return ("", DiffEmptyState.untrackedBinary)
            }
            let probeLength = min(8000, data.count)
            if data.prefix(probeLength).contains(0) {
                return ("", DiffEmptyState.untrackedBinary)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return ("", DiffEmptyState.untrackedBinary)
            }
            return (Self.synthesizeAddDiff(text: text), DiffEmptyState.empty)
        }.value
    }

    /// Builds a single `@@ -0,0 +1,N @@` hunk where every line is a `+`. The
    /// `\ No newline at end of file` trailer matches what `git diff` emits so
    /// the parser's existing newline handling kicks in unchanged.
    nonisolated static func synthesizeAddDiff(text: String) -> String {
        guard !text.isEmpty else { return "" }
        let endsWithNewline = text.hasSuffix("\n")
        let lines = text.components(separatedBy: "\n")
        // `components(separatedBy:)` leaves a trailing empty element when the
        // string ends with a newline — that element isn't a real line, drop it.
        let actual: ArraySlice<String> = endsWithNewline ? lines.dropLast() : ArraySlice(lines)
        guard !actual.isEmpty else { return "" }
        var output = "@@ -0,0 +1,\(actual.count) @@\n"
        output += actual.map { "+\($0)" }.joined(separator: "\n")
        output += "\n"
        if !endsWithNewline {
            output += "\\ No newline at end of file\n"
        }
        return output
    }

    /// Inspects the raw diff output to figure out *why* the parser produced no
    /// hunks. Git emits `Binary files X and Y differ` for binaries and
    /// `rename from`/`rename to` headers for pure renames — neither contain
    /// `@@`, so the parser empties out and we'd otherwise fall back to the
    /// generic "No changes" copy.
    nonisolated static func classifyEmptyDiff(raw: String) -> DiffEmptyState {
        if raw.contains("Binary files") || raw.contains("GIT binary patch") {
            return .binary
        }
        if raw.contains("\nrename from ") || raw.hasPrefix("rename from ") {
            return .renameOnly
        }
        return .empty
    }

    /// Returns the cached `CommitDetail` for `commit`, fetching once if not
    /// cached. Concurrent callers requesting the same sha share a single
    /// in-flight fetch instead of each spawning their own CLI call.
    func detail(for commit: Commit) async -> CommitDetail? {
        if let cached = detailCache[commit.sha] { return cached }
        if let inflight = inFlightDetail(for: commit.sha) {
            return await inflight.value
        }

        let task = Task<CommitDetail?, Never> { [self] in
            // Innermost defer runs first: clear the loading marker before the
            // in-flight slot, so the UI's "loading" state goes away in sync
            // with the await returning to the original caller.
            defer { setInFlightDetail(nil, for: commit.sha) }
            setLoadingDetail(commit.sha)
            defer {
                if loadingDetailFor == commit.sha { setLoadingDetail(nil) }
            }
            do {
                let detail = try await cli.commitDetail(for: commit)
                cacheDetail(detail, for: commit.sha)
                return detail
            } catch {
                Self.logger.error("Failed to load detail for \(commit.sha, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        setInFlightDetail(task, for: commit.sha)
        return await task.value
    }
}
