import Foundation
import Testing
@testable import gitForge

@Suite("LogSanitizer")
struct LogSanitizerTests {
    private let home = "/Users/alice"

    private func clean(_ text: String) -> String {
        LogSanitizer.sanitize(text, homeDirectory: home)
    }

    @Test("URL userinfo is blanked, as in GitCLI.redacted")
    func urlUserinfo() {
        let out = clean("fatal: unable to access 'https://oauth2:s3cr3tvalue@gitlab.com/a/b.git/'")
        #expect(out == "fatal: unable to access 'https://****@gitlab.com/a/b.git/'")
    }

    @Test("A token registered with SecretRedactor is blanked anywhere in the text")
    func registeredToken() {
        SecretRedactor.shared.register("test-log-sanitizer-token-1")
        #expect(clean("remote echoed test-log-sanitizer-token-1 back") == "remote echoed **** back")
    }

    @Test("Well-known token shapes are blanked even if never registered",
          arguments: [
              "ghp_" + String(repeating: "a", count: 36),
              "gho_" + String(repeating: "B", count: 36),
              "github_pat_11ABCDEFG0" + String(repeating: "x", count: 40),
              "glpat-" + String(repeating: "Z", count: 20),
          ])
    func tokenShapes(token: String) {
        let out = clean("hook said: \(token) done")
        #expect(!out.contains(token))
        #expect(out == "hook said: **** done")
    }

    @Test("Authorization headers and Bearer values keep their label, lose their value")
    func authHeaders() {
        #expect(clean("> Authorization: Basic dXNlcjpwYXNz") == "> Authorization: ****")
        #expect(clean("Proxy-Authorization: Bearer abcdef123456") == "Proxy-Authorization: ****")
        #expect(clean("sent bearer abcdefghijkl to api") == "sent bearer **** to api")
    }

    @Test("password= and token: pairs are blanked")
    func keyValuePairs() {
        #expect(clean("url?private_token=abc123&x=1") == "url?private_token=****&x=1")
        #expect(clean("password: hunter22") == "password: ****")
        #expect(clean("token=deadbeef") == "token=****")
    }

    @Test("The home folder becomes ~, but not a longer sibling path")
    func homeFolder() {
        #expect(clean("/Users/alice/src/app: not a git repository") == "~/src/app: not a git repository")
        #expect(clean("cwd '/Users/alice'") == "cwd '~'")
        #expect(clean("/Users/alice2/src") == "/Users/alice2/src")
    }

    @Test("ANSI colours and other control characters are dropped; newlines and tabs stay")
    func controlCharacters() {
        #expect(clean("\u{1B}[31merror:\u{1B}[0m bad\u{07}\n\tfile.txt") == "error: bad\n\tfile.txt")
    }

    @Test("Ordinary git output is left alone")
    func passthrough() {
        let text = "error: pathspec 'feature/token-refresh' did not match any file(s) known to git"
        #expect(clean(text) == text)
        #expect(clean("git@github.com:org/repo.git") == "git@github.com:org/repo.git")
    }
}
