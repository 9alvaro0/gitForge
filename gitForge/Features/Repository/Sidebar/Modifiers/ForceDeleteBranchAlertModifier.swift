import SwiftUI

struct ForceDeleteBranchAlertModifier: ViewModifier {
    @Binding var target: GitRef?
    let appState: AppState

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Branch \(target?.name ?? "") is not fully merged",
            isPresented: isPresented,
            presenting: target
        ) { ref in
            Button("Force Delete", role: .destructive) {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.deleteBranch(ref, force: true)
                    if case .failure(let error) = result {
                        appState.presentedError = PresentedError(error: error, title: "Couldn’t force-delete branch")
                    }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { _ in
            Text("Some commits exist only on this branch and will become unreachable. Force delete anyway?")
        }
    }
}
