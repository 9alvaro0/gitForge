import SwiftUI

/// Fetch + Pull (split) + Push (split) for the shell toolbar on every
/// repository screen (redesign spec §6.1). Force-with-lease sits behind a
/// confirmation when `confirmForcePush` is on. Offline disables the group.
struct RemoteToolbarGroup: View {
    @Bindable var viewModel: RepositoryViewModel
    let online: Bool

    @Environment(\.appPreferences) private var preferences
    @State private var pendingForcePush = false

    var body: some View {
        HStack(spacing: Spacing.s6) {
            if !online {
                Image(systemName: "wifi.slash")
                    .accessibilityLabel("Offline")
                    .help("Offline")
            }
            ToolButton(
                .fetch,
                label: "Fetch",
                disabled: !online || (viewModel.remoteOperation != nil && viewModel.remoteOperation != .fetching),
                loading: viewModel.remoteOperation == .fetching
            ) {
                Task { await viewModel.fetch() }
            }
            .help(ShellStatus.fetchHelp(lastFetch: viewModel.lastFetchedAt, now: .now, online: online))
            pullSplitButton
            pushSplitButton
        }
        // The toolbar compresses items to fit; the labels must not truncate.
        .fixedSize()
    }

    @ViewBuilder
    private var pullSplitButton: some View {
        SplitToolButton(
            kind: .pull,
            label: "Pull",
            badge: viewModel.behindCount,
            primary: false,
            loading: viewModel.remoteOperation == .pulling,
            // Pull is also a local mutation (see `RepositoryViewModel.pull`).
            disabled: !online || ((viewModel.remoteOperation != nil || viewModel.isMutating)
                && viewModel.remoteOperation != .pulling),
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
            disabled: !online || (viewModel.remoteOperation != nil && viewModel.remoteOperation != .pushing),
            action: { Task { await viewModel.push() } }
        ) {
            Button("Force push (only if remote unchanged)", role: .destructive) {
                if preferences.confirmForcePush {
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
    RemoteToolbarGroup(viewModel: .preview, online: true)
        .padding()
}
