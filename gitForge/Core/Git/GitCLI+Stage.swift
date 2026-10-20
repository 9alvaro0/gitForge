import Foundation

extension GitCLI {
    func stage(paths: [String]) async throws {
        try await runInBatches(["add", "--"], paths: paths)
    }

    func unstage(paths: [String]) async throws {
        try await runInBatches(["restore", "--staged", "--"], paths: paths)
    }

    func discardChanges(paths: [String]) async throws {
        try await runInBatches(["restore", "--"], paths: paths)
    }

    /// Resets unmerged paths to HEAD content — the equivalent of "abandon
    /// this conflict and keep what HEAD says". `git restore --` (and the
    /// equivalent `git checkout --`) refuse to touch unmerged paths because
    /// the index has multiple stages; `git checkout HEAD --` overwrites both
    /// the index entry and the worktree from HEAD, which is what users want
    /// when they pick "Discard" on a conflicted file.
    func discardUnmerged(paths: [String]) async throws {
        try await runInBatches(["checkout", "HEAD", "--"], paths: paths)
    }

    /// Bytes of paths per git run. macOS caps a process's arguments plus
    /// environment at `ARG_MAX` (1 MB); staging tens of thousands of files
    /// in one run failed to launch.
    static let pathBatchBytes = 128 * 1024

    /// Runs `command` once per batch of `paths`, in order; stops at the
    /// first failure.
    private func runInBatches(_ command: [String], paths: [String]) async throws {
        for batch in Self.pathBatches(paths) {
            try await run(command + batch)
        }
    }

    /// `paths` split so each batch's bytes (with separators) stay under
    /// `limit`; a single longer path gets a batch of its own.
    nonisolated static func pathBatches(_ paths: [String], limit: Int = pathBatchBytes) -> [[String]] {
        var batches: [[String]] = []
        var current: [String] = []
        var size = 0
        for path in paths {
            let bytes = path.utf8.count + 1
            if !current.isEmpty, size + bytes > limit {
                batches.append(current)
                current = []
                size = 0
            }
            current.append(path)
            size += bytes
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    /// Sends untracked files to the Trash when the volume has one, so a
    /// misclick on "Discard" is usually recoverable; volumes without a Trash
    /// (network shares, some external disks) fall back to deleting — the UI
    /// copy already says the action can't be undone. Paths already gone are
    /// skipped. Files that could be neither trashed nor deleted are reported
    /// together at the end instead of silently staying on disk.
    func deleteUntracked(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let fm = FileManager.default
        let base = workingDirectory.path(percentEncoded: false)
        var failures: [String] = []
        for path in paths {
            let full = URL(fileURLWithPath: (base as NSString).appendingPathComponent(path))
            guard fm.fileExists(atPath: full.path(percentEncoded: false)) else { continue }
            do {
                try fm.trashItem(at: full, resultingItemURL: nil)
            } catch {
                do {
                    try fm.removeItem(at: full)
                } catch {
                    failures.append(path)
                }
            }
        }
        if !failures.isEmpty {
            throw DeleteUntrackedError(paths: failures)
        }
    }

    /// Applies a patch built by `HunkPatch` — to the index (`cached`) or the
    /// worktree, forward or `reverse`. The patch goes through a temporary
    /// file; `--recount` lets a partial-line patch carry approximate counts.
    func apply(patch: String, cached: Bool, reverse: Bool) async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-hunk-\(UUID().uuidString).patch")
        try Data(patch.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var args = ["apply", "--recount", "--whitespace=nowarn"]
        if cached { args.append("--cached") }
        if reverse { args.append("--reverse") }
        if HunkPatch.hasNoContext(patch) { args.append("--unidiff-zero") }
        args += [Self.endOfOptions, file.path(percentEncoded: false)]
        try await run(args)
    }

    /// `signOff` adds the `Signed-off-by:` trailer (`--signoff`).
    func commit(subject: String, body: String? = nil, amend: Bool = false, signOff: Bool = false) async throws {
        var args: [String] = ["commit"]
        if amend { args.append("--amend") }
        if signOff { args.append("--signoff") }
        args.append("-m")
        args.append(subject)
        if let body, !body.isEmpty {
            args.append("-m")
            args.append(body)
        }
        try await run(args)
    }
}

/// Untracked files that survived `deleteUntracked` (permissions, locks).
nonisolated struct DeleteUntrackedError: LocalizedError, Equatable {
    let paths: [String]

    var errorDescription: String? {
        let listed = paths.prefix(3).joined(separator: ", ")
        if paths.count > 3 {
            let more = paths.count - 3
            return String(localized: "Couldn't delete \(listed) and \(more) more. Check the file permissions and try again.")
        }
        return String(localized: "Couldn't delete \(listed). Check the file permissions and try again.")
    }
}
