import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — tag remote ops", .serialized)
@MainActor
struct RepositoryViewModelTagPushTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    private static func tag(_ name: String) -> GitRef {
        GitRef(name: name, kind: .tag, targetSha: "deadbeef", isHead: false)
    }

    @Test("pushTag is a no-op when another remote operation is in flight")
    func pushTagGuard() async {
        let vm = Self.makeVM()
        vm.remoteOperation = .pulling
        vm.remoteFailure = nil
        let result = await vm.pushTag(Self.tag("v1.0.0"))
        guard case .failure(let error) = result,
              let gitError = error as? GitError, gitError == .busy else {
            Issue.record("Expected GitError.busy, got \(result)")
            return
        }
        // Guard must fire before mutation: pre-existing operation untouched.
        #expect(vm.remoteOperation == .pulling)
        #expect(vm.remoteFailure == nil)
    }

    @Test("pushDeleteTag is a no-op when another remote operation is in flight")
    func pushDeleteTagGuard() async {
        let vm = Self.makeVM()
        vm.remoteOperation = .fetching
        let result = await vm.pushDeleteTag(Self.tag("v1.0.0"))
        guard case .failure(let error) = result,
              let gitError = error as? GitError, gitError == .busy else {
            Issue.record("Expected GitError.busy, got \(result)")
            return
        }
        #expect(vm.remoteOperation == .fetching)
    }

    @Test("pushAllTags is a no-op when another remote operation is in flight")
    func pushAllTagsGuard() async {
        let vm = Self.makeVM()
        vm.remoteOperation = .pushing
        let result = await vm.pushAllTags()
        guard case .failure(let error) = result,
              let gitError = error as? GitError, gitError == .busy else {
            Issue.record("Expected GitError.busy, got \(result)")
            return
        }
        #expect(vm.remoteOperation == .pushing)
    }

    @Test("pushTag clears stale remoteFailure on entry, then surfaces a fresh one on bogus dir")
    func pushTagClearsStaleFailureAndSurfacesFresh() async {
        let vm = Self.makeVM()
        // Pre-seed a sentinel failure from a prior op. The entry-clear sets
        // it to nil; the bogus dir then makes the cli call throw, so the
        // catch repopulates it with a fresh RemoteFailure that's not the
        // sentinel.
        vm.remoteFailure = .authenticationHTTPS
        let result = await vm.pushTag(Self.tag("v1.0.0"))
        guard case .failure = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect(vm.remoteOperation == nil, "defer must reset remoteOperation")
        #expect(vm.remoteFailure != nil)
        #expect(vm.remoteFailure != .authenticationHTTPS, "stale failure must not survive entry-clear")
    }

    @Test("pushDeleteTag surfaces a RemoteFailure on a bogus dir and clears remoteOperation via defer")
    func pushDeleteTagSurfacesFailure() async {
        let vm = Self.makeVM()
        let result = await vm.pushDeleteTag(Self.tag("v1.0.0"))
        guard case .failure = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect(vm.remoteOperation == nil)
        #expect(vm.remoteFailure != nil)
    }

    @Test("pushAllTags surfaces a RemoteFailure on a bogus dir and clears remoteOperation via defer")
    func pushAllTagsSurfacesFailure() async {
        let vm = Self.makeVM()
        let result = await vm.pushAllTags()
        guard case .failure = result else {
            Issue.record("Expected .failure, got \(result)")
            return
        }
        #expect(vm.remoteOperation == nil)
        #expect(vm.remoteFailure != nil)
    }
}
