import Foundation
import Testing
@testable import gitForge

@Suite("Onboarding steps")
@MainActor
struct OnboardingStateTests {
    typealias Step = OnboardingState.Step

    @Test("Appearance sits between Identity and Defaults")
    func order() {
        #expect(Step.allCases == [.welcome, .git, .identity, .appearance, .defaults, .firstRepo])
    }

    @Test("Appearance can be skipped and gone back from, and continues")
    func appearanceRules() {
        #expect(Step.appearance.canSkip)
        #expect(Step.appearance.canGoBack)
        #expect(Step.appearance.primaryLabel == "Continue")
        #expect(!Step.identity.canSkip)
    }

    @Test("Each step names the next one and its place")
    func navigation() {
        #expect(Step.identity.nextLabel == "Next: Appearance")
        #expect(Step.appearance.nextLabel == "Next: Defaults")
        #expect(Step.firstRepo.nextLabel == nil)
        #expect(Step.appearance.counter == "Step 4 of 6")
        #expect(Step.welcome.counter == "Step 1 of 6")
    }

    @Test("Every step has a rail subtitle, a heading and a lede")
    func copy() {
        for step in Step.allCases {
            #expect(!step.railSubtitle.isEmpty)
            #expect(!step.heading.isEmpty)
            #expect(!step.lede.isEmpty)
        }
        #expect(Step.appearance.heading == "Make it yours")
    }

    @Test("Advancing from Identity lands on Appearance")
    func advance() {
        let state = OnboardingState()
        state.currentStep = .identity
        state.advance()
        #expect(state.currentStep == .appearance)
        state.advance()
        #expect(state.currentStep == .defaults)
    }
}
