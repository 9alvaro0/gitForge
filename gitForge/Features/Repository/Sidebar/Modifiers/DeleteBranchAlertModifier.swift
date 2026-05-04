import SwiftUI

struct DeleteBranchAlertModifier: ViewModifier {
    @Binding var target: GitRef?
    @Binding var unmerged: GitRef?
    let appState: AppState

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Delete branch \(target?.name ?? "")?",
            isPresented: isPresented,
            presenting: target
        ) { ref in
            Button("Delete", role: .destructive) {
                guard let viewModel = appState.activeViewModel else { return }
                Task {
                    let result = await viewModel.deleteBranch(ref, force: false)
                    if case .failure(let error) = result {
                        let stderr = Self.extractStderr(from: error)
                        if stderr.contains("not fully merged") {
                            unmerged = ref
                        } else {
                            appState.presentedError = PresentedError(error: error, title: "Couldn’t delete branch")
                        }
                    }
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { _ in
            Text("This removes the local branch reference. Commits remain in the repository.")
        }
    }

    private static func extractStderr(from error: Error) -> String {
        guard let gitError = error as? GitError,
              case .commandFailed(_, _, let stderr) = gitError else {
            return ""
        }
        return stderr
    }
}
