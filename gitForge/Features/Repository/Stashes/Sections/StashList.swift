import SwiftUI

struct StashList: View {
    let stashes: [Stash]
    let selectedIndex: Int?
    let onSelect: (Stash) -> Void
    let onApply: (Stash) -> Void
    let onPop: (Stash) -> Void
    let onDrop: (Stash) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(stashes) { stash in
                    StashRow(
                        stash: stash,
                        isSelected: stash.index == selectedIndex,
                        onSelect: { onSelect(stash) },
                        onApply:  { onApply(stash) },
                        onPop:    { onPop(stash) },
                        onDrop:   { onDrop(stash) }
                    )
                }
            }
            .padding(Spacing.s6)
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    StashList(stashes: Stash.previewSamples, selectedIndex: 1,
              onSelect: { _ in }, onApply: { _ in }, onPop: { _ in }, onDrop: { _ in })
        .frame(width: 360, height: 300)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
