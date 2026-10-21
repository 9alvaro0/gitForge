import SwiftUI

/// Above a file's diff: the threads that aren't under one of its lines
/// (outdated, gone from the diff, or on a file without a patch). Folded
/// until opened, and open while one of its reply boxes is.
struct FileThreadsSection: View {
    let store: PullRequestStore
    let threads: [ReviewThread]

    @Environment(\.appTheme) private var theme
    @State private var expanded = false
    @State private var contentHeight: CGFloat = 0

    /// Taller than this, the threads scroll inside the block.
    private static let maxHeight: CGFloat = 320

    var body: some View {
        let isOpen = expanded || threads.contains { $0.id == store.replyingThreadId }
        VStack(spacing: 0) {
            Button { expanded = !isOpen } label: {
                HStack(spacing: Spacing.s6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Image(systemName: "text.bubble")
                    Text("Comments not on the current diff (\(threads.count))")
                        .textRole(.callout, weight: .semibold)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.horizontal, Spacing.s12)
                .frame(height: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            if isOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s8) {
                        ForEach(threads) { thread in
                            ReviewThreadCard(store: store, thread: thread, header: ReviewThreadCard.header(for: thread))
                        }
                    }
                    .padding(.horizontal, Spacing.s12)
                    .padding(.bottom, Spacing.s12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, Self.maxHeight))
            }
        }
        .background(theme.colors.bgContent)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.separator).frame(height: 1)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    FileThreadsSection(store: .previewWithThreads, threads: [.previewOutdated])
        .previewAppState(.preview)
        .frame(width: 720)
        .appTheme(theme)
}
