import Foundation
import Testing
@testable import gitForge

@Suite("WorkspaceUI — clone requests")
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
}
