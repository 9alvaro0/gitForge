import Foundation

/// Whether a clone URL answers, as the clone sheet's "Reachable" line shows it.
nonisolated enum RemoteProbeResult: Equatable, Sendable {
    case reachable(defaultBranch: String?)
    /// `nil`: the URL isn't one git can clone, or the reason is unknown.
    case unreachable(RemoteFailure?)
}

/// `git ls-remote --symref -- <url> HEAD` from `$HOME`, signed like the clone
/// would be. Runs as background network work, so it never asks which
/// account to use.
nonisolated enum RemoteProbe {
    static func run(url: String, credentials: GitCredentialProvider?) async -> RemoteProbeResult {
        guard let safeURL = try? CloneURLValidator.validate(url) else { return .unreachable(nil) }
        let cli = GitCLI(workingDirectory: URL(fileURLWithPath: NSHomeDirectory()), credentials: credentials)
        let args = ["ls-remote", "--symref", GitCLI.endOfOptions, safeURL, "HEAD"]
        do {
            let result = try await GitNetworkContext.$isBackground.withValue(true) {
                guard let credentials else { return try await cli.run(args) }
                return try await credentials.withCredential(remoteURL: safeURL, remoteName: "origin", repoPath: "") { credential in
                    try await cli.run(args, credential: credential)
                }
            }
            return .reachable(defaultBranch: parse(lsRemoteOutput: result.stdout))
        } catch {
            return .unreachable(RemoteFailure.from(error))
        }
    }

    /// The branch `HEAD` points to, from `ref: refs/heads/<branch>\tHEAD`.
    static func parse(lsRemoteOutput output: String) -> String? {
        for line in output.split(separator: "\n") where line.hasPrefix("ref: refs/heads/") {
            let ref = line.dropFirst("ref: refs/heads/".count)
            return ref.split(separator: "\t").first.map(String.init)
        }
        return nil
    }
}
