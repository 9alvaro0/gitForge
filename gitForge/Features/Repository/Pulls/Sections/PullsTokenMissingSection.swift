import SwiftUI

/// No credential for this repo's host (spec §7.4): connect an account, or
/// reconnect the one whose token was rejected.
struct PullsTokenMissingSection: View {
    let host: RemoteHost?
    let nounPlural: String
    let reconnect: Bool
    let onConnect: () -> Void
    let onOpenAccounts: () -> Void

    var body: some View {
        let provider = host?.provider.label ?? String(localized: "hosting")
        let hostName = host?.host ?? String(localized: "the host")
        EmptyState(
            symbol: "arrow.triangle.pull",
            title: reconnect ? String(localized: "Reconnect your \(provider) account")
                             : String(localized: "Connect a \(provider) account"),
            subtitle: reconnect
                ? String(localized: "The account's token was rejected. Sign in again to list \(nounPlural).")
                : String(localized: "Sign in to \(hostName) to list \(nounPlural) and push over HTTPS.")
        ) {
            HStack(spacing: Spacing.s8) {
                GFButton(title: reconnect ? String(localized: "Reconnect…") : String(localized: "Connect account…"),
                         style: .primary, action: onConnect)
                GFButton(title: String(localized: "Open Accounts"), action: onOpenAccounts)
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
        onConnect: {}, onOpenAccounts: {}
    )
    .padding()
    .frame(width: 800, height: 400)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
