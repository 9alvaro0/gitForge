import Foundation

/// A commit's GPG / SSH signature as `git log --format=%G?` judges it with
/// the user's own keyring or `gpg.ssh.allowedSignersFile`.
nonisolated struct CommitSignature: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        /// `G`: good signature from a trusted key.
        case verified
        /// `U`: good signature, key of unknown validity.
        case untrusted
        /// `X` / `Y`: good signature, but the signature or the key expired.
        case expired
        /// `R`: good signature made by a revoked key.
        case revoked
        /// `B`: the signature doesn't match the commit.
        case bad
        /// `E`: signed, but it can't be checked (missing key or tool).
        case unverifiable
    }

    let status: Status
    /// `%GS`: who signed it, when the key says.
    let signer: String?
    /// `%GK`: the key that made it.
    let key: String?

    var label: String {
        switch status {
        case .verified: "Verified"
        case .untrusted: "Signed · untrusted key"
        case .expired: "Signed · expired"
        case .revoked: "Signed · revoked key"
        case .bad: "Bad signature"
        case .unverifiable: "Signed · can't verify"
        }
    }

    /// Fields separated by U+001F: `%G?`, `%GS`, `%GK`. `nil` for an
    /// unsigned commit (`N`) or output it doesn't recognise.
    static func parse(_ output: String) -> CommitSignature? {
        let fields = output.trimmingCharacters(in: .newlines)
            .split(separator: "\u{1F}", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let code = fields.first else { return nil }
        let status: Status
        switch code {
        case "G": status = .verified
        case "U": status = .untrusted
        case "X", "Y": status = .expired
        case "R": status = .revoked
        case "B": status = .bad
        case "E": status = .unverifiable
        default: return nil
        }
        func field(_ index: Int) -> String? {
            fields.indices.contains(index) && !fields[index].isEmpty ? fields[index] : nil
        }
        return CommitSignature(status: status, signer: field(1), key: field(2))
    }
}
