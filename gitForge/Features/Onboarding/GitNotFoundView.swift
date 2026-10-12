import SwiftUI

/// Post-onboarding gate: shown when `gitEnvironment.gitStatus == .notFound`
/// after the user has already finished the initial flow (e.g. they
/// uninstalled git later). Shares `GitInstallPrompt` with `GitStep` so both
/// entry points look and behave the same.
struct GitNotFoundView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        GitInstallPrompt()
            .frame(maxWidth: 480)
            .padding(Spacing.s48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.bgContent)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    GitNotFoundView()
        .previewAppState(.previewMissingGit)
        .frame(width: 720, height: 480)
        .appTheme(theme)
}
