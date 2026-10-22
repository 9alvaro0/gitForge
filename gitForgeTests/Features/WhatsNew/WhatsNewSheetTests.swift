import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// Renders the sheet in an offscreen window to check what AppKit sees.
@Suite("WhatsNewSheet")
@MainActor
struct WhatsNewSheetTests {
    private func host(styleMask: NSWindow.StyleMask) -> (NSWindow, NSHostingView<some View>) {
        let host = NSHostingView(rootView: WhatsNewSheet(presentation: .previewSingle, language: "en")
            .appTheme(AppTheme()))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: styleMask,
                              backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Lets the scroll area pick up its measured height.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return (window, host)
    }

    @Test("The sheet paints its own background")
    func paintsItsOwnBackground() throws {
        let (_, host) = host(styleMask: [.borderless])
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        // A corner pixel: inside the sheet, away from any text.
        let corner = try #require(rep.colorAt(x: 4, y: 4))
        #expect(corner.alphaComponent > 0.99, "corner alpha \(corner.alphaComponent)")
    }

    @Test("Esc is handled even when nothing has focus")
    func escapeIsHandledWithoutFocus() throws {
        let (window, _) = host(styleMask: [.titled])
        window.makeFirstResponder(nil)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                   characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                   isARepeat: false, keyCode: 53))
        #expect(window.performKeyEquivalent(with: escape))
    }
}
