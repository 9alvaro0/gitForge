import Foundation

extension GitCLI {
    /// `fetch --all --prune`. With accounts, one run when a single account
    /// signs and every other remote on its host resolves to it too. A run
    /// carries one credential, scoped to a host (spec §6), so otherwise the
    /// remotes are fetched one by one: a same-host remote without that
    /// account keeps the system's helper.
    func fetchAll() async throws {
        guard let credentials else {
            try await run(["fetch", "--all", "--prune"])
            return
        }
        let repoPath = workingDirectory.path(percentEncoded: false)
        var signers: [(remote: String, url: String?, account: UUID?)] = []
        for remote in await fetchAllRemoteNames() {
            let url = await remoteURL(remote)
            var account: UUID?
            if let url {
                switch await credentials.signer(remoteURL: url, remoteName: remote, repoPath: repoPath) {
                case .none: account = nil
                case .account(let id): account = id
                // A key no other remote shares: forces the split, so this
                // remote's own run can stop and ask.
                case .needsChoice: account = UUID()
                }
            }
            signers.append((remote, url, account))
        }
        let accounts = Set(signers.compactMap(\.account))
        if accounts.isEmpty {
            try await run(["fetch", "--all", "--prune"])
            return
        }
        if accounts.count == 1, let signed = signers.first(where: { $0.account != nil }) {
            let host = GitCredentialInjection.urlContext(signed.url ?? "")
            let sharesHost = signers.filter { GitCredentialInjection.urlContext($0.url ?? "") == host }
            if sharesHost.allSatisfy({ $0.account == signed.account }) {
                try await runNetwork(["fetch", "--all", "--prune"], remote: signed.remote)
                return
            }
        }
        // Like `fetch --all`: keep going after a failing remote and report
        // the first failure at the end — but stop at once when cancelled.
        var firstFailure: Error?
        for signer in signers {
            do {
                try await runNetwork(["fetch", "--prune", Self.endOfOptions, signer.remote], remote: signer.remote)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    /// Fetches a single remote — used as the implicit refresh before a
    /// `--force-with-lease` push so the lease compares against a fresh
    /// remote-tracking ref instead of a stale one.
    func fetch(remote: String) async throws {
        try await runNetwork(["fetch", Self.endOfOptions, remote], remote: remote)
    }

    func pull(rebase: Bool = false, ffOnly: Bool = false) async throws {
        var args: [String] = ["pull"]
        if rebase { args.append("--rebase") }
        if ffOnly { args.append("--ff-only") }
        try await runNetwork(args, remote: credentials == nil ? "origin" : await pullRemote())
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
        try await runNetwork(args, remote: remote)
    }

    /// Pushes a local branch that needn't be checked out. Without
    /// `setUpstream` it goes to the branch it tracks (`branch.<b>.merge`)
    /// when `remote` is its tracking remote, else to a same-named branch —
    /// what `git push` does for the current branch.
    func pushBranch(_ branch: String, remote: String, setUpstream: Bool) async throws {
        var args = ["push"]
        if setUpstream { args.append("--set-upstream") }
        args.append(Self.endOfOptions)
        args.append(remote)
        var refspec = "refs/heads/\(branch)"
        if !setUpstream,
           await configValue("branch.\(branch).remote") == remote,
           let merge = await configValue("branch.\(branch).merge") {
            refspec += ":\(merge)"
        }
        args.append(refspec)
        try await runNetwork(args, remote: remote)
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

    /// The remote a push of `branch` goes to, in git's order:
    /// `branch.<name>.pushRemote`, `remote.pushDefault`, `branch.<name>.remote`.
    /// `nil` when none is set (git then uses `origin`).
    func pushRemoteName(forBranch branch: String) async -> String? {
        for key in ["branch.\(branch).pushRemote", "remote.pushDefault", "branch.\(branch).remote"] {
            if let value = await configValue(key) { return value }
        }
        return nil
    }

    private func configValue(_ key: String) async -> String? {
        guard let result = try? await run(["config", "--get", key]) else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    // MARK: Signing network commands

    func remoteNames() async -> [String] {
        guard let result = try? await run(["remote"]) else { return [] }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    /// The remotes `fetch --all` visits: all but those with
    /// `remote.<name>.skipFetchAll` set.
    func fetchAllRemoteNames() async -> [String] {
        let names = await remoteNames()
        guard let result = try? await run(["config", "--type=bool", "--get-regexp", #"^remote\..*\.skipfetchall$"#]) else {
            return names
        }
        let skipped = Self.skipFetchAllRemotes(result.stdout)
        return names.filter { !skipped.contains($0) }
    }

    /// Remote names whose `skipFetchAll` is true, from `config --get-regexp`
    /// lines (`remote.<name>.skipfetchall true`). Names may contain dots.
    nonisolated static func skipFetchAllRemotes(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, parts[1] == "true" else { return nil }
            let key = parts[0]
            let prefix = "remote.", suffix = ".skipfetchall"
            guard key.hasPrefix(prefix), key.hasSuffix(suffix), key.count > prefix.count + suffix.count else { return nil }
            return String(key.dropFirst(prefix.count).dropLast(suffix.count))
        })
    }

    /// The URL git talks to for `remote` (its `pushurl` when `push`); `nil`
    /// when there's no such remote.
    func remoteURL(_ remote: String, push: Bool = false) async -> String? {
        let args = ["remote", "get-url"] + (push ? ["--push"] : []) + [Self.endOfOptions, remote]
        guard let result = try? await run(args) else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    /// Every remote with its fetch URL, in `git remote` order.
    func remotesWithURLs() async -> [GitRemoteURL] {
        var result: [GitRemoteURL] = []
        for name in await remoteNames() {
            if let url = await remoteURL(name) { result.append(GitRemoteURL(name: name, url: url)) }
        }
        return result
    }

    /// The remote a bare `git pull` talks to: the current branch's
    /// `branch.<name>.remote`, else `origin`.
    func pullRemote() async -> String {
        guard let branch = await currentBranchName() else { return "origin" }
        return await upstreamRemoteName(forBranch: branch) ?? "origin"
    }

    /// Runs a network command against `remote` with its account's credential
    /// when there is one; otherwise exactly like `run`. A push is signed for
    /// the remote's push URL (`pushurl`), the one git will talk to.
    @discardableResult
    func runNetwork(_ args: [String], remote: String) async throws -> GitResult {
        guard let credentials, let url = await remoteURL(remote, push: args.first == "push") else { return try await run(args) }
        let repoPath = workingDirectory.path(percentEncoded: false)
        return try await credentials.withCredential(remoteURL: url, remoteName: remote, repoPath: repoPath) { credential in
            try await self.run(args, credential: credential)
        }
    }
}

nonisolated enum RemoteFailure: Sendable, Equatable {
    /// HTTPS auth — token expired, missing, or never configured.
    case authenticationHTTPS
    /// SSH auth — key not in agent, locked, or wrong key for the host.
    case authenticationSSH
    /// The server refused the credential of the repo's hosting account
    /// (gitForge's own, not the system helper's).
    case accountRejected(account: String, host: String)
    /// The token git sent (an account's or the system helper's) lacks a scope the operation needs (GitHub wants
    /// `workflow` to change files under `.github/workflows`).
    case missingScope(String)
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
    /// The user cancelled (e.g. "Choose an account" → Cancel): no toast.
    case cancelled
    case other(String)

    init(stderr: String) {
        let lower = stderr.lowercased()
        // SSL/TLS issues before generic auth — git phrases them as access
        // failures but the cause and remediation are very different.
        if let scope = Self.missingScope(in: lower) {
            self = .missingScope(scope)
        } else if lower.contains("ssl certificate problem")
            || lower.contains("server certificate verification failed")
            || lower.contains("ssl_error")
            || lower.contains("certificate verify failed") {
            self = .sslCertificate
        } else if lower.contains("could not resolve host") // also matches ssh's "…hostname"
                    || lower.contains("connection refused")
                    || lower.contains("connection timed out")
                    || lower.contains("operation timed out")
                    || lower.contains("network is unreachable")
                    || lower.contains("no route to host")
                    || lower.contains("connection reset by peer") {
            // Network before SSH: ssh prefixes its own connectivity errors
            // with "ssh:" ("ssh: Could not resolve hostname …"), and an
            // offline user with an SSH remote was told to check their keys.
            self = .network
        } else if lower.contains("publickey")
                    || lower.contains("host key verification failed")
                    || lower.contains("ssh:") {
            self = .authenticationSSH
        } else if lower.contains("authentication failed")
            || lower.contains("could not read username")
            || lower.contains("invalid credentials")
            || lower.contains("bad credentials")
            || lower.contains("http basic")
            || lower.contains("token has expired")
            || lower.contains("error: 401")
            || lower.contains("401 unauthorized")
            || lower.contains("error: 403")
            || lower.contains("403 forbidden") {
            // Status codes are matched with their curl prefix: a bare "401"
            // also matched SHAs, line numbers and byte counts in stderr.
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
        } else if lower.contains("no upstream")
                    || lower.contains("no tracking information") {
            self = .noUpstream
        } else {
            // Shown in a toast: blank any account token a hook or server echoed.
            self = .other(GitCLI.redacted(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    /// GitHub's "… without `workflow` scope" (OAuth App or personal token).
    private static func missingScope(in lower: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "without [`'\"]?([a-z_:]+)[`'\"]? scope") else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let scope = Range(match.range(at: 1), in: lower) else { return nil }
        return String(lower[scope])
    }

    var title: String {
        switch self {
        case .authenticationHTTPS: "HTTPS authentication failed"
        case .authenticationSSH:   "SSH authentication failed"
        case .accountRejected:     "Account rejected"
        case .missingScope:        "Missing permission"
        case .nonFastForward:      "Push rejected"
        case .divergentBranches:   "Pull rejected"
        case .conflict:            "Merge conflict"
        case .network:             "Network unreachable"
        case .sslCertificate:      "Certificate not trusted"
        case .protectedBranch:     "Branch is protected"
        case .serverUnavailable:   "Remote is unavailable"
        case .rateLimited:         "Rate limit reached"
        case .noUpstream:          "No upstream branch"
        case .cancelled:           "Cancelled"
        case .other:               "Operation failed"
        }
    }

    var message: String {
        switch self {
        case .authenticationHTTPS:
            "Your token or credential helper rejected the request. Refresh the token (or sign in again) and retry. If a stale credential is cached, `git credential-osxkeychain erase` clears it."
        case .accountRejected(let account, let host):
            "\(host) rejected the \(account) account gitForge used for this remote. Reconnect it in Settings › Accounts."
        case .missingScope(let scope):
            // git doesn't say whose token it was: a gitForge account or the
            // system's credential helper.
            "The token used for this remote lacks the `\(scope)` scope this operation needs. If it's a gitForge account, reconnect it to grant the scope; if it comes from your credential helper, replace it with a token that has it."
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
        case .cancelled:
            "The operation was cancelled."
        case .noUpstream:
            "This branch isn't tracking a remote. The first push will set the upstream automatically."
        case .other(let raw):
            raw.isEmpty ? "The git command failed without a message." : raw
        }
    }

    /// Combined headline + actionable detail for a single-line toast.
    var toastMessage: String { "\(title) — \(message)" }
}

nonisolated extension RemoteFailure {
    static func from(_ error: Error) -> RemoteFailure {
        if error is CancellationError { return .cancelled }
        if let gitError = error as? GitError, case .commandFailed(_, _, let stderr) = gitError {
            return RemoteFailure(stderr: stderr)
        }
        if case .rejected(let account, let host)? = error as? GitAccountError {
            return .accountRejected(account: account, host: host)
        }
        if let authError = error as? HostingAuthError {
            switch authError {
            case .network: return .network
            case .tls: return .sslCertificate
            default: return .other(authError.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }
}

nonisolated struct GitRemoteURL: Equatable, Sendable {
    let name: String
    let url: String
}
