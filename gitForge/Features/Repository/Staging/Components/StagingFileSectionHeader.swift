import SwiftUI

/// Header above the Staged / Unstaged blocks. The action button (e.g. "Stage
/// all") is optional so the loading-skeleton can reuse the same header
/// without an active button.
struct StagingFileSectionHeader: View {
    let title: String
    let count: Int
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(title.uppercased())
                    .font(AppFont.mono(10.5, family: theme.monoFont))
                    .tracking(0.6)
                Text("(\(count))")
                    .font(AppFont.mono(10.5, family: theme.monoFont))
            }
            .foregroundStyle(theme.palette.fg3)
            Spacer()
            if let actionLabel, let onAction {
                Button(action: onAction) {
                    Text(actionLabel)
                        .font(AppFont.mono(10.5, family: theme.monoFont))
                        .foregroundStyle(theme.palette.accent)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .contentShape(.rect(cornerRadius: DesignTokens.Radius.xs))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 0) {
        StagingFileSectionHeader(title: "Staged", count: 3, actionLabel: "Unstage all", onAction: {})
        StagingFileSectionHeader(title: "Unstaged", count: 7, actionLabel: "Stage all", onAction: {})
        StagingFileSectionHeader(title: "Staged", count: 0)
    }
    .frame(width: 360)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
