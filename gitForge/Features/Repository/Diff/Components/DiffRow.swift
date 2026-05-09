import SwiftUI

/// Wrapping vs. horizontal-overflow is driven by the user's
/// `diffWrapLongLines` setting.
struct DiffRow: View {
    let line: DiffLine
    /// Pre-tokenised attributed string for this line. When present, the row
    /// trusts its embedded foreground colours and skips the kind-based
    /// `textColor` tint — the +/− sign column and `rowBackground` already
    /// signal added/removed without overpainting the syntax tokens.
    let attributed: AttributedString?

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: theme.diffWrapLongLines ? .top : .center, spacing: DesignTokens.Spacing.none) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)
            Text(sign)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .frame(width: DesignTokens.IconSize.xl)
                .foregroundStyle(signColor)
            wrappedContent
            if !theme.diffWrapLongLines { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }

    /// Toggle between horizontal-overflow (default, matches Tower/GitHub) and
    /// soft-wrap when the user opts in via Settings → Appearance.
    @ViewBuilder
    private var wrappedContent: some View {
        if theme.diffWrapLongLines {
            content
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, DesignTokens.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, DesignTokens.Spacing.xxl)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let attributed {
            Text(attributed)
        } else {
            Text(line.content.isEmpty ? " " : line.content)
                .foregroundStyle(textColor)
        }
    }

    @ViewBuilder
    private func lineNumber(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(AppFont.mono(11, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg4)
            .frame(width: 44, alignment: .trailing)
            .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var sign: String {
        switch line.kind {
        case .added:    return "+"
        case .removed:  return "−"
        case .context:  return " "
        case .noNewline: return "\\"
        }
    }
    private var signColor: Color {
        switch line.kind {
        case .added:    return theme.palette.add
        case .removed:  return theme.palette.del
        case .context:  return theme.palette.fg3
        case .noNewline: return theme.palette.fg3
        }
    }
    private var textColor: Color {
        switch line.kind {
        case .added:   return theme.palette.add
        case .removed: return theme.palette.del
        default:       return theme.palette.fg2
        }
    }
    private var rowBackground: Color {
        switch line.kind {
        case .added:   return theme.palette.addSoft
        case .removed: return theme.palette.delSoft
        default:       return .clear
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 0) {
        ForEach(DiffHunk.previewSamples[0].lines) { line in
            DiffRow(line: line, attributed: nil)
        }
    }
    .frame(width: 640)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
