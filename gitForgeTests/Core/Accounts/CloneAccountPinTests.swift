import Foundation
import Testing
@testable import gitForge

@Suite("Clone › the browsed account signs the clone", .serialized)
@MainActor
struct CloneAccountPinTests {
    static let url = "https://github.com/acme/app.git"

    private func setup() throws -> (AccountStore, AccountGitCredentials, HostingAccount, HostingAccount) {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-pin-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets)
        let octo = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        let work = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "work", method: .oauth, status: .ok)
        try store.addAccount(octo, secret: AccountSecret(accessToken: "test-a"))
        try store.addAccount(work, secret: AccountSecret(accessToken: "test-b"))
        return (store, AccountGitCredentials(store: store, refresher: TokenRefresher(secrets: secrets),
                                              chooseAccount: { _ in nil }), octo, work)
    }

    @Test("Pinned: the destination resolves to the chosen one of two accounts; undo forgets it")
    func pinAndUndo() async throws {
        let (store, credentials, _, work) = try setup()
        let destination = URL(fileURLWithPath: "/tmp/gitforge-pin-\(UUID().uuidString)/app")
        let path = destination.path(percentEncoded: false)
        #expect(await credentials.signer(remoteURL: Self.url, remoteName: "origin", repoPath: path) == .needsChoice)

        let pin = try #require(CloneAccountPin.pin(work.id, destination: destination, in: store))
        #expect(await credentials.signer(remoteURL: Self.url, remoteName: "origin", repoPath: path) == .account(work.id))

        pin.undo()
        #expect(store.choice(repoPath: path, remoteName: "origin") == nil)
        #expect(CloneAccountPin.pin(nil, destination: destination, in: store) == nil)
    }

    @Test("Opened under another path: the choice follows the repo")
    func move() async throws {
        let (store, credentials, octo, _) = try setup()
        let destination = URL(fileURLWithPath: "/tmp/gitforge-pin-\(UUID().uuidString)/app")
        var pin = try #require(CloneAccountPin.pin(octo.id, destination: destination, in: store))
        let opened = "/private" + destination.path(percentEncoded: false)
        pin.move(to: opened)
        #expect(store.choice(repoPath: destination.path(percentEncoded: false), remoteName: "origin") == nil)
        #expect(await credentials.signer(remoteURL: Self.url, remoteName: "origin", repoPath: opened) == .account(octo.id))
        #expect(pin.repoPath == opened)
    }

    @Test("After cloning, the choice follows the clone's own git root, not whichever repo is active")
    func followsRoot() async throws {
        let (store, _, octo, _) = try setup()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-pin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        var pin = try #require(CloneAccountPin.pin(octo.id, destination: destination, in: store))
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await GitCLI(workingDirectory: destination).run(["init", "-q"])
        let root = try #require(await GitCLI.resolveRepositoryRoot(at: destination)).path(percentEncoded: false)

        await pin.followRepositoryRoot()
        #expect(pin.repoPath == root)
        #expect(store.choice(repoPath: root, remoteName: "origin") == .account(octo.id))
        if root != destination.path(percentEncoded: false) {
            #expect(store.choice(repoPath: destination.path(percentEncoded: false), remoteName: "origin") == nil)
        }
    }
}
