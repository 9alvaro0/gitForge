import SwiftUI

/// Right-side toolbar of the History header: Fetch + Pull (split) + Push
/// (split, with force-with-lease behind a confirmation when the theme flag
/// `confirmForcePush` is on).
struct HistoryToolbar: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme
    @State private var pendingForcePush = false

    var body: some View {
        Group {
            ToolButton(
                .fetch,
                label: "Fetch",
                disabled: viewModel.remoteOperation != nil && viewModel.remoteOperation != .fetching,
                loading: viewModel.remoteOperation == .fetching
            ) {
                Task { await viewModel.fetch() }
            }
            pullSplitButton
            pushSplitButton
        }
    }

    @ViewBuilder
    private var pullSplitButton: some View {
        SplitToolButton(
            kind: .pull,
            label: "Pull",
            badge: viewModel.behindCount,
            primary: false,
            loading: viewModel.remoteOperation == .pulling,
            disabled: viewModel.remoteOperation != nil && viewModel.remoteOperation != .pulling,
            action: { Task { await viewModel.pull() } }
        ) {
            Button("Pull (only if no merge needed)") {
                Task { await viewModel.pull(ffOnly: true) }
            }
            Button("Pull and rebase my commits") {
                Task { await viewModel.pull(rebase: true) }
            }
        }
    }

    @ViewBuilder
    private var pushSplitButton: some View {
        SplitToolButton(
            kind: .push,
            label: "Push",
            badge: viewModel.aheadCount,
            primary: true,
            loading: viewModel.remoteOperation == .pushing,
            disabled: viewModel.remoteOperation != nil && viewModel.remoteOperation != .pushing,
            action: { Task { await viewModel.push() } }
        ) {
            Button("Force push (only if remote unchanged)", role: .destructive) {
                if theme.confirmForcePush {
                    pendingForcePush = true
                } else {
                    Task { await viewModel.push(forceWithLease: true) }
                }
            }
        }
        .confirmationDialog(
            "Force push to \(viewModel.currentBranchName ?? "remote")?",
            isPresented: $pendingForcePush,
            titleVisibility: .visible
        ) {
            Button("Force push", role: .destructive) {
                Task { await viewModel.push(forceWithLease: true) }
            }
        } message: {
            Text("Uses --force-with-lease, so the push only succeeds if the remote hasn't moved since your last fetch. This still rewrites remote history.")
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack {
        HistoryToolbar(viewModel: .preview)
    }
    .padding()
    .background(theme.palette.bg2)
    .appTheme(theme)
}
