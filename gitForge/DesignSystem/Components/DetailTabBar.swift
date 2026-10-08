import SwiftUI

/// A tab of a detail pane (stash, pull request…): every case, in order,
/// with its visible label.
protocol DetailTab: Hashable, CaseIterable {
    var label: String { get }
}

/// Segmented tab strip under a detail header, with a trailing spinner while
/// the pane loads. Shared by the stash and pull-request detail views, which
/// used to carry identical copies.
struct DetailTabBar<Tab: DetailTab>: View {
    @Binding var tab: Tab
    let loading: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            SegmentedControl<Tab>(Tab.allCases.map { ($0, $0.label) }, selection: $tab)
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
    DetailTabBar(tab: $tab, loading: true)
        .frame(width: 1100)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
