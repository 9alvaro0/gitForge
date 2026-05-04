import SwiftUI

struct RemoteToolbar: View {
    @Bindable var viewModel: RepositoryViewModel

    private var hasUpstream: Bool { viewModel.upstream != nil }
    private var canPull: Bool {
        hasUpstream && viewModel.behindCount > 0 && viewModel.remoteOperation == nil
    }
    private var canPush: Bool {
        viewModel.remoteOperation == nil && (viewModel.aheadCount > 0 || !hasUpstream)
    }

    var body: some View {
        HStack(spacing: 4) {
            RemoteToolbarButton(
                icon: "arrow.clockwise",
                label: "Fetch",
                badge: nil,
                isLoading: viewModel.remoteOperation == .fetching,
                disabled: viewModel.remoteOperation != nil,
                action: { Task { await viewModel.fetch() } }
            )
            RemoteToolbarButton(
                icon: "arrow.down",
                label: "Pull",
                badge: viewModel.behindCount > 0 ? "\(viewModel.behindCount)" : nil,
                isLoading: viewModel.remoteOperation == .pulling,
                disabled: !canPull,
                action: { Task { await viewModel.pull() } }
            )
            RemoteToolbarButton(
                icon: "arrow.up",
                label: "Push",
                badge: viewModel.aheadCount > 0 ? "\(viewModel.aheadCount)" : nil,
                isLoading: viewModel.remoteOperation == .pushing,
                disabled: !canPush,
                action: { Task { await viewModel.push() } }
            )
        }
    }
}

private struct RemoteToolbarButton: View {
    let icon: String
    let label: String
    let badge: String?
    let isLoading: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: icon)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
    }
}
