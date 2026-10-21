import SwiftUI

/// "Merge #42": method, squash, commit messages and branch deletion, then
/// the confirm button that says what will happen. The sheet is the
/// confirmation: there's no second "Are you sure?".
struct MergeSheet: View {
    let store: PullRequestStore

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            header
            content
            blockedReason
            buttons
        }
        .padding(Spacing.s20)
        .frame(width: 480)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
        // The options aren't remembered: the detail clears them when the
        // sheet closes, so each opening reads them again.
        .task { if store.mergeOptions == nil { await store.prepareMerge() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text("Merge \(reference)")
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
            if let pull = store.selected {
                Text("Into \(branch(pull.targetBranch)) from \(branch(pull.sourceBranch))")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private func branch(_ name: String) -> Text {
        Text(name)
            .font(AppFont.font(.monoSmall, weight: .semibold, monoFamily: theme.monoFont))
            .foregroundStyle(theme.colors.textPrimary)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let options = store.mergeOptions, store.mergeDraft != nil {
            MergeOptionsForm(options: options, draft: draftBinding(options),
                             sourceBranch: store.selected?.sourceBranch ?? "", hostLabel: hostLabel)
                .disabled(store.isMerging)
        } else if let error = store.mergeOptionsError {
            HStack(alignment: .top, spacing: Spacing.s8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.del)
                Text(error)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                GFButton(title: String(localized: "Retry")) { Task { await store.prepareMerge() } }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    /// The verdict can change while the sheet is open (a reload after a
    /// refusal): say why the confirm button went off.
    @ViewBuilder
    private var blockedReason: some View {
        if store.mergeDraft != nil, let reason = store.mergeBlockedReason {
            HStack(alignment: .top, spacing: Spacing.s8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(theme.colors.del)
                Text(reason)
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Edits go straight to the store's draft.
    private func draftBinding(_ options: MergeOptions) -> Binding<MergeDraft> {
        Binding(get: { store.mergeDraft ?? MergeDraft(options: options) },
                set: { store.mergeDraft = $0 })
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: Spacing.s8) {
            Spacer(minLength: 0)
            if store.isMerging {
                ProgressView().controlSize(.small)
            }
            GFButton(title: String(localized: "Cancel"), disabled: store.isMerging, shortcut: .cancelAction) { dismiss() }
            GFButton(title: confirmTitle, style: .primary, disabled: !canConfirm,
                     shortcut: KeyboardShortcut(.return, modifiers: .command), action: confirm)
                .help(Text(verbatim: "⌘↩"))
        }
    }

    private var confirmTitle: String {
        guard let options = store.mergeOptions, let draft = store.mergeDraft else { return String(localized: "Merge") }
        return options.confirmTitle(method: draft.method, squash: options.resolvedSquash(draft.squash, method: draft.method))
    }

    private var canConfirm: Bool {
        store.mergeDraft != nil && !store.isMerging && store.mergeBlockedReason == nil
    }

    private var reference: String {
        guard let number = store.selected?.number else { return "" }
        return store.host?.provider.reference(number) ?? "#\(number)"
    }

    private var hostLabel: String { store.host?.provider.label ?? "" }

    /// The toast names the PR, read before the await. A failure keeps the
    /// sheet and the draft; new commits close it so they get reviewed.
    private func confirm() {
        let done = String(localized: "Merged \(reference)")
        Task {
            switch await store.merge() {
            case .merged(let warning):
                dismiss()
                appState.ui.activeToast = warning.map { ToastMessage(message: $0, kind: .warn) }
                    ?? ToastMessage(message: done, kind: .ok)
            case .headChanged(let message):
                dismiss()
                appState.ui.activeToast = ToastMessage(message: message, kind: .warn)
            case .failed(let message):
                appState.ui.activeToast = ToastMessage(message: message, kind: .error)
            case .ignored:
                break
            }
        }
    }
}

/// The sheet's choices for one set of options: GitHub's method, GitLab's
/// squash, the messages the method writes, and the branch deletion.
struct MergeOptionsForm: View {
    let options: MergeOptions
    @Binding var draft: MergeDraft
    let sourceBranch: String
    /// "GitHub" / "GitLab", for the "… default" placeholders.
    let hostLabel: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            if case .github(let methods) = options.kind, methods.count > 1 {
                SegmentedControl<MergeMethod>(methods.map { ($0, title(for: $0)) },
                                              selection: Binding(get: { draft.method ?? methods[0] },
                                                                 set: { draft.method = $0 }))
                    .fixedSize()
            }
            if options.showsSquashToggle {
                Toggle("Squash commits", isOn: Binding(get: { squash }, set: { draft.squash = $0 }))
                    .disabled(options.squashLocked)
                    .help(options.squashLocked ? String(localized: "This project always squashes") : String())
            }
            let fields = options.messageFields(method: draft.method, squash: squash)
            if !fields.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    ForEach(fields, id: \.self) { field in
                        messageField(field)
                    }
                }
            }
            if options.canDeleteSourceBranch {
                Toggle("Delete \(sourceBranch) after merging", isOn: $draft.deleteSourceBranch)
            }
        }
        .toggleStyle(.checkbox)
        .textRole(.callout)
    }

    private var squash: Bool { options.resolvedSquash(draft.squash, method: draft.method) }

    private func title(for method: MergeMethod) -> String {
        switch method {
        case .squash: String(localized: "Squash")
        case .merge: String(localized: "Merge commit")
        case .rebase: String(localized: "Rebase")
        }
    }

    private func label(for field: MergeMessageField) -> String {
        switch field {
        case .title: String(localized: "Commit title")
        case .body: String(localized: "Commit message")
        case .squashMessage: String(localized: "Squash commit message")
        case .mergeMessage: String(localized: "Merge commit message")
        }
    }

    private func messageField(_ field: MergeMessageField) -> some View {
        let text = Binding(get: { draft.text(for: field, options: options) },
                           set: { draft.setText($0, for: field) })
        // Only where the host's text is unknown: an emptied field then
        // means "the host's default", and nothing is sent for it.
        let placeholder = options.defaults(for: draft.method)[field] == nil ? String(localized: "\(hostLabel) default") : ""
        return VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(label(for: field))
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)
            if field == .title {
                GFTextField(placeholder: placeholder, text: text)
            } else {
                MergeMessageEditor(text: text, placeholder: placeholder, label: label(for: field))
            }
        }
    }
}

/// A multi-line commit message, drawn like `GFTextField`.
private struct MergeMessageEditor: View {
    @Binding var text: String
    let placeholder: String
    let label: String

    @Environment(\.appTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        TextEditor(text: $text)
            .font(AppFont.font(.body))
            .foregroundStyle(theme.colors.textPrimary)
            .scrollContentBackground(.hidden)
            // An empty box would show a phantom track with a mouse attached.
            .scrollIndicators(.never)
            .focused($focused)
            .frame(height: 84)
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
            .accessibilityLabel(label)
    }
}

#Preview("GitHub") {
    @Previewable @State var theme = AppTheme()
    MergeSheet(store: .previewMergeGitHub)
        .previewAppState(.preview)
        .appTheme(theme)
}

#Preview("GitLab ff, always squash") {
    @Previewable @State var theme = AppTheme()
    MergeSheet(store: .previewMergeGitLab)
        .previewAppState(.preview)
        .appTheme(theme)
}
