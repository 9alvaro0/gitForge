import SwiftUI
import AppKit

struct StagingDiffColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    let hasFiles: Bool
    let statusLoading: Bool
    @Binding var diffMode: DiffPane.ViewMode

    var body: some View {
        Group {
            if let file = viewModel.selectedWorkingCopyFile {
                DiffPane(
                    file: file.path,
                    hunks: viewModel.workingCopyDiff,
                    loading: viewModel.loadingWorkingCopyDiff,
                    emptyState: viewModel.workingCopyDiffEmptyState,
                    onOpenInEditor: { openInEditor(file: file) },
                    viewMode: $diffMode
                )
            } else if hasFiles {
                EmptyState(icon: .diff, title: "Pick a file to see the diff",
                           subtitle: "Selection drives the right-hand pane.") { EmptyView() }
            } else if statusLoading {
                DiffPane(file: nil, hunks: [], loading: true, viewMode: $diffMode)
            } else {
                EmptyState(icon: .check, title: "Working tree is clean",
                           subtitle: "No changes to stage.") { EmptyView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openInEditor(file: WorkingCopyFile) {
        let absolute = viewModel.repository.url.appendingPathComponent(file.path)
        NSWorkspace.shared.open(absolute)
    }
}
