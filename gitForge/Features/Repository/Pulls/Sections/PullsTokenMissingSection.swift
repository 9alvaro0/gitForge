import SwiftUI

struct PullsTokenMissingSection: View {
    let host: RemoteHost?
    let nounPlural: String
    let onAddToken: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        if let host {
            EmptyState(
                icon: .pr,
                title: "\(host.provider.label) token required",
                subtitle: "No token stored for \(host.host). Add a Personal Access Token to list \(nounPlural)."
            ) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    GFButton(title: "Add token…", style: .primary, action: onAddToken)
                    GFButton(title: "Open Settings", action: onOpenSettings)
                }
            }
        } else {
            EmptyState(
                icon: .pr,
                title: "Token required",
                subtitle: "Add a Personal Access Token in Settings → Remote hosts."
            ) { EmptyView() }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullsTokenMissingSection(
        host: RemoteHost(provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge"),
        nounPlural: "pull requests",
        onAddToken: {}, onOpenSettings: {}
    )
    .padding()
    .frame(width: 800, height: 400)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
