import SwiftUI

/// A pattern row opened as an editor in Settings › Reviews: which pattern,
/// accepted or proposed, by `FollowPattern.id`. Previews also set what's typed
/// and whether Save was pressed.
struct ReviewsPatternEdit: Equatable {
    let patternId: String
    /// What the field starts with; `nil` is the pattern's own text.
    var draft: String? = nil
    /// Save was pressed: an invalid draft shows as an error.
    var submitted = false
}

/// Settings › Reviews (R3 Ruling 15): the repos the inbox follows, by host,
/// with where each comes from and how to drop it; the accepted patterns and
/// the one gitForge proposes, each editable in its row; the hidden repos;
/// and "Add repository…".
struct ReviewsSettingsSection: View {
    let store: ReviewsStore

    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState
    @State private var addingRepo = false
    @State private var edit: ReviewsPatternEdit?

    init(store: ReviewsStore, edit: ReviewsPatternEdit? = nil) {
        self.store = store
        _edit = State(initialValue: edit)
    }

    var body: some View {
        SettingsSection(title: String(localized: "Reviews"),
                        subtitle: String(localized: "Repositories whose pull requests appear in Reviews.")) {
            if store.hasAccounts {
                followedBlock
                if !store.config.patterns.isEmpty || store.proposal != nil {
                    SettingsDivider()
                    patternsBlock
                }
                let hidden = ReviewsSettingsModel.sortedHidden(store.config.hidden)
                if !hidden.isEmpty {
                    SettingsDivider()
                    hiddenBlock(hidden)
                }
            } else {
                noAccounts
            }
        }
        .sheet(isPresented: $addingRepo) { AddFollowedRepoSheet(store: store) }
    }

    // MARK: Followed

