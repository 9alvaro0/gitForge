import SwiftUI

struct ChangesView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var pendingDiscard: WorkingCopyFile?

    var body: some View {
        VSplitView {
            HSplitView {
                fileSections
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                    .layoutPriority(0)
                DiffView(
                    hunks: viewModel.workingCopyDiff,
                    isLoading: viewModel.loadingWorkingCopyDiff,
                    emptyMessage: untrackedMessage
                )
                .frame(minWidth: 280)
                .layoutPriority(1)
            }
            CommitComposerView(viewModel: viewModel)
                .frame(minHeight: 200, idealHeight: 240)
        }
        .task {
            await viewModel.refreshStatus()
        }
        .modifier(DiscardConfirmationModifier(target: $pendingDiscard, viewModel: viewModel))
    }

    private var untrackedMessage: String {
        if viewModel.selectedWorkingCopyFile?.isUntracked == true {
            return "Untracked file — stage to compare with the index"
        }
        return "Select a file to see its diff"
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
                                isSelected: viewModel.selectedWorkingCopyFile?.id == file.id,
                                onSelect: { viewModel.selectedWorkingCopyFile = file },
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
                                isSelected: viewModel.selectedWorkingCopyFile?.id == file.id,
                                onSelect: { viewModel.selectedWorkingCopyFile = file },
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

private struct DiscardConfirmationModifier: ViewModifier {
    @Binding var target: WorkingCopyFile?
    let viewModel: RepositoryViewModel

    private var isPresented: Binding<Bool> {
        Binding(
            get: { target != nil },
            set: { if !$0 { target = nil } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(
            "Discard changes?",
            isPresented: isPresented,
            presenting: target
        ) { file in
            Button("Discard", role: .destructive) {
                Task {
                    await viewModel.discardChanges([file])
                    target = nil
                }
            }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { file in
            Text("This will permanently discard local changes to “\(file.path)”. This cannot be undone.")
        }
    }
}

#Preview("With changes") {
    ChangesView(viewModel: RepositoryViewModel.preview)
        .frame(width: 1000, height: 720)
}

#Preview("Clean") {
    ChangesView(viewModel: RepositoryViewModel(repository: Repository.preview))
        .frame(width: 1000, height: 720)
}
