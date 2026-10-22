import Foundation
import Testing
@testable import gitForge

@Suite("WhatsNewController")
@MainActor
struct WhatsNewControllerTests {
    /// 1.4.0 brings one highlight.
    private let catalog: WhatsNewCatalog = {
        let text = LocalizedText(["en": "x"])
        return WhatsNewCatalog(releases: [
            WhatsNewRelease(version: "1.4.0",
                            highlights: [WhatsNewHighlight(symbol: nil, title: text, body: text)],
                            fixes: [], improvements: []),
        ])
    }()

    private func gate(_ suite: TestDefaults, lastSeen: String = "1.3.0") -> WhatsNewGate {
        suite.defaults.set(lastSeen, forKey: WhatsNewGate.lastSeenKey)
        suite.defaults.set(true, forKey: WhatsNewGate.onboardingCompletedKey)
        return WhatsNewGate(defaults: suite.defaults) { $0.compare($1, options: .numeric) }
    }

    private func controller(_ gate: WhatsNewGate, catalog: WhatsNewCatalog? = nil) -> WhatsNewController {
        WhatsNewController(catalog: catalog ?? self.catalog, gate: gate, currentVersion: "1.4.0")
    }

    @Test("Launch evaluation leaves a presentation pending")
    func launchSetsPending() {
        TestDefaults.with { suite in
            let controller = controller(gate(suite))
            controller.evaluateAtLaunch()
            #expect(controller.pending?.source == .launch)
            #expect(controller.showsSheetThisLaunch)
        }
    }

    @Test("Launch evaluation runs once")
    func launchOnce() {
        TestDefaults.with { suite in
            let controller = controller(gate(suite))
            controller.evaluateAtLaunch()
            _ = controller.claim(otherSheetUp: false)
            // Undo the seen mark: only the once-per-launch guard can stop it now.
            suite.defaults.set("1.3.0", forKey: WhatsNewGate.lastSeenKey)
            controller.evaluateAtLaunch()
            #expect(controller.pending == nil)
        }
    }

    @Test("A presentation is handed out once")
    func claimOnce() {
        TestDefaults.with { suite in
            let controller = controller(gate(suite))
            controller.evaluateAtLaunch()
            #expect(controller.claim(otherSheetUp: false) != nil)
            #expect(controller.claim(otherSheetUp: false) == nil)
        }
    }

    @Test("Another sheet keeps it pending")
    func claimWaits() {
        TestDefaults.with { suite in
            let controller = controller(gate(suite))
            controller.evaluateAtLaunch()
            #expect(controller.claim(otherSheetUp: true) == nil)
            #expect(controller.pending != nil)
            #expect(controller.claim(otherSheetUp: false) != nil)
        }
    }

    @Test("Claiming the launch sheet marks the version seen")
    func claimMarksLaunchSeen() {
        TestDefaults.with { suite in
            let gate = gate(suite)
            let controller = controller(gate)
            controller.evaluateAtLaunch()
            #expect(gate.lastSeenVersion == "1.3.0")
            _ = controller.claim(otherSheetUp: false)
            #expect(gate.lastSeenVersion == "1.4.0")
        }
    }

    @Test("Opening from the menu leaves the seen version alone")
    func menuDoesNotMarkSeen() throws {
        try TestDefaults.with { suite in
            let gate = gate(suite)
            let controller = controller(gate)
            #expect(controller.canShowFromMenu)
            controller.showFromMenu()
            let presentation = try #require(controller.claim(otherSheetUp: false))
            #expect(presentation.source == .menu)
            #expect(presentation.currentVersion == "1.4.0")
            #expect(presentation.previousVersion == nil)
            #expect(gate.lastSeenVersion == "1.3.0")
        }
    }

    @Test("The menu does nothing while the sheet shows and works again after it closes")
    func menuWhileShowing() {
        TestDefaults.with { suite in
            let controller = controller(gate(suite))
            controller.evaluateAtLaunch()
            #expect(controller.claim(otherSheetUp: false) != nil)
            #expect(!controller.canShowFromMenu)
            controller.showFromMenu()
            #expect(controller.pending == nil)

            controller.dismissed()
            #expect(controller.canShowFromMenu)
            controller.showFromMenu()
            #expect(controller.claim(otherSheetUp: false)?.source == .menu)
        }
    }

    @Test("An empty catalog disables the menu and shows nothing")
    func emptyCatalog() {
        TestDefaults.with { suite in
            let controller = controller(gate(suite), catalog: .empty)
            #expect(!controller.canShowFromMenu)
            controller.evaluateAtLaunch()
            #expect(controller.pending == nil)
            #expect(!controller.showsSheetThisLaunch)
        }
    }
}
