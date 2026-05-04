import SwiftUI

struct CommitComposerView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var fileToConfirmDiscard: WorkingCopyFile?
    @State private var isCommitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COMMIT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Amend last commit", isOn: $viewModel.amendMode)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)
            }

            TextField("Subject", text: $viewModel.commitSubject, axis: .horizontal)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }

            TextEditor(text: $viewModel.commitBody)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.commitBody.isEmpty {
                        Text("Body (optional)")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            if let error = viewModel.commitError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if viewModel.amendMode {
                    Label("Amending the latest commit", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button {
                    commit()
                } label: {
                    if isCommitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(viewModel.amendMode ? "Amend Commit" : "Commit", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isCommitting || viewModel.commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!viewModel.amendMode && !viewModel.status.hasStagedChanges))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .background(.bar)
    }

    private func commit() {
        guard !isCommitting else { return }
        isCommitting = true
        Task {
            _ = await viewModel.commit()
            isCommitting = false
        }
    }
}

#Preview {
    CommitComposerView(viewModel: RepositoryViewModel.preview)
        .frame(width: 480)
}
