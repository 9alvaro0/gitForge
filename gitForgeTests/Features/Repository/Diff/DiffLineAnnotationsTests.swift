import SwiftUI
import Testing
@testable import gitForge

@Suite("Diff line annotations")
@MainActor
struct DiffLineAnnotationsTests {
    static let context = DiffLine(id: 0, kind: .context, content: "x", oldLineNumber: 10, newLineNumber: 10)

    static func annotations(_ refs: Set<DiffLineRef>) -> DiffLineAnnotations {
        DiffLineAnnotations(refs: refs, content: { _ in AnyView(EmptyView()) })
    }

    @Test("Unified rows match both refs of a context line")
    func unified() {
        #expect(Self.annotations([DiffLineRef(side: .old, line: 10)]).matches(Self.context) == [DiffLineRef(side: .old, line: 10)])
        #expect(Self.annotations([DiffLineRef(side: .new, line: 11)]).matches(Self.context).isEmpty)
    }

    @Test("Split rows take old refs from the left and new from the right, once")
    func split() {
        let both = Self.annotations([DiffLineRef(side: .old, line: 10), DiffLineRef(side: .new, line: 10)])
        #expect(both.matches(left: Self.context, right: Self.context)
                == [DiffLineRef(side: .new, line: 10), DiffLineRef(side: .old, line: 10)])
        let removed = DiffLine(id: 1, kind: .removed, content: "b", oldLineNumber: 11, newLineNumber: nil)
        let added = DiffLine(id: 2, kind: .added, content: "c", oldLineNumber: nil, newLineNumber: 11)
        let pair = Self.annotations([DiffLineRef(side: .old, line: 11), DiffLineRef(side: .new, line: 11)])
        #expect(pair.matches(left: removed, right: added) == [DiffLineRef(side: .new, line: 11), DiffLineRef(side: .old, line: 11)])
        // The new side of the left half isn't the left's to show.
        #expect(Self.annotations([DiffLineRef(side: .new, line: 10)]).matches(left: Self.context, right: nil).isEmpty)
        #expect(pair.matches(left: nil, right: nil).isEmpty)
    }

    @Test("Comment sides: the side the cell is on, nowhere on no-newline markers")
    func commentSides() {
        let marker = DiffLine(id: 3, kind: .noNewline, content: "", oldLineNumber: nil, newLineNumber: nil)
        #expect(DiffLineAnnotations.splitCommentSide(for: Self.context, left: true) == .old)
        #expect(DiffLineAnnotations.splitCommentSide(for: Self.context, left: false) == .new)
        #expect(DiffLineAnnotations.splitCommentSide(for: marker, left: true) == nil)
        #expect(DiffLineAnnotations.splitCommentSide(for: nil, left: false) == nil)
    }
}
