import SwiftUI

/// Presents the "Rename branch" sheet for `WorkspaceUI.renameBranchTarget`.
/// Mounted once by `ContentRouter`, so the sidebar, Branches & Tags and the
/// Repository menu share it whatever section is showing.
struct BranchRenameSheetModifier: ViewModifier {
    let viewModel: RepositoryViewModel

    @Environment(AppState.self) private var appState
    @State private var draft: String = ""

    func body(content: Content) -> some View {
        content
            .sheet(item: Bindable(appState.ui).renameBranchTarget) { ref in
                BranchInputSheet(
                    title: String(localized: "Rename \(ref.name)"),
                    placeholder: ref.name,
                    confirmTitle: String(localized: "Rename"),
                    text: $draft,
                    confirmDisabled: Self.confirmDisabled(draft: draft, original: ref.name),
                    onCancel: { appState.ui.renameBranchTarget = nil },
                    onConfirm: { newName in Task { await rename(ref, to: newName) } }
                )
                .onAppear { draft = ref.name }
            }
    }

    /// Nothing to do for an empty name or the name the branch already has.
    static func confirmDisabled(draft: String, original: String) -> Bool {
        let name = draft.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == original
    }

    private func rename(_ ref: GitRef, to rawName: String) async {
        let newName = rawName.trimmingCharacters(in: .whitespaces)
        switch await viewModel.renameBranch(from: ref.name, to: newName) {
        case .success:
            appState.ui.renameBranchTarget = nil
            appState.ui.activeToast = ToastMessage(
                message: String(localized: "Renamed \(ref.name) to \(newName)"), kind: .ok)
        case .failure(let error) where error is CancellationError:
            break
        case .failure(let error):
            // The sheet stays open so the name can be fixed and retried.
            appState.ui.activeToast = ToastMessage(
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                kind: .error)
        }
    }
}

extension View {
    func branchRenameSheet(viewModel: RepositoryViewModel) -> some View {
        modifier(BranchRenameSheetModifier(viewModel: viewModel))
    }
}
