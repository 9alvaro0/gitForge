import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — identity values that look like options")
struct GitCLIIdentityDashTests {
    @Test("Values starting with '-' are stored as values (git stops reading options after the key)")
    func dashValues() async throws {
        let repo = try await GitTestRepo.make()
        defer { repo.remove() }
        try await repo.cli.setLocalIdentity(name: "--global", email: "-e", signingKey: "--unset")
        #expect(try await repo.gitAsync("config", "--local", "--get", "user.name").trimmingCharacters(in: .newlines) == "--global")
        #expect(try await repo.gitAsync("config", "--local", "--get", "user.email").trimmingCharacters(in: .newlines) == "-e")
        #expect(try await repo.gitAsync("config", "--local", "--get", "user.signingkey").trimmingCharacters(in: .newlines) == "--unset")
    }
}
