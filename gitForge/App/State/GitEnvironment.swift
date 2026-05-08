import Foundation

/// Snapshot of how `git` looks on this machine: whether the CLI is reachable
/// and the parsed `git config --global` (identity, signing key, default
/// branch, pull strategy, auto-fetch interval). Owns the config reader and
/// installation probe so `AppState` doesn't have to.
///
/// Mutating methods throw rather than presenting their own alerts; callers
/// (typically `AppState`) decide how to surface failures.
@Observable
@MainActor
final class GitEnvironment {
    var gitStatus: GitInstallationStatus = .checking
    var globalConfig: GitGlobalConfig = .unknown

    private let configReader = GitGlobalConfigReader.shared

    /// Probes `git --version` and updates `gitStatus`. The DEBUG hook lets the
    /// "git not found" UI be exercised without uninstalling git.
    func refreshGitInstallation() async {
        // @Observable fires its didChange on every assignment, even no-op
        // ones. This guard avoids triggering a redundant view rebuild when
        // we're already in the checking state.
        if gitStatus != .checking {
            gitStatus = .checking
        }
        let isAvailable = await GitCLI.isGitAvailable()
        gitStatus = isAvailable ? .available : .notFound
    }

    /// Re-reads `git config --global` into `globalConfig`.
    func refreshGlobalConfig() async {
        globalConfig = await configReader.read()
    }

    func setIdentity(name: String? = nil, email: String? = nil) async throws {
        if let name { try await configReader.setName(name) }
        if let email { try await configReader.setEmail(email) }
        await refreshGlobalConfig()
    }

    func setSigningKey(_ key: String?) async throws {
        try await configReader.setSigningKey(key)
        await refreshGlobalConfig()
    }

    func setDefaultBranch(_ name: String?) async throws {
        try await configReader.setDefaultBranch(name)
        await refreshGlobalConfig()
    }

    func setPullStrategy(_ strategy: String?) async throws {
        try await configReader.setPullStrategy(strategy)
        await refreshGlobalConfig()
    }

    func setAutoFetchInterval(_ seconds: Int?) async throws {
        try await configReader.setAutoFetchInterval(seconds)
        await refreshGlobalConfig()
    }
}
