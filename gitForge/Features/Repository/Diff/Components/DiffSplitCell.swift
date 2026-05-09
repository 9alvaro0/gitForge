import SwiftUI

/// `nil` `line` means "this slot doesn't exist on this side" — the cell
/// renders a muted background so the asymmetry reads without overpainting
/// the actual added/removed tints.
struct DiffSplitCell: View {
    enum Side { case left, right }

    let line: DiffLine?
    let side: Side
    let attributed: AttributedString?

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.none) {
            lineNumber
            Text(sign)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .frame(width: DesignTokens.IconSize.xl)
                .foregroundStyle(signColor)
            content
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, DesignTokens.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    /// Long lines wrap to multiple visual rows so the content stays readable
    /// without horizontal scroll. `GridRow` in `DiffSplitContent` aligns both
    /// sides to the taller wrapped height — so paired changed lines remain
    /// horizontally aligned even when one side wraps further than the other.
    @ViewBuilder
    private var content: some View {
        if let attributed {
            Text(attributed)
        } else {
            Text(displayContent)
                .foregroundStyle(textColor)
        }
    }

    private var lineNumber: some View {
        let number: Int? = {
            guard let line else { return nil }
            return side == .left ? line.oldLineNumber : line.newLineNumber
        }()
        return Text(number.map(String.init) ?? "")
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg4)
            .frame(width: 44, alignment: .trailing)
            .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var displayContent: String {
        guard let line, !line.content.isEmpty else { return " " }
        return line.content
    }

    private var sign: String {
        guard let line else { return " " }
        switch line.kind {
        case .added:    return side == .right ? "+" : " "
        case .removed:  return side == .left  ? "−" : " "
        case .context:  return " "
        case .noNewline: return "\\"
        }
    }

    private var signColor: Color {
        guard let line else { return .clear }
        switch line.kind {
        case .added:    return theme.palette.add
        case .removed:  return theme.palette.del
        case .context:  return theme.palette.fg3
        case .noNewline: return theme.palette.fg3
        }
    }

    private var textColor: Color {
        guard let line else { return .clear }
        switch line.kind {
        case .added:   return theme.palette.add
        case .removed: return theme.palette.del
        default:       return theme.palette.fg2
        }
    }

    /// Standard split-diff convention: nil cells render as a muted gray
    /// "this line doesn't exist here" indicator — subtler than tinting them
    /// like a change so the actual changes still pop.
    private var background: Color {
        guard let line else { return theme.palette.bg3.opacity(0.5) }
        switch line.kind {
        case .added:   return theme.palette.addSoft
        case .removed: return theme.palette.delSoft
        default:       return .clear
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let sample = DiffHunk.previewSamples[0].lines
    Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
        ForEach(sample) { line in
            GridRow {
                DiffSplitCell(line: line, side: .left,  attributed: nil)
                Rectangle().fill(theme.palette.line).frame(width: 1)
                DiffSplitCell(line: line, side: .right, attributed: nil)
            }
        }
    }
    .frame(width: 720)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
