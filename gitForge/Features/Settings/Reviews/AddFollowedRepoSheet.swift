import SwiftUI

/// "Add repository…" in Settings › Reviews (R3 Ruling 15): the repos of every
/// account's membership that Reviews doesn't follow nor hide, by host, found
/// by path as ⌘K finds them (Ruling H), with "Follow" on each.
///
/// The list is the one the sheet opened with: a repo followed here stays,
/// marked "Followed", instead of leaving under the pointer. One the limit
/// refuses says so under its row (Ruling 6).
struct AddFollowedRepoSheet: View {
    /// What the sheet starts with; previews set it.
    struct Start {
        var query = ""
        /// `FollowedRepos.key`s shown as followed from the sheet.
        var followed: Set<String> = []
        /// The `FollowedRepos.key` the limit refused.
        var refused: String? = nil
    }

    let store: ReviewsStore
    var start = Start()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var query = ""
    @State private var repos: [FoundRepo] = []
    @State private var loaded = false
    /// `FollowedRepos.key`s followed from this sheet.
    @State private var followed: Set<String> = []
    /// Keys whose follow is still running.
    @State private var following: Set<String> = []
    /// The key of the last repo the limit refused.
    @State private var refused: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Add repository")
                .textRole(.title)
                .foregroundStyle(theme.colors.textPrimary)
            GFTextField(placeholder: String(localized: "Search your repositories"), text: $query)
            // Rows clipped to the card, and its border drawn over them whole,
            // as `SettingsSection` draws its own.
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.bgElevated))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(theme.colors.separator, lineWidth: 1))
            HStack {
                Spacer()
                GFButton(title: String(localized: "Done"), style: .primary, shortcut: .cancelAction) { dismiss() }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 480, height: 460)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            query = start.query
            followed = start.followed
            refused = start.refused
            repos = store.followableRepos
        }
    }

    @ViewBuilder
    private var results: some View {
        let shown = ReviewsSettingsModel.filter(repos, query: query)
        if shown.isEmpty {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            EmptyState(symbol: "magnifyingglass",
                       title: trimmed.isEmpty ? String(localized: "No repositories found.")
                                              : String(localized: "No matches for “\(trimmed)”"))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ReviewsSettingsModel.groups(shown), id: \.host) { group in
                        MonoText(group.host, dim: true)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.s12)
                            .padding(.top, Spacing.s8).padding(.bottom, Spacing.s6)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.repos, id: \.self) { repo in
                            row(repo)
                        }
                    }
                }
                .padding(.bottom, Spacing.s4)
            }
        }
    }

    private func row(_ repo: FoundRepo) -> some View {
        let key = FollowedRepos.key(repo.host)
        return VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s8) {
                Text(verbatim: repo.host.slug)
                    .textRole(.body, weight: .medium)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    // A nested GitLab path keeps both ends: group and repo.
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.s8)
                if followed.contains(key) {
                    Label(String(localized: "Followed"), systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .textRole(.caption, weight: .semibold)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                } else if following.contains(key) {
                    ProgressView().controlSize(.small)
                } else {
                    GFButton(title: String(localized: "Follow"), size: .small) { follow(repo) }
                        .fixedSize()
                }
            }
            if refused == key {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.colors.warn)
                        .accessibilityHidden(true)
                    Text("Following it would pass the limit of 100 repositories.")
                        .textRole(.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // One height whether the row shows its button, the spinner or
        // "Followed": the list doesn't jump.
        .frame(minHeight: theme.density.metrics.buttonSmall)
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s6)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.separator).frame(height: 1) }
    }

    private func follow(_ repo: FoundRepo) {
        let key = FollowedRepos.key(repo.host)
        following.insert(key)
        refused = nil
        Task {
            let outcome = await store.follow(repo)
            following.remove(key)
            switch outcome {
            case .done: followed.insert(key)
            case .overLimit: refused = key
            }
        }
    }
}

#Preview("Add repository") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.settings)
    Color.clear
        .frame(width: 480, height: 460)
        .task { await store.refreshForPreview() }
        .overlay {
            // The list is read when the sheet appears: after the refresh.
            if !store.repos.isEmpty { AddFollowedRepoSheet(store: store) }
        }
        .previewAppState(.preview)
        .appTheme(theme)
}

#Preview("Add repository, searching") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.settings)
    Color.clear
        .frame(width: 480, height: 460)
        .task { await store.refreshForPreview() }
        .overlay {
            if !store.repos.isEmpty { AddFollowedRepoSheet(store: store, start: .init(query: "oss")) }
        }
        .previewAppState(.preview)
        .appTheme(theme)
}

#Preview("Add repository, followed and refused") {
    @Previewable @State var theme = AppTheme()
    let store = ReviewsStore.preview(.settings)
    let key = { (path: String) in FollowedRepos.key(RemoteHost.make(fullName: path, on: PreviewReviewsWorld.gitHub)!) }
    Color.clear
        .frame(width: 480, height: 460)
        .task { await store.refreshForPreview() }
        .overlay {
            if !store.repos.isEmpty {
                AddFollowedRepoSheet(store: store, start: .init(followed: [key("oss/cli")], refused: key("octo/dotfiles")))
            }
        }
        .previewAppState(.preview)
        .appTheme(theme)
}
