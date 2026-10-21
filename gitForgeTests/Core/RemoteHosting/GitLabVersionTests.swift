import Foundation
import Testing
@testable import gitForge

@Suite("GitLab version and instance info")
struct GitLabVersionTests {
    @Test("Parses major.minor and ignores patch and edition", arguments: [
        ("17.5.1-ee", 17, 5), ("16.11.3", 16, 11), ("18.0.0-pre", 18, 0),
    ])
    func parses(raw: String, major: Int, minor: Int) {
        #expect(GitLabVersion(raw) == GitLabVersion(major: major, minor: minor))
    }

    @Test("Garbage isn't a version")
    func garbage() {
        #expect(GitLabVersion("") == nil)
        #expect(GitLabVersion("unknown") == nil)
        #expect(GitLabVersion("17") == nil)
    }

    @Test("Orders by major then minor; 17.3 is the request-changes floor")
    func order() {
        #expect(GitLabVersion(major: 16, minor: 11) < GitLabVersion(major: 17, minor: 2))
        #expect(GitLabVersion(major: 17, minor: 3) >= .requestChanges)
        #expect(!(GitLabVersion(major: 17, minor: 2) >= .requestChanges))
    }

    @Test("Device flow keeps its 17.2 floor")
    func deviceFlow() {
        #expect(InstanceVerifier.supportsDeviceFlow("17.2.0-ee"))
        #expect(!InstanceVerifier.supportsDeviceFlow("17.1.9"))
        #expect(!InstanceVerifier.supportsDeviceFlow("nonsense"))
    }

    @Test("The cache loads each host once")
    func cacheOnce() async {
        let cache = GitLabInstanceInfoCache()
        let calls = Counter()
        let load: @Sendable () async -> (info: GitLabInstanceInfo, keep: Bool) = {
            await calls.bump()
            return (GitLabInstanceInfo(version: GitLabVersion(major: 17, minor: 5), hasRequestChangesMutation: false), keep: true)
        }
        _ = await cache.info(for: "gitlab.example.test", load: load)
        _ = await cache.info(for: "gitlab.example.test", load: load)
        _ = await cache.info(for: "other.example.test", load: load)
        #expect(await calls.value == 2)
    }

    @Test("A failed read isn't kept: the next ask tries again")
    func failureNotCached() async {
        let cache = GitLabInstanceInfoCache()
        let calls = Counter()
        let info = GitLabInstanceInfo(version: GitLabVersion(major: 17, minor: 5), hasRequestChangesMutation: false)
        let failing: @Sendable () async -> (info: GitLabInstanceInfo, keep: Bool) = {
            await calls.bump()
            return (info, keep: false)
        }
        #expect(await cache.info(for: "gitlab.example.test", load: failing) == info)
        _ = await cache.info(for: "gitlab.example.test", load: failing)
        #expect(await calls.value == 2)
    }
}

private actor Counter {
    var value = 0
    func bump() { value += 1 }
}
