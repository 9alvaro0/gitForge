import SwiftUI

/// Wraps `CommandPaletteBuilder.build` in a stand-alone view so its body —
/// and therefore the build call — only re-runs when the collections it
/// depends on actually change, not on every unrelated `AppState` mutation.
struct PaletteOverlay: View {
    let repositories: [Repository]
    let branches: [GitRef]
    let commits: [Commit]
    let workingFiles: [WorkingCopyFile]
    /// The inbox's pull requests (`ReviewsStore.searchablePulls`) and the
    /// followed repos that aren't cloned.
    let pulls: [InboxPull]
    let unclonedRepos: [ReviewRepo]
    /// The declared instances, to read a pasted pull request link against.
    let instances: [HostingInstance]
    /// The Search all group for a query, built from the inbox's state when
    /// the palette draws (`CommandPaletteView.trailingItems`).
    let trailingItems: (String) -> [CommandPaletteItem]
    /// `keepOpen`: `PaletteAction.keepOpen`, a search that runs inside the
    /// palette or ⌘↵ on an action that doesn't present a panel or sheet.
    let onPick: (PaletteAction, _ keepOpen: Bool) -> Void
    let onClose: () -> Void

    var body: some View {
        let items = CommandPaletteBuilder.build(
            repositories: repositories,
            branches: branches,
            commits: commits,
            workingFiles: workingFiles,
            pulls: pulls,
            unclonedRepos: unclonedRepos
        )
        CommandPaletteView(
            items: items,
            pinnedItems: { CommandPaletteBuilder.linkItems(for: $0, instances: instances) },
            trailingItems: trailingItems,
            onPick: { item, commandHeld in
                onPick(item.action, PaletteAction.keepOpen(item.action, commandHeld: commandHeld))
            },
            onClose: onClose
        )
    }
}

#Preview("Palette") {
    PaletteOverlay(
        repositories: Repository.previewSamples,
        branches: GitRef.previewSamples,
        commits: Commit.previewSamples,
        workingFiles: [],
        pulls: CommandPaletteItem.previewPulls,
        unclonedRepos: CommandPaletteItem.previewUnclonedRepos,
        instances: CommandPaletteItem.previewInstances,
        trailingItems: CommandPaletteItem.previewSearchItems,
        onPick: { _, _ in },
        onClose: {}
    )
    .previewAppState(.previewWithActive)
    .frame(width: 720, height: 480)
}