    private var followedBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            blockHeader(String(localized: "Repositories you follow")) {
                GFButton(title: String(localized: "Add repository…"), size: .small) { addingRepo = true }
            }
            ForEach(Array(ReviewsSettingsModel.groups(store.repos).enumerated()), id: \.element.host) { index, group in
                // The first sits right under the block's header, whose bottom
                // padding already makes most of the gap.
                HostGroupLabel(host: group.host, first: index == 0, firstTopInset: Spacing.s4)
                ForEach(group.repos) { repo in followedRow(repo) }
            }
            if store.droppedByLimit > 0 {
                // `FollowedRepos.limit`, spelled out for the translations.
                Text("\(store.droppedByLimit) repositories left out (limit of 100).")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { rowSeparator }
            }
        }
    }

    private func followedRow(_ repo: ReviewRepo) -> some View {
        HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                path(repo.host.slug)
                caption(ReviewsSettingsModel.sourceTitles(repo.sources).joined(separator: " · "))
                if let old = repo.outdatedOrigin {
                    HStack(spacing: Spacing.s4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.colors.warn)
                            .accessibilityHidden(true)
                        Text("origin still points to \(old.slug)")
                            .textRole(.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: Spacing.s8)
            switch ReviewsSettingsModel.removal(for: repo) {
            case .stopFollowing:
                GFButton(title: String(localized: "Stop following"), size: .small) {
                    Task { await store.unfollow(repo.host) }
                }
                .fixedSize()
            case .hide:
                GFButton(title: String(localized: "Hide"), size: .small) {
                    Task { await store.hide(repo.host) }
                }
                .fixedSize()
            }
        }
        .rowChrome(separator: rowSeparator)
    }

    // MARK: Patterns

    private var patternsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            blockHeader(String(localized: "Patterns")) { EmptyView() }
            ForEach(store.config.patterns) { pattern in
                if edit?.patternId == pattern.id {
                    editor(pattern, isProposal: false)
                } else {
                    patternRow(pattern)
                }
            }
            if let proposal = store.proposal {
                if edit?.patternId == proposal.pattern.id {
                    editor(proposal.pattern, isProposal: true)
                } else {
                    proposalRow(proposal)
                }
            }
        }
    }

    private func patternRow(_ pattern: FollowPattern) -> some View {
        HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                path(pattern.text)
                caption(Self.summary(host: pattern.host,
                                     count: ReviewsSettingsModel.repoCount(of: pattern, in: store.repos)))
            }
            Spacer(minLength: Spacing.s8)
            GFButton(title: String(localized: "Edit"), size: .small) { edit = ReviewsPatternEdit(patternId: pattern.id) }
                .fixedSize()
            GFButton(title: String(localized: "Remove"), size: .small) { Task { await store.removePattern(pattern) } }
                .fixedSize()
        }
        .rowChrome(separator: rowSeparator)
    }

    /// The pattern gitForge proposes (R3 Ruling 3): "Follow" accepts it,
    /// unless that takes the inbox over the limit (Ruling M), which the row
    /// says instead; "Edit" narrows it first; "Not now" answers it.
    private func proposalRow(_ proposal: PatternProposal) -> some View {
        let overLimit = store.exceedsLimit(proposal.total)
        let count = ReviewsSettingsModel.repoCount(of: proposal.pattern, in: store.repos) + proposal.adds
        return HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s6) {
                    path(proposal.pattern.text)
                    Text("Proposed")
                        .textRole(.caption, weight: .semibold)
                        .foregroundStyle(theme.colors.accent)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.s6)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.accentSoft))
                        .fixedSize()
                }
                caption(Self.summary(host: proposal.pattern.host, count: count))
                if overLimit {
                    PatternLimitMessage(total: proposal.total)
                }
            }
            Spacer(minLength: Spacing.s8)
            GFButton(title: String(localized: "Follow"), size: .small, disabled: overLimit) {
                Task {
                    if case .overLimit = await store.acceptProposal() {
                        appState.ui.activeToast = ToastMessage(
                            message: String(localized: "Following it would pass the limit of 100 repositories."),
                            kind: .warn)
                    }
                }
            }
            .fixedSize()
            GFButton(title: String(localized: "Edit"), size: .small) {
                edit = ReviewsPatternEdit(patternId: proposal.pattern.id)
            }
            .fixedSize()
            QuietButton(title: String(localized: "Not now")) { store.dismissProposal() }
                .fixedSize()
        }
        .rowChrome(separator: rowSeparator)
    }

    private func editor(_ pattern: FollowPattern, isProposal: Bool) -> some View {
        PatternEditorRow(store: store, original: pattern, isProposal: isProposal,
                         draft: edit?.draft ?? pattern.text, submitted: edit?.submitted ?? false) { edit = nil }
            .overlay(alignment: .top) { rowSeparator }
    }

    /// "gitlab.example.test · 4 repositories".
    static func summary(host: String, count: Int) -> String {
        [host, String(localized: "\(count) repositories")].joined(separator: " · ")
    }

    // MARK: Hidden

    private func hiddenBlock(_ hidden: [RemoteHost]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            blockHeader(String(localized: "Hidden")) { EmptyView() }
            ForEach(hidden) { host in
                HStack(spacing: Spacing.s8) {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        path(host.slug)
                        caption(host.host)
                    }
                    Spacer(minLength: Spacing.s8)
                    GFButton(title: String(localized: "Show again"), size: .small) { Task { await store.unhide(host) } }
                        .fixedSize()
                }
                .rowChrome(separator: rowSeparator)
            }
        }
    }

    // MARK: No accounts

    private var noAccounts: some View {
        HStack(spacing: Spacing.s8) {
            Text("Connect an account to follow repositories.")
                .textRole(.callout)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer(minLength: Spacing.s8)
            GFButton(title: String(localized: "Connect account…"), size: .small) {
                appState.ui.connectAccountRequest = ConnectAccountRequest()
            }
            .fixedSize()
        }
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
    }

    // MARK: Pieces

    private func blockHeader<Trailing: View>(_ title: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Spacing.s8) {
            Text(title)
                .textRole(.body, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.s8)
            trailing()
                .fixedSize()
        }
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
    }

    /// A repo or pattern path: both ends kept when it doesn't fit, so a
    /// nested GitLab path still shows its group and its repo.
    private func path(_ text: String) -> some View {
        Text(verbatim: text)
            .textRole(.body, weight: .medium)
            .foregroundStyle(theme.colors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .textRole(.caption)
            .foregroundStyle(theme.colors.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var rowSeparator: some View {
        Rectangle().fill(theme.colors.separator).frame(height: 1)
    }
}

/// A host heading a group of repos in Settings › Reviews and in "Add
/// repository…". The first one sits under its block's header (`first`, with
/// `firstTopInset` above it); every other one has a line over it, as
/// Settings › Accounts separates its instances, and more room above than
/// below, so it heads the rows under it rather than ending the row above.
struct HostGroupLabel: View {
    let host: String
    let first: Bool
    var firstTopInset: CGFloat = Spacing.s8

    @Environment(\.appTheme) private var theme

    var body: some View {
        MonoText(host, dim: true)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s12)
            .padding(.top, first ? firstTopInset : Spacing.s12)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                if !first { Rectangle().fill(theme.colors.separator).frame(height: 1) }
            }
            .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// A row's inset and the line over it, as Settings › Accounts draws its rows.
    func rowChrome(separator: some View) -> some View {
        padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
            .overlay(alignment: .top) { separator }
    }
}

/// "With them you'd follow N repositories, over the limit of 100." (R3
/// Ruling 6), under a pattern that can't be followed as it is.
private struct PatternLimitMessage: View {
    let total: Int

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.colors.warn)
                .accessibilityHidden(true)
            // `FollowedRepos.limit`, spelled out for the translations.
            Text("With them you'd follow \(total) repositories, over the limit of 100.")
                .textRole(.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A pattern's row while it's edited (R3 Rulings 1, 6, K and M): the text
/// in a field with Save and Cancel; under it, how many repos the pattern
/// would follow, or why it can't be saved.
///
/// - An invalid text shows Ruling 1's rule, as an error once Save is pressed.
/// - A pattern that takes the inbox over the limit says so while it's typed
///   (`exceedsLimit` on `patternCount`), and Save is still allowed to try: an
///   `.overLimit` answer says the same.
/// - An accepted pattern is saved in its own place. The proposal, edited or
///   not, is saved as a new pattern and answered in one go, so it doesn't
///   come back (Rulings K and V): the store decides that, not the row.
private struct PatternEditorRow: View {
    let store: ReviewsStore
    let original: FollowPattern
    let isProposal: Bool
    let onClose: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var draft: String
    @State private var submitted: Bool
    /// The total of the last Save the limit refused, until the text changes.
    @State private var refusedTotal: Int?
    @State private var saving = false
    @FocusState private var focused: Bool

    init(store: ReviewsStore, original: FollowPattern, isProposal: Bool, draft: String, submitted: Bool,
         onClose: @escaping () -> Void) {
        self.store = store
        self.original = original
        self.isProposal = isProposal
        self.onClose = onClose
        _draft = State(initialValue: draft)
        _submitted = State(initialValue: submitted)
    }

    var body: some View {
        let candidate = FollowPattern(host: original.host, text: draft)
        let count = candidate.map { store.patternCount($0, replacing: replaced) }
        let liveOver = count.flatMap { store.exceedsLimit($0.total) ? $0.total : nil }
        let showsError = candidate == nil && submitted
        VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack(spacing: Spacing.s8) {
                TextField(String(localized: "Pattern"), text: $draft)
                    .textFieldStyle(.plain)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, Spacing.s8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.bgContent))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control)
                        .stroke(showsError ? theme.colors.del : theme.colors.accent, lineWidth: 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand(perform: onClose)
                    .accessibilityLabel(Text("Pattern"))
                GFButton(title: String(localized: "Save"), style: .primary, size: .small, disabled: saving, action: save)
                    .fixedSize()
                GFButton(title: String(localized: "Cancel"), size: .small, action: onClose)
                    .fixedSize()
            }
            Group {
                if let candidate, let count {
                    Text(verbatim: ReviewsSettingsSection.summary(
                        host: candidate.host,
                        count: ReviewsSettingsModel.repoCount(of: candidate, in: store.repos) + count.adds))
                        .foregroundStyle(theme.colors.textTertiary)
                } else {
                    Text("Segments separated by /, with * for any one segment and at least one fixed segment.")
                        .foregroundStyle(showsError ? theme.colors.del : theme.colors.textTertiary)
                }
            }
            .textRole(.caption)
            .fixedSize(horizontal: false, vertical: true)
            if let total = liveOver ?? refusedTotal {
                PatternLimitMessage(total: total)
            }
        }
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
        .onChange(of: draft) {
            submitted = false
            refusedTotal = nil
        }
        .onAppear { focused = true }
    }

    /// What the edit takes the place of: the accepted pattern itself; the
    /// proposal isn't among the patterns yet.
    private var replaced: FollowPattern? { isProposal ? nil : original }

    private func save() {
        guard !saving else { return }
        guard let candidate = FollowPattern(host: original.host, text: draft) else {
            submitted = true
            return
        }
        saving = true
        Task {
            let outcome = isProposal
                ? await store.acceptProposal(original, as: candidate)
                : await store.savePattern(candidate, replacing: original)
            saving = false
            switch outcome {
            case .done: onClose()
            case .overLimit(let total): refusedTotal = total
            }
        }
    }
}

