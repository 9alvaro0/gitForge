import SwiftUI

/// "Other comments": threads on files the PR no longer lists (changes
/// reverted, the old path of a rename), grouped by path, with the same
/// actions as anywhere else.
struct OtherCommentsList: View {
    let store: PullRequestStore
    let threads: [ReviewThread]

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s20) {
                ForEach(groups, id: \.path) { group in
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        Text(group.path)
                            .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        ForEach(group.threads) { thread in
                            ReviewThreadCard(store: store, thread: thread, header: ReviewThreadCard.header(for: thread))
                        }
                    }
                }
            }
            .padding(Spacing.s16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.bgCode)
    }

    /// By path, in the order the host listed them.
    private var groups: [(path: String, threads: [ReviewThread])] {
        var order: [String] = []
        var byPath: [String: [ReviewThread]] = [:]
        for thread in threads {
            if byPath[thread.path] == nil { order.append(thread.path) }
            byPath[thread.path, default: []].append(thread)
        }
        return order.map { ($0, byPath[$0] ?? []) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    OtherCommentsList(store: .previewWithThreads, threads: [.previewElsewhere])
        .previewAppState(.preview)
        .frame(width: 720, height: 300)
        .appTheme(theme)
}
