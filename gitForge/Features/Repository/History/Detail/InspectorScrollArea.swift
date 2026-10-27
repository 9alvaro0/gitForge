import SwiftUI

/// A scrolling section of History's inspector (the changed files, a long
/// commit message): a scroll view of its own, so the header above stays put
/// (audit M5); a hairline on top once scrolled; and a short fade at the
/// bottom, so a line cut by the edge reads as "more below" rather than as a
/// glitch.
struct InspectorScrollArea<Content: View>: View {
    /// Inset of the content from the sides (rows bring their own padding).
    var horizontalMargin: CGFloat = Spacing.s16
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme
    @State private var scrolled = false

    static var fadeHeight: CGFloat { 12 }

    var body: some View {
        ScrollView {
            content
        }
        .contentMargins(.horizontal, horizontalMargin, for: .scrollContent)
        // The last row clears the fade once scrolled to the end.
        .contentMargins(.bottom, Self.fadeHeight, for: .scrollContent)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 0.5
        } action: { _, isScrolled in
            scrolled = isScrolled
        }
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fadeHeight)
            }
        }
        .overlay(alignment: .top) {
            if scrolled {
                Rectangle().fill(theme.colors.separator).frame(height: 1)
            }
        }
    }
}
