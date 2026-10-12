import SwiftUI

/// "Add instance" (P4 spec §5.3).
struct AddInstanceSheet: View {
    var request = AddInstanceRequest()
    var onAdded: (HostingInstance) -> Void = { _ in }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var model: AddInstanceModel?
    @State private var trustHost: String?
    @State private var showAdvanced = false

    var body: some View {
        Group {
            if let model {
                form(model)
            } else {
                Color.clear.frame(width: 460, height: 160)
            }
        }
        .onAppear {
            if model == nil { model = AddInstanceModel(store: appState.accounts, kind: request.kind, url: request.url) }
        }
    }

    private func form(_ model: AddInstanceModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Add instance").textRole(.title)
            Picker("Type", selection: Bindable(model).kind) {
                Text("GitLab").tag(HostingInstance.Kind.gitlab)
                Text("GitHub Enterprise").tag(HostingInstance.Kind.github)
            }
            .pickerStyle(.segmented)
            GFTextField(placeholder: "https://git.example.com", text: Bindable(model).url)
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                GFTextField(placeholder: model.defaultAPIURL.isEmpty ? "API URL" : model.defaultAPIURL,
                            text: Bindable(model).apiURL)
            }
            status(model.state)
            HStack {
                Spacer()
                GFButton(title: "Cancel") { dismiss() }
                GFButton(title: "Add", style: .primary, disabled: model.state == .verifying) {
                    Task { await model.add() }
                }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 460)
        .onChange(of: model.state) { _, state in
            switch state {
            case .needsTrust(let host): trustHost = host
            case .added(let instance, nil): onAdded(instance); dismiss()
            default: break
            }
        }
        .trustCertificatePrompt(host: $trustHost) { Task { await model.add() } }
    }

    @ViewBuilder
    private func status(_ state: AddInstanceModel.State) -> some View {
        switch state {
        case .editing:
            EmptyView()
        case .needsTrust(let host):
            HStack(spacing: Spacing.s8) {
                Text("macOS doesn't trust \(host)'s certificate.").textRole(.callout).foregroundStyle(theme.colors.warn)
                Button("Review Certificate…") { trustHost = host }
                    .buttonStyle(.link)
            }
        case .verifying:
            HStack(spacing: Spacing.s6) { ProgressView().controlSize(.small); Text("Checking the API…").textRole(.callout) }
        case .failed(let message):
            Text(message).textRole(.callout).foregroundStyle(theme.colors.del)
        case .added(let instance, let warning?):
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text(warning).textRole(.callout).foregroundStyle(theme.colors.warn)
                GFButton(title: "Done", style: .primary) { onAdded(instance); dismiss() }
            }
        case .added:
            EmptyView()
        }
    }
}
