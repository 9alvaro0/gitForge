import Foundation

extension GitCLI {
    func fetchAll() async throws {
        try await run(["fetch", "--all", "--prune"])
    }

    /// Fetches a single remote — used as the implicit refresh before a
    /// `--force-with-lease` push so the lease compares against a fresh
    /// remote-tracking ref instead of a stale one.
    func fetch(remote: String) async throws {
        try await run(["fetch", Self.endOfOptions, remote])
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

    /// `branch.<name>.remote` — the remote configured for push/pull on this
    /// branch. Returns nil if the branch has no tracking config. Used to push
    /// to `upstream`/`fork`/etc. when the user renamed `origin`.
    func upstreamRemoteName(forBranch branch: String) async -> String? {
        do {
            let result = try await run(["config", "--get", "branch.\(branch).remote"])
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
    /// HTTPS auth — token expired, missing, or never configured.
    case authenticationHTTPS
    /// SSH auth — key not in agent, locked, or wrong key for the host.
    case authenticationSSH
    case nonFastForward
    case divergentBranches
    case conflict
    case network
    /// SSL/TLS cert validation failed. Usually captive portals, MITM proxies,
    /// or self-signed enterprise certs — distinct from `.network` because
    /// the remote IS reachable but our trust chain rejected it.
    case sslCertificate
    /// Remote upstream protected the branch (GitHub, GitLab, Bitbucket
    /// admin-side rules). Pull-first wouldn't help; the user needs to PR
    /// instead or get the branch unprotected.
    case protectedBranch
    /// Remote returned 502/503/504. Different from `.network` (reached the
    /// remote, server can't satisfy) and from rate limit.
    case serverUnavailable
    /// Remote returned 429.
    case rateLimited
    case noUpstream
    case other(String)

    init(stderr: String) {
        let lower = stderr.lowercased()
        // SSL/TLS issues before generic auth — git phrases them as access
        // failures but the cause and remediation are very different.
        if lower.contains("ssl certificate problem")
            || lower.contains("server certificate verification failed")
            || lower.contains("ssl_error")
            || lower.contains("certificate verify failed") {
            self = .sslCertificate
        } else if lower.contains("publickey") || lower.contains("ssh:") {
            self = .authenticationSSH
        } else if lower.contains("authentication failed")
            || lower.contains("could not read username")
            || lower.contains("invalid credentials")
            || lower.contains("bad credentials")
            || lower.contains("http basic")
            || lower.contains("token has expired")
            || lower.contains("401")
            || lower.contains("403 forbidden") {
            self = .authenticationHTTPS
        } else if lower.contains("permission denied") {
            // Permission denied without a protocol hint — fall back to SSH
            // since that's its canonical phrasing.
            self = .authenticationSSH
        } else if lower.contains("protected branch")
                    || lower.contains("gh006")
                    || lower.contains("required reviews")
                    || lower.contains("required status check") {
            self = .protectedBranch
        } else if lower.contains("rate limit")
                    || lower.contains("error: 429") {
            self = .rateLimited
        } else if lower.contains("error: 502")
                    || lower.contains("error: 503")
                    || lower.contains("error: 504")
                    || lower.contains("bad gateway")
                    || lower.contains("service unavailable")
                    || lower.contains("gateway timeout") {
            self = .serverUnavailable
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
        case .authenticationHTTPS: "HTTPS authentication failed"
        case .authenticationSSH:   "SSH authentication failed"
        case .nonFastForward:      "Push rejected"
        case .divergentBranches:   "Pull rejected"
        case .conflict:            "Merge conflict"
        case .network:             "Network unreachable"
        case .sslCertificate:      "Certificate not trusted"
        case .protectedBranch:     "Branch is protected"
        case .serverUnavailable:   "Remote is unavailable"
        case .rateLimited:         "Rate limit reached"
        case .noUpstream:          "No upstream branch"
        case .other:               "Operation failed"
        }
    }

    var message: String {
        switch self {
        case .authenticationHTTPS:
            "Your token or credential helper rejected the request. Refresh the token (or sign in again) and retry. If a stale credential is cached, `git credential-osxkeychain erase` clears it."
        case .authenticationSSH:
            "The host refused your SSH key. Run `ssh-add -l` to confirm it's loaded, or `ssh -T git@<host>` to test it. If the key has a passphrase, the agent needs it unlocked before the app can use it."
        case .nonFastForward:
            "The remote has commits you don't have locally. Pull first to merge or rebase, then push again — or use Force-push (with lease) if you intentionally rewrote local history."
        case .divergentBranches:
            "Local and remote have diverged. Pick \"Pull and rebase\" or \"Pull (only if no merge needed)\" from the Pull menu."
        case .conflict:
            "Merging produced conflicts. Resolve them in the working copy, then commit the result."
        case .network:
            "Couldn't reach the remote. Check your internet connection and try again."
        case .sslCertificate:
            "The server's SSL certificate isn't trusted. Often a captive portal (airport/coffee shop Wi-Fi), a MITM proxy, or a self-signed enterprise cert. Verify the network is what you expect before retrying."
        case .protectedBranch:
            "The remote rejected the push because the branch is protected by repository policy (required reviews, status checks, signed commits, etc.). Open a pull request instead."
        case .serverUnavailable:
            "The remote service is down or overloaded. Retry in a few minutes."
        case .rateLimited:
            "Too many requests in a short window. Wait a few minutes before retrying."
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
