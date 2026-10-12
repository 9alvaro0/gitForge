import Foundation
import Testing
@testable import gitForge

@Suite("HostingInstance — typed input")
struct HostingInstanceInputTests {
    @Test("Valid addresses: normalised host and default API base",
          arguments: [("https://GitLab.Empresa.com/", "gitlab.empresa.com"),
                      ("git.empresa.com.", "git.empresa.com"),
                      ("  http://git.empresa.com/group  ", "git.empresa.com")])
    func valid(input: String, host: String) throws {
        let instance = try HostingInstance.make(kind: .gitlab, url: input).get()
        #expect(instance.host == host)
        #expect(instance.apiBaseURL.absoluteString == "https://\(host)/api/v4")
    }

    @Test("Empty or malformed addresses are refused with a reason")
    func invalid() {
        #expect(HostingInstance.make(kind: .gitlab, url: "   ") == .failure(.missingHost))
        #expect(HostingInstance.make(kind: .gitlab, url: "git empresa.com") == .failure(.invalidHost("git empresa.com")))
        #expect(HostingInstance.make(kind: .gitlab, url: "git_empresa.com") == .failure(.invalidHost("git_empresa.com")))
        #expect(HostingInstance.make(kind: .github, url: "https://") == .failure(.invalidHost("https://")))
    }

    @Test("An API URL override must be HTTPS")
    func apiOverride() throws {
        let instance = try HostingInstance.make(kind: .gitlab, url: "git.empresa.com",
                                                apiBaseURL: "https://git.empresa.com:8443/api/v4").get()
        #expect(instance.apiBaseURL.absoluteString == "https://git.empresa.com:8443/api/v4")
        #expect(HostingInstance.make(kind: .gitlab, url: "git.empresa.com", apiBaseURL: "http://git.empresa.com/api/v4")
                == .failure(.invalidAPIURL("http://git.empresa.com/api/v4")))
        #expect(HostingInstance.make(kind: .gitlab, url: "git.empresa.com", apiBaseURL: "nonsense")
                == .failure(.invalidAPIURL("nonsense")))
    }

    @Test("A bad host never crashes the default API base")
    func noCrash() {
        _ = HostingInstance.defaultAPIBaseURL(kind: .gitlab, host: "bad host")
        _ = HostingInstance.defaultAPIBaseURL(kind: .github, host: "")
    }
}
