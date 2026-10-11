import Foundation
import Observation

/// State of the "Add instance" sheet (P4 spec §5.3): validate what was
/// typed, verify it against the API, then save it.
@MainActor
@Observable
final class AddInstanceModel {
    enum State: Equatable {
        case editing
        case verifying
        /// macOS doesn't trust the certificate: the sheet offers to trust it, then retries.
        case needsTrust(host: String)
        case failed(String)
        case added(HostingInstance, warning: String?)
    }

    var kind: HostingInstance.Kind = .gitlab
    var url = ""
    /// "Advanced": empty means the default for the kind.
    var apiURL = ""
    private(set) var state: State = .editing

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let verifier: InstanceVerifier

    init(store: AccountStore, verifier: InstanceVerifier = InstanceVerifier(),
         kind: HostingInstance.Kind = .gitlab, url: String = "") {
        self.store = store
        self.verifier = verifier
        self.kind = kind
        self.url = url
    }

    /// The API address used when "API URL" is empty.
    var defaultAPIURL: String {
        (try? HostingInstance.make(kind: kind, url: url).get())?.apiBaseURL.absoluteString ?? ""
    }

    func add() async {
        let instance: HostingInstance
        switch HostingInstance.make(kind: kind, url: url, apiBaseURL: apiURL) {
        case .failure(let error):
            state = .failed(error.localizedDescription)
            return
        case .success(let made):
            instance = made
        }
        guard store.instance(forHost: instance.host) == nil else {
            state = .failed(AccountStoreError.duplicateHost(instance.host).localizedDescription)
            return
        }
        state = .verifying
        switch await verifier.verify(instance) {
        case .verified(let deviceFlow):
            save(instance, warning: deviceFlow ? nil
                 : "Sign-in with the browser needs GitLab 17.2 or later; this instance will use tokens.")
        case .needsSignIn:
            save(instance, warning: "The API needs a token to answer; it'll be checked when you connect the first account.")
        case .untrustedCertificate:
            state = .needsTrust(host: instance.host)
        case .unreachable(let message):
            state = .failed(message)
        }
    }

    private func save(_ instance: HostingInstance, warning: String?) {
        do {
            try store.addInstance(instance)
            state = .added(instance, warning: warning)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
