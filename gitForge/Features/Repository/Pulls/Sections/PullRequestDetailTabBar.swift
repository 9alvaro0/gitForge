import SwiftUI

struct PullRequestDetailTabBar: View {
    @Binding var tab: PullRequestDetailView.Tab
    let loading: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            SegmentedControl<PullRequestDetailView.Tab>(
                PullRequestDetailView.Tab.allCases.map { ($0, $0.label) },
                selection: $tab
            )
            Spacer()
            if loading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxxl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var tab: PullRequestDetailView.Tab = .overview
    PullRequestDetailTabBar(tab: $tab, loading: true)
        .frame(width: 1100)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
