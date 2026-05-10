import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — identity", .serialized)
@MainActor
struct RepositoryViewModelIdentityTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("repoIdentity defaults to nil and identityGen starts at zero")
    func defaults() {
        let vm = Self.makeVM()
        #expect(vm.repoIdentity == nil)
        #expect(vm.identityGen == 0)
    }

    @Test("refreshIdentity bumps the gen-token and writes a snapshot")
    func refreshBumpsGenAndWritesSnapshot() async {
        let vm = Self.makeVM()
        let before = vm.identityGen
        await vm.refreshIdentity()
        #expect(vm.identityGen == before &+ 1)
        // Bogus dir → currentIdentity returns a RepoIdentity with all-nil
        // fields and isLocal == false. We still expect a non-nil cache so
        // the UI knows "first read landed".
        #expect(vm.repoIdentity != nil)
        #expect(vm.repoIdentity?.name == nil)
        #expect(vm.repoIdentity?.email == nil)
        #expect(vm.repoIdentity?.isLocal == false)
    }

    @Test("clearLocalIdentity refreshes the cached snapshot")
    func clearLocalIdentityRefreshes() async {
        let vm = Self.makeVM()
        await vm.clearLocalIdentity()
        #expect(vm.identityGen >= 1)
        #expect(vm.repoIdentity != nil)
    }

    @Test("applyProfile refreshes the cached snapshot even when the CLI write fails")
    func applyProfileRefreshesOnFailure() async {
        let vm = Self.makeVM()
        let profile = GitProfile(
            name: "Test",
            userName: "alvaro",
            userEmail: "alvaro@example.com",
            signingKey: nil
        )
        // Bogus dir → setLocalIdentity throws on the first config write.
        // The catch branch should still refresh the snapshot so the cache
        // reflects on-disk state instead of staying at the pre-call value.
        await #expect(throws: (any Error).self) {
            try await vm.applyProfile(profile)
        }
        #expect(vm.repoIdentity != nil)
        #expect(vm.identityGen >= 1)
    }
}
