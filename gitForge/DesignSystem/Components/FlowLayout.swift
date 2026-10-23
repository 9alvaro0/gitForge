import SwiftUI

/// Simple flow / wrap layout for chips and tag rows. Each item keeps its own
/// width and goes to the next line when it doesn't fit. With
/// `fitsWideItems`, an item wider than a whole line is offered the line's
/// width instead, so one that can truncate (a long branch name) stays inside.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var fitsWideItems = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let s = size(of: sub, lineWidth: maxWidth)
            if x + s.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            totalWidth = max(totalWidth, x + s.width)
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // The same arithmetic as `sizeThatFits`, from 0, moved to `bounds`
        // only when placing.
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = size(of: sub, lineWidth: maxWidth)
            if x + s.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }

    /// The item's own size; with `fitsWideItems`, its size at the line's
    /// width when it's wider than that.
    private func size(of sub: LayoutSubview, lineWidth: CGFloat) -> CGSize {
        let ideal = sub.sizeThatFits(.unspecified)
        guard fitsWideItems, ideal.width > lineWidth else { return ideal }
        return sub.sizeThatFits(ProposedViewSize(width: lineWidth, height: nil))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    FlowLayout(spacing: Spacing.s6) {
        ForEach(["v2.3.1", "v2.3.0", "v2.2.4", "v2.2.3", "v2.2.2", "v2.2.1", "v2.1.0", "v2.0.0"], id: \.self) { tag in
            HStack(spacing: Spacing.s6) {
                SymbolGlyph("diamond", size: 10, framed: false)
                Text(tag).textRole(.monoSmall)
            }
            .foregroundStyle(theme.colors.mod)
            .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s4)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.mod.opacity(0.10)))
        }
    }
    .frame(width: 460)
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
