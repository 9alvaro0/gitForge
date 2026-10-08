import SwiftUI

/// Trust flow for a host whose certificate macOS rejects. Setting `host`
/// reads the certificate it presents and asks the user to confirm its
/// SHA-256 fingerprint; only on confirmation is that exact certificate
/// pinned in `RemoteHostTrust`. `host` is reset to nil when the flow ends.
struct TrustCertificatePrompt: ViewModifier {
    @Binding var host: String?
    let onTrusted: () -> Void

    private struct Pending: Equatable {
        let host: String
        let fingerprint: String
    }

    @State private var pending: Pending?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .task(id: host) {
                guard let host else { return }
                if let fingerprint = await RemoteHostTrust.presentedFingerprint(host: host) {
                    pending = Pending(host: host, fingerprint: fingerprint)
                } else {
                    failure = "Couldn't read the certificate presented by \(host). Check the host name and your connection."
                    self.host = nil
                }
            }
            .confirmationDialog(
                "Trust the certificate of \(pending?.host ?? "this host")?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { finish() } }),
                titleVisibility: .visible,
                presenting: pending
            ) { pending in
                Button("Trust this certificate") {
                    RemoteHostTrust.shared.trust(pending.host, fingerprint: pending.fingerprint)
                    onTrusted()
                    finish()
                }
                Button("Cancel", role: .cancel) { finish() }
            } message: { pending in
                Text("macOS doesn't trust this certificate. Only continue if the fingerprint matches the one your administrator gave you — afterwards, any other certificate for this host is refused.\n\nSHA-256\n\(pending.fingerprint)")
            }
            .alert("Couldn't verify the host",
                   isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private func finish() {
        pending = nil
        host = nil
    }
}

extension View {
    /// See `TrustCertificatePrompt`.
    func trustCertificatePrompt(host: Binding<String?>, onTrusted: @escaping () -> Void) -> some View {
        modifier(TrustCertificatePrompt(host: host, onTrusted: onTrusted))
    }
}
