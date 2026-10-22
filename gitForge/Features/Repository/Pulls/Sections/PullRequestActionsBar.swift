import SwiftUI

/// Request changes / Approve / Merge… in the detail header. The review
/// buttons open a panel for the comment; Merge… opens the merge sheet, only
/// active when the host says it can merge. `compact` (the header is too
/// narrow) folds the review buttons into a "Review" menu rather than
/// cutting their titles.
///
/// The header lays the bar out in several variants, each its own view with
/// its own state, so neither the open panel nor the popover live here: the
/// panel is the store's, and the detail shows it over the bar on screen
/// (`ReviewPanelAnchor`), so a relayout doesn't close it.
struct PullRequestActionsBar: View {
    let store: PullRequestStore
    var compact = false
    /// Opens the merge sheet, which the detail owns so a header relayout
    /// can't close it.
    var onMerge: () -> Void = {}

    var body: some View {
        let actions = store.reviewActions
        if actions != .hidden || showsMerge {
            HStack(spacing: Spacing.s8) {
                if !compact {
                    requestChangesButton(actions.requestChanges)
                    approveButton(actions.approve)
                } else if actions != .hidden {
                    reviewMenu(actions)
                }
                mergeButton
            }
            // Only the variant on screen reports where it is.
            .anchorPreference(key: ReviewPanelAnchor.self, value: .bounds) { $0 }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private func requestChangesButton(_ state: ReviewActions.RequestChanges) -> some View {
        switch state {
        case .hidden:
            EmptyView()
        case .available:
            GFButton(title: String(localized: "Request changes"), disabled: busy) { store.reviewPanel = .requestChanges }
        case .unavailable(let reason):
            GFButton(title: String(localized: "Request changes"), disabled: true) {}
                .help(reason)
        }
    }

    @ViewBuilder
    private func approveButton(_ state: ReviewActions.Approve) -> some View {
        switch state {
        case .hidden:
            EmptyView()
        case .available:
            GFButton(title: String(localized: "Approve"), systemImage: "checkmark", disabled: busy) { store.reviewPanel = .approve }
        case .approved:
            GFButton(title: String(localized: "Approved"), systemImage: "checkmark", disabled: true) {}
        }
    }

    private func reviewMenu(_ actions: ReviewActions) -> some View {
        Menu {
            switch actions.approve {
            case .hidden: EmptyView()
            case .available: Button("Approve…") { presentFromMenu(.approve) }
            case .approved: Button("Approved") {}.disabled(true)
            }
            switch actions.requestChanges {
            case .hidden: EmptyView()
            case .available: Button("Request changes…") { presentFromMenu(.requestChanges) }
            case .unavailable(let reason): Button("Request changes (\(reason))") {}.disabled(true)
            }
        } label: {
            ReviewMenuLabel(disabled: busy)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(busy)
    }

    private var busy: Bool { store.isReviewBusy }

    // MARK: Merge

    /// Merge… is there while the PR is open or a draft, yours or not.
    private var showsMerge: Bool {
        guard let pull = store.selected else { return false }
        let state = store.detail?.pull.id == pull.id ? (store.detail?.pull.state ?? pull.state) : pull.state
        return state == .open || state == .draft
    }

    @ViewBuilder
    private var mergeButton: some View {
        if showsMerge {
            GFButton(title: String(localized: "Merge…"), style: .primary,
                     disabled: store.mergeBlockedReason != nil || store.isMerging, action: onMerge)
                .help(mergeHelp)
        }
    }

    /// Why it can't merge, as the banner says; otherwise (or while the
    /// detail loads) what it does.
    private var mergeHelp: String {
        if store.mergeReadiness != nil, let reason = store.mergeBlockedReason { return reason }
        return store.host?.provider == .gitlab ? String(localized: "Merge this merge request")
                                               : String(localized: "Merge this pull request")
    }

    /// A menu item's action runs while the menu is still closing, and a
    /// popover asked for in that moment never shows: open it on the next turn.
    private func presentFromMenu(_ verdict: ReviewVerdict) {
        let store = store
        DispatchQueue.main.async { store.reviewPanel = verdict }
    }
}

/// "Review ⌄" drawn like a secondary `GFButton`, as the menu's label.
private struct ReviewMenuLabel: View {
    let disabled: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        HStack(spacing: Spacing.s6) {
            Text("Review")
                .textRole(.callout, weight: .semibold)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .lineLimit(1)
        .foregroundStyle(disabled ? theme.colors.textQuaternary : theme.colors.textPrimary)
        .padding(.horizontal, 14)
        .frame(height: theme.density.metrics.buttonRegular)
        .background(shape.fill(theme.colors.fillControl))
        .overlay(shape.strokeBorder(disabled ? .clear : theme.colors.strokeControl, lineWidth: 1))
        .contentShape(shape)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    PullRequestActionsBar(store: .previewWithDetail)
        .padding()
        .previewAppState(.preview)
        .appTheme(theme)
}
