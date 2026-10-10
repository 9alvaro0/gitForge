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

    @Test("Errors stay until dismissed")
    func errorsStay() {
        #expect(ToastMessage(message: "x", kind: .error).autoDismissAfter == nil)
    }

    @Test("Errors wrap in full so the remedy at the end stays readable; the rest keep to two lines")
    func lineLimit() {
        #expect(ToastMessage(message: "x", kind: .error).lineLimit == nil)
        #expect(ToastMessage(message: "x", kind: .ok).lineLimit == 2)
    }
}
