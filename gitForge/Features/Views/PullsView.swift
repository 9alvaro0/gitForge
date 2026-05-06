import SwiftUI

/// `.gf-view-pulls` — pull/merge request list. Real integrations (GitHub /
/// GitLab / Bitbucket) aren't implemented yet, so the view advertises that
/// honestly instead of showing fake rows.
struct PullsView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Pull requests") {
                MonoText("not connected", dim: true)
            } right: {
                EmptyView()
            }
            EmptyState(
                icon: .pr,
                title: "Connect a host to see pull requests",
                subtitle: "GitHub, GitLab and Bitbucket integrations aren't wired yet. They'll show up here when they are."
            ) { EmptyView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullsView()
        .frame(width: 1100, height: 700)
        .appTheme(theme)
}
