import Foundation

extension GitCLI {
    func fetchAll() async throws {
        try await run(["fetch", "--all", "--prune"])
    }

    func pull() async throws {
        try await run(["pull"])
    }

    func push(setUpstream: Bool, remote: String = "origin", branch: String? = nil) async throws {
        var args: [String] = ["push"]
        if setUpstream {
            args.append("--set-upstream")
            args.append(remote)
            if let branch { args.append(branch) }
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
        let result = try await run(["rev-list", "--left-right", "--count", "\(branch)...\(upstream)"])
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
}

extension RemoteFailure {
    static func from(_ error: Error) -> RemoteFailure {
        if let gitError = error as? GitError, case .commandFailed(_, _, let stderr) = gitError {
            return RemoteFailure(stderr: stderr)
        }
        return .other(error.localizedDescription)
    }
}
