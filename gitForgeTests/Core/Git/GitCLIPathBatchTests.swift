import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI — paths in batches under ARG_MAX")
struct GitCLIPathBatchTests {
    @Test("Batches stay under the byte limit, keep order and lose nothing")
    func batches() {
        let paths = (0..<10).map { "dir/file-\($0).txt" }   // 14 bytes + separator: 4 per batch
        let batches = GitCLI.pathBatches(paths, limit: 60)
        #expect(batches.flatMap { $0 } == paths)
        #expect(batches.allSatisfy { $0.reduce(0) { $0 + $1.utf8.count + 1 } <= 60 })
        #expect(batches.map(\.count) == [4, 4, 2])
        #expect(GitCLI.pathBatches([]).isEmpty)
        #expect(GitCLI.pathBatches([String(repeating: "x", count: 100)], limit: 60).count == 1)
    }

    @Test("Staging more paths than one run's arguments can hold stages them all")
    func stagesManyFiles() async throws {
        // 3,000 paths of ~200 bytes: about 600 KB of arguments, several batches.
        let names = (0..<3000).map { String(format: "%@-%04d.txt", String(repeating: "n", count: 190), $0) }
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("first", files: ["README.md": "x\n"])
            for name in names { try repo.write("x\n", to: name) }
        }
        defer { repo.remove() }
        #expect(GitCLI.pathBatches(names).count > 1)
        try await repo.cli.stage(paths: names)
        let staged = try await repo.gitAsync("diff", "--cached", "--name-only")
        #expect(staged.split(separator: "\n").count == 3000)
    }
}
