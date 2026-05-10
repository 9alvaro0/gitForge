import Foundation

extension GitCLI {
    func fetchAll() async throws {
        try await run(["fetch", "--all", "--prune"])
    }

    func pull(rebase: Bool = false, ffOnly: Bool = false) async throws {
        var args: [String] = ["pull"]
        if rebase { args.append("--rebase") }
        if ffOnly { args.append("--ff-only") }
        try await run(args)
    }

    func push(setUpstream: Bool,
              remote: String = "origin",
              branch: String? = nil,
              forceWithLease: Bool = false) async throws {
        var args: [String] = ["push"]
        if forceWithLease { args.append("--force-with-lease") }
        if setUpstream {
            args.append("--set-upstream")
            args.append(Self.endOfOptions)
            args.append(remote)
            if let branch { args.append(branch) }
        } else if let branch, forceWithLease {
            // force-with-lease without --set-upstream still needs the
            // remote+branch when the user explicitly wants to be safe.
            args.append(Self.endOfOptions)
            args.append(remote)
            args.append(branch)
        }
        try await run(args)
    }

    func upstreamName() async -> String? {
        do {
            let result = try await run(["rev-parse", "--abbrev-ref", "@{upstream}"])
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    func aheadBehind(branch: String, upstream: String) async throws -> (ahead: Int, behind: Int) {
        let result = try await run(["rev-list", "--left-right", "--count", Self.endOfOptions, "\(branch)...\(upstream)"])
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }
}

enum RemoteFailure: Sendable, Equatable {
    case authentication
    case nonFastForward
    case divergentBranches
    case conflict
    case network
    case noUpstream
    case other(String)

    init(stderr: String) {
        let lower = stderr.lowercased()
        if lower.contains("authentication failed")
            || lower.contains("permission denied")
            || lower.contains("could not read username")
            || lower.contains("publickey") {
            self = .authentication
        } else if lower.contains("divergent branches")
                    || lower.contains("need to specify how to reconcile") {
            // git ≥ 2.27 refuses ambiguous pulls until pull.rebase /
            // pull.ff is configured — surface this as its own failure
            // rather than the generic "rejected" bucket.
            self = .divergentBranches
        } else if lower.contains("non-fast-forward")
                    || lower.contains("rejected")
                    || lower.contains("updates were rejected") {
            self = .nonFastForward
        } else if lower.contains("automatic merge failed")
                    || lower.contains("conflict") {
            self = .conflict
        } else if lower.contains("could not resolve host")
                    || lower.contains("connection refused")
                    || lower.contains("connection timed out")
                    || lower.contains("network is unreachable") {
            self = .network
        } else if lower.contains("no upstream")
                    || lower.contains("no tracking information") {
            self = .noUpstream
        } else {
            self = .other(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    var title: String {
        switch self {
        case .authentication: "Authentication failed"
        case .nonFastForward: "Push rejected"
        case .divergentBranches: "Pull rejected"
        case .conflict: "Merge conflict"
        case .network: "Network unreachable"
        case .noUpstream: "No upstream branch"
        case .other: "Operation failed"
        }
    }

    var message: String {
        switch self {
        case .authentication:
            "Check your SSH key or credential helper. Try running the command in Terminal first to verify access."
        case .nonFastForward:
            "The remote has commits you don't have locally. Pull first to merge or rebase, then push again."
        case .divergentBranches:
            "Local and remote have diverged. Pick \"Pull and rebase\" or \"Pull (only if no merge needed)\" from the Pull menu."
        case .conflict:
            "Merging produced conflicts. Resolve them in the working copy, then commit the result."
        case .network:
            "Couldn't reach the remote. Check your internet connection and try again."
        case .noUpstream:
            "This branch isn't tracking a remote. The first push will set the upstream automatically."
        case .other(let raw):
            raw.isEmpty ? "The git command failed without a message." : raw
        }
    }

    /// Combined headline + actionable detail for a single-line toast.
    var toastMessage: String { "\(title) — \(message)" }
}

extension RemoteFailure {
    static func from(_ error: Error) -> RemoteFailure {
        if let gitError = error as? GitError, case .commandFailed(_, _, let stderr) = gitError {
            return RemoteFailure(stderr: stderr)
        }
        return .other(error.localizedDescription)
    }
}
