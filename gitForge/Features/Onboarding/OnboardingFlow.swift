import SwiftUI

/// First-run flow shown by `RootView` until `gitForge.onboarding.completed`
/// flips to `true`. Walks the user through five steps; identity is the only
/// hard gate after `git` itself, defaults / first repo are skippable.
struct OnboardingFlow: View {
    let onComplete: () -> Void

    @State private var state = OnboardingState()
    @State private var busy = false
    @State private var prefilled = false

    @Environment(AppState.self) private var appState
    @Environment(GitEnvironment.self) private var gitEnvironment

    /// Same key `CloneView` reads from — picking a default during onboarding
    /// pre-fills the next clone session for free.
    @AppStorage("gitForge.clone.lastParentDir") private var lastParentDir: String = ""

    var body: some View {
        OnboardingShell(
            currentStep: state.currentStep,
            primaryLabel: state.currentStep.primaryLabel,
            primaryEnabled: primaryEnabled,
            primaryBusy: busy,
            onBack: { state.back() },
            onSkip: handleSkip,
            onPrimary: { Task { await handlePrimary() } }
        ) {
            stepContent
        }
        .task { prefillIfNeeded() }
        .onChange(of: appState.catalog.activeRepository) { _, repo in
            // Opening a folder via FirstRepoStep arrives here once the catalog
            // confirms the activation. Closing the flow then drops the user
            // straight into the new repo's history.
            if repo != nil, state.currentStep == .firstRepo { onComplete() }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch state.currentStep {
        case .welcome:
            WelcomeStep()
        case .git:
            GitStep(onAvailable: { if state.currentStep == .git { state.advance() } })
        case .identity:
            IdentityStep(state: state)
        case .defaults:
            DefaultsStep(state: state, onPickDirectory: pickCloneDirectory)
        case .firstRepo:
            FirstRepoStep(
                onOpenLocal: openLocal,
                onClone: openClonePane,
                onConnect: openClonePane
            )
        }
    }

    private var primaryEnabled: Bool {
        switch state.currentStep {
        case .welcome:    return true
        case .git:        return gitEnvironment.gitStatus == .available
        case .identity:   return state.identityValid
        case .defaults:   return true
        case .firstRepo:  return false
        }
    }

    private func handlePrimary() async {
        switch state.currentStep {
        case .welcome, .git:
            state.advance()
        case .identity:
            await commitIdentity()
        case .defaults:
            await commitDefaults()
        case .firstRepo:
            break
        }
    }

    private func handleSkip() {
        switch state.currentStep {
        case .defaults:   state.advance()
        case .firstRepo:  onComplete()
        default:          break
        }
    }

    private func commitIdentity() async {
        busy = true
        defer { busy = false }
        let n = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = state.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = state.signingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await gitEnvironment.setIdentity(name: n, email: e)
            if !key.isEmpty {
                try await gitEnvironment.setSigningKey(key)
            }
            state.advance()
        } catch {
            appState.ui.presentedError = PresentedError(error: error, title: "Couldn’t save identity")
        }
    }

    private func commitDefaults() async {
        busy = true
        defer { busy = false }
        let branch = state.defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = state.cloneDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await gitEnvironment.setDefaultBranch(branch.isEmpty ? nil : branch)
            if !dir.isEmpty { lastParentDir = dir }
            state.advance()
        } catch {
            appState.ui.presentedError = PresentedError(error: error, title: "Couldn’t save defaults")
        }
    }

    private func openLocal() {
        Task { await appState.presentOpenRepositoryPanel() }
    }

    private func openClonePane() {
        appState.ui.workspaceSection = .clone
        onComplete()
    }

    private func pickCloneDirectory() {
        Task {
            if let dir = await appState.pickDirectoryPath(prompt: "Default clone directory") {
                state.cloneDirectory = dir
            }
        }
    }

    private func prefillIfNeeded() {
        guard !prefilled else { return }
        state.prefill(from: gitEnvironment.globalConfig, lastCloneDir: lastParentDir)
        prefilled = true
    }
}

#Preview("Flow — git available, empty config") {
    OnboardingFlow(onComplete: {})
        .previewAppState(.previewEmpty)
        .frame(width: 900, height: 620)
}

#Preview("Flow — git missing") {
    OnboardingFlow(onComplete: {})
        .previewAppState(.previewMissingGit)
        .frame(width: 900, height: 620)
}
