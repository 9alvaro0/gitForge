import SwiftUI

enum RepositoryTab: String, CaseIterable, Identifiable {
    case history
    case changes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .changes: "Changes"
        }
    }

    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .changes: "pencil.line"
        }
    }
}

struct RepositoryView: View {
    let repository: Repository
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let viewModel = appState.activeViewModel,
               viewModel.repository.url == repository.url {
                RepositoryContentView(repository: repository, viewModel: viewModel)
                    .id(repository.url)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: repository.url) {
            guard let viewModel = appState.activeViewModel else { return }
            await viewModel.loadInitial()
            await viewModel.loadRefs()
            await viewModel.refreshStatus()
        }
    }
}

private struct RepositoryContentView: View {
    let repository: Repository
    @Bindable var viewModel: RepositoryViewModel
    @State private var tab: RepositoryTab = .history

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case .history:
                HSplitView {
                    CommitLogView(viewModel: viewModel)
                        .frame(minWidth: 360, idealWidth: 480)
                    detailPane
                        .frame(minWidth: 320)
                }
            case .changes:
                ChangesView(viewModel: viewModel)
            }
        }
        .modifier(RemoteFailureAlertModifier(viewModel: viewModel))
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
            Picker("", selection: $tab) {
                ForEach(RepositoryTab.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .labelsHidden()
            if tab == .history {
                BranchFilterMenu(viewModel: viewModel)
            } else {
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

private struct RemoteToolbar: View {
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
            button(
                icon: "arrow.clockwise",
                label: "Fetch",
                badge: nil,
                isLoading: viewModel.remoteOperation == .fetching,
                disabled: viewModel.remoteOperation != nil,
                action: { Task { await viewModel.fetch() } }
            )
            button(
                icon: "arrow.down",
                label: "Pull",
                badge: viewModel.behindCount > 0 ? "\(viewModel.behindCount)" : nil,
                isLoading: viewModel.remoteOperation == .pulling,
                disabled: !canPull,
                action: { Task { await viewModel.pull() } }
            )
            button(
                icon: "arrow.up",
                label: "Push",
                badge: viewModel.aheadCount > 0 ? "\(viewModel.aheadCount)" : nil,
                isLoading: viewModel.remoteOperation == .pushing,
                disabled: !canPush,
                action: { Task { await viewModel.push() } }
            )
        }
    }

    private func button(
        icon: String,
        label: String,
        badge: String?,
        isLoading: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minWidth: 78)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
    }
}

private struct RemoteFailureAlertModifier: ViewModifier {
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

private struct BranchFilterMenu: View {
    @Bindable var viewModel: RepositoryViewModel

    private var label: String {
        switch viewModel.selectedFilterBranch {
        case nil:
            return viewModel.currentBranchName ?? "HEAD"
        case "ALL":
            return "All branches"
        case .some(let name):
            return name
        }
    }

    var body: some View {
        Menu {
            Button {
                viewModel.selectedFilterBranch = nil
            } label: {
                if viewModel.selectedFilterBranch == nil {
                    Label("Current Branch", systemImage: "checkmark")
                } else {
                    Text("Current Branch")
                }
            }

            Button {
                viewModel.selectedFilterBranch = "ALL"
            } label: {
                if viewModel.selectedFilterBranch == "ALL" {
                    Label("All Branches", systemImage: "checkmark")
                } else {
                    Text("All Branches")
                }
            }

            if !viewModel.localBranches.isEmpty {
                Divider()
                Section("Local") {
                    ForEach(viewModel.localBranches) { ref in
                        Button {
                            viewModel.selectedFilterBranch = ref.name
                        } label: {
                            if viewModel.selectedFilterBranch == ref.name {
                                Label(ref.name, systemImage: "checkmark")
                            } else {
                                Text(ref.name)
                            }
                        }
                    }
                }
            }

            if !viewModel.remoteBranches.isEmpty {
                Section("Remote") {
                    ForEach(viewModel.remoteBranches) { ref in
                        Button {
                            viewModel.selectedFilterBranch = ref.name
                        } label: {
                            if viewModel.selectedFilterBranch == ref.name {
                                Label(ref.name, systemImage: "checkmark")
                            } else {
                                Text(ref.name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 120, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview {
    RepositoryView(repository: Repository.preview)
        .environment(AppState.previewWithActive)
        .frame(width: 1280, height: 680)
}
