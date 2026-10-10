import Foundation
import Testing
@testable import gitForge

@Suite("Account secrets", .serialized)
@MainActor
struct AccountSecretStoreTests {

    @Test("Status survives a JSON round-trip, including needsAttention reasons")
    func statusCodable() throws {
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "me", method: .oauth,
                                     status: .needsAttention(.revoked))
        let data = try JSONEncoder().encode(account)
        let back = try JSONDecoder().decode(HostingAccount.self, from: data)
        #expect(back == account)
    }

    @Test("In-memory store reads what it wrote, deletes, and can be made to fail")
    func inMemory() throws {
        let store = InMemoryAccountSecretStore()
        let id = UUID()
        try store.write(AccountSecret(accessToken: "t"), for: id)
        #expect(store.read(id)?.accessToken == "t")
        store.delete(id)
        #expect(store.read(id) == nil)
        store.failWrites = true
        #expect(throws: (any Error).self) { try store.write(AccountSecret(accessToken: "x"), for: id) }
    }

    @Test("Keychain store round-trips a secret with refresh token and expiry")
    func keychainRoundTrip() throws {
        let store = KeychainAccountSecretStore(service: "com.warwarelabs.gitForge.account.tests")
        let id = UUID()
        defer { store.delete(id) }
        let secret = AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.write(secret, for: id)
        #expect(store.read(id) == secret)
        try store.write(AccountSecret(accessToken: "b"), for: id)
        #expect(store.read(id)?.accessToken == "b")
    }
}
