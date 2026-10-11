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
}
