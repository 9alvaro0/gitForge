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

    /// Sends untracked files to the Trash (recoverable) instead of `removeItem`
    /// so a misclick on "Discard" doesn't permanently lose unstaged work.
    func deleteUntracked(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let fm = FileManager.default
        let base = workingDirectory.path(percentEncoded: false)
        for path in paths {
            let full = URL(fileURLWithPath: (base as NSString).appendingPathComponent(path))
            do {
                try fm.trashItem(at: full, resultingItemURL: nil)
            } catch {
                try? fm.removeItem(at: full)
            }
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
