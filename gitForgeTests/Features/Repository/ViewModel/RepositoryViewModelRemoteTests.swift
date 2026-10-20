import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — ahead/behind loader", .serialized)
@MainActor
struct RepositoryViewModelAheadBehindTests {

    private static func makeVM() -> RepositoryViewModel {
        // Bogus dir → cli.upstreamName() returns nil (its `try?` swallows the
        // GitError.invalidWorkingDirectory). We exercise the gen-token path
        // and the "no upstream → reset counts to 0" branch without DI.
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("loadAheadBehind bumps aheadBehindGen by one")
    func bumpsGen() async {
        let vm = Self.makeVM()
        let before = vm.aheadBehindGen
        await vm.loadAheadBehind()
        #expect(vm.aheadBehindGen == before &+ 1)
    }

    @Test("loadAheadBehind is monotonic across consecutive calls")
    func monotonic() async {
        let vm = Self.makeVM()
        await vm.loadAheadBehind()
        let mid = vm.aheadBehindGen
        await vm.loadAheadBehind()
        #expect(vm.aheadBehindGen == mid &+ 1)
    }

    @Test("loadAheadBehind resets ahead/behind to zero when upstream is missing")
    func resetsCountsWhenNoUpstream() async {
        let vm = Self.makeVM()
        // Pre-seed non-zero counts so we can detect the reset.
        vm.aheadCount = 7
        vm.behindCount = 3
        await vm.loadAheadBehind()
        // Bogus dir → upstream nil → guard hits → counts reset to 0.
        #expect(vm.aheadCount == 0)
        #expect(vm.behindCount == 0)
        #expect(vm.upstream == nil)
    }
}

@Suite("RepositoryViewModel — remote operations guards", .serialized)
@MainActor
struct RepositoryViewModelRemoteOpsTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        return RepositoryViewModel(repository: Repository(url: url))
    }

    @Test("fetch is a no-op when another remote operation is in flight")
    func fetchGuard() async {
        let vm = Self.makeVM()
        vm.remoteOperation = .pulling
        vm.lastFetchedAt = nil
        await vm.fetch()
        // The guard fires before the cli call, so lastFetchedAt and
        // remoteOperation stay exactly where the test put them.
        #expect(vm.lastFetchedAt == nil)
        #expect(vm.remoteOperation == .pulling)
    }

    @Test("fetch is a no-op when a silent auto-fetch is already in flight")
    func fetchGuardAgainstAutoFetch() async {
        let vm = Self.makeVM()
        vm.autoFetchInFlight = true
        vm.lastFetchedAt = nil
        await vm.fetch()
        // Auto-fetch was running — manual fetch must bail without touching
        // remoteOperation (would have flickered the spinner) or lastFetchedAt.
        #expect(vm.remoteOperation == nil)
        #expect(vm.lastFetchedAt == nil)
        #expect(vm.autoFetchInFlight == true, "manual fetch shouldn't reset the auto-fetch flag")
    }

    @Test("pull is a no-op when another remote operation is in flight")
    func pullGuard() async {
        let vm = Self.makeVM()
        vm.remoteOperation = .pushing
        vm.remoteFailure = nil
        await vm.pull()
        #expect(vm.remoteFailure == nil, "guard should bail before touching anything")
        #expect(vm.remoteOperation == .pushing)
    }

    @Test("push is a no-op when another remote operation is in flight")
    func pushGuard() async {
        let vm = Self.makeVM()
        vm.remoteOperation = .fetching
        vm.remoteFailure = nil
        await vm.push()
        #expect(vm.remoteFailure == nil)
        #expect(vm.remoteOperation == .fetching)
    }

    @Test("fetch surfaces a RemoteFailure on a bogus dir and clears remoteOperation via defer")
    func fetchSurfacesFailureAndClearsOperation() async {
        let vm = Self.makeVM()
        vm.lastFetchedAt = nil
        await vm.fetch()
        #expect(vm.remoteFailure != nil)
        #expect(vm.remoteOperation == nil, "defer must reset remoteOperation")
        #expect(vm.lastFetchedAt == nil, "lastFetchedAt only updates on success")
    }

    @Test("pull surfaces a RemoteFailure on a bogus dir and clears remoteOperation via defer")
    func pullSurfacesFailureAndClearsOperation() async {
        let vm = Self.makeVM()
        await vm.pull()
        #expect(vm.remoteFailure != nil)
        #expect(vm.remoteOperation == nil)
    }

    @Test("push surfaces a RemoteFailure on a bogus dir and clears remoteOperation via defer")
    func pushSurfacesFailureAndClearsOperation() async {
        let vm = Self.makeVM()
        await vm.push()
        #expect(vm.remoteFailure != nil)
        #expect(vm.remoteOperation == nil)
    }
}

@Suite("RepositoryViewModel — success feedback", .serialized)
@MainActor
struct RepositoryViewModelSuccessFeedbackTests {
    @Test("Commit, push and fetch each publish a success event")
    func commitPushFetch() async throws {
        let origin = try await GitTestRepo.make(bare: true)
        let work = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["a.txt": "a\n"])
            try repo.git("remote", "add", "origin", origin.url.path)
        }
        defer { origin.remove(); work.remove() }
        let vm = RepositoryViewModel(repository: Repository(url: work.url))
        await vm.loadRefs()

        // First push: no upstream yet.
        #expect(await vm.push())
        #expect(vm.operationSuccess?.message == "Published main to origin/main")

        try await work.externalWriteAsync("b\n", to: "b.txt")
        try await work.gitAsync("add", "b.txt")
        await vm.workingCopy.refreshStatus()
        vm.workingCopy.commitSubject = "Add b"
        #expect(await vm.commit())
        let sha = try await work.gitAsync("rev-parse", "--short=7", "HEAD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(vm.operationSuccess?.message == "Committed \(sha) — Add b")

        #expect(await vm.push())
        #expect(vm.operationSuccess?.message == "Pushed 1 commit to origin/main")

        #expect(await vm.fetch())
        #expect(vm.operationSuccess?.message == "Fetched — origin/main has nothing new")
    }

    @Test("A failed push publishes no success")
    func failedPushIsSilent() async {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        let vm = RepositoryViewModel(repository: Repository(url: url))
        #expect(await vm.push() == false)
        #expect(vm.operationSuccess == nil)
    }
}
