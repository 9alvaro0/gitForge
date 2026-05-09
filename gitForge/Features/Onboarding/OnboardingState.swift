import Foundation
import Observation
import SwiftUI

/// Holds the current step of the onboarding flow plus the inputs the user
/// types across steps. Owned by `OnboardingFlow`; passed to each step view
/// so they can read/write the relevant fields and call `advance()` when
/// their work is done.
@Observable
@MainActor
final class OnboardingState {
    enum Step: Int, CaseIterable, Identifiable, Sendable {
        case welcome
        case git
        case identity
        case defaults
        case firstRepo

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:    return "Welcome"
            case .git:        return "Git"
            case .identity:   return "Identity"
            case .defaults:   return "Defaults"
            case .firstRepo:  return "First repository"
            }
        }

        /// Steps the user can rewind into. Step 0 has nothing behind it,
        /// step 4 (firstRepo) is terminal — any action there closes the flow.
        var canGoBack: Bool { rawValue > 0 && self != .firstRepo }

        /// Steps that the user is allowed to skip without completing.
        /// Identity is mandatory because committing without it produces
        /// junk authorship; everything after is opt-in.
        var canSkip: Bool {
            switch self {
            case .welcome, .git, .identity:    return false
            case .defaults, .firstRepo:        return true
            }
        }

        var primaryLabel: String {
            switch self {
            case .welcome:    return "Get started"
            case .git:        return "Continue"
            case .identity:   return "Continue"
            case .defaults:   return "Continue"
            case .firstRepo:  return ""
            }
        }
    }

    var currentStep: Step = .welcome

    // Identity step
    var name: String = ""
    var email: String = ""
    var signingKey: String = ""
    var showSigningField: Bool = false

    // Defaults step
    var defaultBranch: String = "main"
    var cloneDirectory: String = ""

    /// Validation gate for the Continue button on the Identity step.
    /// `@/.` substring check is intentionally lax — git itself accepts
    /// anything as `user.email`, so we only reject the obviously wrong.
    var identityValid: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && !e.isEmpty && e.contains("@") && e.contains(".")
    }

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    func back() {
        guard let prev = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prev
    }

    /// Pre-fills fields from `git config --global` so users with an existing
    /// `.gitconfig` see the Identity / Defaults steps already filled in and
    /// can simply press Continue.
    func prefill(from config: GitGlobalConfig, lastCloneDir: String) {
        if name.isEmpty, let n = config.identity.name { name = n }
        if email.isEmpty, let e = config.identity.email { email = e }
        if signingKey.isEmpty, let k = config.signingKey { signingKey = k }
        if let branch = config.defaultBranch, !branch.isEmpty { defaultBranch = branch }
        if cloneDirectory.isEmpty {
            cloneDirectory = lastCloneDir.isEmpty
                ? ("~/code" as NSString).expandingTildeInPath
                : lastCloneDir
        }
    }
}
