import SwiftUI

/// A comment box with Cancel and a send button: ⌘↩ sends, Esc cancels.
/// Shared by the review panels and, later, thread replies and new comments.
struct ReviewComposer: View {
    @Binding var text: String
    let placeholder: String
    let sendTitle: String
    var sendStyle: GFButton.Style = .primary
    /// The send button stays disabled until there's non-blank text.
    var requiresText = false
    var sending = false
    let onSend: () -> Void
    let onCancel: () -> Void

    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            editor
            HStack(spacing: Spacing.s8) {
                Spacer(minLength: 0)
                if sending {
                    ProgressView().controlSize(.small)
                }
                GFButton(title: String(localized: "Cancel"), shortcut: .cancelAction, action: onCancel)
                GFButton(title: sendTitle, style: sendStyle, disabled: !canSend,
                         shortcut: KeyboardShortcut(.return, modifiers: .command), action: onSend)
                    .help(Text(verbatim: "⌘↩"))
            }
        }
        .onAppear { focused = true }
        // With a list holding focus (the Files tab's file list), the request
        // in onAppear lands before the editor can take it and typing goes
        // nowhere: ask again once the box is on screen, as the command
        // palette does.
        .task {
            await Task.yield()
            focused = true
        }
    }

    private var canSend: Bool {
        !sending && (!requiresText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return TextEditor(text: $text)
            .font(AppFont.font(.body))
            .foregroundStyle(theme.colors.textPrimary)
            .scrollContentBackground(.hidden)
            // With a mouse attached macOS keeps legacy scroll bars on: an
            // empty box would show a phantom track. Wheel scrolling still works.
            .scrollIndicators(.never)
            .focused($focused)
            .frame(minHeight: 64, maxHeight: 180)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s6)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .textRole(.body)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, Spacing.s8)
                        .padding(.vertical, Spacing.s6)
                        .allowsHitTesting(false)
                }
            }
            .background(shape.fill(theme.effectiveMode == .dark ? Color.black.opacity(0.3) : .white))
            .overlay(shape.strokeBorder(focused ? theme.colors.accent : theme.colors.strokeControl, lineWidth: 1))
            // Redesign spec §5: focus adds a 3 pt accent ring at 30 %.
            .background(shape.stroke(theme.colors.accent.opacity(focused ? 0.3 : 0), lineWidth: 3))
            .accessibilityLabel(placeholder)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var text = ""
    ReviewComposer(text: $text, placeholder: "What needs to change (required)", sendTitle: "Request changes",
                   sendStyle: .destructive, requiresText: true, onSend: {}, onCancel: {})
        .padding()
        .frame(width: 380)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
