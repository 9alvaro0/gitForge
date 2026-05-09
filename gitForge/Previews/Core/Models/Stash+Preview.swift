import Foundation

extension Stash {
    static let previewSamples: [Stash] = [
        Stash(index: 0, sha: "abc1234abcdef5678", subject: "WIP: refactor commit graph layout"),
        Stash(index: 1, sha: "def5678abcdef9012", subject: "Fix flaky stage/unstage race"),
        Stash(index: 2, sha: "fab9012abcdef3456", subject: "Experiment: collapse remote branches"),
    ]
}
