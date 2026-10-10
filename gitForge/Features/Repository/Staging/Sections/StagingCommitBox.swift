import SwiftUI

/// Commit composer under the file lists: who will author the commit, the
/// message, Amend, and the commit button with "Commit & push" in its menu.
/// Subject and body bind straight to the view model so the amend prefill
/// (HEAD's message) shows up in the fields.
struct StagingCommitBox: View {
    @Bindable var viewModel: RepositoryViewModel
    let stagedCount: Int

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @FocusState private var focusedField: Field?
    @State private var confirmingPublishedAmend = false

    private enum Field { case subject, body }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            authorChip
            messageField
            amendToggle
            HStack(spacing: Spacing.s8) {
                commitButton
                moreMenu
            }
            if let error = viewModel.commitError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.del)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Spacing.s12)
        .background(theme.colors.bgElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
        .confirmationDialog(
            "Amend a commit that’s already pushed?",
            isPresented: $confirmingPublishedAmend,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Amend", role: .destructive) {
                Task { await commit(push: false, confirmedAmendOfPublished: true) }
            }
        } message: {
            Text("HEAD is already on the remote. Amending rewrites published history, and the next push will need to force-push.")
        }
    }

    // MARK: Author

    /// Read-only: identity switching stays in the sidebar's profile card.
    private var authorChip: some View {
        let identity = authorIdentity
        return HStack(spacing: Spacing.s6) {
            Avatar(name: identity.name ?? "?", size: 18, colorSeed: identity.email)
            Text(identity.displayName)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textPrimary)
            if let profile = authorProfileName {
                Text("· \(profile)")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .lineLimit(1)
        .padding(.leading, Spacing.s4)
        .padding(.trailing, Spacing.s8)
        .frame(height: 26)
        .background(Capsule().fill(theme.colors.fillControl))
        .help(identity.email.map { "Commits as \($0). Change identity from the sidebar profile." } ?? "Change identity from the sidebar profile.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Author: \(identity.displayName)")
    }

    private var authorIdentity: GitIdentity {
        if let repo = viewModel.repoIdentity {
            return GitIdentity(name: repo.name, email: repo.email)
        }
        return appState.gitEnvironment.globalConfig.identity
    }

    private var authorProfileName: String? {
        viewModel.repoIdentity.flatMap { appState.profiles.match(for: $0)?.name }
    }

    // MARK: Message

    private var messageField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        let focused = focusedField != nil
        return VStack(alignment: .leading, spacing: 0) {
            TextField("Commit message", text: $viewModel.commitSubject)
                .textFieldStyle(.plain)
                .textRole(.body, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .focused($focusedField, equals: .subject)
                .padding(.horizontal, Spacing.s8)
                .padding(.top, Spacing.s8)
            TextField("Description (optional)", text: $viewModel.commitBody, axis: .vertical)
                .lineLimit(3...3)
                .textFieldStyle(.plain)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .focused($focusedField, equals: .body)
                .padding(.horizontal, Spacing.s8)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s8)
        }
        .background(shape.fill(theme.effectiveMode == .dark ? Color.black.opacity(0.3) : .white))
        .overlay(shape.strokeBorder(focused ? theme.colors.accent : theme.colors.strokeControl, lineWidth: 1))
        // Redesign spec §5: focus adds a 3 pt accent ring at 30 %.
        .background(shape.stroke(theme.colors.accent.opacity(focused ? 0.3 : 0), lineWidth: 3))
    }

    // MARK: Amend

    /// Switch before its label, as in the artboard; the label names HEAD.
    private var amendToggle: some View {
        HStack(spacing: Spacing.s6) {
            Toggle("Amend", isOn: $viewModel.amendMode)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            // The switch already carries "Amend" for VoiceOver.
            Text("Amend")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityHidden(true)
            if let sha = viewModel.headSha {
                Text(String(sha.prefix(7)))
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .disabled(viewModel.headSha == nil || viewModel.isMutating)
        .help("Replace the last commit with the staged changes and this message")
    }

    // MARK: Commit

    private var canCommit: Bool {
        !viewModel.commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (stagedCount > 0 || viewModel.amendMode)
            && !viewModel.isMutating
    }

    private var commitButton: some View {
        GFButton(
            title: CommitButtonTitle.make(fileCount: stagedCount, branch: viewModel.currentBranchName, amend: viewModel.amendMode),
            style: .primary,
            size: .large,
            disabled: !canCommit,
            fullWidth: true
        ) {
            requestCommit(push: false)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Commit & push") { requestCommit(push: true) }
                // An amend of pushed history needs a force-push, which this
                // shortcut doesn't do.
                .disabled(!canCommit || viewModel.amendWouldRewritePublishedHistory)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: theme.density.metrics.buttonLarge, height: theme.density.metrics.buttonLarge)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.fillControl))
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More commit options")
        .help("More commit options")
    }

    private func requestCommit(push: Bool) {
        // "Commit & push" is disabled in this case, so only a plain amend
        // reaches the confirmation.
        if viewModel.amendWouldRewritePublishedHistory {
            confirmingPublishedAmend = true
            return
        }
        Task { await commit(push: push, confirmedAmendOfPublished: false) }
    }

    private func commit(push: Bool, confirmedAmendOfPublished: Bool) async {
        let ok = await viewModel.commit(confirmedAmendOfPublished: confirmedAmendOfPublished)
        if ok, push { await viewModel.push() }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StagingCommitBox(viewModel: .preview, stagedCount: 3)
        .previewAppState(.preview)
        .frame(width: 440)
        .appTheme(theme)
}
