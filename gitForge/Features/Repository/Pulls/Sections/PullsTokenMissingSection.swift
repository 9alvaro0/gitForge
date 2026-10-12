import SwiftUI

/// No credential for this repo's host (spec §7.4): connect an account, or
/// reconnect the one whose token was rejected.
struct PullsTokenMissingSection: View {
    let host: RemoteHost?
    let nounPlural: String
    let reconnect: Bool
    let onConnect: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let provider = host?.provider.label ?? "hosting"
        EmptyState(
            symbol: "arrow.triangle.pull",
            title: reconnect ? "Reconnect your \(provider) account" : "Connect a \(provider) account",
            subtitle: reconnect
                ? "The account's token was rejected. Sign in again to list \(nounPlural)."
                : "Sign in to \(host?.host ?? "the host") to list \(nounPlural) and push over HTTPS."
        ) {
            HStack(spacing: Spacing.s8) {
                GFButton(title: reconnect ? "Reconnect…" : "Connect account…", style: .primary, action: onConnect)
                GFButton(title: "Open Settings", action: onOpenSettings)
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullsTokenMissingSection(
        host: .previewGitHub,
        nounPlural: "pull requests",
        reconnect: false,
        onConnect: {}, onOpenSettings: {}
    )
    .padding()
    .frame(width: 800, height: 400)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
