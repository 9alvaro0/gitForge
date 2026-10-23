import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// How wide `FlowLayout` says it is for a width it's offered.
@Suite("FlowLayout")
@MainActor
struct FlowLayoutTests {
    private static let longName = String(repeating: "feature-branch-", count: 20)

    private static func width(of view: some View, offered width: CGFloat) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 2_000)).width
    }

    @Test("An item wider than the line keeps its own width, unless the layout fits wide items: then the line's")
    func wideItems() {
        let name = Text(Self.longName).lineLimit(1).truncationMode(.middle)
        #expect(Self.width(of: FlowLayout { name }, offered: 200) > 200)
        #expect(Self.width(of: FlowLayout(fitsWideItems: true) { name }, offered: 200) <= 200)
    }

    @Test("An item narrower than the line keeps its own width, wide items fitted or not, though it would grow if offered the line")
    func narrowItems() {
        // 50 pt on its own; as wide as it's offered otherwise.
        let stretchy = Color.clear.frame(minWidth: 50, idealWidth: 50, maxWidth: .infinity).frame(height: 10)
        let fitted = Self.width(of: FlowLayout(fitsWideItems: true) { stretchy }, offered: 200)
        #expect(fitted == Self.width(of: FlowLayout { stretchy }, offered: 200))
        #expect(fitted == 50)
    }

    @Test("A line is as wide as its items and the spacing between them, not the spacing after the last one")
    func noTrailingSpacing() {
        let box = Color.clear.frame(width: 50, height: 10)
        #expect(Self.width(of: FlowLayout(spacing: 6) { box; box }, offered: 300) == 106)
    }
}
