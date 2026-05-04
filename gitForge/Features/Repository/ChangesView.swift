import SwiftUI

struct ChangesView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var pendingDiscard: WorkingCopyFile?

    var body: some View {
        VSplitView {
            fileSections
            CommitComposerView(viewModel: viewModel)
                .frame(minHeight: 220, idealHeight: 260)
        }
        .task {
            await viewModel.refreshStatus()
        }
        .alert(
            "Discard changes?",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            presenting: pendingDiscard
        ) { file in
            Button("Discard", role: .destructive) {
                Task {
                    await viewModel.discardChanges([file])
                    pendingDiscard = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDiscard = nil }
        } message: { file in
            Text("This will permanently discard local changes to “\(file.path)”. This cannot be undone.")
        }
    }

    private var fileSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.status.isClean {
                    cleanState
                } else {
                    if !viewModel.status.unstagedFiles.isEmpty {
                        sectionHeader(
                            title: "Unstaged",
                            count: viewModel.status.unstagedFiles.count,
                            actionTitle: "Stage All",
                            action: {
                                Task { await viewModel.stage(viewModel.status.unstagedFiles) }
                            }
                        )
                        ForEach(viewModel.status.unstagedFiles) { file in
                            FileChangeRow(
                                file: file,
                                isStagedSection: false,
                                onPrimary: { Task { await viewModel.stage([file]) } },
                                onDiscard: { pendingDiscard = file }
                            )
                            Divider()
                        }
                    }
                    if !viewModel.status.stagedFiles.isEmpty {
                        sectionHeader(
                            title: "Staged",
                            count: viewModel.status.stagedFiles.count,
                            actionTitle: "Unstage All",
                            action: {
                                Task { await viewModel.unstage(viewModel.status.stagedFiles) }
                            }
                        )
                        ForEach(viewModel.status.stagedFiles) { file in
                            FileChangeRow(
                                file: file,
                                isStagedSection: true,
                                onPrimary: { Task { await viewModel.unstage([file]) } },
                                onDiscard: { pendingDiscard = file }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, count: Int, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text("\(title) (\(count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.background.secondary)
    }

    private var cleanState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green.gradient)
            Text("Working copy clean")
                .font(.headline)
            Text("Nothing to commit, nothing to stage.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
    }
}

#Preview("With changes") {
    ChangesView(viewModel: RepositoryViewModel.preview)
        .frame(width: 600, height: 720)
}

#Preview("Clean") {
    ChangesView(viewModel: RepositoryViewModel(repository: Repository.preview))
        .frame(width: 600, height: 720)
}
