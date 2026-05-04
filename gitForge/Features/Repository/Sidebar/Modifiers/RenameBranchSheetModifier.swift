import SwiftUI

struct RenameBranchSheetModifier: ViewModifier {
    @Binding var target: GitRef?
    let appState: AppState

    func body(content: Content) -> some View {
        content.sheet(item: $target) { ref in
            if let viewModel = appState.activeViewModel {
                RenameBranchSheet(oldName: ref.name) { newName in
                    Task {
                        let result = await viewModel.renameBranch(from: ref.name, to: newName)
                        if case .failure(let error) = result {
                            appState.presentedError = PresentedError(error: error, title: "Couldn’t rename branch")
                        }
                    }
                }
            }
        }
    }
}
