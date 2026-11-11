import Foundation
import Testing
@testable import gitForge

/// Requests and answers of the host avatar lookup (#65), against `StubServer`:
/// nothing leaves the process.
@Suite("HostAvatarLookup")
struct HostAvatarLookupTests {
    let server = StubServer()

    private var github: RemoteHost {
        RemoteHost(provider: .github, host: server.host, owner: "octo", repo: "app",
                   apiBaseURL: URL(string: "https://\(server.host)/api/v3"))
    }

    private var gitlab: RemoteHost {
        RemoteHost(provider: .gitlab, host: server.host, owner: "group/sub", repo: "app",
                   apiBaseURL: URL(string: "https://\(server.host)/api/v4"))
    }

    private var lookup: HostAvatarLookup { HostAvatarLookup(http: server.http) }

    private static func json(_ text: String) -> Data { Data(text.utf8) }

    // MARK: GitHub

    @Test("GitHub: one commit from the list endpoint, with the account's token")
    func gitHubRequest() async throws {
        server.on("GET", "/api/v3/repos/octo/app/commits", body: Self.json("""
        [{ "sha": "abc123def", "author": { "login": "ana", "avatar_url": "https://\(server.host)/avatars/u/7?v=4" } }]
        """))
        let result = try await lookup.avatar(email: "ana@forge.dev", sha: "abc123def", host: github, token: "test-token")
        let request = try #require(server.requests("GET", "/api/v3/repos/octo/app/commits").first)
        #expect(request.query["sha"] == "abc123def")
        #expect(request.query["per_page"] == "1")
        #expect(request.header("Authorization") == "Bearer test-token")
        #expect(request.header("Accept") == "application/vnd.github+json")
        // The email itself never goes to GitHub: the commit names the account.
        #expect(!request.rawURL.contains("forge.dev"))
        guard case .found(let url) = result else {
            Issue.record("expected an avatar, got \(result)")
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == server.host && url.path == "/avatars/u/7")
        #expect(items.contains(URLQueryItem(name: "s", value: "64")))
        #expect(items.contains(URLQueryItem(name: "v", value: "4")))
    }

