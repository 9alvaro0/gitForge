import Foundation

extension GitCLI {
    /// The `RemoteHost` of `remoteName` (default `origin`), recognised
    /// against the declared instances. `nil` when the remote doesn't exist
    /// or its host isn't an instance.
    func remoteHost(named remoteName: String = "origin", instances: [HostingInstance]) async -> RemoteHost? {
        guard let url = await remoteURL(remoteName) else { return nil }
        return RemoteHost.parse(url, instances: instances)
    }
}
