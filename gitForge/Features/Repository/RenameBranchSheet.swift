import SwiftUI

struct RenameBranchSheet: View {
    let oldName: String
    let onRename: (_ newName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newName: String
    @FocusState private var isNameFocused: Bool

    init(oldName: String, onRename: @escaping (_ newName: String) -> Void) {
        self.oldName = oldName
        self.onRename = onRename
        self._newName = State(initialValue: oldName)
    }

    private var isValid: Bool {
        BranchValidator.isValidName(newName) && newName != oldName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename branch")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("From: \(oldName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("New name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit { rename() }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") { rename() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { isNameFocused = true }
    }

    private func rename() {
        guard isValid else { return }
        onRename(newName.trimmingCharacters(in: .whitespaces))
        dismiss()
    }
}

#Preview {
    RenameBranchSheet(oldName: "feature/old-name") { _ in }
}
