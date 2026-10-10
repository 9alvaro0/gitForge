import AppKit
import Testing
@testable import gitForge

@Suite("GFIcon — SF Symbols")
@MainActor
struct GFIconSymbolTests {

    @Test("Every icon kind maps to a symbol that exists on this system", arguments: GFIconKind.allCases)
    func symbolExists(kind: GFIconKind) {
        #expect(NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) != nil, "\(kind) → \(kind.symbolName)")
    }

    @Test("The dot renders smaller than the other glyphs")
    func dotScale() {
        #expect(GFIconKind.dot.glyphScale < GFIconKind.check.glyphScale)
    }
}
