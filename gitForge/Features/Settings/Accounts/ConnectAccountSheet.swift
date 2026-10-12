import AppKit
import SwiftUI

/// "Connect account" (P4 spec §5.2): one sheet that adapts to the instance
/// and method.
struct ConnectAccountSheet: View {
    let request: ConnectAccountRequest

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var model: ConnectAccountModel?
    @State private var addingInstance = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .padding(Spacing.s16)
        .frame(width: 460)
        .onAppear {
            guard model == nil else { return }
            let instanceId = request.instanceId ?? appState.accounts.instances.first?.id
            model = ConnectAccountModel(store: appState.accounts, connector: appState.accountConnector,
                                        instanceId: instanceId, replacing: request.replacing)
        }
        .onDisappear { model?.close() }
        .sheet(isPresented: $addingInstance) {
            AddInstanceSheet { instance in model?.instanceId = instance.id }
        }
    }

    @ViewBuilder
    private func content(_ model: ConnectAccountModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text(request.replacing == nil ? "Connect account" : "Reconnect account").textRole(.title)
            if let account = model.result {
                result(account, model)
            } else {
                form(model)
            }
        }
    }

    @ViewBuilder
    private func form(_ model: ConnectAccountModel) -> some View {
        Picker("Instance", selection: Binding(get: { model.instanceId }, set: { newValue in
            if newValue == nil { addingInstance = true } else { model.instanceId = newValue }
        })) {
            ForEach(model.instances) { instance in
                Text("\(instance.kind.label) · \(instance.host)").tag(Optional(instance.id))
            }
            Divider()
            Text("Add instance…").tag(UUID?.none)
        }
        .disabled(request.replacing != nil)

        if model.methods.count > 1 {
            Picker("Method", selection: Bindable(model).method) {
                Text("Sign in with browser").tag(ConnectAccountModel.Method.browser)
                Text("Use a token").tag(ConnectAccountModel.Method.token)
            }
            .pickerStyle(.segmented)
        } else {
            Text("Sign-in with the browser isn't set up for this instance.")
                .textRole(.callout).foregroundStyle(theme.colors.textTertiary)
        }

        switch model.method {
        case .browser: browser(model)
        case .token: token(model)
        }

        HStack {
            Spacer()
            GFButton(title: "Cancel") { model.cancel(); dismiss() }
        }
    }

    @ViewBuilder
    private func browser(_ model: ConnectAccountModel) -> some View {
        switch model.deviceFlow?.state {
        case nil, .idle?, .cancelled?:
            GFButton(title: "Get sign-in code", style: .primary) { model.startBrowser() }
        case .requestingCode?, .finishing?:
            ProgressView().controlSize(.small)
        case .waitingForUser(let code, let expiresAt)?:
            VStack(spacing: Spacing.s8) {
                Text(code.userCode).font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                GFButton(title: "Copy code & open browser", style: .primary) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    NSWorkspace.shared.open(code.verificationURIComplete ?? code.verificationURI)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(expiresAt.timeIntervalSince(context.date)))
                    Text("Waiting for approval in the browser… code expires in \(left / 60):\(String(format: "%02d", left % 60))")
                        .textRole(.callout).foregroundStyle(theme.colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        case .failed(let error)?:
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text(error.localizedDescription).textRole(.callout).foregroundStyle(theme.colors.del)
                GFButton(title: "Try again") { model.startBrowser() }
            }
        case .connected?:
            EmptyView()
        }
    }

    @ViewBuilder
    private func token(_ model: ConnectAccountModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text("1. Create a token with the scopes \(model.requiredScopes)").textRole(.callout)
            GFButton(title: "Create token in browser", size: .small) {
                if let url = model.createTokenURL { NSWorkspace.shared.open(url) }
            }
            Text("2. Paste it").textRole(.callout)
            SecureField("Token", text: Bindable(model).token)
                .textFieldStyle(.roundedBorder)
            if case .failed(let message) = model.tokenState {
                Text(message).textRole(.callout).foregroundStyle(theme.colors.del)
            }
            HStack {
                Spacer()
                if model.tokenState == .validating { ProgressView().controlSize(.small) }
                GFButton(title: "Connect", style: .primary,
                         disabled: model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.tokenState == .validating) {
                    Task { await model.connectToken() }
                }
            }
        }
    }

    @ViewBuilder
    private func result(_ account: HostingAccount, _ model: ConnectAccountModel) -> some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.ok)
            VStack(alignment: .leading) {
                Text(account.displayName ?? account.login ?? "Connected").textRole(.body, weight: .semibold)
                MonoText("\(account.login ?? "") · \(model.instance?.host ?? "")", dim: true)
            }
        }
        if model.scopesWarning {
            Text("Scopes couldn't be verified (fine-grained token).").textRole(.callout).foregroundStyle(theme.colors.warn)
        }
        Picker("Use it for identity profile", selection: Bindable(model).profileChoice) {
            Text("None").tag(UUID?.none)
            ForEach(appState.profiles.profiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        }
        HStack {
            Spacer()
            GFButton(title: "Done", style: .primary) { model.finish(); dismiss() }
        }
    }
}
