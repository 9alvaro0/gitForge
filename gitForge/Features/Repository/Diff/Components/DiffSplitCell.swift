import SwiftUI

/// One side of a split-diff row. A `nil` `line` means "this slot doesn't
/// exist on this side": the cell shows a diagonal hatch so the asymmetry
/// reads without overpainting the added/removed tints.
struct DiffSplitCell: View {
    enum Side { case left, right }

    let line: DiffLine?
    let side: Side
    let attributed: AttributedString?

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            DiffLineNumber(number: number, width: DiffGutter.splitNumber)
            DiffSign(kind: signKind, width: DiffGutter.splitSign)
            if let line {
                // Long lines wrap so both halves stay readable without
                // horizontal scroll.
                DiffCode(line: line, attributed: attributed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, Spacing.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(" ")
                    .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: theme.density.metrics.diffLine, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .leading) {
            gutterTint
                .frame(width: DiffGutter.splitNumber + DiffGutter.numberTrailing)
        }
        .background {
            if let line {
                DiffTint.row(line.kind, colors: theme.colors)
            } else {
                DiffHatch(color: theme.colors.textPrimary.opacity(0.05))
            }
        }
    }

    private var number: Int? {
        guard let line else { return nil }
        return side == .left ? line.oldLineNumber : line.newLineNumber
    }

    /// The sign only shows on the side the change belongs to.
    private var signKind: DiffLine.Kind {
        guard let line else { return .context }
        switch line.kind {
        case .added: return side == .right ? .added : .context
        case .removed: return side == .left ? .removed : .context
        case .context, .noNewline: return line.kind
        }
    }

    /// The number column carries a second layer of the change tint, so the
    /// changed side reads at a glance down the gutter.
    private var gutterTint: Color {
        guard let line else { return .clear }
        return DiffTint.row(line.kind, colors: theme.colors)
    }
}

/// 135° stripes for the empty side of a split row, as in the artboard.
struct DiffHatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 2.8)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let sample = DiffHunk.previewSamples[0].lines
    VStack(spacing: 0) {
        ForEach(sample) { line in
            HStack(spacing: 0) {
                DiffSplitCell(line: line.kind == .added ? nil : line, side: .left, attributed: nil)
                Rectangle().fill(theme.colors.separator).frame(width: 1)
                DiffSplitCell(line: line.kind == .removed ? nil : line, side: .right, attributed: nil)
            }
        }
    }
    .frame(width: 720)
    .background(theme.colors.bgCode)
    .appTheme(theme)
}
