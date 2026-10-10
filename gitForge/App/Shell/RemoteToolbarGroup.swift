import SwiftUI

/// Fetch + Pull (split) + Push (split) for the shell toolbar on every
/// repository screen (redesign spec §6.1). Native controls only: the
/// toolbar's Liquid Glass capsule is the one and only chrome, so nothing
/// here draws its own background. Force-with-lease sits behind a
/// confirmation when `confirmForcePush` is on. Offline disables the group.
struct RemoteToolbarGroup: View {
    @Bindable var viewModel: RepositoryViewModel
    let online: Bool

    @Environment(\.appPreferences) private var preferences
    @State private var pendingForcePush = false

    var body: some View {
        ControlGroup {
            Button { Task { await viewModel.fetch() } } label: {
                label("Fetch", systemImage: "arrow.triangle.2.circlepath",
                      loading: viewModel.remoteOperation == .fetching)
            }
            .disabled(!online || (viewModel.remoteOperation != nil && viewModel.remoteOperation != .fetching))
            .help(ShellStatus.fetchHelp(lastFetch: viewModel.lastFetchedAt, now: .now, online: online))

            Menu {
                Button("Pull (only if no merge needed)") {
                    Task { await viewModel.pull(ffOnly: true) }
                }
                Button("Pull and rebase my commits") {
                    Task { await viewModel.pull(rebase: true) }
                }
            } label: {
                label(countedTitle("Pull", viewModel.behindCount), systemImage: "arrow.down.to.line",
                      loading: viewModel.remoteOperation == .pulling)
            } primaryAction: {
                Task { await viewModel.pull() }
            }
            // Pull is also a local mutation (see `RepositoryViewModel.pull`).
            .disabled(!online || ((viewModel.remoteOperation != nil || viewModel.isMutating)
                && viewModel.remoteOperation != .pulling))
            .help(online ? "Pull" : "Offline")

            Menu {
                Button("Force push (only if remote unchanged)", role: .destructive) {
                    if preferences.confirmForcePush {
                        pendingForcePush = true
                    } else {
                        Task { await viewModel.push(forceWithLease: true) }
                    }
                }
            } label: {
                label(countedTitle("Push", viewModel.aheadCount), systemImage: "arrow.up.to.line",
                      loading: viewModel.remoteOperation == .pushing)
            } primaryAction: {
                Task { await viewModel.push() }
            }
            .disabled(!online || (viewModel.remoteOperation != nil && viewModel.remoteOperation != .pushing))
            .help(online ? "Push" : "Offline")
        }
        .labelStyle(.titleAndIcon)
        // A ControlGroup reports a flexible width; without this the toolbar
        // reserves too much room and pushes items into its overflow menu.
        .fixedSize()
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

    /// "Push 2": the count rides in the title, as in the design.
    private func countedTitle(_ title: String, _ count: Int) -> String {
        count > 0 ? "\(title) \(count)" : title
    }

    @ViewBuilder
    private func label(_ title: String, systemImage: String, loading: Bool) -> some View {
        if loading {
            Label { Text(title) } icon: { ProgressView().controlSize(.small) }
        } else {
            Label(title, systemImage: online ? systemImage : "wifi.slash")
        }
    }
}

#Preview {
    RemoteToolbarGroup(viewModel: .preview, online: true)
        .padding()
}
