import Foundation

extension GitCLI {
    /// Resolve a `RemoteHost` for the given remote name (default `origin`).
    /// Returns nil when the remote doesn't exist or doesn't belong to a
    /// supported provider.
    func remoteHost(named remoteName: String = "origin") async -> RemoteHost? {
        do {
            let result = try await run(["remote", "get-url", Self.endOfOptions, remoteName])
            let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return RemoteHost.parse(url)
        } catch {
            return nil
        }
    }
}
