import Foundation
import Testing
@testable import gitForge

@Suite("PaletteActionRouter", .serialized)
@MainActor
struct PaletteActionRouterTests {
    @Test("Clone repository… opens the clone sheet")
    func clone() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.cloneRepository)
        #expect(app.ui.cloneRequest != nil)
    }
}
