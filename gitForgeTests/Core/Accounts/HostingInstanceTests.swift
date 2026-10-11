import Foundation
import Testing
@testable import gitForge

@Suite("HostingInstance")
struct HostingInstanceTests {

    @Test("Hosts normalise to lowercase, no scheme, port, path or www",
          arguments: [
            ("https://GitLab.Empresa.com/", "gitlab.empresa.com"),
            ("gitlab.empresa.com:443", "gitlab.empresa.com"),
            ("http://git.example.org/some/path", "git.example.org"),
            ("www.github.com", "github.com"),
            ("  GitHub.com ", "github.com"),
          ])
    func normalise(input: String, expected: String) {
        #expect(HostingInstance.normalizedHost(input) == expected)
    }

    @Test("Empty or hostless input is rejected", arguments: ["", "   ", "https://", "/just/a/path"])
    func rejects(input: String) {
        #expect(HostingInstance.normalizedHost(input) == nil)
    }

    @Test("Default API base: github.com, Enterprise and GitLab")
    func apiBase() {
        #expect(HostingInstance.defaultAPIBaseURL(kind: .github, host: "github.com").absoluteString == "https://api.github.com")
        #expect(HostingInstance.defaultAPIBaseURL(kind: .github, host: "git.empresa.com").absoluteString == "https://git.empresa.com/api/v3")
        #expect(HostingInstance.defaultAPIBaseURL(kind: .gitlab, host: "gitlab.com").absoluteString == "https://gitlab.com/api/v4")
    }

    @Test("Built-ins are fixed, built-in and use the default API base")
    func builtIns() {
        #expect(HostingInstance.gitHubDotCom.host == "github.com")
        #expect(HostingInstance.gitHubDotCom.isBuiltIn)
        #expect(HostingInstance.gitLabDotCom.apiBaseURL.absoluteString == "https://gitlab.com/api/v4")
        #expect(HostingInstance.gitHubDotCom.id != HostingInstance.gitLabDotCom.id)
    }

    @Test("The initialiser normalises the host and fills the API base")
    func initNormalises() {
        let instance = HostingInstance(kind: .gitlab, host: "https://Git.Empresa.com/")
        #expect(instance.host == "git.empresa.com")
        #expect(instance.apiBaseURL.absoluteString == "https://git.empresa.com/api/v4")
        #expect(!instance.isBuiltIn)
    }
}
