import SwiftUI

/// One unified-diff line: old and new numbers, sign, code. Wrapping vs.
/// horizontal overflow is driven by the user's `diffWrapLongLines` setting.
struct DiffRow: View {
    let line: DiffLine
    /// Pre-tokenised attributed string for this line. When present its
    /// embedded colours win; plain runs fall back to the syntax `plain`.
    let attributed: AttributedString?

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    var body: some View {
        let wrap = preferences.diffWrapLongLines
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            DiffLineNumber(number: line.oldLineNumber, width: DiffGutter.unifiedNumber)
            DiffLineNumber(number: line.newLineNumber, width: DiffGutter.unifiedNumber)
            DiffSign(kind: line.kind, width: DiffGutter.unifiedSign)
            DiffCode(line: line, attributed: attributed)
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: !wrap, vertical: wrap)
                .padding(.trailing, Spacing.s12)
                .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
            if !wrap { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, minHeight: theme.density.metrics.diffLine, alignment: .leading)
        .background(DiffTint.row(line.kind, colors: theme.colors))
    }
}

/// Gutter widths shared by unified rows, split cells and the skeleton.
enum DiffGutter {
    static let unifiedNumber: CGFloat = 34
    static let unifiedSign: CGFloat = 16
    static let splitNumber: CGFloat = 36
    static let splitSign: CGFloat = 18
    static let numberTrailing: CGFloat = Spacing.s6
}

enum DiffTint {
    static func row(_ kind: DiffLine.Kind, colors: GFColors) -> Color {
        switch kind {
        case .added: colors.addSoft
        case .removed: colors.delSoft
        case .context, .noNewline: .clear
        }
    }

    static func sign(_ kind: DiffLine.Kind, colors: GFColors) -> Color {
        switch kind {
        case .added: colors.add
        case .removed: colors.del
        case .context, .noNewline: colors.textQuaternary
        }
    }
}

struct DiffLineNumber: View {
    let number: Int?
    let width: CGFloat

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(number.map(String.init) ?? "")
            .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
            .foregroundStyle(theme.colors.textQuaternary)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, DiffGutter.numberTrailing)
    }
}

struct DiffSign: View {
    let kind: DiffLine.Kind
    let width: CGFloat

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(symbol)
            .font(AppFont.font(.mono, weight: .bold, monoFamily: theme.monoFont))
            .foregroundStyle(DiffTint.sign(kind, colors: theme.colors))
            .frame(width: width)
    }

    private var symbol: String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        case .noNewline: "\\"
        }
    }
}

/// The code itself: highlighted runs when tokenised, otherwise the line in
/// the syntax `plain` colour (the row tint and sign already carry +/−, so
/// nothing flashes green or red while highlighting settles).
struct DiffCode: View {
    let line: DiffLine
    let attributed: AttributedString?

    @Environment(\.appTheme) private var theme

    var body: some View {
        if let attributed {
            // Highlighted runs carry their own colours; a foregroundStyle here
            // would paint over them.
            Text(attributed)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
        } else {
            Text(line.content.isEmpty ? " " : line.content)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                .foregroundStyle(plainColor)
        }
    }

    private var plainColor: Color {
        line.kind == .noNewline
            ? theme.colors.textQuaternary
            : Color(hex: SyntaxPalette.make(theme.variant).plain)
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
    .background(theme.colors.bgCode)
    .appTheme(theme)
}
