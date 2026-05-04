import SwiftUI

struct RemoteFailureAlertModifier: ViewModifier {
    @Bindable var viewModel: RepositoryViewModel

    private var isPresented: Binding<Bool> {
        Binding(
            get: { viewModel.remoteFailure != nil },
            set: { if !$0 { viewModel.remoteFailure = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            viewModel.remoteFailure?.title ?? "",
            isPresented: isPresented,
            presenting: viewModel.remoteFailure
        ) { _ in
            Button("OK", role: .cancel) {
                viewModel.remoteFailure = nil
            }
        } message: { failure in
            Text(failure.message)
        }
    }
}
