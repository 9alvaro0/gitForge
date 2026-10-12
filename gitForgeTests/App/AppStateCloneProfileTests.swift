import Foundation
import Testing
@testable import gitForge

@Suite("AppState — profile chosen at clone", .serialized)
@MainActor
struct AppStateCloneProfileTests {

    @Test("The chosen profile is pinned to the opened clone; none leaves the identity as it was")
    func appliesProfile() async throws {
        let app = AppState.isolated()
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("first", files: ["a.txt": "a\n"])
        try await app.openRepository(at: repo.url)

        let before = try repo.git(["config", "--local", "user.email"], allowFailure: true)
        await app.applyCloneProfile(nil)
        #expect(try repo.git(["config", "--local", "user.email"], allowFailure: true) == before)

        let work = GitProfile(name: "Work", userName: "Test Worker", userEmail: "worker@example.test")
        app.profiles.add(work)
        await app.applyCloneProfile(work.id)
        #expect(try repo.git("config", "--local", "user.email").trimmingCharacters(in: .whitespacesAndNewlines)
                == "worker@example.test")
        #expect(app.ui.activeToast == nil)
    }

    @Test("A profile that can't be applied says so, and reports failure so the clone toast doesn't hide it")
    func failure() async throws {
        let app = AppState.isolated()
        let repo = try GitTestRepo()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url.appendingPathComponent(".git").path)
            repo.remove()
        }
        try repo.commit("first", files: ["a.txt": "a\n"])
        try await app.openRepository(at: repo.url)
        let work = GitProfile(name: "Work", userName: "Test Worker", userEmail: "worker@example.test")
        app.profiles.add(work)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: repo.url.appendingPathComponent(".git").path)

        let applied = await app.applyCloneProfile(work.id)
        #expect(!applied)
        #expect(app.ui.activeToast?.kind == .warn)
        #expect(await app.applyCloneProfile(nil))
    }

    @Test("A profile deleted meanwhile isn't skipped silently")
    func deletedProfile() async throws {
        let app = AppState.isolated()
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.commit("first", files: ["a.txt": "a\n"])
        try await app.openRepository(at: repo.url)
        #expect(!(await app.applyCloneProfile(UUID())))
        #expect(app.ui.activeToast?.kind == .warn)
    }
}
