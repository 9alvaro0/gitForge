import Foundation
import Testing
@testable import gitForge

@Suite("OAuth client ids", .serialized)
@MainActor
struct OAuthClientIDsTests {

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-clientids-\(UUID().uuidString)")
    }

    @Test("Info.plist values: set, empty, unexpanded or missing")
    func parse() {
        #expect(OAuthClientIDs.from(["GFGitHubOAuthClientID": "Ov23abc", "GFGitLabOAuthClientID": " gl123 "])
                == OAuthClientIDs(gitHub: "Ov23abc", gitLab: "gl123"))
        #expect(OAuthClientIDs.from(["GFGitHubOAuthClientID": "", "GFGitLabOAuthClientID": "$(GITLAB_CLIENT_ID)"]) == .none)
        #expect(OAuthClientIDs.from(nil) == .none)
    }

    @Test("Built-ins take the bundled ids; they aren't persisted, so a new build's ids win")
    func builtIns() throws {
        let dir = Self.tempDir()
        let store = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(),
                                 clientIds: OAuthClientIDs(gitHub: "gh-1", gitLab: nil))
        #expect(store.instance(forHost: "github.com")?.oauthClientId == "gh-1")
        #expect(store.instance(forHost: "gitlab.com")?.oauthClientId == nil)
        try store.addInstance(HostingInstance(kind: .gitlab, host: "git.empresa.com", oauthClientId: "own"))

        let reloaded = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(),
                                    clientIds: OAuthClientIDs(gitHub: "gh-2", gitLab: "gl-2"))
        #expect(reloaded.instance(forHost: "github.com")?.oauthClientId == "gh-2")
        #expect(reloaded.instance(forHost: "gitlab.com")?.oauthClientId == "gl-2")
        #expect(reloaded.instance(forHost: "git.empresa.com")?.oauthClientId == "own")
    }
}
