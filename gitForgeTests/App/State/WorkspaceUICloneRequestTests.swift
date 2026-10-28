import Foundation
import Testing
@testable import gitForge

@Suite("WorkspaceUI — clone requests and Settings links")
@MainActor
struct WorkspaceUICloneRequestTests {
    @Test("A clone sheet already up isn't replaced (it may be cloning)")
    func keepsOpenSheet() {
        let ui = WorkspaceUI()
        ui.requestClone(CloneRequest(source: .github))
        let first = ui.cloneRequest
        ui.requestClone()
        #expect(ui.cloneRequest == first)
        #expect(ui.cloneRequest?.source == .github)

        ui.cloneRequest = nil
        ui.requestClone()
        #expect(ui.cloneRequest?.source == .url)
    }

    @Test("Open accounts lands on Settings, on the Accounts pane")
    func openSettingsAtAccounts() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.openSettings(at: .accounts)
            #expect(ui.workspaceSection == .settings)
            #expect(ui.settingsPane == .accounts)
            #expect(ui.settingsAnchor == .accounts)
        }
    }

    @Test("The Reviews link lands on Settings, on the Pull requests pane")
    func openSettingsAtReviews() {
        TestDefaults.with { suite in
            let ui = WorkspaceUI(defaults: suite.defaults)
            ui.openSettings(at: .reviews)
            #expect(ui.workspaceSection == .settings)
            #expect(ui.settingsPane == .pullRequests)
            #expect(ui.settingsAnchor == .reviews)
        }
    }
}
