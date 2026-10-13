import Foundation
import Testing
@testable import gitForge

@Suite("CommitSignature.parse")
struct CommitSignatureTests {

    @Test("Each %G? code maps to its status, with signer and key")
    func codes() {
        let cases: [(String, CommitSignature.Status)] = [
            ("G", .verified), ("U", .untrusted), ("X", .expired), ("Y", .expired),
            ("R", .revoked), ("B", .bad), ("E", .unverifiable),
        ]
        for (code, status) in cases {
            let parsed = CommitSignature.parse("\(code)\u{1F}Ada <ada@example.com>\u{1F}ABCDEF12\n")
            #expect(parsed == CommitSignature(status: status, signer: "Ada <ada@example.com>", key: "ABCDEF12"))
        }
    }

    @Test("Unsigned (N), empty or unknown output reads as no signature")
    func unsigned() {
        #expect(CommitSignature.parse("N\u{1F}\u{1F}\n") == nil)
        #expect(CommitSignature.parse("") == nil)
        #expect(CommitSignature.parse("?\u{1F}x\u{1F}y") == nil)
    }

    @Test("A verifier git couldn't start reads as can't verify, not bad or unsigned")
    func verifierMissing() {
        let ssh = CommitSignature.parse("B\u{1F}\u{1F}\n", stderr: "error: cannot run : No such file or directory\n")
        #expect(ssh == CommitSignature(status: .unverifiable, signer: nil, key: nil))
        let gpg = CommitSignature.parse("N\u{1F}\u{1F}\n", stderr: "error: cannot run gpg: No such file or directory\n")
        #expect(gpg == CommitSignature(status: .unverifiable, signer: nil, key: nil))
        let exec = CommitSignature.parse("B\u{1F}\u{1F}K\n", stderr: "fatal: cannot exec '/x/ssh-keygen': No such file or directory\n")
        #expect(exec == CommitSignature(status: .unverifiable, signer: nil, key: "K"))
    }

    @Test("Without a tool failure on stderr the code stands")
    func stderrWithoutToolFailure() {
        #expect(CommitSignature.parse("B\u{1F}\u{1F}\n", stderr: "")?.status == .bad)
        #expect(CommitSignature.parse("N\u{1F}\u{1F}\n", stderr: "") == nil)
        #expect(CommitSignature.parse("G\u{1F}Ada\u{1F}K\n", stderr: "")?.status == .verified)
    }

    @Test("Missing signer or key stay nil")
    func missingFields() {
        #expect(CommitSignature.parse("E\u{1F}\u{1F}ABC") == CommitSignature(status: .unverifiable, signer: nil, key: "ABC"))
        #expect(CommitSignature.parse("G") == CommitSignature(status: .verified, signer: nil, key: nil))
    }
}