#Preview("Reviews settings") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.settings)
    ScrollView {
        ReviewsSettingsSection(store: store)
            .padding(Spacing.s20)
    }
    .task { await store.refreshForPreview() }
    .previewAppState(.preview)
    .frame(width: 860, height: 760)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}

#Preview("Editing a pattern, over the limit") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.settingsOverLimit)
    ScrollView {
        ReviewsSettingsSection(store: store, edit: ReviewsPatternEdit(patternId: PreviewReviewsWorld.androidPattern.id,
                                                                      draft: "tools/*/*"))
            .padding(Spacing.s20)
    }
    .task { await store.refreshForPreview() }
    .previewAppState(.preview)
    .frame(width: 860, height: 760)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}

#Preview("Editing a pattern, invalid") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.settings)
    ScrollView {
        ReviewsSettingsSection(store: store, edit: ReviewsPatternEdit(patternId: PreviewReviewsWorld.androidPattern.id,
                                                                      draft: "apps/pay*", submitted: true))
            .padding(Spacing.s20)
    }
    .task { await store.refreshForPreview() }
    .previewAppState(.preview)
    .frame(width: 860, height: 760)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}

#Preview("No accounts") {
    @Previewable @State var theme = AppTheme()
    ReviewsSettingsSection(store: .preview(.noAccounts))
        .padding(Spacing.s20)
        .previewAppState(.preview)
        .frame(width: 860)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
