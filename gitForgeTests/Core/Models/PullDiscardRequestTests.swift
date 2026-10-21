import Foundation
import Testing
@testable import gitForge

@Suite("PullDiscardRequest — the question's text")
struct PullDiscardRequestTests {

    private static func request(_ paths: [String], refusedByRebase: Bool = false) -> PullDiscardRequest {
        let files = paths.map {
            WorkingCopyFile(path: $0, stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil)
        }
        return PullDiscardRequest(files: files, refusedByRebase: refusedByRebase, rebase: false, ffOnly: false)
    }

    @Test("The title counts the files, singular and plural")
    func title() {
        #expect(Self.request(["a.txt"]).title == "Discard changes to 1 file and pull?")
        #expect(Self.request(["a.txt", "b.txt", "c.txt"]).title == "Discard changes to 3 files and pull?")
    }

    @Test("A few files are all listed, one per line")
    func fewFiles() {
        let lines = Self.request(["a.txt", "dir/b.txt"]).message.split(separator: "\n").map(String.init)
        #expect(Array(lines.dropFirst()) == ["a.txt", "dir/b.txt"])
    }

    @Test("Past ten files the rest are counted instead of listed")
    func manyFiles() {
        let paths = (1...12).map { "f\($0).txt" }
        let lines = Self.request(paths).message.split(separator: "\n").map(String.init)
        #expect(Array(lines.dropFirst()) == Array(paths.prefix(10)) + ["…and 2 more"])
    }

    @Test("A refusal by rebase explains why every tracked change is listed")
    func rebaseIntro() {
        let merge = Self.request(["a.txt"]).message
        let rebase = Self.request(["a.txt"], refusedByRebase: true).message
        #expect(merge.split(separator: "\n").first != rebase.split(separator: "\n").first)
    }
}
