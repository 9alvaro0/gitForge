import SwiftUI

/// Wraps `CommandPaletteBuilder.build` in a stand-alone view so its body —
/// and therefore the build call — only re-runs when the four collections it
/// depends on actually change, not on every unrelated `AppState` mutation.
struct PaletteOverlay: View {
    let repositories: [Repository]
    let branches: [GitRef]
    let commits: [Commit]
    let workingFiles: [WorkingCopyFile]
    let onPick: (PaletteAction) -> Void
    let onClose: () -> Void

    var body: some View {
        let items = CommandPaletteBuilder.build(
            repositories: repositories,
            branches: branches,
            commits: commits,
            workingFiles: workingFiles
        )
        CommandPaletteView(
            items: items,
            onPick: { onPick($0.action) },
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
        onPick: { _ in },
        onClose: {}
    )
    .previewAppState(.previewWithActive)
    .frame(width: 720, height: 480)
}
