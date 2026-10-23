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
    /// `keepOpen`: ⌘↵ on an action that doesn't present a panel or sheet.
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
            onPick: { item, keepOpen in onPick(item.action, keepOpen && !item.action.presentsUI) },
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
        onPick: { _, _ in },
        onClose: {}
    )
    .previewAppState(.previewWithActive)
    .frame(width: 720, height: 480)
}
