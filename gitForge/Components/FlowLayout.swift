import SwiftUI

/// Simple flow / wrap layout for chips and tag rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.minX + maxWidth, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    FlowLayout(spacing: 6) {
        ForEach(["v2.3.1", "v2.3.0", "v2.2.4", "v2.2.3", "v2.2.2", "v2.2.1", "v2.1.0", "v2.0.0"], id: \.self) { tag in
            HStack(spacing: 5) {
                GFIcon(kind: .diamond, size: 10, stroke: theme.palette.mod)
                Text(tag).font(AppFont.mono(11.5, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.mod)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.palette.mod.opacity(0.12)))
        }
    }
    .frame(width: 460)
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
