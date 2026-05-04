import SwiftUI

struct DirtyCheckoutAlertModifier: ViewModifier {
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
            "Working copy has uncommitted changes",
            isPresented: isPresented,
            presenting: target
        ) { ref in
            Button("Continue Checkout") {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.checkoutBranch(ref)
                    if case .failure(let error) = result {
                        appState.presentedError = PresentedError(error: error, title: "Couldn’t checkout")
                    }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { ref in
            Text("Switching to “\(ref.displayName)” may carry your local changes. Commit or discard them first if you want a clean switch.")
        }
    }
}
