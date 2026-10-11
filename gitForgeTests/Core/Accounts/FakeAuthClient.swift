import Foundation
@testable import gitForge

/// Scripted `HostingAuthClient` for the refresher, validator and connector.
final class FakeAuthClient: HostingAuthClient, @unchecked Sendable {
    let instance: HostingInstance
    private let lock = NSLock()
    private var refreshTokens: [String] = []
    private var tokens: [String] = []
    private let onRefresh: @Sendable (String) async throws -> TokenGrant
    private let onValidate: @Sendable (String) async throws -> TokenValidation

    init(instance: HostingInstance = .gitLabDotCom,
         refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
         validate: @escaping @Sendable (String) async throws -> TokenValidation = { _ in throw HostingAuthError.unauthorized }) {
        self.instance = instance
        self.onRefresh = refresh
        self.onValidate = validate
    }

    /// Refresh tokens sent, in order.
    var refreshCalls: [String] { lock.withLock { refreshTokens } }
    /// Access tokens validated, in order.
    var validatedTokens: [String] { lock.withLock { tokens } }

    func requestDeviceCode(clientId: String) async throws -> DeviceCode { throw HostingAuthError.deviceFlowUnsupported }

    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome {
        throw HostingAuthError.deviceFlowUnsupported
    }

    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant {
        lock.withLock { refreshTokens.append(refreshToken) }
        return try await onRefresh(refreshToken)
    }

    func fetchUser(token: String) async throws -> HostingUser {
        try await validate(token: token, method: .oauth).user
    }

    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation {
        lock.withLock { tokens.append(token) }
        return try await onValidate(token)
    }
}

/// Values collected from concurrent callbacks.
final class LockedList<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.withLock { items.append(item) } }
    var values: [T] { lock.withLock { items } }
}
