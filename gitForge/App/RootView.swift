import SwiftUI

/// Top of the view tree. Gates the UI on the onboarding flag first
/// (`OnboardingFlow` until completed) and then on `gitStatus` (checking ·
/// notFound · available). The actual app shell — sidebar, content router,
/// command palette, toasts — lives in `App/Shell/ShellView`.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("gitForge.onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        @Bindable var ui = appState.ui
        Group {
            if !onboardingCompleted {
                OnboardingFlow(onComplete: { onboardingCompleted = true })
            } else {
                switch appState.gitEnvironment.gitStatus {
                case .checking:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notFound:
                    GitNotFoundView()
                case .available:
                    ShellView()
                }
            }
        }
        .appTheme(ui.theme)
        .alert(
            ui.presentedError?.title ?? "",
            isPresented: $ui.presentedError.isPresent(),
            presenting: ui.presentedError
        ) { _ in
            // Cancel-role buttons in `.alert` automatically clear the
            // `isPresented` binding, which clears `presentedError` for us.
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
        .onAppear { ui.theme.systemColorScheme = systemColorScheme }
        .onChange(of: systemColorScheme) { _, scheme in
            ui.theme.systemColorScheme = scheme
        }
    }
}

private extension Binding {
    /// Adapts a `Binding<T?>` to a `Binding<Bool>` for SwiftUI presenters
    /// (`.alert(_:isPresented:)`, `.sheet(isPresented:)`, …) that key off a
    /// boolean flag while the source of truth is an optional payload. Reading
    /// returns `wrappedValue != nil`; writing `false` clears the optional,
    /// writing `true` is a no-op (the payload must be set explicitly).
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}

#Preview("Welcome (no active repo)") {
    RootView()
        .previewAppState(.preview)
        .frame(width: 1200, height: 720)
}

#Preview("Repository active") {
    RootView()
        .previewAppState(.previewWithActive)
        .frame(width: 1280, height: 760)
}

#Preview("Git not found") {
    RootView()
        .previewAppState(.previewMissingGit)
        .frame(width: 1100, height: 720)
}

#Preview("First-run onboarding") {
    RootView()
        .previewAppState(.previewEmpty)
        .frame(width: 1100, height: 720)
        .onAppear {
            // Reset the persisted flag so the preview always shows the flow,
            // not whatever the host machine has stored. Scoped to DEBUG so it
            // never ships.
            UserDefaults.standard.set(false, forKey: "gitForge.onboarding.completed")
        }
}
