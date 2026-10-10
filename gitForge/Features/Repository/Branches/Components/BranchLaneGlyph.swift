import SwiftUI

/// 16 pt lane mark: a vertical line with the branch's node, filled for HEAD.
struct BranchLaneGlyph: View {
    let color: BranchGlyphColor
    var isHead: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        let tint = resolved
        Canvas { context, size in
            let midX = size.width / 2
            var line = Path()
            line.move(to: CGPoint(x: midX, y: 0))
            line.addLine(to: CGPoint(x: midX, y: size.height))
            context.stroke(line, with: .color(tint), lineWidth: 2)
            let r: CGFloat = isHead ? 4 : 3.5
            let node = Path(ellipseIn: CGRect(x: midX - r, y: size.height / 2 - r, width: r * 2, height: r * 2))
            context.fill(node, with: .color(isHead ? tint : theme.colors.bgContent))
            context.stroke(node, with: .color(tint), lineWidth: 2)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private var resolved: Color {
        switch color {
        case .accent: theme.colors.accent
        case .lane(let lane): Color(hex: LaneColors.hex(lane, dark: theme.effectiveMode == .dark))
        case .neutral: theme.colors.textTertiary
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: 12) {
        BranchLaneGlyph(color: .accent, isHead: true)
        BranchLaneGlyph(color: .lane(.lane0))
        BranchLaneGlyph(color: .lane(.lane3))
        BranchLaneGlyph(color: .neutral)
    }
    .padding()
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
