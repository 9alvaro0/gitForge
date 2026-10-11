import Foundation
import Observation

/// State of the "Connect account" sheet (P4 spec §5.2): instance, method,
/// the browser or token flow, and the connected account.
@MainActor
@Observable
final class ConnectAccountModel {
    enum Method: Equatable { case browser, token }
    enum TokenState: Equatable { case idle, validating, failed(String) }

    var instanceId: UUID? {
        didSet {
            guard oldValue != instanceId else { return }
            resetFlow()
            method = methods.first ?? .token
        }
    }
    var method: Method = .token {
        didSet { if oldValue != method { resetFlow() } }
    }
    var token = ""
    /// "Use it for identity profile"; starts as the reconnected account's.
    var profileChoice: UUID?
    private(set) var tokenState: TokenState = .idle
    private(set) var deviceFlow: DeviceFlowSession?
    private(set) var scopesWarning = false
    private var tokenAccount: HostingAccount?

    let replacing: UUID?
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let connector: AccountConnector

    init(store: AccountStore, connector: AccountConnector, instanceId: UUID?, replacing: UUID?) {
        self.store = store
        self.connector = connector
        self.replacing = replacing
        self.instanceId = instanceId
        self.profileChoice = replacing.flatMap { id in store.accounts.first { $0.id == id }?.linkedProfileId }
        self.method = methods.first ?? .token
    }

    var instances: [HostingInstance] { store.instances }
    var instance: HostingInstance? { store.instances.first { $0.id == instanceId } }

    var methods: [Method] {
        guard let instance else { return [] }
        return connector.supportsOAuth(instance) ? [.browser, .token] : [.token]
    }

    var createTokenURL: URL? { instance.map(HostingScopes.createTokenURL) }
    var requiredScopes: String {
        instance.map { HostingScopes.required(for: $0.kind).joined(separator: ", ") } ?? ""
    }

    /// The connected account, from either flow.
    var result: HostingAccount? {
        if let tokenAccount { return tokenAccount }
        if case .connected(let account)? = deviceFlow?.state { return account }
        return nil
    }

    func startBrowser() {
        guard let instance, method == .browser else { return }
        deviceFlow?.cancel()
        deviceFlow = connector.deviceFlow(on: instance, replacing: replacing)
        deviceFlow?.start()
    }

    func connectToken() async {
        guard let instance else { return }
        tokenState = .validating
        do {
            let connection = try await connector.connect(token: token, on: instance, replacing: replacing)
            tokenAccount = connection.account
            scopesWarning = !connection.scopesVerified
            tokenState = .idle
        } catch {
            tokenState = .failed(HostingAuthError.wrapping(error).localizedDescription)
        }
    }

    func cancel() {
        deviceFlow?.cancel()
    }

    /// "Done": applies the profile choice.
    func finish() {
        guard let result else { return }
        store.linkAccount(result.id, toProfile: profileChoice)
    }

    private func resetFlow() {
        deviceFlow?.cancel()
        deviceFlow = nil
        tokenAccount = nil
        scopesWarning = false
        tokenState = .idle
    }
}
