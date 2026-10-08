import Foundation

extension GitCLI {
    func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["add", "--"] + paths)
    }

    func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["restore", "--staged", "--"] + paths)
    }

    func discardChanges(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["restore", "--"] + paths)
    }

    /// Resets unmerged paths to HEAD content — the equivalent of "abandon
    /// this conflict and keep what HEAD says". `git restore --` (and the
    /// equivalent `git checkout --`) refuse to touch unmerged paths because
    /// the index has multiple stages; `git checkout HEAD --` overwrites both
    /// the index entry and the worktree from HEAD, which is what users want
    /// when they pick "Discard" on a conflicted file.
    func discardUnmerged(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["checkout", "HEAD", "--"] + paths)
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

    func commit(subject: String, body: String? = nil, amend: Bool = false) async throws {
        var args: [String] = ["commit"]
        if amend { args.append("--amend") }
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
        let more = paths.count > 3 ? " and \(paths.count - 3) more" : ""
        return "Couldn't delete \(listed)\(more). Check the file permissions and try again."
    }
}
