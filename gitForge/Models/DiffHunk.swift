import Foundation

nonisolated struct DiffHunk: Sendable, Equatable, Identifiable, Hashable {
    let id: Int
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String
    let lines: [DiffLine]
}
