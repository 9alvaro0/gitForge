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
        case appearance
        case defaults
        case firstRepo

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:    return String(localized: "Welcome")
            case .git:        return "Git"
            case .identity:   return String(localized: "Identity")
            case .appearance: return String(localized: "Appearance")
            case .defaults:   return String(localized: "Defaults")
            case .firstRepo:  return String(localized: "First repository")
            }
        }

        /// The second line of the step in the rail.
        var railSubtitle: String {
            switch self {
            case .welcome:    return String(localized: "What gitForge does")
            case .git:        return String(localized: "Find the git tool")
            case .identity:   return String(localized: "Name and email")
            case .appearance: return String(localized: "Theme, accent, density")
            case .defaults:   return String(localized: "Branch and clone folder")
            case .firstRepo:  return String(localized: "Open or clone a repo")
            }
        }

        var heading: String {
            switch self {
            case .welcome:    return String(localized: "Welcome to gitForge")
            case .git:        return String(localized: "Find git")
            case .identity:   return String(localized: "Who are you?")
            case .appearance: return String(localized: "Make it yours")
            case .defaults:   return String(localized: "Defaults")
            case .firstRepo:  return String(localized: "Add your first repository")
            }
        }

        var lede: String {
            switch self {
            case .welcome:
                return String(localized: "A native macOS git client built around fast history navigation, fluid diffs, and a quiet UI.")
            case .git:
                return String(localized: "gitForge drives the git command-line tool installed on this Mac.")
            case .identity:
                return String(localized: "git records your name and email on every commit. This writes to `~/.gitconfig` and applies to every repository.")
            case .appearance:
                return String(localized: "Pick a look. The preview updates as you go.")
            case .defaults:
                return String(localized: "Two preferences that pay off later. You can change them anytime in Settings.")
            case .firstRepo:
                return String(localized: "Pick how you want to get started — or skip and add one later.")
            }
        }

        /// Steps the user can rewind into. Step 0 has nothing behind it,
        /// firstRepo is terminal — any action there closes the flow.
        var canGoBack: Bool { rawValue > 0 && self != .firstRepo }

        /// Steps that the user is allowed to skip without completing.
        /// Identity is mandatory because committing without it produces
        /// junk authorship; everything after is opt-in.
        var canSkip: Bool {
            switch self {
            case .welcome, .git, .identity:                return false
            case .appearance, .defaults, .firstRepo:       return true
            }
        }

        var primaryLabel: String {
            switch self {
            case .welcome:    return String(localized: "Get started")
            case .git, .identity, .appearance, .defaults: return String(localized: "Continue")
            case .firstRepo:  return ""
            }
        }

        var next: Step? { Step(rawValue: rawValue + 1) }

        /// "Next: Defaults" beside the primary button.
        var nextLabel: String? { next.map { String(localized: "Next: \($0.title)") } }

        var counter: String {
            let number = rawValue + 1
            let total = Step.allCases.count
            return String(localized: "Step \(number) of \(total)")
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
