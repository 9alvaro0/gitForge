import Foundation
import Testing
@testable import gitForge

@Suite("ExternalURL")
struct ExternalURLTests {

    @Test("Only web and mail links are considered safe")
    func safeSchemes() {
        for url in ["https://github.com/x", "http://example.com", "mailto:a@b.c", "HTTPS://GITHUB.COM"] {
            #expect(ExternalURL.isSafeWebURL(URL(string: url)!), "\(url)")
        }
        for url in ["file:///Applications/Calculator.app", "x-apple.systempreferences:com.apple.preference",
                    "javascript:alert(1)", "ssh://host", "vscode://open?x"] {
            #expect(!ExternalURL.isSafeWebURL(URL(string: url)!), "\(url)")
        }
    }

    @Test("Bundles and launchable files are revealed instead of opened")
    func launchable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Evil.app/Contents"), withIntermediateDirectories: true)
        try Data("echo hi".utf8).write(to: dir.appendingPathComponent("run.command"))
        try Data("text".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(ExternalURL.isLaunchable(dir.appendingPathComponent("Evil.app")))
        #expect(ExternalURL.isLaunchable(dir.appendingPathComponent("run.command")))
        #expect(!ExternalURL.isLaunchable(dir.appendingPathComponent("notes.txt")))
    }
}
