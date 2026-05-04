import SwiftUI

struct NewBranchSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let appState: AppState

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            if let viewModel = appState.activeViewModel {
                NewBranchSheet(baseDescription: viewModel.currentBranchName ?? "HEAD") { name, shouldCheckout in
                    Task {
                        let result = await viewModel.createBranch(name: name, checkout: shouldCheckout)
                        if case .failure(let error) = result {
                            appState.presentedError = PresentedError(error: error, title: "Couldn’t create branch")
                        }
                    }
                }
            }
        }
    }
}
