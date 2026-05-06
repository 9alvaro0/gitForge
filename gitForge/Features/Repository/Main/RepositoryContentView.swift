import SwiftUI

struct RepositoryContentView: View {
    let repository: Repository
    @Bindable var viewModel: RepositoryViewModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // Both panes are kept in the hierarchy at all times so the HSplitView /
            // VSplitView dividers don't reset every time the tab is switched.
            ZStack {
                HSplitView {
                    CommitLogView(viewModel: viewModel)
                        .frame(minWidth: 320, idealWidth: 480)
                        .layoutPriority(1)
                    detailPane
                        .frame(minWidth: 280)
                        .layoutPriority(0)
                }
                .opacity(viewModel.currentTab == .history ? 1 : 0)
                .allowsHitTesting(viewModel.currentTab == .history)

                ChangesView(viewModel: viewModel)
                    .opacity(viewModel.currentTab == .changes ? 1 : 0)
                    .allowsHitTesting(viewModel.currentTab == .changes)
            }
        }
        .modifier(RemoteFailureAlertModifier(viewModel: viewModel))
        .modifier(DiscardAllAlertModifier(appState: appState, viewModel: viewModel))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .font(.title3.weight(.semibold))
                Text(repository.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            RemoteToolbar(viewModel: viewModel)
            Picker("", selection: $viewModel.currentTab) {
                ForEach(RepositoryTab.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
            if viewModel.currentTab == .changes {
                changesBadge
            }
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var changesBadge: some View {
        let total = viewModel.status.files.count
        if total > 0 {
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                Text("\(total)")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.background.secondary, in: Capsule())
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let commit = viewModel.selectedCommit {
            CommitDetailView(commit: commit, viewModel: viewModel)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.righthalf.inset.filled.arrow.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select a commit to see its details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
