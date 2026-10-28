import Foundation
import Testing
@testable import gitForge

@Suite("AppState — profile chosen at clone", .serialized)
@MainActor
struct AppStateCloneProfileTests {

    @Test("The chosen profile is pinned to the opened clone; none leaves the identity as it was")
    func appliesProfile() async throws {
        let app = AppState.isolated()
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "a\n"])
        }
        defer { repo.remove() }
        try await app.openRepository(at: repo.url)

        let before = try await repo.gitAsync(["config", "--local", "user.email"], allowFailure: true)
        await app.applyCloneProfile(nil)
        #expect(try await repo.gitAsync(["config", "--local", "user.email"], allowFailure: true) == before)

        let work = GitProfile(name: "Work", userName: "Test Worker", userEmail: "worker@example.test")
        app.profiles.add(work)
        await app.applyCloneProfile(work.id)
        #expect(try await repo.gitAsync("config", "--local", "user.email").trimmingCharacters(in: .whitespacesAndNewlines)
                == "worker@example.test")
        #expect(app.ui.activeToast == nil)
    }

    @Test("A profile that can't be applied says so, and reports failure so the clone toast doesn't hide it")
    func failure() async throws {
        let app = AppState.isolated()
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "a\n"])
        }
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.url.appendingPathComponent(".git").path)
            repo.remove()
        }
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
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "a\n"])
        }
        defer { repo.remove() }
        try await app.openRepository(at: repo.url)
        #expect(!(await app.applyCloneProfile(UUID())))
        #expect(app.ui.activeToast?.kind == .warn)
    }

    @Test("A whole clone: the repo opens with the profile picked in the sheet, and the toast says Cloned")
    func runCloneEndToEnd() async throws {
        let server = try GitHTTPTestServer()
        try await server.start()
        defer { server.stop() }
        let bare = try await server.makeBareRepo("app.git")
        let seed = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["README.md": "hello\n"])
            try repo.git("push", "-q", bare.path, "main")
        }
        defer { seed.remove() }

        let app = AppState.isolated()
        let work = GitProfile(name: "Work", userName: "Test Worker", userEmail: "worker@example.test")
        app.profiles.add(work)
        let destination = TemporaryDirectories.make("gitForge-runclone").appendingPathComponent("app")
        app.startClone(url: server.url("app.git"), path: destination.path(percentEncoded: false), branch: nil,
                       profileId: work.id)
        // The clone itself, not a deadline: a real clone over HTTP took over
        // 20 s on a busy CI runner.
        await app.clone.finished()

        #expect(app.ui.presentedError == nil)
        #expect(app.ui.activeToast?.message == "Cloned app")
        #expect(app.catalog.activeRepository?.url.lastPathComponent == "app")
        let identity = await GitCLI(workingDirectory: destination).currentIdentity()
        #expect(identity.email == "worker@example.test")
        #expect(identity.isLocal)
    }
}
