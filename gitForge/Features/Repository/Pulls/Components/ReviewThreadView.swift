import SwiftUI

/// A review thread as a card: its comments, a reply box and Resolve. A
/// resolved thread folds into one line until the user shows it.
struct ReviewThreadView: View {
    let thread: ReviewThread
    /// Shown above the comments ("Outdated · line 9") when the thread isn't
    /// under its line.
    var header: String? = nil
    @Binding var replyText: String
    /// The store's open box is this thread's.
    let isReplying: Bool
    let sending: Bool
    let resolving: Bool
    let onStartReply: () -> Void
    let onCancelReply: () -> Void
    let onReply: () -> Void
    let onToggleResolved: () -> Void
    /// Whether the reply box takes the focus as it comes on screen, and
    /// told when it leaves (`ReviewComposer`).
    var claimsFocus: () -> Bool = { true }
    var onReplyLeave: (_ hadFocus: Bool) -> Void = { _ in }

    @Environment(\.appTheme) private var theme
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            if let header {
                headerLabel(header)
            }
            if isOpen {
                if thread.isResolved { resolvedBar(folding: true) }
                ForEach(thread.comments) { comment in
                    ReviewCommentView(comment: comment)
                }
                footer
            } else {
                resolvedBar(folding: false)
            }
        }
        .padding(Spacing.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.bgElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(theme.colors.separator, lineWidth: 1))
    }

    /// A box being written stays visible, folded or not.
    private var isOpen: Bool { !thread.isResolved || expanded || isReplying }

    private func headerLabel(_ text: String) -> some View {
        HStack(spacing: Spacing.s4) {
            if thread.isOutdated {
                Image(systemName: "clock.arrow.circlepath")
            }
            Text(text)
        }
        .textRole(.caption, weight: .semibold)
        .foregroundStyle(thread.isOutdated ? theme.colors.warn : theme.colors.textTertiary)
    }

    /// "Resolved by marta · 2 comments", with Show (folded) or Hide.
    private func resolvedBar(folding: Bool) -> some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.colors.ok)
            Text(resolvedSummary)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !isReplying {
                GFButton(title: folding ? String(localized: "Hide") : String(localized: "Show"), size: .small) {
                    expanded = !folding
                }
            }
        }
    }

    private var resolvedSummary: String {
        let count = thread.comments.count
        if let by = thread.resolvedBy {
            return count == 1 ? String(localized: "Resolved by \(by) · 1 comment")
                              : String(localized: "Resolved by \(by) · \(count) comments")
        }
        return count == 1 ? String(localized: "Resolved · 1 comment") : String(localized: "Resolved · \(count) comments")
    }

    @ViewBuilder
    private var footer: some View {
        if isReplying {
            ReviewComposer(text: $replyText, placeholder: String(localized: "Reply…"), sendTitle: String(localized: "Reply"),
                           requiresText: true, sending: sending, claimsFocus: claimsFocus, onLeave: onReplyLeave,
                           onSend: onReply, onCancel: onCancelReply)
        } else {
            HStack(spacing: Spacing.s8) {
                if thread.canReply {
                    ReplyField(text: $replyText, onTap: onStartReply)
                } else {
                    Spacer(minLength: 0)
                }
                resolveButton
            }
        }
    }

    @ViewBuilder
    private var resolveButton: some View {
        if !thread.isResolved, thread.canResolve {
            GFButton(title: String(localized: "Resolve"), systemImage: "checkmark", size: .small, disabled: resolving,
                     action: onToggleResolved)
        } else if thread.isResolved, thread.canUnresolve {
            GFButton(title: String(localized: "Unresolve"), size: .small, disabled: resolving, action: onToggleResolved)
        }
    }
}

/// Looks like the box it opens; a draft left in it shows as its first line.
/// Its own view, reading only its own draft: typing in another box doesn't
/// redraw it, and typing in this one redraws only this line.
private struct ReplyField: View {
    @Binding var text: String
    let onTap: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            Text(text.isEmpty ? String(localized: "Reply…") : text)
                .textRole(.body)
                .foregroundStyle(text.isEmpty ? theme.colors.textTertiary : theme.colors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(theme.colors.strokeControl, lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reply")
    }
}

#Preview("Open, resolved, outdated") {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var text = ""
    VStack(spacing: Spacing.s12) {
        ReviewThreadView(thread: .previewOpen, replyText: $text, isReplying: false, sending: false, resolving: false,
                         onStartReply: {}, onCancelReply: {}, onReply: {}, onToggleResolved: {})
        ReviewThreadView(thread: .previewResolved, replyText: $text, isReplying: false, sending: false, resolving: false,
                         onStartReply: {}, onCancelReply: {}, onReply: {}, onToggleResolved: {})
        ReviewThreadView(thread: .previewOutdated, header: "Outdated · line 9", replyText: $text, isReplying: true,
                         sending: false, resolving: false,
                         onStartReply: {}, onCancelReply: {}, onReply: {}, onToggleResolved: {})
    }
    .padding()
    .frame(width: 560)
    .background(theme.colors.bgCode)
    .appTheme(theme)
}
