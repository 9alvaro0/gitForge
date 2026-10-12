import Foundation
import Testing
@testable import gitForge

@Suite("StagingFileFilter")
struct StagingFileFilterTests {

    private static func file(_ path: String, from original: String? = nil) -> WorkingCopyFile {
        WorkingCopyFile(path: path, stagedStatus: original == nil ? .unmodified : .renamed,
                        unstagedStatus: original == nil ? .modified : .unmodified,
                        originalPath: original)
    }

    private static let files = [
        file("Sources/App/Main.swift"),
        file("Sources/Café/Menu.swift"),
        file("README.md"),
        file("docs/new-name.md", from: "docs/old-name.md"),
    ]

    @Test("An empty or blank query keeps every file")
    func emptyQuery() {
        #expect(StagingFileFilter.apply(Self.files, query: "").count == 4)
        #expect(StagingFileFilter.apply(Self.files, query: "   ").count == 4)
    }

    @Test("Matches any part of the path, ignoring case")
    func caseInsensitive() {
        #expect(StagingFileFilter.apply(Self.files, query: "main").map(\.path) == ["Sources/App/Main.swift"])
        #expect(StagingFileFilter.apply(Self.files, query: "SOURCES").count == 2)
    }

    @Test("Ignores diacritics")
    func diacritics() {
        #expect(StagingFileFilter.apply(Self.files, query: "cafe").map(\.path) == ["Sources/Café/Menu.swift"])
    }

    @Test("A rename also matches by its original path")
    func renameOriginal() {
        #expect(StagingFileFilter.apply(Self.files, query: "old-name").map(\.path) == ["docs/new-name.md"])
    }
}
