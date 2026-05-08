import Foundation

extension Commit {
    static let preview = Commit(
        sha: "a1b2c3d4e5f6789012345678901234567890abcd",
        parentShas: ["b2c3d4e5f6789012345678901234567890abcdab"],
        authorName: "Alvaro Guerra",
        authorEmail: "alvaro@warwarelabs.com",
        authorDate: .now.addingTimeInterval(-3_600),
        subject: "feat: render commit graph with lanes"
    )

    static let previewSamples: [Commit] = [
        Commit(
            sha: "a1b2c3d4e5f6789012345678901234567890abcd",
            parentShas: ["b2c3d4e5f6789012345678901234567890abcdab"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-1_800),
            subject: "feat: render commit graph with lanes"
        ),
        Commit(
            sha: "b2c3d4e5f6789012345678901234567890abcdab",
            parentShas: ["c3d4e5f6789012345678901234567890abcdabcd", "d4e5f6789012345678901234567890abcdabcdef"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-7_200),
            subject: "Merge branch \"feature/working-copy\" into main"
        ),
        Commit(
            sha: "c3d4e5f6789012345678901234567890abcdabcd",
            parentShas: ["d4e5f6789012345678901234567890abcdabcdef"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-86_400),
            subject: "fix: avoid pipe deadlock with concurrent draining"
        ),
        Commit(
            sha: "d4e5f6789012345678901234567890abcdabcdef",
            parentShas: ["e5f6789012345678901234567890abcdabcdef12"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-259_200),
            subject: "chore: organize sources into App, Features, Core"
        ),
        Commit(
            sha: "e5f6789012345678901234567890abcdabcdef12",
            parentShas: [],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-604_800),
            subject: "chore: initial project scaffold"
        ),
    ]
}
