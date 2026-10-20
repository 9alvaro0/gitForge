import SwiftUI

/// First-fetch placeholder rows for the History table. Realistic-looking
/// commit subjects keep the layout grounded so the skeleton reads as
/// "loading commits", not as a blank pane.
struct HistorySkeleton: View {
    @Environment(\.appTheme) private var theme

    // Deliberately bland fillers — they show only while the real log is
    // loading, and shouldn't ever look like a real commit subject the user
    // is about to see.
    private static let placeholderSubjects = [
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
        String(localized: "Loading commit subject…"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { index in
                    row(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.bgContent)
        .skeleton(true)
    }

    @ViewBuilder
    private func row(index: Int) -> some View {
        let subject = Self.placeholderSubjects[index % Self.placeholderSubjects.count]
        HStack(spacing: Spacing.s12) {
            Text(verbatim: "main")
                .textRole(.monoSmall)
                .padding(.horizontal, Spacing.s6).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
                .frame(width: 100, alignment: .leading)
            Text(subject)
                .textRole(.body)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: "9alvaro0")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 110, alignment: .leading)
            Text(verbatim: "abc1234")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 70, alignment: .leading)
            Text(verbatim: "2h")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 50, alignment: .leading)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s6)
        .frame(height: LayoutMetrics.controlHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.colors.separator).frame(height: 1) }
    }
}

/// Capsule shown over the table while the next page of commits is loading.
struct LoadingMoreFooter: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s8) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text("Loading more commits…")
                .textRole(.monoSmall)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(theme.colors.separator, lineWidth: 1))
        .padding(.bottom, Spacing.s12)
    }
}

#Preview("Skeleton") {
    @Previewable @State var theme = AppTheme()
    HistorySkeleton()
        .frame(width: 760, height: 480)
        .appTheme(theme)
}

#Preview("Loading more") {
    @Previewable @State var theme = AppTheme()
    LoadingMoreFooter()
        .padding()
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
