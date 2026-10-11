import Foundation
import Testing
@testable import gitForge

@Suite("AddInstanceModel", .serialized)
@MainActor
struct AddInstanceModelTests {
    private func makeStore() -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-addinstance-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(), clientIds: .none)
    }

    private func model(_ server: StubServer, _ store: AccountStore, kind: HostingInstance.Kind) -> AddInstanceModel {
        let model = AddInstanceModel(store: store, verifier: InstanceVerifier(http: server.http))
        model.kind = kind
        model.url = "https://\(server.host)/"
        return model
    }

    @Test("A verified GitHub Enterprise is added")
    func addsVerified() async {
        let server = StubServer(), store = makeStore()
        server.on("GET", "/api/v3/meta", fixture: "github-meta")
        let model = model(server, store, kind: .github)
        await model.add()
        guard case .added(let instance, let warning) = model.state else { Issue.record("\(model.state)"); return }
        #expect(warning == nil)
        #expect(store.instance(forHost: server.host)?.id == instance.id)
    }

    @Test("Old GitLab is added with the tokens-only warning; a 401 is added to check later")
    func addsWithWarnings() async {
        let old = StubServer(), store = makeStore()
        old.on("GET", "/api/v4/version", fixture: "gitlab-version-old")
        let oldModel = model(old, store, kind: .gitlab)
        await oldModel.add()
        guard case .added(_, let warning?) = oldModel.state else { Issue.record("\(oldModel.state)"); return }
        #expect(warning.contains("17.2"))

        let locked = StubServer()
        locked.on("GET", "/api/v4/version", status: 401, body: Data())
        let lockedModel = model(locked, store, kind: .gitlab)
        await lockedModel.add()
        guard case .added(_, let lockedWarning?) = lockedModel.state else { Issue.record("\(lockedModel.state)"); return }
        #expect(lockedWarning.contains("first account"))
    }

    @Test("Unreachable or no API: not saved, with the reason")
    func unreachable() async {
        let server = StubServer(), store = makeStore()
        server.on("GET", "/api/v4/version", status: 404, body: Data())
        let model = model(server, store, kind: .gitlab)
        await model.add()
        guard case .failed(let message) = model.state else { Issue.record("\(model.state)"); return }
        #expect(message.contains("404"))
        #expect(store.instance(forHost: server.host) == nil)
    }

    @Test("A private certificate asks to trust it, without saving")
    func needsTrust() async {
        let server = StubServer(), store = makeStore()
        server.fail("GET", "/api/v4/version", with: .serverCertificateHasUnknownRoot)
        let model = model(server, store, kind: .gitlab)
        await model.add()
        #expect(model.state == .needsTrust(host: server.host))
        #expect(store.instance(forHost: server.host) == nil)
    }

    @Test("Bad input and duplicates are refused before any request")
    func refusals() async {
        let server = StubServer(), store = makeStore()
        let bad = AddInstanceModel(store: store, verifier: InstanceVerifier(http: server.http))
        bad.url = "   "
        await bad.add()
        #expect(bad.state == .failed(InstanceInputError.missingHost.localizedDescription))
        let duplicate = AddInstanceModel(store: store, verifier: InstanceVerifier(http: server.http))
        duplicate.kind = .gitlab
        duplicate.url = "gitlab.com"
        await duplicate.add()
        #expect(duplicate.state == .failed("gitlab.com is already in the list."))
        #expect(server.requests.isEmpty)
    }
}
