import Foundation
import Testing
@testable import gitForge

@Suite("WhatsNewGate")
struct WhatsNewGateTests {
    /// 1.3.0 and 1.5.0 bring something new; 1.4.0 only fixes a bug.
    private let catalog: WhatsNewCatalog = {
        let text = LocalizedText(["en": "x"])
        let highlight = WhatsNewHighlight(symbol: nil, title: text, body: text)
        return WhatsNewCatalog(releases: [
            WhatsNewRelease(version: "1.3.0", highlights: [highlight], fixes: [], improvements: []),
            WhatsNewRelease(version: "1.4.0", highlights: [], fixes: [LocalizedText(["en": "fix"])], improvements: []),
            WhatsNewRelease(version: "1.5.0", highlights: [highlight], fixes: [], improvements: []),
        ])
    }()

    private func gate(_ suite: TestDefaults, lastSeen: String? = nil, onboarded: Bool = true) -> WhatsNewGate {
        if let lastSeen { suite.defaults.set(lastSeen, forKey: WhatsNewGate.lastSeenKey) }
        suite.defaults.set(onboarded, forKey: WhatsNewGate.onboardingCompletedKey)
        return WhatsNewGate(defaults: suite.defaults) { $0.compare($1, options: .numeric) }
    }

    @Test("Fresh install records the version and shows nothing")
    func freshInstall() {
        TestDefaults.with { suite in
            let gate = gate(suite, onboarded: false)
            #expect(gate.evaluate(currentVersion: "1.5.0", catalog: catalog) == nil)
            #expect(gate.lastSeenVersion == "1.5.0")
        }
    }

    @Test("A user from before the feature sees only the current release")
    func preFeatureUser() throws {
        try TestDefaults.with { suite in
            let gate = gate(suite)
            let presentation = try #require(gate.evaluate(currentVersion: "1.5.0", catalog: catalog))
            #expect(presentation.releases.map(\.version) == ["1.5.0"])
            #expect(presentation.previousVersion == nil)
            #expect(presentation.source == .launch)
            #expect(gate.lastSeenVersion == nil)
        }
    }

    @Test("A user from before the feature sees nothing when the current release only has fixes")
    func preFeatureFixOnly() {
        TestDefaults.with { suite in
            let gate = gate(suite)
            #expect(gate.evaluate(currentVersion: "1.4.0", catalog: catalog) == nil)
            #expect(gate.lastSeenVersion == "1.4.0")
        }
    }

    @Test("An update shows the releases since the last one seen")
    func normalUpdate() throws {
        try TestDefaults.with { suite in
            let gate = gate(suite, lastSeen: "1.3.0")
            let presentation = try #require(gate.evaluate(currentVersion: "1.5.0", catalog: catalog))
            #expect(presentation.releases.map(\.version) == ["1.5.0", "1.4.0"])
            #expect(presentation.highlightGroups.map(\.version) == ["1.5.0"])
            #expect(presentation.alsoItems == [LocalizedText(["en": "fix"])])
            #expect(presentation.currentVersion == "1.5.0")
            #expect(presentation.previousVersion == "1.3.0")
            #expect(presentation.releaseNotesURL.absoluteString == "https://github.com/9alvaro0/gitForge/releases/tag/v1.5.0")
            #expect(gate.lastSeenVersion == "1.3.0")
        }
    }

    @Test("A fix-only update shows nothing")
    func fixOnlyUpdate() {
        TestDefaults.with { suite in
            let gate = gate(suite, lastSeen: "1.3.0")
            #expect(gate.evaluate(currentVersion: "1.4.0", catalog: catalog) == nil)
            #expect(gate.lastSeenVersion == "1.4.0")
        }
    }

    @Test("The same version shows nothing twice")
    func alreadySeen() {
        TestDefaults.with { suite in
            let gate = gate(suite, lastSeen: "1.5.0")
            #expect(gate.evaluate(currentVersion: "1.5.0", catalog: catalog) == nil)
            #expect(gate.lastSeenVersion == "1.5.0")
        }
    }

    @Test("Going back keeps the newer version seen")
    func downgrade() {
        TestDefaults.with { suite in
            let gate = gate(suite, lastSeen: "1.5.0")
            #expect(gate.evaluate(currentVersion: "1.3.0", catalog: catalog) == nil)
            #expect(gate.lastSeenVersion == "1.5.0")
        }
    }

    @Test("markSeen never lowers the stored version")
    func markSeenKeepsMax() {
        TestDefaults.with { suite in
            let gate = gate(suite)
            gate.markSeen("1.5.0")
            gate.markSeen("1.3.0")
            #expect(gate.lastSeenVersion == "1.5.0")
        }
    }

    @Test("Production comparator orders double digits and prereleases")
    func sparkleOrdering() {
        #expect(WhatsNewGate.sparkleCompare("1.10.0", "1.9.0") == .orderedDescending)
        #expect(WhatsNewGate.sparkleCompare("1.4.0-beta.1", "1.4.0") == .orderedAscending)
    }
}
