import Foundation

/// What "Add instance" learned from the server (P4 spec §4.4).
nonisolated enum InstanceVerification: Equatable, Sendable {
    /// The API answered. `deviceFlow`: false on GitLab before 17.2.
    case verified(deviceFlow: Bool)
    /// The API wants a token first: saved, checked at the first sign-in.
    case needsSignIn
    /// macOS doesn't trust the certificate: offer "Trust certificate…".
    case untrustedCertificate
    case unreachable(String)
}

/// Checks a declared instance against its API before saving it:
/// `GET <api>/meta` on GitHub Enterprise, `GET <api>/version` on GitLab.
/// Uses the pinned-trust session, so a trusted private CA passes.
nonisolated struct InstanceVerifier: Sendable {
    let http: HostingHTTP

    init(http: HostingHTTP = .live) {
        self.http = http
    }

    func verify(_ instance: HostingInstance) async -> InstanceVerification {
        let url = instance.apiBaseURL.appending(path: instance.kind == .github ? "meta" : "version")
        do {
            let (data, _) = try await http.get(url, token: nil)
            guard instance.kind == .gitlab else { return .verified(deviceFlow: true) }
            let version = (try? JSONDecoder().decode(GitLabVersionBody.self, from: data))?.version
            return .verified(deviceFlow: version.map(Self.supportsDeviceFlow) ?? true)
        } catch HostingAuthError.unauthorized {
            return .needsSignIn
        } catch HostingAuthError.server(let status) where status == 403 {
            return .needsSignIn
        } catch HostingAuthError.tls(_) {
            return .untrustedCertificate
        } catch HostingAuthError.server(let status) {
            let address = url.absoluteString
            return .unreachable(String(localized: "The server answered \(status) at \(address). Check the address and the API URL."))
        } catch {
            return .unreachable(HostingAuthError.wrapping(error).localizedDescription)
        }
    }

    /// `"17.2.0-ee"` → true; anything before 17.2 or unparsable → false.
    static func supportsDeviceFlow(_ version: String) -> Bool {
        GitLabVersion(version).map { $0 >= GitLabVersion(major: 17, minor: 2) } ?? false
    }
}

nonisolated private struct GitLabVersionBody: Decodable {
    let version: String
}
