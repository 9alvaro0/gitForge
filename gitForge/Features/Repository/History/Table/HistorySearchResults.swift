import SwiftUI

/// What History shows instead of the graph while a git-backed search is active (#62): the
/// matching commits as a flat list, newest first. A filtered walk leaves out the commits
/// between two matches, so lines and lanes drawn for it would be made up; the graph hides
/// until the search ends. Return or a double-click reveals the result in the graph.
struct HistorySearchResults: View {
    let search: HistorySearchStore
    let selectedSha: String?
    let onSelect: (String) -> Void
    let onJump: (String) -> Void

    @Environment(\.appTheme) private var theme
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if search.isSearching && search.results.isEmpty {
                VStack(spacing: Spacing.s8) {
                    ProgressView().controlSize(.small)
                    Text("Searching the whole history…")
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = search.error, search.results.isEmpty {
                EmptyState(symbol: "exclamationmark.triangle", title: String(localized: "The search failed"),
                           subtitle: error)
            } else if search.results.isEmpty {
                EmptyState(symbol: "magnifyingglass",
                           title: search.isStopped ? String(localized: "Search stopped") : String(localized: "No commits match"),
                           subtitle: search.isStopped
                               ? String(localized: "Nothing matched before it stopped.")
                               : String(localized: "A commit has to match every criterion. Try removing one."))
            } else {
                list
            }
        }
        .overlay(alignment: .bottom) {
            if search.isLoadingMore || search.isJumping {
                LoadingMoreFooter()
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(search.results) { commit in
                        HistorySearchResultRow(
                            commit: commit,
                            isSelected: commit.sha == selectedSha,
                            onSelect: {
                                listFocused = true
                                onSelect(commit.sha)
                            },
                            onJump: { onJump(commit.sha) }
                        )
                        .id(commit.sha)
                        .onAppear { search.loadMoreIfNeeded(currentItem: commit) }
                    }
                }
                .padding(Spacing.s6)
            }
            .listKeyboardNavigation(
                ids: search.results.map(\.sha),
                selection: selectedSha,
                isFocused: $listFocused,
                scrollProxy: proxy,
                onSelect: onSelect
            )
            .onKeyPress(.return) {
                guard let sha = selectedSha, search.resultsById[sha] != nil else { return .ignored }
                onJump(sha)
                return .handled
            }
        }
    }
}

/// One result: subject, author, date and short SHA.
private struct HistorySearchResultRow: View {
    let commit: Commit
    let isSelected: Bool
    let onSelect: () -> Void
    let onJump: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s12) {
            Text(commit.subject)
                .textRole(.callout, weight: .medium)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(commit.authorName)
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Text(preferences.dateDisplayMode.format(commit.authorDate))
                .textRole(.callout)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .fixedSize()
            Text(commit.shortSha)
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .fixedSize()
        }
        .padding(.horizontal, Spacing.s8)
        .frame(height: theme.density.metrics.rowList)
        .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowFill))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onJump)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(commit.subject), \(commit.authorName), \(commit.shortSha)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: "Show in graph", onJump)
        .help("Double-click or press Return to show it in the graph")
    }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}
