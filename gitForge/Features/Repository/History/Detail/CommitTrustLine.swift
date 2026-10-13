import SwiftUI

/// Under the commit's parents: its signature (when signed) and the CI that
/// ran on it (when the host reports any). The detail column shows the line
/// only when `hasContent`.
struct CommitTrustLine: View {
    let signature: CommitSignature?
    let checks: [CICheck]?

    @Environment(\.appTheme) private var theme
    @State private var showsChecks = false

    static func hasContent(signature: CommitSignature?, checks: [CICheck]?) -> Bool {
        signature != nil || checks.flatMap { CIStatus.summarize($0) } != nil
    }

    var body: some View {
        HStack(spacing: Spacing.s12) {
            if let signature { signatureBadge(signature) }
            if let checks, let status = CIStatus.summarize(checks) { ciButton(status, count: checks.count) }
        }
    }

    private func signatureBadge(_ signature: CommitSignature) -> some View {
        let tint = color(for: signature.status)
        return HStack(spacing: Spacing.s4) {
            Image(systemName: symbol(for: signature.status))
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(signature.label)
                .textRole(.caption, weight: .semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .help(Self.tooltip(for: signature))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signature: \(signature.label)")
    }

    private func ciButton(_ status: CIStatus, count: Int) -> some View {
        Button {
            showsChecks = true
        } label: {
            HStack(spacing: Spacing.s4) {
                CIBadge(status: status)
                Text(count == 1 ? "1 check" : "\(count) checks")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .help("Show the CI checks of this commit")
        .accessibilityLabel("CI \(status.label), \(count) checks")
        .popover(isPresented: $showsChecks, arrowEdge: .bottom) {
            ScrollView {
                PullRequestChecksTab(checks: checks ?? [], loading: false)
                    .padding(Spacing.s12)
            }
            .frame(width: 480)
            .frame(maxHeight: 420)
        }
    }

    private func symbol(for status: CommitSignature.Status) -> String {
        switch status {
        case .verified: "checkmark.seal.fill"
        case .bad, .revoked: "xmark.seal.fill"
        case .untrusted, .expired, .unverifiable: "seal"
        }
    }

    private func color(for status: CommitSignature.Status) -> Color {
        switch status {
        case .verified: theme.colors.ok
        case .bad, .revoked: theme.colors.del
        case .expired, .untrusted: theme.colors.warn
        case .unverifiable: theme.colors.textTertiary
        }
    }

    static func tooltip(for signature: CommitSignature) -> String {
        var lines = [signature.label]
        if let signer = signature.signer { lines.append("Signer: \(signer)") }
        if let key = signature.key { lines.append("Key: \(key)") }
        if signature.status == .unverifiable {
            lines.append("Git couldn't check it: the key isn't in your keyring (GPG) or allowed signers file (SSH), or the signing tool isn't on the app's PATH.")
        }
        return lines.joined(separator: "\n")
    }
}
