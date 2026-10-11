import Foundation
import Observation

/// A token account just saved. `scopesVerified == false`: the server
/// doesn't report scopes (GitHub fine-grained token); the UI warns.
nonisolated struct TokenConnection: Equatable, Sendable {
    let account: HostingAccount
    let scopesVerified: Bool
}

/// Connecting accounts, without UI (phase 4 builds the wizard on this):
/// a validated personal token (spec §5.2) or OAuth device flow (§5.1).
@MainActor
final class AccountConnector {
    private let store: AccountStore
    private let makeClient: @Sendable (HostingInstance) -> any HostingAuthClient
    private let clock: DeviceFlowClock

    init(store: AccountStore,
         makeClient: @escaping @Sendable (HostingInstance) -> any HostingAuthClient = { HostingAuthClients.make(for: $0) },
         clock: DeviceFlowClock = .live) {
        self.store = store
        self.makeClient = makeClient
        self.clock = clock
    }

    /// OAuth needs a client id; without one the instance offers only tokens.
    func supportsOAuth(_ instance: HostingInstance) -> Bool {
        !(instance.oauthClientId ?? "").isEmpty
    }

    /// A device flow ready to `start()`, or `nil` without a client id.
    func deviceFlow(on instance: HostingInstance) -> DeviceFlowSession? {
        guard let clientId = instance.oauthClientId, !clientId.isEmpty else { return nil }
        return DeviceFlowSession(instance: instance, clientId: clientId, client: makeClient(instance),
                                 store: store, clock: clock)
    }

    /// Validates `token` and saves it as a token account (or updates the
    /// account with the same login). Missing scopes throw `missingScopes`
    /// with the list, and nothing is saved.
    func connect(token: String, on instance: HostingInstance) async throws -> TokenConnection {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HostingAuthError.unauthorized }
        do {
            let validation = try await makeClient(instance).validate(token: trimmed, method: .personalToken)
            let account = try store.connectAccount(instanceId: instance.id, method: .personalToken, validation: validation,
                                                   secret: AccountSecret(accessToken: trimmed), now: clock.now())
            return TokenConnection(account: account, scopesVerified: validation.scopes != nil)
        } catch {
            throw HostingAuthError.wrapping(error)
        }
    }
}

/// One OAuth device-flow attempt, observable by the wizard: show
/// `userCode`, open `verificationURI`, count down to `expiresAt`, cancel.
/// The owner cancels it when the wizard closes.
@MainActor
@Observable
final class DeviceFlowSession {
    enum State: Equatable {
        case idle
        case requestingCode
        /// Waiting for the user to approve `code` in the browser.
        case waitingForUser(DeviceCode, expiresAt: Date)
        /// Approved: checking the user and saving the account.
        case finishing
        case connected(HostingAccount)
        case failed(HostingAuthError)
        case cancelled
    }

    let instance: HostingInstance
    private(set) var state: State = .idle

    @ObservationIgnored private let clientId: String
    @ObservationIgnored private let client: any HostingAuthClient
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let clock: DeviceFlowClock
    @ObservationIgnored private var task: Task<Void, Never>?

    init(instance: HostingInstance, clientId: String, client: any HostingAuthClient,
         store: AccountStore, clock: DeviceFlowClock) {
        self.instance = instance
        self.clientId = clientId
        self.client = client
        self.store = store
        self.clock = clock
    }

    var isRunning: Bool { task != nil }

    /// Starts the flow, or starts it again after a failure or cancel.
    func start() {
        guard task == nil else { return }
        state = .requestingCode
        task = Task { await run() }
    }

    /// Stops waiting at once; nothing is saved.
    func cancel() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        state = .cancelled
    }

    private func run() async {
        do {
            let code = try await client.requestDeviceCode(clientId: clientId)
            try Task.checkCancellation()
            state = .waitingForUser(code, expiresAt: clock.now().addingTimeInterval(TimeInterval(code.expiresIn)))
            let grant = try await client.pollToken(clientId: clientId, code: code, clock: clock)
            try Task.checkCancellation()
            state = .finishing
            let validation = try await client.validate(token: grant.accessToken, method: .oauth)
            try Task.checkCancellation()
            // GitLab doesn't report an OAuth token's scopes on /user: check
            // what the grant says.
            if validation.scopes == nil, let granted = grant.scopes {
                let missing = HostingScopes.missing(granted, kind: instance.kind)
                guard missing.isEmpty else { throw HostingAuthError.missingScopes(missing) }
            }
            let now = clock.now()
            let account = try store.connectAccount(instanceId: instance.id, method: .oauth, validation: validation,
                                                   grantedScopes: grant.scopes, secret: grant.secret(now: now), now: now)
            state = .connected(account)
        } catch {
            // `cancel()` already set the state and released the task.
            guard !Task.isCancelled else { return }
            state = .failed(HostingAuthError.wrapping(error))
        }
        task = nil
    }
}
