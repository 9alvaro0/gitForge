import SwiftUI

/// A thread wired to the store: its reply draft, the open box, sending and
/// resolving, and the toast when the host says no. Reads the store in its
/// own body, so typing or sending doesn't redraw the diff around it.
struct ReviewThreadCard: View {
    let store: PullRequestStore
    let thread: ReviewThread
    var header: String? = nil

    @Environment(AppState.self) private var appState

    var body: some View {
        let key = ReviewDraftKey.reply(pullId: store.selected?.id ?? "", threadId: thread.id)
        ReviewThreadView(thread: thread, header: header, replyText: store.draftBinding(key),
                         isReplying: store.replyingThreadId == thread.id,
                         sending: store.sendingDraft == key,
                         resolving: store.resolvingThreadId == thread.id,
                         onStartReply: { store.replyingThreadId = thread.id },
                         onCancelReply: { store.replyingThreadId = nil },
                         onReply: reply,
                         onToggleResolved: toggleResolved)
    }

    private func reply() {
        Task { appState.ui.show(await store.reply(to: thread)) }
    }

    private func toggleResolved() {
        Task { appState.ui.show(await store.setResolved(!thread.isResolved, thread: thread)) }
    }

    /// Where a thread that isn't under its line was left: "Outdated · line 9".
    static func header(for thread: ReviewThread) -> String? {
        let line = thread.originalLine ?? thread.ref?.line
        switch (thread.isOutdated, line) {
        case (true, let line?): return String(localized: "Outdated · line \(line)")
        case (true, nil): return String(localized: "Outdated")
        case (false, let line?): return String(localized: "line \(line)")
        case (false, nil): return nil
        }
    }
}

/// What goes under one diff row: its threads, then the new-comment box if
/// it's open on that line.
struct DiffLineThreads: View {
    let store: PullRequestStore
    let path: String
    let refs: [DiffLineRef]

    var body: some View {
        let threads = refs.flatMap { store.placedThreads.inline[path]?[$0] ?? [] }
        let composer = store.composerTarget.flatMap { $0.path == path && refs.contains($0.ref) ? $0 : nil }
        VStack(alignment: .leading, spacing: Spacing.s8) {
            ForEach(threads) { thread in
                ReviewThreadCard(store: store, thread: thread)
            }
            if let composer {
                NewCommentBox(store: store, target: composer)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
    }
}

/// The box a new line comment is written in.
struct NewCommentBox: View {
    let store: PullRequestStore
    let target: CommentTarget

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    var body: some View {
        let key = ReviewDraftKey.comment(pullId: store.selected?.id ?? "", target: target)
        ReviewComposer(text: store.draftBinding(key),
                       placeholder: String(localized: "Comment on line \(target.ref.line)…"),
                       sendTitle: String(localized: "Comment"), requiresText: true,
                       sending: store.sendingDraft == key,
                       onSend: send, onCancel: { store.composerTarget = nil })
            .padding(Spacing.s12)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.bgElevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(theme.colors.separator, lineWidth: 1))
    }

    private func send() {
        Task { appState.ui.show(await store.addComment(at: target)) }
    }
}

extension WorkspaceUI {
    /// A thread action's outcome: a warning when the host had moved on (and
    /// it was reloaded), an error when it refused; nothing when it worked.
    func show(_ result: ThreadActionResult) {
        switch result {
        case .changedOnHost(let message): activeToast = ToastMessage(message: message, kind: .warn)
        case .failed(let message): activeToast = ToastMessage(message: message, kind: .error)
        case .done, .ignored: break
        }
    }
}
