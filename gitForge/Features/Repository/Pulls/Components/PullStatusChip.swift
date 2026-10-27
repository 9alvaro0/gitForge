import SwiftUI

extension GFColors {
    /// A row verdict's colour and its soft fill.
    func tone(_ tone: PullStatusTone) -> (fg: Color, soft: Color) {
        switch tone {
        case .ok: (ok, okSoft)
        case .info: (info, infoSoft)
        case .warn: (warn, warnSoft)
        case .danger: (del, delSoft)
        case .neutral: (textTertiary, fillControl)
        }
    }
}

/// A row's verdict (`PullListStatus`) as a capsule with glyph and word,
/// tinted by its tone; the help says what it means.
struct PullStatusChip: View {
    let status: PullListStatus

    @Environment(\.appTheme) private var theme

    var body: some View {
        let colors = theme.colors.tone(status.tone)
        HStack(spacing: Spacing.s4) {
            Image(systemName: status.symbol)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(status.label)
                .textRole(.caption, weight: .semibold)
                .lineLimit(1)
                // Shortened rather than run under what follows it on a
                // narrow row; the help still has it whole.
                .truncationMode(.tail)
        }
        .foregroundStyle(colors.fg)
        .padding(.horizontal, Spacing.s6)
        .frame(height: 18)
        .background(Capsule().fill(colors.soft))
        .fixedSize(horizontal: false, vertical: true)
        .help(status.help)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: Spacing.s8) {
        ForEach(PullListStatus.Kind.allCases, id: \.self) { kind in
            PullStatusChip(status: PullListStatus(kind: kind, hostCode: kind == .blocked ? "blocked_status" : nil))
        }
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
