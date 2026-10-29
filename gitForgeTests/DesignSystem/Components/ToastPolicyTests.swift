import Foundation
import Testing
@testable import gitForge

@Suite("Toast — dismissal policy")
@MainActor
struct ToastPolicyTests {

    @Test("Ok, info and warn dismiss themselves after 4 s", arguments: [ToastMessage.Kind.ok, .info, .warn])
    func autoDismiss(kind: ToastMessage.Kind) {
        #expect(ToastMessage(message: "x", kind: kind).autoDismissAfter == .seconds(4))
    }

    @Test("Errors dismiss themselves too, after 10 s so the remedy can be read")
    func errorsLeaveLater() {
        #expect(ToastMessage(message: "x", kind: .error).autoDismissAfter == .seconds(10))
    }

    @Test("No toast leaves while the pointer rests on it", arguments: [ToastMessage.Kind.ok, .info, .warn, .error])
    func hoverHolds(kind: ToastMessage.Kind) {
        #expect(ToastMessage(message: "x", kind: kind).dismissDelay(isHovered: true) == nil)
    }

    @Test("Once the pointer leaves, the full lifetime starts again", arguments: [ToastMessage.Kind.ok, .info, .warn, .error])
    func unhoveredRunsFullLifetime(kind: ToastMessage.Kind) {
        let toast = ToastMessage(message: "x", kind: kind)
        #expect(toast.dismissDelay(isHovered: false) == toast.autoDismissAfter)
    }

    @Test("Errors wrap in full so the remedy at the end stays readable; the rest keep to two lines")
    func lineLimit() {
        #expect(ToastMessage(message: "x", kind: .error).lineLimit == nil)
        #expect(ToastMessage(message: "x", kind: .ok).lineLimit == 2)
    }
}
