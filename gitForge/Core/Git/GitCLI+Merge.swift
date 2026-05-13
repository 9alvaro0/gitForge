import Foundation

enum MergeState: Sendable, Equatable {
    case clean
    case merging
    case rebasing
    case cherryPicking
    case reverting
    case bisecting
    /// Unmerged paths exist but no marker file is present. Typically a
    /// `git stash apply/pop` that produced conflicts — stash doesn't write
    /// the marker files merge/rebase rely on, so we infer from
    /// `git diff --diff-filter=U`.
    case unmerged

    var isInProgress: Bool { self != .clean }
}

extension GitCLI {
    /// Inspect the `.git` directory (and unmerged paths as a fallback) to
    /// figure out whether the worktree is mid-integration. Marker files
    /// have priority over `.unmerged` because the same conflict can show
    /// up alongside `CHERRY_PICK_HEAD`; the marker tells us which command
    /// owns the resolution path (`cherry-pick --continue` vs a plain commit).
    func mergeState() async -> MergeState {
        let gitDir = workingDirectory.appendingPathComponent(".git")
        let fm = FileManager.default
        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: gitDir.appendingPathComponent(name).path(percentEncoded: false))
        }
        if exists("MERGE_HEAD") { return .merging }
        if exists("rebase-merge") || exists("rebase-apply") { return .rebasing }
        if exists("CHERRY_PICK_HEAD") { return .cherryPicking }
        if exists("REVERT_HEAD") { return .reverting }
        if exists("BISECT_LOG") { return .bisecting }
        if let paths = try? await unmergedPaths(), !paths.isEmpty {
            return .unmerged
        }
        return .clean
    }

    /// Files currently in `unmerged` state (`U` in porcelain v2).
    func unmergedPaths() async throws -> [String] {
        let result = try await run(["diff", "--name-only", "--diff-filter=U"])
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func mergeAbort() async throws {
        _ = try await run(["merge", "--abort"])
    }

    func mergeContinue() async throws {
        _ = try await run(["merge", "--continue"])
    }

    func rebaseAbort() async throws {
        _ = try await run(["rebase", "--abort"])
    }

    func rebaseContinue() async throws {
        _ = try await run(["rebase", "--continue"])
    }

    /// `git merge <branch> [--no-ff] [--squash] [-m message]`. Throws on
    /// conflicts — caller should refresh conflict state and route the user
    /// to the conflict resolver.
    func merge(branch: String, noFastForward: Bool = false, squash: Bool = false, message: String? = nil) async throws {
        var args: [String] = ["merge"]
        if noFastForward { args.append("--no-ff") }
        if squash        { args.append("--squash") }
        if let message {
            args.append(contentsOf: ["-m", message])
        }
        args.append(Self.endOfOptions)
        args.append(branch)
        _ = try await run(args)
    }

    /// `git rebase <upstream>`. Throws on conflicts.
    func rebase(onto upstream: String) async throws {
        _ = try await run(["rebase", Self.endOfOptions, upstream])
    }

    /// Stages a path so git knows the conflict is resolved.
    func markResolved(path: String) async throws {
        _ = try await run(["add", "--", path])
    }

    /// Replaces the working-tree content of an unmerged path with the "ours"
    /// side. Caller must follow up with `markResolved(path:)` to clear the
    /// unmerged status.
    func checkoutOurs(path: String) async throws {
        _ = try await run(["checkout", "--ours", "--", path])
    }

    /// Replaces the working-tree content of an unmerged path with the "theirs"
    /// side. Caller must follow up with `markResolved(path:)` to clear the
    /// unmerged status.
    func checkoutTheirs(path: String) async throws {
        _ = try await run(["checkout", "--theirs", "--", path])
    }
}
