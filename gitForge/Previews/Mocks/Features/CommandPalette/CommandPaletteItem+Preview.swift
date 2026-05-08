import Foundation

extension CommandPaletteItem {
    @MainActor
    static var previewSamples: [CommandPaletteItem] {
        CommandPaletteBuilder.build(
            repositories: Repository.previewSamples,
            branches: GitRef.previewSamples,
            commits: Commit.previewSamples,
            workingFiles: WorkingCopyStatus.preview.files
        )
    }
}
