import SwiftUI

/// Each `DiffEmptyState` branch tells the user *why* there's nothing to
/// render so a binary or pure rename doesn't read as "the app forgot to
/// load my changes".
struct DiffEmptyContent: View {
    let state: DiffEmptyState

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Text(copy.title)
                .font(AppFont.sans(12.5, weight: .semibold))
                .foregroundStyle(theme.palette.fg2)
            if let subtitle = copy.subtitle {
                Text(subtitle)
                    .font(AppFont.sans(11.5))
                    .foregroundStyle(theme.palette.fg3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var copy: (title: String, subtitle: String?) {
        switch state {
        case .empty:
            return ("No changes", nil)
        case .binary:
            return ("Binary file", "Diff isn't rendered for non-text content.")
        case .untrackedBinary:
            return ("New binary file",
                    "This file is untracked and isn't text — open it in an external app to inspect it.")
        case .renameOnly:
            return ("Renamed", "The file was moved without content changes.")
        }
    }
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .empty)
        .frame(width: 520, height: 200)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Binary") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .binary)
        .frame(width: 520, height: 200)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Untracked binary") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .untrackedBinary)
        .frame(width: 520, height: 200)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Rename only") {
    @Previewable @State var theme = AppTheme()
    DiffEmptyContent(state: .renameOnly)
        .frame(width: 520, height: 200)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