    @Test("GitHub: a commit whose email isn't linked to an account has no avatar")
    func gitHubNoAccount() async throws {
        server.on("GET", "/api/v3/repos/octo/app/commits", body: Self.json(#"[{ "sha": "abc123", "author": null }]"#))
        #expect(try await lookup.avatar(email: "x@forge.dev", sha: "abc123", host: github, token: "t") == .none)
    }

    @Test("GitHub: a commit the host doesn't have is unknown, so another can be tried", arguments: [404, 422, 409])
    func gitHubUnknownCommit(status: Int) async throws {
        server.on("GET", "/api/v3/repos/octo/app/commits", status: status, body: Self.json(#"{"message":"No commit found"}"#))
        #expect(try await lookup.avatar(email: "x@forge.dev", sha: "abc123", host: github, token: "t") == .unknownCommit)
    }

    @Test("GitHub: an answer for another commit is unknown, not someone else's avatar")
    func gitHubOtherCommit() throws {
        let data = Self.json(#"[{ "sha": "fff000", "author": { "avatar_url": "https://github.com/a.png" } }]"#)
        #expect(try HostAvatarLookup.parse(data, status: 200, sha: "abc123", host: github) == .unknownCommit)
        #expect(try HostAvatarLookup.parse(Self.json("[]"), status: 200, sha: "abc123", host: github) == .unknownCommit)
    }

    @Test("GitHub: a Gravatar or third-party avatar URL is refused")
    func gitHubGravatar() throws {
        for raw in ["https://secure.gravatar.com/avatar/0bc83cb571cd1c50ba6f3e8a78ef1346",
                    "https://cdn.example.net/u/7.png",
                    "http://\(server.host)/avatars/u/7"] {
            let data = Self.json(#"[{ "sha": "abc123", "author": { "avatar_url": "\#(raw)" } }]"#)
            #expect(try HostAvatarLookup.parse(data, status: 200, sha: "abc123", host: github) == .none, "\(raw)")
        }
    }

    @Test("GitHub.com: a noreply address with an id needs no request")
    func noreply() async throws {
        let dotCom = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")
        let url = HostAvatarLookup.gitHubNoreplyAvatar(email: "12345+ana@users.noreply.github.com", host: dotCom)
        #expect(url?.absoluteString == "https://avatars.githubusercontent.com/u/12345?s=64")
        #expect(HostAvatarLookup.gitHubNoreplyAvatar(email: "ana@users.noreply.github.com", host: dotCom) == nil)
        #expect(HostAvatarLookup.gitHubNoreplyAvatar(email: "12a+ana@users.noreply.github.com", host: dotCom) == nil)
        // Only on github.com: an Enterprise server has its own ids.
        #expect(HostAvatarLookup.gitHubNoreplyAvatar(email: "12345+ana@users.noreply.github.com", host: github) == nil)

        let viaLookup = try await lookup.avatar(email: "12345+ana@users.noreply.github.com", sha: "abc", host: dotCom, token: "t")
        #expect(viaLookup == .found(try #require(url)))
        #expect(server.requests.isEmpty)
    }

    // MARK: GitLab

    @Test("GitLab: the email's avatar, encoded so a '+' survives, at the size drawn")
    func gitLabRequest() async throws {
        server.on("GET", "/api/v4/avatar", body: Self.json("""
        { "avatar_url": "https://\(server.host)/uploads/-/system/user/avatar/9/avatar.png" }
        """))
        let result = try await lookup.avatar(email: "ana+git@forge.dev", sha: "abc", host: gitlab, token: "test-token")
        let request = try #require(server.requests("GET", "/api/v4/avatar").first)
        #expect(request.query["email"] == "ana+git@forge.dev")
        #expect(request.rawURL.contains("email=ana%2Bgit@forge.dev"))
        #expect(request.query["size"] == "64")
        #expect(request.header("Authorization") == "Bearer test-token")
        #expect(result == .found(URL(string: "https://\(server.host)/uploads/-/system/user/avatar/9/avatar.png")!))
    }

    @Test("GitLab: Gravatar fallbacks and the default placeholder read as no avatar")
    func gitLabFallbacks() throws {
        let gravatar = Self.json(#"{ "avatar_url": "https://www.gravatar.com/avatar/abc?s=64&d=identicon" }"#)
        #expect(try HostAvatarLookup.parse(gravatar, status: 200, sha: "", host: gitlab) == .none)
        let placeholder = Self.json(#"{ "avatar_url": "https://\#(server.host)/assets/no_avatar-849f9c04a3a0d0cea2424ae97b27447dc64a7dbfae83c036c45b403392f0e8ba.png" }"#)
        #expect(try HostAvatarLookup.parse(placeholder, status: 200, sha: "", host: gitlab) == .none)
        #expect(try HostAvatarLookup.parse(Self.json(#"{ "avatar_url": null }"#), status: 200, sha: "", host: gitlab) == .none)
    }

    @Test("GitLab: a relative avatar path is on the instance")
    func gitLabRelative() throws {
        let data = Self.json(#"{ "avatar_url": "/uploads/-/system/user/avatar/9/a.png" }"#)
        let result = try HostAvatarLookup.parse(data, status: 200, sha: "", host: gitlab)
        #expect(result == .found(URL(string: "https://\(server.host)/uploads/-/system/user/avatar/9/a.png")!))
    }

    // MARK: Errors

    @Test("A rejected token, a rate limit and a server error are told apart")
    func errors() {
        #expect(throws: AvatarLookupError.unauthorized) { try HostAvatarLookup.parse(Data(), status: 401, sha: "a", host: github) }
        #expect(throws: AvatarLookupError.throttled) { try HostAvatarLookup.parse(Data(), status: 403, sha: "a", host: github) }
        #expect(throws: AvatarLookupError.throttled) { try HostAvatarLookup.parse(Data(), status: 429, sha: "a", host: gitlab) }
        #expect(throws: AvatarLookupError.failed) { try HostAvatarLookup.parse(Data(), status: 502, sha: "a", host: github) }
        #expect(throws: AvatarLookupError.failed) { try HostAvatarLookup.parse(Self.json("{"), status: 200, sha: "a", host: github) }
    }

    @Test("A transport failure is a failed lookup")
    func transport() async {
        server.fail("GET", "/api/v3/repos/octo/app/commits", with: .notConnectedToInternet)
        await #expect(throws: AvatarLookupError.failed) {
            _ = try await lookup.avatar(email: "a@b.c", sha: "abc", host: github, token: "t")
        }
    }

    // MARK: Policy

    @Test("Allowed avatar hosts: the instance, its subdomains, its API host and GitHub's CDN")
    func policy() {
        let dotCom = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        #expect(HostAvatarLookup.isAllowed(URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!, for: dotCom))
        #expect(!HostAvatarLookup.isAllowed(URL(string: "https://www.gravatar.com/avatar/x")!, for: dotCom))
        #expect(!HostAvatarLookup.isAllowed(URL(string: "https://avatars.githubusercontent.com.evil.test/u/1")!, for: dotCom))

        let enterprise = RemoteHost(provider: .github, host: "ghe.corp.test", owner: "o", repo: "r",
                                    apiBaseURL: URL(string: "https://api.ghe-corp.test/api/v3"))
        #expect(HostAvatarLookup.isAllowed(URL(string: "https://avatars.ghe.corp.test/u/3")!, for: enterprise))
        #expect(HostAvatarLookup.isAllowed(URL(string: "https://ghe.corp.test/avatars/u/3")!, for: enterprise))
        #expect(HostAvatarLookup.isAllowed(URL(string: "https://api.ghe-corp.test/avatars/u/3")!, for: enterprise))
        #expect(!HostAvatarLookup.isAllowed(URL(string: "https://avatars.githubusercontent.com/u/3")!, for: enterprise))
        #expect(!HostAvatarLookup.isAllowed(URL(string: "https://notghe.corp.test/u/3")!, for: enterprise))
        #expect(!HostAvatarLookup.isAllowed(URL(string: "http://ghe.corp.test/avatars/u/3")!, for: enterprise))

        let lab = RemoteHost(provider: .gitlab, host: "gitlab.lab.test", owner: "g", repo: "r",
                             apiBaseURL: URL(string: "http://gitlab.lab.test/api/v4"))
        #expect(HostAvatarLookup.isAllowed(URL(string: "http://gitlab.lab.test/uploads/a.png")!, for: lab))
    }

    @Test("A downloaded avatar must be a modest image that ended on an allowed host")
    func imageAcceptance() throws {
        let url = URL(string: "https://\(server.host)/avatars/u/7")!
        func response(_ status: Int = 200, type: String? = "image/png", at final: URL? = nil) -> HTTPURLResponse {
            HTTPURLResponse(url: final ?? url, statusCode: status, httpVersion: nil,
                            headerFields: type.map { ["Content-Type": $0] } ?? [:])!
        }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(HostAvatarLookup.acceptImage(png, response: response(), host: github) == png)
        #expect(HostAvatarLookup.acceptImage(png, response: response(404), host: github) == nil)
        #expect(HostAvatarLookup.acceptImage(png, response: response(type: "text/html"), host: github) == nil)
        #expect(HostAvatarLookup.acceptImage(png, response: response(type: nil), host: github) == nil)
        #expect(HostAvatarLookup.acceptImage(Data(), response: response(), host: github) == nil)
        let huge = Data(count: HostAvatarLookup.maxImageBytes + 1)
        #expect(HostAvatarLookup.acceptImage(huge, response: response(), host: github) == nil)
        let redirected = response(at: URL(string: "https://secure.gravatar.com/avatar/abc")!)
        #expect(HostAvatarLookup.acceptImage(png, response: redirected, host: github) == nil)
    }

    @Test("An avatar download only follows redirects to the host's own avatar hosts")
    func redirectGuard() {
        let dotCom = RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "r")
        let original = URLRequest(url: URL(string: "https://avatars.githubusercontent.com/u/1?s=64")!)
        func follows(_ target: String) -> Bool {
            AvatarRedirectGuard.redirect(URLRequest(url: URL(string: target)!), from: original, host: dotCom) != nil
        }
        #expect(follows("https://avatars.githubusercontent.com/u/1?s=64&v=4"))
        #expect(follows("https://github.com/identicons/x.png"))
        #expect(!follows("https://secure.gravatar.com/avatar/0bc83cb571cd1c50ba6f3e8a78ef1346"))
        #expect(!follows("https://cdn.example.net/a.png"))
        #expect(!follows("http://avatars.githubusercontent.com/u/1"))
    }

    @Test("The picture is downloaded without the token")
    func imageDownload() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        server.on("GET", "/avatars/u/7", headers: ["Content-Type": "image/png"], body: png)
        let data = await lookup.image(at: URL(string: "https://\(server.host)/avatars/u/7?s=64")!, host: github)
        #expect(data == png)
        let request = try #require(server.requests("GET", "/avatars/u/7").first)
        #expect(request.header("Authorization") == nil)
    }
}
