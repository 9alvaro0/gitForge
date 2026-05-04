import Foundation

nonisolated struct DiffLine: Sendable, Equatable, Identifiable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case context
        case added
        case removed
        case noNewline
    }

    let id: Int
    let kind: Kind
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}
