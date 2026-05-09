import Foundation

@MainActor
extension OnboardingState {
    /// Pre-populated state used by step previews so each one can render
    /// the "user already typed something" path without a closure-with-return
    /// inside the `#Preview` body (ViewBuilder rejects explicit returns).
    static var previewFilled: OnboardingState {
        let s = OnboardingState()
        s.name = "Alvaro Guerra"
        s.email = "alvaro@example.com"
        s.cloneDirectory = "/Users/alvaro/code"
        return s
    }
}
