import Foundation
import Testing
@testable import gitForge

@Suite("TypeRole")
struct TypeRoleTests {

    @Test("Sizes and line heights match the design sheet")
    func values() {
        let expected: [(TypeRole, CGFloat, CGFloat)] = [
            (.largeTitle, 28, 34), (.title, 20, 26), (.headline, 15, 20), (.body, 13, 18),
            (.callout, 12, 16), (.caption, 11, 14), (.mono, 12, 19), (.monoSmall, 11, 14),
        ]
        for (role, size, lineHeight) in expected {
            #expect(role.size == size, "\(role)")
            #expect(role.lineHeight == lineHeight, "\(role)")
        }
    }

    @Test("Sans roles grow strictly from caption to largeTitle")
    func sansScale() {
        let sizes = [TypeRole.caption, .callout, .body, .headline, .title, .largeTitle].map(\.size)
        #expect(zip(sizes, sizes.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("No role uses a half point and every line height clears its size")
    func wholePoints() {
        for role in TypeRole.allCases {
            #expect(role.size.rounded() == role.size, "\(role)")
            #expect(role.lineHeight > role.size, "\(role)")
        }
    }

    @Test("Only the two code roles are monospaced")
    func mono() {
        #expect(TypeRole.allCases.filter(\.isMono) == [.mono, .monoSmall])
    }
}
