import Foundation
import Testing
@testable import gitForge

@Suite("ActiveProfileLookup")
@MainActor
struct ActiveProfileLookupTests {
    private let defaults = TestDefaults(prefix: "gitForge-profile-lookup")
    private let personal = GitProfile(name: "Personal", userName: "Test User", userEmail: "personal@example.test")
    private let work = GitProfile(name: "Work", userName: "Test User", userEmail: "work@example.test")

    private func lookup(seen: LockedList<String> = LockedList()) -> ActiveProfileLookup {
        let store = ProfileStore(defaults: defaults.defaults)
        store.add(personal)
        store.add(work)
        return ActiveProfileLookup(profiles: store) { directory in
            seen.append(directory.path(percentEncoded: false))
            let email = directory.path(percentEncoded: false).contains("work") ? "work@example.test" : "personal@example.test"
            return RepoIdentity(name: "Test User", email: email, signingKey: nil, isLocal: false)
        }
    }

    @Test("An existing repo: the profile matching its identity")
    func existingRepo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(await lookup().profileId(forRepoAt: dir.path(percentEncoded: false)) == work.id)
    }

    @Test("A clone in progress uses the profile picked in the sheet, then forgets it")
    func cloneInProgress() async {
        let lookup = lookup()
        let destination = "/tmp/gitForge-missing-\(UUID().uuidString)/app"
        lookup.beginClone(at: destination, profileId: work.id)
        #expect(await lookup.profileId(forRepoAt: destination) == work.id)
        lookup.endClone(at: destination)
        #expect(await lookup.profileId(forRepoAt: destination) == personal.id)
    }

    @Test("A destination that doesn't exist yet reads the global identity, not a missing directory")
    func missingDirectoryUsesHome() async {
        let seen = LockedList<String>()
        _ = await lookup(seen: seen).profileId(forRepoAt: "/tmp/gitForge-missing-\(UUID().uuidString)/app")
        #expect(seen.values == [FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)])
    }
}
