import SwiftUI

struct StashList: View {
    let stashes: [Stash]
    let hasDirtyChanges: Bool
    let onSelect: (Stash) -> Void
    let onApply: (Stash) -> Void
    let onPop: (Stash) -> Void
    let onDrop: (Stash) -> Void

    var body: some View {
        if stashes.isEmpty {
            EmptyState(
                icon: .stash,
                title: "No stashes",
                subtitle: hasDirtyChanges
                    ? "Use \u{201C}Stash changes…\u{201D} to park your work-in-progress."
                    : "When you stash work-in-progress it'll show up here."
            ) { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(stashes) { stash in
                        StashRow(
                            stash: stash,
                            onSelect: { onSelect(stash) },
                            onApply:  { onApply(stash) },
                            onPop:    { onPop(stash) },
                            onDrop:   { onDrop(stash) }
                        )
                    }
                }
                .padding(DesignTokens.Spacing.xxxxl)
            }
        }
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    StashList(
        stashes: Stash.previewSamples, hasDirtyChanges: true,
        onSelect: { _ in }, onApply: { _ in }, onPop: { _ in }, onDrop: { _ in }
    )
    .frame(width: 980, height: 600)
    .background(theme.palette.bg2)
    .appTheme(theme)
}

#Preview("Empty (clean tree)") {
    @Previewable @State var theme = AppTheme()
    StashList(
        stashes: [], hasDirtyChanges: false,
        onSelect: { _ in }, onApply: { _ in }, onPop: { _ in }, onDrop: { _ in }
    )
    .frame(width: 980, height: 600)
    .background(theme.palette.bg2)
    .appTheme(theme)
}

#Preview("Empty (dirty tree)") {
    @Previewable @State var theme = AppTheme()
    StashList(
        stashes: [], hasDirtyChanges: true,
        onSelect: { _ in }, onApply: { _ in }, onPop: { _ in }, onDrop: { _ in }
    )
    .frame(width: 980, height: 600)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
