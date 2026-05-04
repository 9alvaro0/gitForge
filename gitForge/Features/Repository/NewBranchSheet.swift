import SwiftUI

struct NewBranchSheet: View {
    let baseDescription: String
    var startingSha: String? = nil
    let onCreate: (_ name: String, _ checkout: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var checkout: Bool = true
    @FocusState private var isNameFocused: Bool

    private var isValid: Bool { BranchValidator.isValidName(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Branch")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Starting from \(baseDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("branch-name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit { create() }
            }

            Toggle("Checkout after create", isOn: $checkout)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard isValid else { return }
        onCreate(name.trimmingCharacters(in: .whitespaces), checkout)
        dismiss()
    }
}

#Preview {
    NewBranchSheet(baseDescription: "main") { _, _ in }
}
