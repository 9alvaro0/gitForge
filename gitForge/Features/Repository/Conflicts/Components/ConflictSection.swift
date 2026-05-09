import SwiftUI

/// Pick button lives in the section header so the action is always
/// reachable, regardless of how far the user has scrolled the lines below.
struct ConflictSection: View {
    let title: String
    let subtitle: String
    let lines: [String]
    let tagColor: Color
    let rowBackground: Color
    let isPicked: Bool
    /// `nil` for read-only sections like the result preview.
    var actionLabel: String? = nil
    var onPick: (() -> Void)? = nil
    var emptyMessage: String = "(no lines on this side)"

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            sectionHeader
            content
        }
        .background(theme.palette.bg1)
        .overlay(alignment: .leading) {
            if isPicked {
                Rectangle().fill(tagColor).frame(width: 3)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(AppFont.mono(10.5, weight: .medium, family: theme.monoFont))
                .foregroundStyle(tagColor)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.hairline)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(tagColor.opacity(DesignTokens.Opacity.muted)))
            Text(subtitle)
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            Spacer()
            if let actionLabel, let onPick {
                Button(action: onPick) {
                    Text(actionLabel)
                        .font(AppFont.sans(11.5, weight: .medium))
                        .foregroundStyle(isPicked ? .white : tagColor)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .fill(isPicked ? tagColor : tagColor.opacity(DesignTokens.Opacity.subtle)))
                        .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    @ViewBuilder
    private var content: some View {
        if lines.isEmpty {
            Text(emptyMessage)
                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .italic()
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        ConflictLineRow(lineNumber: index + 1, content: line, background: rowBackground)
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ConflictSection(
        title: "ours",
        subtitle: "main",
        lines: ConflictHunk.previewSamples[0].ours,
        tagColor: theme.palette.add,
        rowBackground: theme.palette.addSoft,
        isPicked: true,
        actionLabel: "Pick ours",
        onPick: {}
    )
    .frame(width: 560)
    .appTheme(theme)
}
