import Foundation
import Testing
@testable import gitForge

@Suite("Reviews config store")
@MainActor
struct ReviewsConfigStoreTests {
    static let host = "gitlab.example.test"

    static let pattern = FollowPattern(host: host, text: "apps/*/android/*")!
    static let otherPattern = FollowPattern(host: "github.com", text: "octo/*")!

    static let manual = RemoteHost(provider: .gitlab, host: host, owner: "marta", repo: "tools",
                                   apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))
    static let hidden = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "hello")

    static func config() -> ReviewsConfig {
        ReviewsConfig(patterns: [pattern, otherPattern], manual: [manual], hidden: [hidden],
                      answeredProposals: ["\(host)|oss/*/lib", "github.com|octo/*"])
    }

    static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("reviews-settings.json")
    }

    /// The files set aside next to the settings, by name.
    static func setAside(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("reviews-settings.corrupted.") && $0.pathExtension == "json" }
    }

    @Test("Without a file the settings are empty, and nothing is written")
    func missingIsEmpty() {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)

        #expect(store.load() == ReviewsConfig())
        #expect(!FileManager.default.fileExists(atPath: Self.fileURL(in: dir).path))
    }

    @Test("Saving and reading again gives the same settings, also from a new store")
    func roundTrip() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let config = Self.config()
        ReviewsConfigStore(directory: dir).save(config)

        #expect(ReviewsConfigStore(directory: dir).load() == config)

        // The file is readable, sorted, and carries the version next to the four lists.
        let text = try String(contentsOf: Self.fileURL(in: dir), encoding: .utf8)
        #expect(text.contains("\n"))
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect(Set(json.keys) == ["version", "patterns", "manual", "hidden", "answeredProposals"])
    }

    @Test("Saving again replaces the previous settings, and the order is kept")
    func overwrite() {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        store.save(Self.config())
        let second = ReviewsConfig(patterns: [Self.otherPattern, Self.pattern], manual: [], hidden: [Self.hidden, Self.manual],
                                   answeredProposals: ["b", "a", "b"])
        store.save(second)

        #expect(store.load() == second)
    }

    @Test("The settings are version 1")
    func currentVersion() {
        #expect(ReviewsConfig.currentVersion == 1)
        #expect(ReviewsConfig() == ReviewsConfig(patterns: [], manual: [], hidden: [], answeredProposals: []))
    }

    @Test("Settings from a newer build are set aside with their content and read as empty; saving leaves them alone")
    func newerVersionSetAside() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        // A newer build may also have changed the shape, which must not matter.
        let future = Data(#"{"version": 2, "patterns": [{"host": "gitlab.example.test", "rules": ["apps/*/*"]}], "manual": 7}"#.utf8)
        try future.write(to: Self.fileURL(in: dir))

        #expect(store.load() == ReviewsConfig())

        let aside = try Self.setAside(in: dir)
        let kept = try #require(aside.first)
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: kept) == future)
        #expect(!FileManager.default.fileExists(atPath: Self.fileURL(in: dir).path))

        // The next save writes a fresh file and never the set-aside one.
        let config = Self.config()
        store.save(config)
        #expect(try Self.setAside(in: dir) == aside)
        #expect(try Data(contentsOf: kept) == future)
        #expect(ReviewsConfigStore(directory: dir).load() == config)
    }

    @Test("Settings that can't be read are set aside with their content and read as empty; saving leaves them alone")
    func unreadableSetAside() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        let garbage = Data("{oops".utf8)
        try garbage.write(to: Self.fileURL(in: dir))

        #expect(store.load() == ReviewsConfig())

        let aside = try Self.setAside(in: dir)
        let kept = try #require(aside.first)
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: kept) == garbage)
        #expect(!FileManager.default.fileExists(atPath: Self.fileURL(in: dir).path))

        let config = Self.config()
        store.save(config)
        #expect(try Self.setAside(in: dir) == aside)
        #expect(try Data(contentsOf: kept) == garbage)
        #expect(ReviewsConfigStore(directory: dir).load() == config)
    }

    @Test("A file of the right version but the wrong shape is set aside too")
    func wrongShapeSetAside() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        let wrong = Data(#"{"version": 1, "patterns": "none"}"#.utf8)
        try wrong.write(to: Self.fileURL(in: dir))

        #expect(store.load() == ReviewsConfig())

        let aside = try Self.setAside(in: dir)
        let kept = try #require(aside.first)
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: kept) == wrong)
    }

    @Test("The set-aside name follows the accounts file: a stamp without colons")
    func setAsideName() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        try Data("{oops".utf8).write(to: Self.fileURL(in: dir))
        _ = store.load()

        let name = try #require(Self.setAside(in: dir).first?.lastPathComponent)
        #expect(!name.contains(":"))
        #expect(name.hasPrefix("reviews-settings.corrupted."))
        #expect(name.hasSuffix(".json"))
    }

    @Test("A stored pattern that is no longer valid is dropped, and the rest loads without setting the file aside")
    func invalidPatternDropped() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        let edited = Data("""
        {
          "version": 1,
          "patterns": [
            {"host": "gitlab.example.test", "segments": ["apps", "*", "android", "*"]},
            {"host": "gitlab.example.test", "segments": ["*", "*"]}
          ],
          "manual": [{"provider": "gitlab", "host": "gitlab.example.test", "owner": "marta", "repo": "tools"}],
          "hidden": [],
          "answeredProposals": ["gitlab.example.test|oss/*/lib"]
        }
        """.utf8)
        try edited.write(to: Self.fileURL(in: dir))

        let loaded = store.load()

        #expect(loaded.patterns == [Self.pattern])
        #expect(loaded.manual.map(\.slug) == ["marta/tools"])
        #expect(loaded.answeredProposals == ["gitlab.example.test|oss/*/lib"])
        #expect(try Self.setAside(in: dir).isEmpty)
        #expect(try Data(contentsOf: Self.fileURL(in: dir)) == edited)
    }

    @Test("Other shapes a hand edit can leave are dropped as well", arguments: [
        ["pay*", "*"], ["apps"], ["apps", ""], ["apps", "payments"], ["**", "x"], [],
    ])
    func otherInvalidShapesDropped(segments: [String]) throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let store = ReviewsConfigStore(directory: dir)
        let list = segments.map { "\"\($0)\"" }.joined(separator: ",")
        try Data("""
        {"version": 1, "patterns": [{"host": "gitlab.example.test", "segments": [\(list)]},
         {"host": "github.com", "segments": ["octo", "*"]}],
         "manual": [], "hidden": [], "answeredProposals": []}
        """.utf8).write(to: Self.fileURL(in: dir))

        #expect(store.load().patterns == [Self.otherPattern])
    }

    @Test("Nothing is de-duplicated or reordered on load")
    func duplicatesKept() throws {
        let dir = TemporaryDirectories.make("gitForge-reviews-config")
        let config = ReviewsConfig(patterns: [Self.pattern, Self.pattern], manual: [Self.manual, Self.manual],
                                   hidden: [Self.hidden, Self.hidden], answeredProposals: ["z", "a", "z"])
        ReviewsConfigStore(directory: dir).save(config)

        #expect(ReviewsConfigStore(directory: dir).load() == config)
    }

    @Test("FollowOutcome and PatternProposal carry what the store reports")
    func valueTypes() {
        #expect(FollowOutcome.done == .done)
        #expect(FollowOutcome.overLimit(total: 101) == .overLimit(total: 101))
        #expect(FollowOutcome.overLimit(total: 101) != .overLimit(total: 102))
        #expect(FollowOutcome.done != .overLimit(total: 0))

        let proposal = PatternProposal(pattern: Self.pattern, adds: 3, total: 12)
        #expect(proposal == PatternProposal(pattern: Self.pattern, adds: 3, total: 12))
        #expect(proposal != PatternProposal(pattern: Self.pattern, adds: 4, total: 12))
        #expect(proposal.pattern == Self.pattern && proposal.adds == 3 && proposal.total == 12)
    }
}
