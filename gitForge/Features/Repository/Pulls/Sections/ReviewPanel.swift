import SwiftUI

/// Where the review buttons are: reported by the actions bar the header
/// shows (its other layout variants don't report), read by `ReviewPanelHost`.
struct ReviewPanelAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Shows the store's review panel as a popover over the review buttons.
/// It sits over the whole header and stays put when the header switches
/// layout, so the panel follows the buttons instead of closing.
struct ReviewPanelHost: View {
    let store: PullRequestStore
    let anchor: Anchor<CGRect>?

    var body: some View {
        GeometryReader { proxy in
            let rect = anchor.map { proxy[$0] } ?? .zero
            Color.clear
                .frame(width: rect.width, height: rect.height)
                .popover(isPresented: shown, arrowEdge: .bottom) {
                    if let verdict = store.reviewPanel { ReviewPanel(store: store, verdict: verdict) }
                }
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private var shown: Binding<Bool> {
        let store = store
        return Binding(get: { store.reviewPanel != nil }, set: { if !$0 { store.reviewPanel = nil } })
    }
}

/// Approve or Request changes on the selected PR, with its comment.
struct ReviewPanel: View {
    let store: PullRequestStore
    let verdict: ReviewVerdict

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text(title)
                .textRole(.body, weight: .semibold)
            ReviewComposer(
                text: store.draftBinding(.review(pullId: store.selected?.id ?? "", verdict)),
                placeholder: verdict == .approve ? String(localized: "Comment (optional)")
                                                 : String(localized: "What needs to change (required)"),
                sendTitle: verdict == .approve ? String(localized: "Approve") : String(localized: "Request changes"),
                sendStyle: verdict == .approve ? .primary : .destructive,
                requiresText: verdict == .requestChanges,
                sending: store.submittingReview == verdict,
                onSend: submit,
                onCancel: { store.reviewPanel = nil }
            )
        }
        .padding(Spacing.s16)
        .frame(width: 380)
    }

    private var reference: String {
        guard let number = store.selected?.number else { return "" }
        return store.host?.provider.reference(number) ?? "#\(number)"
    }

    private var title: String {
        verdict == .approve ? String(localized: "Approve \(reference)") : String(localized: "Request changes on \(reference)")
    }

    /// The toast names the PR the review went to, read before the await; the
    /// store closes the panel once the review lands. A verdict that landed
    /// without its comment gets a lasting toast that can copy the comment,
    /// since its panel may not open again.
    private func submit() {
        let verdict = verdict
        let done = verdict == .approve ? String(localized: "Approved \(reference)")
                                       : String(localized: "Requested changes on \(reference)")
        let comment = store.drafts[.review(pullId: store.selected?.id ?? "", verdict)] ?? ""
        Task {
            switch await store.submitReview(verdict) {
            case .submitted(let warning?):
                appState.ui.activeToast = ToastMessage(
                    message: warning, kind: .error,
                    action: ToastAction(title: String(localized: "Copy comment"), route: .copyText(comment)))
            case .submitted(nil):
                appState.ui.activeToast = ToastMessage(message: done, kind: .ok)
            case .failed(let message):
                appState.ui.activeToast = ToastMessage(message: message, kind: .error)
            case .ignored:
                break
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ReviewPanel(store: .previewWithDetail, verdict: .requestChanges)
        .previewAppState(.preview)
        .appTheme(theme)
}
