import Foundation
import Testing
@testable import gitForge

@Suite("Conflict result panel")
@MainActor
struct ConflictResultBuilderTests {

    private static let file = """
    head
    <<<<<<< HEAD
    ours 1
    ours 2
    =======
    theirs 1
    >>>>>>> feature
    middle
    <<<<<<< HEAD
    a
    =======
    b
    >>>>>>> feature
    tail
    """

    @Test("Text keeps its lines; a picked hunk contributes its side; an unpicked one is one placeholder")
    func mixed() {
        let (segments, hunks) = ConflictParser.parse(Self.file)
        let lines = ConflictResultBuilder.build(segments: segments, hunks: hunks, picks: [hunks[0].id: .ours])
        #expect(lines.map(\.text) == ["head", "ours 1", "ours 2", "middle", "", "tail"])
        #expect(lines.map(\.kind) == [.text, .ours, .ours, .text, .unresolved(hunkIndex: 1), .text])
        // The placeholder has no line number; numbering continues after it.
        #expect(lines.map(\.number) == [1, 2, 3, 4, nil, 5])
    }

    @Test("Both writes ours, then theirs")
    func both() {
        let (segments, hunks) = ConflictParser.parse(Self.file)
        let picks: [UUID: ConflictHunk.Pick] = [hunks[0].id: .both, hunks[1].id: .theirs]
        let lines = ConflictResultBuilder.build(segments: segments, hunks: hunks, picks: picks)
        #expect(lines.map(\.text) == ["head", "ours 1", "ours 2", "theirs 1", "middle", "b", "tail"])
        #expect(lines[3].kind == .theirs)
        #expect(!lines.contains { if case .unresolved = $0.kind { true } else { false } })
    }

    @Test("Both · theirs first writes theirs, then ours — in the result and on disk")
    func bothTheirsFirst() {
        let (segments, hunks) = ConflictParser.parse(Self.file)
        let picks: [UUID: ConflictHunk.Pick] = [hunks[0].id: .bothTheirsFirst, hunks[1].id: .ours]
        let lines = ConflictResultBuilder.build(segments: segments, hunks: hunks, picks: picks)
        #expect(lines.map(\.text) == ["head", "theirs 1", "ours 1", "ours 2", "middle", "a", "tail"])
        #expect(lines[1].kind == .theirs && lines[2].kind == .ours)
        let written = ConflictParser.apply(content: Self.file, picks: picks, hunks: hunks)
        #expect(written == "head\ntheirs 1\nours 1\nours 2\nmiddle\na\ntail")
    }

    @Test("CRLF endings don't leak into the shown text")
    func crlf() {
        let (segments, hunks) = ConflictParser.parse("x\r\n<<<<<<< HEAD\r\no\r\n=======\r\nt\r\n>>>>>>> b\r\n")
        let lines = ConflictResultBuilder.build(segments: segments, hunks: hunks, picks: [hunks[0].id: .theirs])
        #expect(lines.first?.text == "x")
        #expect(lines[1].text == "t")
    }

    @Test("clearPick takes a hunk back to unpicked")
    func clearPick() {
        let store = ConflictStore(repositoryURL: URL(fileURLWithPath: "/var/empty"))
        let id = UUID()
        store.setPick(hunkId: id, pick: .ours)
        store.clearPick(hunkId: id)
        #expect(store.picks[id] == nil)
    }
}
