import SwiftUI

/// The request-driven sheets other screens raise: Connect account, Add
/// instance and Choose an account. macOS shows one sheet per window at a
/// time, so whoever is frontmost presents them: the shell normally, the
/// clone sheet while it's open (`enabled` switches the shell's off), and
/// Connect / Add instance for the chooser while they're up.
private struct RequestSheets: ViewModifier {
    let enabled: Bool
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .sheet(item: binding(\.connectAccountRequest)) { request in
                ConnectAccountSheet(request: request)
            }
            .sheet(item: binding(\.addInstanceRequest)) { request in
                AddInstanceSheet(request: request)
            }
            // Connect account and Add instance present the chooser
            // themselves while they're up (a push started meanwhile).
            .accountChooserSheet(enabled: enabled && appState.ui.connectAccountRequest == nil
                                              && appState.ui.addInstanceRequest == nil)
    }

    private func binding<T: Identifiable>(_ keyPath: ReferenceWritableKeyPath<WorkspaceUI, T?>) -> Binding<T?> {
        let ui = appState.ui
        return Binding(get: { enabled ? ui[keyPath: keyPath] : nil },
                       set: { if enabled { ui[keyPath: keyPath] = $0 } })
    }
}

/// "Choose an account" for a remote operation waiting on the user. Only the
/// frontmost sheet host may enable it: macOS shows one sheet per window
/// level, and a request nobody can present leaves the operation hanging.
private struct AccountChooserSheet: ViewModifier {
    let enabled: Bool
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { enabled ? appState.accountChooser.request : nil }, set: { _ in })) { request in
                ChooseAccountSheet(request: request, profiles: appState.profiles.profiles,
                                   providerLabel: appState.accounts.instance(forHost: request.remote.host)?.kind.label) {
                    appState.accountChooser.answer($0, for: request.id)
                }
                // The sheet went away some other way: that's a Cancel (ignored
                // if it was already answered).
                .onDisappear { appState.accountChooser.answer(nil, for: request.id) }
            }
    }
}

/// Global error alert, presented by whoever is frontmost (see `RequestSheets`).
private struct ErrorAlert: ViewModifier {
    let enabled: Bool
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        let ui = appState.ui
        content.alert(
            ui.presentedError?.title ?? "",
            isPresented: Binding(get: { enabled && ui.presentedError != nil },
                                 set: { if !$0, enabled { ui.presentedError = nil } }),
            presenting: ui.presentedError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}

extension View {
    func requestSheets(enabled: Bool = true) -> some View {
        modifier(RequestSheets(enabled: enabled))
    }

    func accountChooserSheet(enabled: Bool = true) -> some View {
        modifier(AccountChooserSheet(enabled: enabled))
    }

    func errorAlert(enabled: Bool = true) -> some View {
        modifier(ErrorAlert(enabled: enabled))
    }
}
