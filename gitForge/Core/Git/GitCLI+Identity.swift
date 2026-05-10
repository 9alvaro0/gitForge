import Foundation

extension GitCLI {
    /// Reads the *effective* `user.name` / `user.email` / `user.signingkey`
    /// for this repo (local override → global fallback) plus a flag telling
    /// the UI whether the repo has its own `--local` override. Two extra
    /// reads vs. just `--get` — cheap and avoids guessing in the caller.
    func currentIdentity() async -> RepoIdentity {
        async let effectiveName  = effective("user.name")
        async let effectiveEmail = effective("user.email")
        async let effectiveKey   = effective("user.signingkey")
        async let localName      = local("user.name")
        async let localEmail     = local("user.email")
        // Materialise both async-let bindings before composing the bool —
        // autoclosure-backed `||` would refuse to host `async let` reads.
        let resolvedLocalName  = await localName
        let resolvedLocalEmail = await localEmail
        let isLocal = resolvedLocalName != nil || resolvedLocalEmail != nil
        return await RepoIdentity(
            name: effectiveName,
            email: effectiveEmail,
            signingKey: effectiveKey,
            isLocal: isLocal
        )
    }

    /// Writes `user.name` / `user.email` (and optionally `user.signingkey`)
    /// at `--local` scope. Always pins both name and email together so a
    /// half-applied profile can't ship commits with a mismatched pair.
    func setLocalIdentity(name: String, email: String, signingKey: String?) async throws {
        try await run(["config", "--local", "user.name", name])
        try await run(["config", "--local", "user.email", email])
        if let signingKey, !signingKey.isEmpty {
            try await run(["config", "--local", "user.signingkey", signingKey])
        } else {
            // Best effort — exit 5 (key not set) is fine.
            _ = try? await run(["config", "--local", "--unset", "user.signingkey"])
        }
    }

    /// Removes the repo-local override entirely so the repo falls back to
    /// the global identity. Each unset is `try?`'d because exit 5 means the
    /// key wasn't there, which is the desired post-state anyway.
    func clearLocalIdentity() async {
        _ = try? await run(["config", "--local", "--unset", "user.name"])
        _ = try? await run(["config", "--local", "--unset", "user.email"])
        _ = try? await run(["config", "--local", "--unset", "user.signingkey"])
    }

    // MARK: private

    private func effective(_ key: String) async -> String? {
        // No `--local` / `--global` — let git resolve scope precedence itself.
        guard let result = try? await run(["config", "--get", key]) else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func local(_ key: String) async -> String? {
        guard let result = try? await run(["config", "--local", "--get", key]) else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
