import SwiftUI

/// Request changes / Approve / Merge… in the detail header. The review
/// buttons open a panel for the comment; Merge… opens the merge sheet, only
/// active when the host says it can merge. `compact` (the header is too
/// narrow) folds the review buttons into a "Review" menu rather than
/// cutting their titles.
struct PullRequestActionsBar: View {
    let store: PullRequestStore
    var compact = false
    /// Opens the merge sheet, which the detail owns so a header relayout
    /// can't close it.
    var onMerge: () -> Void = {}

    @Environment(AppState.self) private var appState
    @State private var openPanel: ReviewVerdict?

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
            .popover(isPresented: panelShown, arrowEdge: .bottom) {
                if let verdict = openPanel { panel(verdict) }
            }
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private func requestChangesButton(_ state: ReviewActions.RequestChanges) -> some View {
        switch state {
        case .hidden:
            EmptyView()
        case .available:
            GFButton(title: String(localized: "Request changes"), disabled: busy) { openPanel = .requestChanges }
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
            GFButton(title: String(localized: "Approve"), systemImage: "checkmark", disabled: busy) { openPanel = .approve }
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

    private var busy: Bool { store.submittingReview != nil }

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
            let canMerge = store.mergeReadiness?.canMerge ?? false
            GFButton(title: String(localized: "Merge…"), style: .primary, disabled: !canMerge || store.isMerging,
                     action: onMerge)
                .help(mergeHelp(canMerge: canMerge))
        }
    }

    /// Why it can't merge, as the banner says; otherwise what it does.
    private func mergeHelp(canMerge: Bool) -> String {
        if !canMerge, let summary = store.mergeReadiness?.summary { return summary }
        return store.host?.provider == .gitlab ? String(localized: "Merge this merge request")
                                               : String(localized: "Merge this pull request")
    }

    /// A menu item's action runs while the menu is still closing, and a
    /// popover asked for in that moment never shows: open it on the next turn.
    private func presentFromMenu(_ verdict: ReviewVerdict) {
        DispatchQueue.main.async { openPanel = verdict }
    }

    private var panelShown: Binding<Bool> {
        Binding(get: { openPanel != nil }, set: { if !$0 { openPanel = nil } })
    }

    // MARK: Panel

    private func panel(_ verdict: ReviewVerdict) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text(panelTitle(verdict))
                .textRole(.body, weight: .semibold)
            ReviewComposer(
                text: store.draftBinding(.review(pullId: store.selected?.id ?? "", verdict)),
                placeholder: verdict == .approve ? String(localized: "Comment (optional)")
                                                 : String(localized: "What needs to change (required)"),
                sendTitle: verdict == .approve ? String(localized: "Approve") : String(localized: "Request changes"),
                sendStyle: verdict == .approve ? .primary : .destructive,
                requiresText: verdict == .requestChanges,
                sending: store.submittingReview == verdict,
                onSend: { submit(verdict) },
                onCancel: { openPanel = nil }
            )
        }
        .padding(Spacing.s16)
        .frame(width: 380)
    }

    private var reference: String {
        guard let number = store.selected?.number else { return "" }
        return store.host?.provider.reference(number) ?? "#\(number)"
    }

    private func panelTitle(_ verdict: ReviewVerdict) -> String {
        verdict == .approve ? String(localized: "Approve \(reference)") : String(localized: "Request changes on \(reference)")
    }

    /// The toast names the PR the review went to, read before the await.
    /// A verdict that landed without its comment gets a lasting toast that
    /// can copy the comment, since its panel may not open again.
    private func submit(_ verdict: ReviewVerdict) {
        let done = verdict == .approve ? String(localized: "Approved \(reference)")
                                       : String(localized: "Requested changes on \(reference)")
        let comment = store.drafts[.review(pullId: store.selected?.id ?? "", verdict)] ?? ""
        Task {
            switch await store.submitReview(verdict) {
            case .submitted(let warning?):
                openPanel = nil
                appState.ui.activeToast = ToastMessage(
                    message: warning, kind: .error,
                    action: ToastAction(title: String(localized: "Copy comment"), route: .copyText(comment)))
            case .submitted(nil):
                openPanel = nil
                appState.ui.activeToast = ToastMessage(message: done, kind: .ok)
            case .failed(let message):
                appState.ui.activeToast = ToastMessage(message: message, kind: .error)
            case .ignored:
                break
            }
        }
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
